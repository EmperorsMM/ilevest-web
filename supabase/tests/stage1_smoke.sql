-- =============================================================================
-- Ilevest — Build Stage 1 smoke test
-- =============================================================================
-- Run as a SUPERUSER against a database with all migrations freshly applied:
--     createdb ilevest_test && psql ilevest_test -f <each migration> && psql ilevest_test -f this
-- It exercises the schema AS THE SIX ROLES (via SET ROLE authenticated + the app.user_id
-- portability GUC) and asserts the locked invariants. Any failure aborts the run loudly.
--
-- Why SET ROLE: the postgres superuser BYPASSES RLS, so RLS can only be tested as a
-- non-superuser role. `authenticated` is that role; the current user is selected by the
-- app.user_id GUC, exactly as app.current_user_id() reads it.
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- fixed ids for readability
\set admin    '''11111111-1111-1111-1111-111111111111'''
\set ops      '''22222222-2222-2222-2222-222222222222'''
\set reviewer '''33333333-3333-3333-3333-333333333333'''
\set partner1 '''44444444-4444-4444-4444-444444444444'''
\set partner2 '''55555555-5555-5555-5555-555555555555'''
\set client1  '''66666666-6666-6666-6666-666666666666'''
\set client2  '''77777777-7777-7777-7777-777777777777'''
\set prop1    '''aa000000-0000-0000-0000-000000000001'''
\set party1   '''bb000000-0000-0000-0000-000000000001'''
\set order1   '''cc000000-0000-0000-0000-000000000001'''
\set check1   '''dd000000-0000-0000-0000-000000000001'''
\set check2   '''dd000000-0000-0000-0000-000000000002'''
\set check3   '''dd000000-0000-0000-0000-000000000003'''
\set ev1      '''ee000000-0000-0000-0000-000000000001'''
\set rcpt1    '''ee000000-0000-0000-0000-000000000002'''
\set c1       '''c1000000-0000-0000-0000-000000000001'''
\set c2       '''c2000000-0000-0000-0000-000000000002'''
\set c3       '''c3000000-0000-0000-0000-000000000003'''
\set fee1     '''ff000000-0000-0000-0000-000000000001'''
\set fee2     '''ff000000-0000-0000-0000-000000000002'''
\set ab1      '''ab000000-0000-0000-0000-000000000001'''

\echo ''
\echo '################ PART 0 — bootstrap users + roles (privileged seed) ################'
reset role;  -- superuser, like the migration/service-role seed of the first accounts
insert into public.app_user(id,name,email_or_phone) values
  (:admin,'Admin','admin@ilevest.test'), (:ops,'Ops','ops@ilevest.test'),
  (:reviewer,'Reviewer','rev@ilevest.test'), (:partner1,'Partner One','p1@ilevest.test'),
  (:partner2,'Partner Two','p2@ilevest.test'), (:client1,'Client One','c1@ilevest.test'),
  (:client2,'Client Two','c2@ilevest.test');
insert into public.user_role(user_id,role) values
  (:admin,'admin'), (:ops,'ops'), (:reviewer,'reviewer'),
  (:partner1,'partner'), (:partner2,'partner'), (:client1,'client'), (:client2,'client');
insert into public.partner_profile(user_id,states_covered,desks_covered) values
  (:partner1, '{Lagos}', '{LR,SG}'), (:partner2, '{Ogun}', '{LR}');
\echo 'seeded 7 users, 7 role grants, 2 partner profiles'

\echo ''
\echo '################ PART 1 — FSM happy path (each step as the correct role) ################'
-- OPS creates the order and its checks, then assigns them
set role authenticated; set app.user_id = :ops;
insert into public.property(id,lga,state,locality) values (:prop1,'Eti-Osa','Lagos','Lekki Phase 1');
insert into public.party_seller(id,name) values (:party1,'Seller A');
insert into public.order_matter(id,client_id,property_id,party_id,bundle)
  values (:order1,:client1,:prop1,:party1,'complete');
