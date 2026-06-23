-- =============================================================================
-- Ilevest — Build Stage 2 smoke test (RPC layer / workflow engine)
-- =============================================================================
-- Run as a SUPERUSER against a DB with ALL migrations (Stage 1 + Stage 2) applied.
-- Superuser bypasses RLS, so "system" calls (fan_out_order, confirm_payment — granted to
-- service_role) run under reset role; user actions use SET ROLE authenticated + the
-- app.user_id GUC. Captured ids/results are stashed in custom GUCs (t.*) and read with
-- current_setting(), because psql does not substitute :vars inside $$ blocks. Any failure
-- aborts loudly.
\set ON_ERROR_STOP on
set client_min_messages = notice;

\set ops      '''22222222-2222-2222-2222-222222222222'''
\set reviewer '''33333333-3333-3333-3333-333333333333'''
\set partner1 '''44444444-4444-4444-4444-444444444444'''
\set partner2 '''55555555-5555-5555-5555-555555555555'''
\set client1  '''66666666-6666-6666-6666-666666666666'''
\set fa       '''88888888-8888-8888-8888-888888888888'''

\echo ''
\echo '################ PART 0 — seed users + roles (incl. a Field Agent) ################'
reset role;
insert into public.app_user(id,name,email_or_phone) values
  ('11111111-1111-1111-1111-111111111111','Admin','a@x'),
  ('22222222-2222-2222-2222-222222222222','Ops','o@x'),
  ('33333333-3333-3333-3333-333333333333','Reviewer','r@x'),
  ('44444444-4444-4444-4444-444444444444','Partner One','p1@x'),
  ('55555555-5555-5555-5555-555555555555','Partner Two','p2@x'),
  ('66666666-6666-6666-6666-666666666666','Client One','c1@x'),
  ('88888888-8888-8888-8888-888888888888','Field Agent','fa@x');
insert into public.user_role(user_id,role) values
  ('11111111-1111-1111-1111-111111111111','admin'),
  ('22222222-2222-2222-2222-222222222222','ops'),
  ('33333333-3333-3333-3333-333333333333','reviewer'),
  ('44444444-4444-4444-4444-444444444444','partner'),
  ('55555555-5555-5555-5555-555555555555','partner'),
  ('66666666-6666-6666-6666-666666666666','client'),
  ('88888888-8888-8888-8888-888888888888','field_agent');
\echo 'seeded 7 users incl. a field_agent'

\echo ''
\echo '################ PART 1 — fan-out from a bundle + idempotency ################'
set role authenticated; set app.user_id = :ops;
insert into public.property(id,lga,state,locality) values ('aa000000-0000-0000-0000-000000000001','Eti-Osa','Lagos','Lekki Phase 1');
insert into public.order_matter(id,client_id,property_id,bundle) values ('cc000000-0000-0000-0000-000000000001',:client1,'aa000000-0000-0000-0000-000000000001','complete');
select app.add_order_lines_for_bundle('cc000000-0000-0000-0000-000000000001','complete');
insert into public.payment(order_id,service_fee,government_fee_total) values ('cc000000-0000-0000-0000-000000000001', 75000, 50000);
reset role;
do $$ declare nlines int; begin
  select count(*) into nlines from public.order_line where order_id='cc000000-0000-0000-0000-000000000001';
  if nlines <> 3 then raise exception 'FAIL: complete bundle should add 3 lines, got %', nlines; end if;
  raise notice 'PASS: complete bundle expanded to 3 order lines';
end $$;

select set_config('t.r1', public.confirm_payment('cc000000-0000-0000-0000-000000000001','paystack_ref_1')::text, false);
do $$ declare res jsonb := current_setting('t.r1')::jsonb; nc int; begin
  if (res->>'checks_created')::int <> 3 then raise exception 'FAIL: fan-out should create 3 checks, got %', res->>'checks_created'; end if;
  if (res->>'already_verified')::boolean then raise exception 'FAIL: first confirm should not be already_verified'; end if;
  select count(*) into nc from public.check_item where order_id='cc000000-0000-0000-0000-000000000001';
  if nc <> 3 then raise exception 'FAIL: order1 should have 3 checks, got %', nc; end if;
  raise notice 'PASS: confirm_payment created 3 checks from the bundle';
end $$;
select set_config('t.r2', public.confirm_payment('cc000000-0000-0000-0000-000000000001','paystack_ref_1')::text, false);
do $$ declare res jsonb := current_setting('t.r2')::jsonb; nc int; begin
  if not (res->>'already_verified')::boolean then raise exception 'FAIL: second confirm should be already_verified'; end if;
  if (res->>'checks_created')::int <> 0 then raise exception 'FAIL: second confirm should create 0 checks'; end if;
  select count(*) into nc from public.check_item where order_id='cc000000-0000-0000-0000-000000000001';
  if nc <> 3 then raise exception 'FAIL: still expect 3 checks after duplicate webhook, got %', nc; end if;
  raise notice 'PASS: duplicate webhook is idempotent (no double fan-out)';
