-- =============================================================================
-- consent_smoke.sql — Hardening 5.2: recorded consent
-- =============================================================================
\set ON_ERROR_STOP on
reset role;
select set_config('app.user_id', '', false);

insert into public.app_user (id, name, email_or_phone) values
 ('99000000-0000-0000-0000-0000000000a1', 'Consent User', 'consent-a@test.ng'),
 ('99000000-0000-0000-0000-0000000000f1', 'Consent Admin', 'consent-adm@test.ng')
on conflict do nothing;
insert into public.user_role (user_id, role) values
 ('99000000-0000-0000-0000-0000000000a1','client'),
 ('99000000-0000-0000-0000-0000000000f1','admin')
on conflict do nothing;

\set cuser '''99000000-0000-0000-0000-0000000000a1'''
\set cadmin '''99000000-0000-0000-0000-0000000000f1'''

\echo '################ record_consent + my_latest_consent ################'
set role authenticated; set app.user_id = :cuser;
do $$
declare v jsonb;
begin
  -- before consent
  if (public.my_latest_consent()->>'consented')::boolean then
    raise exception 'FAIL: user has not consented yet';
  end if;
  -- record consent
  v := public.record_consent('privacy+terms@2026-07-08', 'test-agent');
  if not (v->>'recorded')::boolean or (v->>'version') <> 'privacy+terms@2026-07-08' then
    raise exception 'FAIL: record_consent did not confirm: %', v;
  end if;
  -- after consent
  v := public.my_latest_consent();
  if not (v->>'consented')::boolean or (v->>'version') <> 'privacy+terms@2026-07-08' then
    raise exception 'FAIL: latest consent wrong: %', v;
  end if;
  raise notice 'PASS: consent recorded and retrievable with its version';
end $$;

\echo '################ empty version refused ################'
do $$
declare ok boolean := false;
begin
  begin perform public.record_consent('   '); exception when others then ok := true; end;
  if not ok then raise exception 'FAIL: empty version should be refused'; end if;
  raise notice 'PASS: an empty document version is refused';
end $$;

\echo '################ written to the audit spine ################'
reset role; select set_config('app.user_id', '', false);
do $$
begin
  if not exists (select 1 from public.audit_event
                 where entity_id = '99000000-0000-0000-0000-0000000000a1'
                   and action = 'consent_recorded'
                   and metadata->>'document_version' = 'privacy+terms@2026-07-08') then
    raise exception 'FAIL: consent must appear in the audit spine';
  end if;
  raise notice 'PASS: consent is recorded in the tamper-evident audit spine';
end $$;

\echo '################ consent records are immutable (append-only) ################'
do $$
declare ok boolean := false;
begin
  begin
    update public.consent_record set document_version = 'tampered'
      where user_id = '99000000-0000-0000-0000-0000000000a1';
    exception when others then ok := true;
  end;
  if not ok then raise exception 'FAIL: consent records must be immutable'; end if;
  raise notice 'PASS: consent records cannot be altered (even by superuser)';
end $$;

do $$
declare ok boolean := false;
begin
  begin
    delete from public.consent_record where user_id = '99000000-0000-0000-0000-0000000000a1';
    exception when others then ok := true;
  end;
  if not ok then raise exception 'FAIL: consent records must not be deletable'; end if;
  raise notice 'PASS: consent records cannot be deleted';
end $$;

\echo '################ RLS: users see only their own consent; admin sees all ################'
set role authenticated; set app.user_id = :cadmin;
do $$
begin
  if not exists (select 1 from public.consent_record
                 where user_id = '99000000-0000-0000-0000-0000000000a1') then
    raise exception 'FAIL: admin should see all consent records';
  end if;
  raise notice 'PASS: admin can query consent records (NDPA accountability)';
end $$;

-- a second ordinary user cannot see the first user's consent
insert into public.app_user (id, name) values ('99000000-0000-0000-0000-0000000000a2','Other User') on conflict do nothing;
insert into public.user_role (user_id, role) values ('99000000-0000-0000-0000-0000000000a2','client') on conflict do nothing;
reset role; select set_config('app.user_id','',false);
set role authenticated; set app.user_id = '99000000-0000-0000-0000-0000000000a2';
do $$
begin
  if exists (select 1 from public.consent_record
             where user_id = '99000000-0000-0000-0000-0000000000a1') then
    raise exception 'FAIL: a user must not see another user''s consent';
  end if;
  raise notice 'PASS: consent records are private to their owner';
end $$;

reset role;
\echo ''
\echo 'ALL CONSENT ASSERTIONS PASSED'