insert into public.check_item(id,order_id,service_code) values (:check1,:order1,'C1-LR-01');
insert into public.check_item(id,order_id,service_code) values (:check2,:order1,'C1-SG-01');
update public.check_item set assigned_partner_id=:partner1, state='assigned' where id=:check1;
update public.check_item set assigned_partner_id=:partner1, state='assigned' where id=:check2;
\echo 'ops: created order + 2 checks, assigned both to partner1'

-- PARTNER1 does the field work and captures evidence
set app.user_id = :partner1;
update public.check_item set state='in_progress' where id=:check1;
insert into public.evidence_item(id,check_id,kind,content_hash,gps_lat,gps_lng)
  values (:ev1,:check1,'register_photo','h_register_photo_dummy', 6.45, 3.47);
insert into public.evidence_item(id,check_id,kind,content_hash)
  values (:rcpt1,:check1,'receipt','h_official_receipt_dummy');
update public.check_item set state='in_review' where id=:check1;
update public.check_item set state='in_progress' where id=:check2;
update public.check_item set state='in_review'  where id=:check2;
\echo 'partner1: worked both checks to in_review; captured 2 evidence items'

-- REVIEWER finalizes, records verdicts, seals commitments
set app.user_id = :reviewer;
update public.check_item set state='finalized' where id=:check1;
update public.check_item set state='finalized' where id=:check2;
insert into public.verdict(check_id,colour,explanation) values (:check1,'green','No adverse entries found as at search date.');
insert into public.verdict(check_id,colour,explanation) values (:check2,'amber','Survey plan predates the latest charting; proceed with caution.');
insert into public.commitment(id,check_id,content_hash) values (:c1,:check1, repeat('a',64));
insert into public.commitment(id,check_id,content_hash) values (:c2,:check2, repeat('b',64));
\echo 'reviewer: finalized both checks, recorded verdicts (green, amber), sealed 2 commitments'

reset role;
do $$
declare s text; hv public.verdict_colour; fin boolean;
begin
  select app.order_status('cc000000-0000-0000-0000-000000000001') into s;
  if s <> 'ready' then raise exception 'FAIL: order status should be ready, got %', s; end if;
  select app.order_headline_verdict('cc000000-0000-0000-0000-000000000001') into hv;
  if hv <> 'amber' then raise exception 'FAIL: headline should be amber (green+amber), got %', hv; end if;
  select is_finalized into fin from public.check_item where id='dd000000-0000-0000-0000-000000000001';
  if not fin then raise exception 'FAIL: check1 should be is_finalized'; end if;
  raise notice 'PASS: order derived status=ready, headline verdict=amber, check1 finalized+sealed';
end $$;

\echo ''
\echo '################ PART 2 — FSM enforcement (illegal moves blocked) ################'
set role authenticated; set app.user_id = :reviewer;
do $$ begin
  begin update public.check_item set state='in_progress' where id='dd000000-0000-0000-0000-000000000001';
  exception when sqlstate '23514' then raise notice 'PASS: finalized check is immutable'; return; end;
  raise exception 'FAIL: was able to move a finalized check';
end $$;

-- set up check3 assigned to partner1 for the next two tests
set app.user_id = :ops;
insert into public.check_item(id,order_id,service_code) values (:check3,:order1,'C1-FD-01');
update public.check_item set assigned_partner_id=:partner1, state='assigned' where id=:check3;

set app.user_id = :partner1;
do $$ begin
  begin update public.check_item set state='finalized' where id='dd000000-0000-0000-0000-000000000003';
  exception when sqlstate '23514' then raise notice 'PASS: illegal transition assigned->finalized blocked'; return; end;
  raise exception 'FAIL: illegal transition assigned->finalized was allowed';
end $$;

update public.check_item set state='in_progress' where id=:check3;
update public.check_item set state='in_review'  where id=:check3;
do $$ begin
  begin update public.check_item set state='finalized' where id='dd000000-0000-0000-0000-000000000003';
  exception when sqlstate '23514' then raise notice 'PASS: partner cannot finalize (reviewer/ops only) — role gate holds'; return; end;
  raise exception 'FAIL: partner was allowed to finalize';
