-- =============================================================================
-- Ilevest — Production hardening 5.2 · Recorded consent at signup
--
-- The NDPA requires evidence of lawful basis (consent + contract). This creates
-- a durable, queryable record of exactly what each user agreed to and when:
--
--   consent_record        append-only table: user, document version, timestamp,
--                         and how it was captured. Immutable by trigger (same
--                         posture as the audit spine) — a consent record, once
--                         written, is evidence and must not be altered.
--
--   record_consent(ver)   SECURITY DEFINER, called by the signed-in user right
--                         after signup. Writes the consent row AND a line to the
--                         business audit spine, so consent shows up in the same
--                         tamper-evident timeline as every other meaningful act.
--
--   my_latest_consent()   lets the app confirm a user has consented to the
--                         current document version (and re-prompt on a new one).
--
-- Design note: the document VERSION is passed by the client from a single
-- source of truth (the /privacy + /terms pages carry a version constant), so
-- when the lawyer finalises the wording and the version bumps, re-consent is
-- detectable. The version string is opaque to the database — it just records
-- what it was told, faithfully and immutably.
-- =============================================================================

create table if not exists public.consent_record (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_user(id) on delete cascade,
  document_version text not null,           -- e.g. 'privacy+terms@2026-07-08'
  agreed_at timestamptz not null default now(),
  capture_channel text not null default 'signup'
    check (capture_channel in ('signup','re-consent','import')),
  user_agent text,                          -- best-effort context, not identity
  created_at timestamptz not null default now()
);

create index if not exists consent_record_user_idx on public.consent_record(user_id, agreed_at desc);

-- Immutable: consent is evidence. Append-only, like the audit spine.
drop trigger if exists consent_record_block_modification on public.consent_record;
create trigger consent_record_block_modification
  before delete or update on public.consent_record
  for each row execute function app.tg_block_modification();

alter table public.consent_record enable row level security;

drop policy if exists consent_select on public.consent_record;
create policy consent_select on public.consent_record for select to authenticated
  using ((user_id = app.current_user_id()) or app.is_admin());
-- No direct insert policy: consent is written only through record_consent (definer).

grant select on public.consent_record to authenticated;

-- ---------------------------------------------------------------------------
-- record_consent: the signed-in user affirms the current document version.
-- ---------------------------------------------------------------------------
create or replace function public.record_consent(p_version text, p_user_agent text default null)
 returns jsonb
 language plpgsql security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare uid uuid := app.current_user_id(); v_id uuid;
begin
  if uid is null then
    raise exception 'must be signed in to record consent' using errcode = 'insufficient_privilege';
  end if;
  if p_version is null or length(btrim(p_version)) = 0 then
    raise exception 'a document version is required to record consent' using errcode = 'check_violation';
  end if;

  insert into public.consent_record(user_id, document_version, capture_channel, user_agent)
  values (uid, btrim(p_version), 'signup', p_user_agent)
  returning id into v_id;

  -- consent belongs in the same tamper-evident timeline as every other act
  perform app.write_audit('app_user', uid, 'consent_recorded', null, null,
    'agreed to Terms + Privacy', null,
    jsonb_build_object('document_version', btrim(p_version)));

  return jsonb_build_object('recorded', true, 'consent_id', v_id, 'version', btrim(p_version));
end;
$function$;

-- ---------------------------------------------------------------------------
-- my_latest_consent: what version did I last agree to (if any)?
-- ---------------------------------------------------------------------------
create or replace function public.my_latest_consent()
 returns jsonb
 language plpgsql stable security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare uid uuid := app.current_user_id(); v jsonb;
begin
  if uid is null then return jsonb_build_object('consented', false); end if;
  select jsonb_build_object('consented', true, 'version', document_version, 'agreed_at', agreed_at)
    into v
  from public.consent_record where user_id = uid
  order by agreed_at desc limit 1;
  return coalesce(v, jsonb_build_object('consented', false));
end;
$function$;

grant execute on function public.record_consent(text, text) to authenticated;
grant execute on function public.my_latest_consent() to authenticated;

select app.write_audit('migration', null, 'applied', null, null,
  'Hardening 5.2 — recorded consent: append-only consent_record table + record_consent/my_latest_consent RPCs, written to the audit spine');