end $$;

\echo ''
\echo '################ PART 1b — diaspora bundle includes the Persons/Entities (KYC) check ################'
set role authenticated; set app.user_id = :ops;
insert into public.order_matter(id,client_id,property_id,bundle) values ('cc000000-0000-0000-0000-000000000003',:client1,'aa000000-0000-0000-0000-000000000001','diaspora');
select app.add_order_lines_for_bundle('cc000000-0000-0000-0000-000000000003','diaspora');
insert into public.payment(order_id,service_fee,government_fee_total) values ('cc000000-0000-0000-0000-000000000003', 120000, 90000);
reset role;
select set_config('t.rd', public.confirm_payment('cc000000-0000-0000-0000-000000000003','paystack_ref_3')::text, false);
do $$ declare res jsonb := current_setting('t.rd')::jsonb; nk int; begin
  if (res->>'checks_created')::int <> 5 then raise exception 'FAIL: diaspora should create 5 checks, got %', res->>'checks_created'; end if;
  select count(*) into nk from public.check_item where order_id='cc000000-0000-0000-0000-000000000003' and service_code='C1-KY-01';
  if nk <> 1 then raise exception 'FAIL: diaspora should include the Persons/Entities (KYC) check'; end if;
  raise notice 'PASS: diaspora expands to 5 checks including the Persons/Entities (KYC) check';
end $$;

\echo ''
\echo '################ PART 2 — a la carte field inspection + Ops-direct assignment ################'
set role authenticated; set app.user_id = :ops;
insert into public.order_matter(id,client_id,property_id,bundle) values ('cc000000-0000-0000-0000-000000000002',:client1,'aa000000-0000-0000-0000-000000000001','ala_carte');
insert into public.order_line(order_id,service_code) values ('cc000000-0000-0000-0000-000000000002','C1-FD-01');
insert into public.payment(order_id,service_fee,government_fee_total) values ('cc000000-0000-0000-0000-000000000002', 20000, 0);
reset role;
select set_config('t.r3', public.confirm_payment('cc000000-0000-0000-0000-000000000002','paystack_ref_2')::text, false);
do $$ declare res jsonb := current_setting('t.r3')::jsonb; begin
  if (res->>'checks_created')::int <> 1 then raise exception 'FAIL: a la carte should create 1 check, got %', res->>'checks_created'; end if;
  raise notice 'PASS: a la carte field inspection created 1 check';
end $$;
select set_config('t.fd_check', (select id::text from public.check_item where order_id='cc000000-0000-0000-0000-000000000002' and service_code='C1-FD-01'), false);
select set_config('t.chk_lr',  (select id::text from public.check_item where order_id='cc000000-0000-0000-0000-000000000001' and service_code='C1-LR-01'), false);
select set_config('t.chk_sg',  (select id::text from public.check_item where order_id='cc000000-0000-0000-0000-000000000001' and service_code='C1-SG-01'), false);

set role authenticated; set app.user_id = :ops;
select public.assign_check(current_setting('t.fd_check')::uuid, :fa);
reset role;
do $$ declare w uuid; s public.check_state; begin
  select assigned_partner_id, state into w, s from public.check_item where id = current_setting('t.fd_check')::uuid;
  if w <> '88888888-8888-8888-8888-888888888888' then raise exception 'FAIL: FD check should be assigned to the field agent'; end if;
  if s <> 'assigned' then raise exception 'FAIL: FD check should be assigned, got %', s; end if;
  raise notice 'PASS: Ops dispatched the field inspection directly to the Field Agent';
end $$;

set role authenticated; set app.user_id = :reviewer;
do $$ begin
  begin perform public.assign_check(current_setting('t.chk_lr')::uuid, '88888888-8888-8888-8888-888888888888'::uuid);
  exception when sqlstate '23514' then raise notice 'PASS: a reviewer cannot assign (Ops-only gate)'; return; end;
  raise exception 'FAIL: reviewer was allowed to assign';
end $$;
set app.user_id = :ops;
do $$ begin
  begin perform public.assign_check(current_setting('t.chk_lr')::uuid, '66666666-6666-6666-6666-666666666666'::uuid);
  exception when sqlstate '23514' then raise notice 'PASS: cannot assign a check to a client (role check)'; return; end;
  raise exception 'FAIL: assigned a check to a client';
end $$;

\echo ''
\echo '################ PART 3 — evidence intake (least-privilege per check) ################'
set app.user_id = :fa;
select public.record_evidence(current_setting('t.fd_check')::uuid,'coordinate','h_fd_coord_1', null, 6.4501, 3.4710, 8.0, now(), 'device-FA-01');
do $$ declare n int; begin
  select count(*) into n from public.evidence_item where check_id = current_setting('t.fd_check')::uuid;
  if n <> 1 then raise exception 'FAIL: field agent should have posted 1 evidence item, got %', n; end if;
  raise notice 'PASS: assigned Field Agent posted evidence on their check';