end $$;

-- reviewer legitimately finalizes check3 with a RED verdict, seals commitment c3 that supersedes c1
set app.user_id = :reviewer;
update public.check_item set state='finalized' where id=:check3;
insert into public.verdict(check_id,colour,explanation) values (:check3,'red','Competing claim discovered on the parcel.');
insert into public.commitment(id,check_id,content_hash,supersedes_id) values (:c3,:check3, repeat('c',64), :c1);
\echo 'reviewer: finalized check3 (RED) and sealed a superseding commitment'

\echo ''
\echo '################ PART 3 — append-only immutability (tested vs the BYPASS-RLS superuser) ################'
-- As superuser, RLS and grants do not apply — only the immutability TRIGGERS stand. If they
-- hold here, they hold against everyone.
reset role;
do $$ begin
  begin update public.audit_event set action='tampered' where true;
  exception when sqlstate '23514' then raise notice 'PASS: audit_event UPDATE blocked'; return; end;
  raise exception 'FAIL: audit_event was updatable'; end $$;
do $$ begin
  begin delete from public.audit_event where true;
  exception when sqlstate '23514' then raise notice 'PASS: audit_event DELETE blocked'; return; end;
  raise exception 'FAIL: audit_event was deletable'; end $$;
do $$ begin
  begin update public.evidence_item set content_hash='tampered' where true;
  exception when sqlstate '23514' then raise notice 'PASS: evidence_item UPDATE blocked'; return; end;
  raise exception 'FAIL: evidence_item was updatable'; end $$;
do $$ begin
  begin delete from public.verdict where true;
  exception when sqlstate '23514' then raise notice 'PASS: verdict DELETE blocked'; return; end;
  raise exception 'FAIL: verdict was deletable'; end $$;

\echo ''
\echo '################ PART 4 — government fee three-state ledger ################'
set role authenticated; set app.user_id = :ops;
insert into public.government_fee(id,order_id,check_id,process,amount_estimated)
  values (:fee1,:order1,:check1,'Lagos Lands Registry CTC fee',50000);
do $$ begin
  begin insert into public.government_fee_transition(government_fee_id,to_state) values ('ff000000-0000-0000-0000-000000000001','paid_with_receipt');
  exception when sqlstate '23514' then raise notice 'PASS: first state must be held (paid rejected as first)'; return; end;
  raise exception 'FAIL: allowed a non-held first state'; end $$;
insert into public.government_fee_transition(government_fee_id,to_state,amount) values (:fee1,'held',50000);
do $$ begin
  begin insert into public.government_fee_transition(government_fee_id,to_state,amount) values ('ff000000-0000-0000-0000-000000000001','paid_with_receipt',50000);
  exception when sqlstate '23514' then raise notice 'PASS: paid_with_receipt requires a receipt'; return; end;
  raise exception 'FAIL: allowed paid without a receipt'; end $$;
insert into public.government_fee_transition(government_fee_id,to_state,amount,receipt_evidence_id)
  values (:fee1,'paid_with_receipt',50000,:rcpt1);
do $$ begin
  begin insert into public.government_fee_transition(government_fee_id,to_state,amount) values ('ff000000-0000-0000-0000-000000000001','refunded',50000);
  exception when sqlstate '23514' then raise notice 'PASS: terminal state (paid) blocks further transitions'; return; end;
  raise exception 'FAIL: allowed transition out of a terminal state'; end $$;

insert into public.government_fee(id,order_id,check_id,process,amount_estimated)
  values (:fee2,:order1,:check2,'Court search fee',15000);
insert into public.government_fee_transition(government_fee_id,to_state,amount) values (:fee2,'held',15000);
insert into public.government_fee_transition(government_fee_id,to_state,amount,reason) values (:fee2,'refunded',15000,'Registry inaccessible; check closed Unresolved.');
reset role;
do $$
declare s1 public.gov_fee_state; s2 public.gov_fee_state;
begin
  select app.gov_fee_state('ff000000-0000-0000-0000-000000000001') into s1;
  select app.gov_fee_state('ff000000-0000-0000-0000-000000000002') into s2;
  if s1 <> 'paid_with_receipt' then raise exception 'FAIL: fee1 should be paid_with_receipt, got %', s1; end if;
  if s2 <> 'refunded' then raise exception 'FAIL: fee2 should be refunded, got %', s2; end if;
  raise notice 'PASS: derived fee states correct (fee1=paid_with_receipt, fee2=refunded); held history preserved';
