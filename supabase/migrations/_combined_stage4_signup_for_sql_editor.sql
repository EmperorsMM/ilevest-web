-- =============================================================================
-- Ilevest — Build Stage 4 combined migration, part 2: signup linkage (Supabase SQL Editor)
-- Apply AFTER the Stage 4 read-model (part 1). Adds the auth->app_user linkage, the
-- structural identity-verification boundary, and — because this runs on the deployed
-- project where auth.users exists — the trigger that fires on signup. One transaction.
-- =============================================================================
begin;

-- =============================================================================
-- 0013  Client Portal — Stage 4 (part 2): signup linkage + identity boundary
-- =============================================================================
-- On Supabase Auth signup (email OR social), create the portable app_user keyed by the
-- auth uid, with the client role. Minimal info only (Call 4). The CISO boundary is made
-- STRUCTURAL, not advisory: a login — however the person authenticated — never implies a
-- verified identity. identity_verified defaults false and can be set true ONLY through a
-- C1-PE-02 identity-verification check. The signup path can never set or fake it.
--
-- Sandbox note: the auth.users trigger half can only run where the auth schema exists
-- (the deployed project). The sandbox proves the LINKAGE LOGIC offline; the trigger is
-- created here only when auth.users is present, and verified on dev.

-- ---- identity boundary fields on the account ----
alter table public.app_user add column if not exists auth_provider        text;          -- informational: 'email','google',...
alter table public.app_user add column if not exists identity_verified     boolean not null default false;
alter table public.app_user add column if not exists identity_verified_at  timestamptz;
alter table public.app_user add column if not exists identity_verified_by  uuid references public.check_item(id);
comment on column public.app_user.identity_verified is
  'TRUE only after a C1-PE-02 identity verification. Signup / social login NEVER sets this — access is not identity.';

-- ---- the portable linkage (logic; offline-testable) ----
create or replace function app.link_auth_user(p_uid uuid, p_name text, p_contact text, p_provider text default null)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  -- mirror the auth user into the portable app_user, keyed by the auth uid. Never touches
  -- identity_verified, so it stays at its default (false) or an existing real verification.
  insert into public.app_user (id, name, email_or_phone, auth_provider)
    values (p_uid, nullif(p_name, ''), p_contact, p_provider)
  on conflict (id) do update set
    name           = coalesce(nullif(excluded.name, ''), app_user.name),
    email_or_phone = coalesce(excluded.email_or_phone, app_user.email_or_phone),
    auth_provider  = coalesce(excluded.auth_provider, app_user.auth_provider);

  insert into public.user_role (user_id, role) values (p_uid, 'client') on conflict do nothing;
end;
$$;
comment on function app.link_auth_user(uuid,text,text,text) is
  'Creates/refreshes the app_user (id = auth uid) + client role on signup. Never sets identity_verified.';

-- ---- the ONLY path to a verified identity: a C1-PE-02 check ----
create or replace function app.mark_identity_verified(p_user uuid, p_check uuid)
returns void language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not exists (select 1 from public.check_item where id = p_check and service_code = 'C1-PE-02') then
    raise exception 'identity can only be marked verified through a C1-PE-02 identity check'
      using errcode = 'check_violation';
  end if;
  update public.app_user
     set identity_verified = true, identity_verified_at = now(), identity_verified_by = p_check
   where id = p_user;
end;
$$;
comment on function app.mark_identity_verified(uuid,uuid) is
  'Sets identity_verified TRUE — gated structurally on a C1-PE-02 check. The single writer of verified identity.';

-- ---- the auth trigger function (thin; calls the linkage with signup values) ----
create or replace function app.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  perform app.link_auth_user(
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.email, new.phone, new.raw_user_meta_data->>'email'),
    coalesce(new.raw_app_meta_data->>'provider', 'email')
  );
  return new;
end;
$$;

-- ---- bind the trigger only where the auth schema exists (deployed project) ----
do $$
begin
  if to_regclass('auth.users') is not null then
    execute 'drop trigger if exists on_auth_user_created on auth.users';
    execute 'create trigger on_auth_user_created after insert on auth.users for each row execute function app.handle_new_user()';
  end if;
end $$;

-- ---- grants (server-side callers only; clients cannot self-verify) ----
grant execute on function app.link_auth_user(uuid,text,text,text) to service_role;
grant execute on function app.mark_identity_verified(uuid,uuid)   to service_role;

commit;