end $$;
set app.user_id = :partner2;
do $$ begin
  begin perform public.record_evidence(current_setting('t.fd_check')::uuid,'note','h_intruder', null, null, null, null, null, null);
  exception when sqlstate '42501' then raise notice 'PASS: a non-assigned worker cannot post evidence (RLS)'; return; end;
  raise exception 'FAIL: a non-assigned worker posted evidence';
end $$;
set app.user_id = :fa;
do $$ declare n int; begin
  select count(*) into n from public.check_item;
  if n <> 1 then raise exception 'FAIL: field agent should see only their 1 assigned check, saw %', n; end if;
  raise notice 'PASS: field agent sees only their own assigned check (not the partner caseload)';
end $$;

\echo ''
\echo '################ PART 4 — seal pipeline + hash-chain ################'
set app.user_id = :ops;       select public.assign_check(current_setting('t.chk_lr')::uuid, :partner1);
set app.user_id = :partner1;  update public.check_item set state='in_progress' where id = current_setting('t.chk_lr')::uuid;
                              update public.check_item set state='in_review'  where id = current_setting('t.chk_lr')::uuid;
set app.user_id = :reviewer;
select set_config('t.s1', public.seal_check(current_setting('t.chk_lr')::uuid,'green','No adverse entries found as at the search date.')::text, false);
do $$ declare res jsonb := current_setting('t.s1')::jsonb; begin
  if res->>'verdict' <> 'green' then raise exception 'FAIL: verdict should be green'; end if;
  if length(res->>'content_hash') <> 64 then raise exception 'FAIL: content_hash should be 64 hex chars, got %', length(res->>'content_hash'); end if;
  if (res->>'content_hash') !~ '^[0-9a-f]{64}$' then raise exception 'FAIL: content_hash should be lowercase hex'; end if;
  if res->>'prev_hash' <> repeat('0',64) then raise exception 'FAIL: first commitment prev_hash must be genesis zeros, got %', res->>'prev_hash'; end if;
  raise notice 'PASS: seal produced a verdict + a 64-hex fingerprint; first commitment links to genesis';
end $$;

set app.user_id = :ops;       select public.assign_check(current_setting('t.chk_sg')::uuid, :partner1);
set app.user_id = :partner1;  update public.check_item set state='in_progress' where id = current_setting('t.chk_sg')::uuid;
                              update public.check_item set state='in_review'  where id = current_setting('t.chk_sg')::uuid;
set app.user_id = :reviewer;
select set_config('t.s2', public.seal_check(current_setting('t.chk_sg')::uuid,'amber','Survey plan predates latest charting; proceed with caution.')::text, false);
do $$ declare res2 jsonb := current_setting('t.s2')::jsonb; first_hash text; begin
  first_hash := (current_setting('t.s1')::jsonb)->>'content_hash';
  if res2->>'prev_hash' <> first_hash then raise exception 'FAIL: second commitment must chain to the first'; end if;
  raise notice 'PASS: second seal chains to the first (prev_hash = previous content_hash)';
end $$;

set app.user_id = :partner1;
do $$ begin
  begin perform public.seal_check(current_setting('t.fd_check')::uuid,'green','x');
  exception when sqlstate '23514' then raise notice 'PASS: a partner cannot seal (reviewer/ops only)'; return; end;
  raise exception 'FAIL: a partner was allowed to seal';
end $$;

\echo ''
\echo '################ PART 5 — public verification (validity + verdict + integrity, NO PII) ################'
reset role; set role anon;
select set_config('t.vc', coalesce(public.verify_certificate(current_setting('t.chk_lr')::uuid)::text,'{"valid":false}'), false);
do $$ declare res jsonb := current_setting('t.vc')::jsonb; begin
  if not (res->>'valid')::boolean then raise exception 'FAIL: sealed check should verify as valid'; end if;
  if res->>'verdict' <> 'green' then raise exception 'FAIL: public verdict should be green'; end if;
  if length(res->>'content_hash') <> 64 then raise exception 'FAIL: public payload should carry the fingerprint'; end if;
  if (res #>> '{property,state}') <> 'Lagos' then raise exception 'FAIL: public payload should include the property location'; end if;
  if res::text ilike '%Client One%' then raise exception 'FAIL: public payload leaked a personal name'; end if;
  raise notice 'PASS: public verification returns validity + verdict + location + fingerprint, and no PII';
end $$;
select set_config('t.vc2', coalesce(public.verify_certificate('dd000000-0000-0000-0000-000000000099'::uuid)::text,'{"valid":false}'), false);
do $$ declare res jsonb := current_setting('t.vc2')::jsonb; begin
  if (res->>'valid')::boolean then raise exception 'FAIL: an unsealed check must not verify as valid'; end if;
  raise notice 'PASS: an unsealed/unknown check verifies as not valid';
end $$;

reset role;
\echo ''
\echo '############################################################'
\echo '   ALL STAGE 2 ASSERTIONS PASSED'
\echo '############################################################'