end $$;
-- now that fee rows exist, prove the core fee row is immutable (vs bypass-RLS superuser)
do $$ begin
  begin update public.government_fee set process='tampered' where true;
  exception when sqlstate '23514' then raise notice 'PASS: government_fee core UPDATE blocked'; return; end;
  raise exception 'FAIL: government_fee core was updatable'; end $$;

\echo ''
\echo '################ PART 5 — proof-layer hash-chain ################'
reset role;
do $$
declare p1 text; p2 text; p3 text; h1 text; h2 text; sup uuid;
begin
  select prev_hash into p1 from public.commitment where id='c1000000-0000-0000-0000-000000000001';
  select prev_hash, content_hash into p2, h1 from public.commitment where id='c2000000-0000-0000-0000-000000000002';
  select prev_hash, supersedes_id into p3, sup from public.commitment where id='c3000000-0000-0000-0000-000000000003';
  select content_hash into h2 from public.commitment where id='c2000000-0000-0000-0000-000000000002';
  if p1 <> repeat('0',64) then raise exception 'FAIL: first commitment prev_hash must be genesis zeros, got %', p1; end if;
  if p2 <> repeat('a',64) then raise exception 'FAIL: c2.prev_hash must equal c1.content_hash, got %', p2; end if;
  if p3 <> repeat('b',64) then raise exception 'FAIL: c3.prev_hash must equal c2.content_hash, got %', p3; end if;
  if sup <> 'c1000000-0000-0000-0000-000000000001' then raise exception 'FAIL: c3 should supersede c1'; end if;
  raise notice 'PASS: chain links genesis -> c1 -> c2 -> c3; supersession recorded';
end $$;

-- integrity fields immutable; anchor batch fills exactly once
do $$ begin
  begin update public.commitment set content_hash=repeat('z',64) where id='c1000000-0000-0000-0000-000000000001';
  exception when sqlstate '23514' then raise notice 'PASS: commitment content_hash is immutable'; return; end;
  raise exception 'FAIL: commitment content_hash was mutable'; end $$;
do $$ begin
  begin delete from public.commitment where id='c1000000-0000-0000-0000-000000000001';
  exception when sqlstate '23514' then raise notice 'PASS: commitment DELETE blocked'; return; end;
  raise exception 'FAIL: commitment was deletable'; end $$;

insert into public.anchor_batch(id,batch_date,merkle_root,anchor_ref)
  values (:ab1, current_date, repeat('m',64), 'ots-proof://demo + mirror-log#1');
update public.commitment set batch_id=:ab1 where id=:c1;  -- null -> value: allowed once
\echo 'anchored c1 to a daily batch (one-way fill succeeded)'
do $$ begin
  begin update public.commitment set batch_id=null where id='c1000000-0000-0000-0000-000000000001';
  exception when sqlstate '23514' then raise notice 'PASS: anchor link cannot be changed once set'; return; end;
  raise exception 'FAIL: anchor batch link was mutable'; end $$;

\echo ''
\echo '################ PART 6 — Row-Level Security (tenant isolation + least privilege) ################'
-- client sees only their own order; the other client sees nothing of it
set role authenticated; set app.user_id = :client1;
do $$ declare n int; begin
  select count(*) into n from public.order_matter;
  if n <> 1 then raise exception 'FAIL: client1 should see exactly 1 order, saw %', n; end if;
  raise notice 'PASS: client1 sees only their own order (1)';
end $$;
set app.user_id = :client2;
do $$ declare n int; begin
  select count(*) into n from public.order_matter;
  if n <> 0 then raise exception 'FAIL: client2 must not see client1''s order, saw %', n; end if;
  raise notice 'PASS: client2 sees none of client1''s orders (0)';
