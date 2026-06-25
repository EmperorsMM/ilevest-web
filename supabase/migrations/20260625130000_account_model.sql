-- =============================================================================
-- 0015  Account model — Admin provisioning/governance + client deactivate-and-anonymize
-- =============================================================================
-- Two additions to the locked role model (Decision H) and retention split (Decision N):
--
-- (1) Admin GOVERNS access — provisions Ops/Reviewer/Field Agent/Partner and assigns exactly
--     those roles — but does NOT inherit the ability to do their jobs. CISO boundary made real:
--     today is_ops()/is_reviewer() wrongly counted 'admin', so an admin could assign and seal.
--     We tighten them to the specific role, so even the most powerful account cannot forge a
--     sealed verdict or move money. Admin keeps is_staff() (read visibility) for governance.
--
-- (2) A client may close their account (deactivate-and-anonymize), UNLESS they owe money or
--     have a paid verification still in progress. Deletion removes personal login/contact data
--     (NDPA minimisation) but NEVER erases sealed/anchored records — those are immutable, the
--     public verification links must keep resolving, and the audit trail must survive.

-- ---- (1a) tighten the operational role checks so 'admin' is NOT ops/reviewer ----
create or replace function app.is_ops()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_role ur
                 where ur.user_id = app.current_user_id() and ur.role = 'ops');
$$;
create or replace function app.is_reviewer()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_role ur
                 where ur.user_id = app.current_user_id() and ur.role = 'reviewer');
$$;
comment on function app.is_ops()      is 'TRUE only for the ops role. Admin is deliberately excluded — admin governs, it does not assign/move money.';
comment on function app.is_reviewer() is 'TRUE only for the reviewer role. Admin is deliberately excluded — admin governs, it does not seal verdicts.';

-- ---- (1b) Admin provisioning: create/assign and revoke the four staff roles ----
create or replace function public.admin_create_or_assign(p_target uuid, p_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not app.is_admin() then
    raise exception 'only an admin may provision staff accounts' using errcode = 'insufficient_privilege';
  end if;
  if p_role not in ('ops','reviewer','field_agent','partner') then
    raise exception 'admins may assign only ops, reviewer, field_agent, or partner' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.app_user where id = p_target) then
    raise exception 'target account does not exist (create the auth account first)' using errcode = 'foreign_key_violation';
  end if;
  insert into public.user_role (user_id, role, granted_by)
    values (p_target, p_role::public.app_role, app.current_user_id())
  on conflict (user_id, role) do nothing;
  perform app.write_audit(p_entity_type => 'user_role', p_entity_id => p_target,
                          p_action => 'role_granted', p_to => p_role, p_reason => 'admin provisioning');
  return jsonb_build_object('ok', true, 'target', p_target, 'role', p_role);
end;
$$;

create or replace function public.admin_revoke_role(p_target uuid, p_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not app.is_admin() then
    raise exception 'only an admin may revoke staff roles' using errcode = 'insufficient_privilege';
  end if;
  if p_role not in ('ops','reviewer','field_agent','partner') then
    raise exception 'admins may revoke only staff roles' using errcode = 'check_violation';
  end if;
  delete from public.user_role where user_id = p_target and role = p_role::public.app_role;
  perform app.write_audit(p_entity_type => 'user_role', p_entity_id => p_target,
                          p_action => 'role_revoked', p_to => p_role, p_reason => 'admin provisioning');
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function public.admin_create_or_assign(uuid,text) to authenticated, service_role;
grant execute on function public.admin_revoke_role(uuid,text)      to authenticated, service_role;

-- ---- (2a) deactivation/anonymisation state on the account ----
alter table public.app_user add column if not exists deactivated_at timestamptz;
alter table public.app_user add column if not exists anonymized     boolean not null default false;

-- ---- (2b) deactivate-and-anonymize, with the money / in-flight guards ----
create or replace function app.delete_client_account(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_owes boolean; v_inflight boolean;
begin
  -- guard (a): an issued-but-unpaid invoice (owes money)
  select exists (
    select 1 from public.payment p join public.order_matter o on o.id = p.order_id
    where o.client_id = p_user and p.webhook_verified = false
  ) into v_owes;
  if v_owes then
    return jsonb_build_object('deleted', false,
      'reason', 'There is an unpaid invoice on your account. Please settle it before closing your account.');
  end if;

  -- guard (b): a paid verification still in progress (not yet finalized)
  select exists (
    select 1 from public.order_matter o
      join public.payment   p  on p.order_id = o.id and p.webhook_verified = true
      join public.check_item ci on ci.order_id = o.id
    where o.client_id = p_user and ci.state not in ('finalized','rejected')
  ) into v_inflight;
  if v_inflight then
    return jsonb_build_object('deleted', false,
      'reason', 'You have a verification in progress. We will finish it first; you can close your account once it is complete.');
  end if;

  -- deactivate + strip personal data. Sealed/anchored records are immutable and untouched; the
  -- order still references this (now anonymised) account, so audit + public links stay valid.
  update public.app_user
     set name = 'Former client', email_or_phone = null, auth_provider = null, nin_ref = null,
         identity_verified = false, identity_verified_at = null, identity_verified_by = null,
         deactivated_at = now(), anonymized = true
   where id = p_user;

  perform app.write_audit(p_entity_type => 'app_user', p_entity_id => p_user,
                          p_action => 'account_deleted',
                          p_reason => 'client-requested deactivate-and-anonymize (NDPA minimisation)');
  return jsonb_build_object('deleted', true);
end;
$$;

-- client-facing, self-only (a client can close only their own account)
create or replace function public.request_account_deletion()
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if app.current_user_id() is null then
    raise exception 'must be signed in' using errcode = 'insufficient_privilege';
  end if;
  return app.delete_client_account(app.current_user_id());
end;
$$;
grant execute on function public.request_account_deletion() to authenticated;