end $$;

-- partner sees only assigned checks and related evidence; the other partner sees none
set app.user_id = :partner1;
do $$ declare nc int; ne int; begin
  select count(*) into nc from public.check_item;
  select count(*) into ne from public.evidence_item;
  if nc <> 3 then raise exception 'FAIL: partner1 should see 3 assigned checks, saw %', nc; end if;
  if ne <> 2 then raise exception 'FAIL: partner1 should see 2 evidence items on their checks, saw %', ne; end if;
  raise notice 'PASS: partner1 sees 3 assigned checks and their 2 evidence items';
end $$;
set app.user_id = :partner2;
do $$ declare nc int; ne int; begin
  select count(*) into nc from public.check_item;
  select count(*) into ne from public.evidence_item;
  if nc <> 0 then raise exception 'FAIL: partner2 has no assignments but saw % checks', nc; end if;
  if ne <> 0 then raise exception 'FAIL: partner2 saw % evidence items it should not', ne; end if;
  raise notice 'PASS: partner2 sees nothing (0 checks, 0 evidence) — isolation holds';
end $$;

-- audit visibility: staff see all; a client sees none (no actions of their own)
set app.user_id = :ops;
do $$ declare n int; begin select count(*) into n from public.audit_event;
  if n < 1 then raise exception 'FAIL: ops should see audit rows'; end if;
  raise notice 'PASS: ops (staff) sees the audit spine (% rows)', n; end $$;
set app.user_id = :client1;
do $$ declare n int; begin select count(*) into n from public.audit_event;
  if n <> 0 then raise exception 'FAIL: client should not see audit rows, saw %', n; end if;
  raise notice 'PASS: client sees no audit rows'; end $$;

-- least privilege on writes: a client cannot create checks or orders for others
do $$ begin
  begin insert into public.check_item(order_id,service_code) values ('cc000000-0000-0000-0000-000000000001','C1-LR-01');
  exception when sqlstate '42501' then raise notice 'PASS: client cannot insert a check (RLS)'; return; end;
  raise exception 'FAIL: client was allowed to insert a check'; end $$;
do $$ begin
  begin insert into public.order_matter(client_id,property_id) values ('77777777-7777-7777-7777-777777777777','aa000000-0000-0000-0000-000000000001');
  exception when sqlstate '42501' then raise notice 'PASS: client cannot create an order for another user (RLS)'; return; end;
  raise exception 'FAIL: client created an order for another user'; end $$;

-- evidence INDEX visibility (ratified refinement): the buyer sees the index of evidence on
-- their own checks (no raw-file pointer); the raw evidence table stays denied to the buyer.
set app.user_id = :client1;
do $$ declare nidx int; nraw int; begin
  select count(*) into nidx from public.evidence_index;
  select count(*) into nraw from public.evidence_item;
  if nidx <> 2 then raise exception 'FAIL: client1 should see 2 evidence-index rows, saw %', nidx; end if;
  if nraw <> 0 then raise exception 'FAIL: client1 must NOT read the raw evidence_item table, saw %', nraw; end if;
  raise notice 'PASS: client1 sees the evidence index (2) but not the raw evidence rows (0)';
end $$;
set app.user_id = :client2;
do $$ declare nidx int; begin
  select count(*) into nidx from public.evidence_index;
  if nidx <> 0 then raise exception 'FAIL: client2 should see no evidence index, saw %', nidx; end if;
  raise notice 'PASS: client2 sees no evidence index (0)';
end $$;
do $$ declare has_ref int; begin
  select count(*) into has_ref from information_schema.columns
   where table_schema='public' and table_name='evidence_index' and column_name='storage_ref';
  if has_ref <> 0 then raise exception 'FAIL: evidence_index must not expose storage_ref'; end if;
  raise notice 'PASS: evidence_index does not expose storage_ref (raw files stay protected)';
end $$;

reset role;
\echo ''
\echo '############################################################'
\echo '   ALL STAGE 1 ASSERTIONS PASSED'
\echo '############################################################'
