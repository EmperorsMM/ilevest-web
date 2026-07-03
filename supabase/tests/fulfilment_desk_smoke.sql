-- =============================================================================
-- fulfilment_desk_smoke.sql — Increment 1: the Fulfilment Desk, proven end to end
-- =============================================================================
-- Seed-based; run against a FRESH database with all migrations applied (like the
-- other suites). Every role-gated assertion executes as a real signed-in caller
-- via the portability shim (SET app.user_id + SET ROLE authenticated), never as
-- superuser — except the deliberate superuser tamper attempts, which prove the
-- trigger law holds against everyone.
--
-- Coverage (~152 executed assertions): the ratified FSM matrix by role
-- (assign/start/submit/return/exception/retry/escalate/seal/reject); the three
-- ceremony doors (finalized state, verdicts, commitments only via seal_check);
-- evidence capture law (assigned worker, working states only, findings carry
-- their own hash); pre-seal void markers + the frozen sealed-evidence manifest;
-- canonical-recipe stability (zero-void seals recompute under the ORIGINAL
-- recipe — already-anchored records stay verifiable); self-seal flagged OFF /
-- blocked ON (D1); retry-first escalation (D4); headline precedence (D5);
-- verdict_ready only on the last seal; cross-tenant RLS walls; authorship
-- stamps tamper-proof; reassignment audited and frozen after work begins.
-- =============================================================================


\set ON_ERROR_STOP on

-- ----------------------------------------------------------------
-- Harness
-- ----------------------------------------------------------------
create schema if not exists tests;

create table if not exists tests.tally (passed int not null default 0);
truncate tests.tally; insert into tests.tally values (0);

create or replace function tests.impersonate(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('app.user_id', p_uid::text, true);  -- the portability shim
  execute 'set local role authenticated';
end $$;

create or replace function tests.god() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('app.user_id', '', true);
end $$;

create or replace function tests.ok(p_cond boolean, p_label text) returns void language plpgsql as $$
begin
  if p_cond is true then
    update tests.tally set passed = passed + 1;
    raise notice 'ok - %', p_label;
  else
    raise exception 'FAIL - %', p_label;
  end if;
end $$;

create or replace function tests.throws(p_sql text, p_label text, p_msg text default null)
returns void language plpgsql as $$
declare v_err text;
begin
  begin
    execute p_sql;
  exception when others then
    v_err := sqlerrm;
  end;
  if v_err is null then
    raise exception 'FAIL (no error raised) - %', p_label;
  end if;
  if p_msg is not null and position(lower(p_msg) in lower(v_err)) = 0 then
    raise exception 'FAIL (wrong error) - % :: got [%], wanted substring [%]', p_label, v_err, p_msg;
  end if;
  update tests.tally set passed = passed + 1;
  raise notice 'ok - % (refused: %)', p_label, left(v_err, 80);
end $$;

create or replace function tests.lives(p_sql text, p_label text) returns void language plpgsql as $$
begin
  execute p_sql;
  update tests.tally set passed = passed + 1;
  raise notice 'ok - %', p_label;
end $$;

grant usage on schema tests to public;
grant execute on all functions in schema tests to public;
grant select, update on tests.tally to public;

-- A full happy-path ceremony helper: assign → start → evidence+findings → submit → seal
create or replace function tests.run_to_sealed(p_check uuid, p_worker uuid, p_ops uuid, p_rev uuid, p_colour verdict_colour)
returns void language plpgsql as $$
begin
  perform tests.impersonate(p_ops);
  perform public.assign_check(p_check, p_worker);
  perform tests.impersonate(p_worker);
  perform public.start_check(p_check);
  perform public.record_evidence(p_check, 'register_photo', md5(p_check::text || 'ev'), 'sandbox://' || p_check);
  perform public.record_findings(p_check, 'Ceremony findings for check ' || p_check);
  perform public.submit_for_review(p_check);
  perform tests.impersonate(p_rev);
  perform public.seal_check(p_check, p_colour, 'Sealed ' || p_colour || ' in ceremony test for ' || p_check);
  perform tests.god();
end $$;
grant execute on function tests.run_to_sealed(uuid, uuid, uuid, uuid, verdict_colour) to public;

-- ----------------------------------------------------------------
-- Fixtures (as postgres): people, roles, orders, checks
-- ----------------------------------------------------------------
begin;
select tests.god();

insert into public.app_user (id, name, email_or_phone) values
 ('00000000-0000-0000-0000-0000000000a1', 'Client A',  'a@test.ng'),
 ('00000000-0000-0000-0000-0000000000b1', 'Client B',  'b@test.ng'),
 ('00000000-0000-0000-0000-0000000000e1', 'Worker One','w1@test.ng'),
 ('00000000-0000-0000-0000-0000000000e2', 'Worker Two','w2@test.ng'),
 ('00000000-0000-0000-0000-0000000000e3', 'Partner P', 'p@test.ng'),
 ('00000000-0000-0000-0000-0000000000c1', 'Ops O',     'ops@test.ng'),
 ('00000000-0000-0000-0000-0000000000d1', 'Reviewer R','rev@test.ng'),
 ('00000000-0000-0000-0000-0000000000f1', 'Admin ADM', 'adm@test.ng'),
 ('00000000-0000-0000-0000-000000000051', 'Solo Launch Human', 'solo@test.ng');

insert into public.user_role (user_id, role) values
 ('00000000-0000-0000-0000-0000000000a1','client'),
 ('00000000-0000-0000-0000-0000000000b1','client'),
 ('00000000-0000-0000-0000-0000000000e1','field_agent'),
 ('00000000-0000-0000-0000-0000000000e2','field_agent'),
 ('00000000-0000-0000-0000-0000000000e3','partner'),
 ('00000000-0000-0000-0000-0000000000c1','ops'),
 ('00000000-0000-0000-0000-0000000000d1','reviewer'),
 ('00000000-0000-0000-0000-0000000000f1','admin'),
 ('00000000-0000-0000-0000-000000000051','ops'),
 ('00000000-0000-0000-0000-000000000051','reviewer'),
 ('00000000-0000-0000-0000-000000000051','field_agent');

commit;

-- shorthand psql vars
\set cl_a  '''00000000-0000-0000-0000-0000000000a1'''
\set cl_b  '''00000000-0000-0000-0000-0000000000b1'''
\set w1    '''00000000-0000-0000-0000-0000000000e1'''
\set w2    '''00000000-0000-0000-0000-0000000000e2'''
\set pr    '''00000000-0000-0000-0000-0000000000e3'''
\set ops   '''00000000-0000-0000-0000-0000000000c1'''
\set rev   '''00000000-0000-0000-0000-0000000000d1'''
\set adm   '''00000000-0000-0000-0000-0000000000f1'''
\set solo  '''00000000-0000-0000-0000-000000000051'''

-- Orders: main (complete, 7 checks) via the real client + payment path
begin;
select tests.impersonate(:cl_a);
create temporary table t_ord on commit drop as
  select public.create_order('complete', null, 'Lagos', 'Eti-Osa', 'Lekki', 'Block 4, Plot 21', 'LA', 'Chief Seller & Sons') as id;
select tests.god();
insert into public.payment(order_id, service_fee) select id, 100000 from t_ord;
select public.confirm_payment((select id from t_ord), 'PSK-TEST-0001');
create table if not exists tests.refs (name text primary key, id uuid);
insert into tests.refs select 'ord_main', id from t_ord;
commit;

begin;
select tests.god();
-- cross-tenant order for client B (essential, 2 checks)
select tests.impersonate(:cl_b);
create temporary table t_ordb on commit drop as
  select public.create_order('essential', null, 'Lagos', 'Ikeja', 'Ogba', 'Plot 2', 'LA', null) as id;
select tests.god();
select public.fan_out_order((select id from t_ordb));
insert into tests.refs select 'ord_b', id from t_ordb;

-- mini orders for headline combos + self-seal + exception, client A, ala_carte 2 services
select tests.impersonate(:cl_a);
create temporary table t_minis on commit drop as
select public.create_order('ala_carte', array['C1-LR-01','C1-SG-02'], 'Lagos','Ikeja','Alausa','m1',null,null) as m1,
       public.create_order('ala_carte', array['C1-LR-01','C1-SG-02'], 'Lagos','Ikeja','Alausa','m2',null,null) as m2,
       public.create_order('ala_carte', array['C1-LR-01','C1-SG-02'], 'Lagos','Ikeja','Alausa','m3',null,null) as m3,
       public.create_order('ala_carte', array['C1-LR-01','C1-SG-02'], 'Lagos','Ikeja','Alausa','m4',null,null) as m4,
       public.create_order('ala_carte', array['C1-LR-01','C1-SG-02'], 'Lagos','Ikeja','Alausa','solo',null,null) as ms,
       public.create_order('ala_carte', array['C1-LR-01','C1-SG-02'], 'Lagos','Ikeja','Alausa','exc',null,null)  as me;
select tests.god();
select public.fan_out_order(m1), public.fan_out_order(m2), public.fan_out_order(m3),
       public.fan_out_order(m4), public.fan_out_order(ms), public.fan_out_order(me) from t_minis;
insert into tests.refs select 'm1', m1 from t_minis;
insert into tests.refs select 'm2', m2 from t_minis;
insert into tests.refs select 'm3', m3 from t_minis;
insert into tests.refs select 'm4', m4 from t_minis;
insert into tests.refs select 'ms', ms from t_minis;
insert into tests.refs select 'me', me from t_minis;

-- name the seven main checks c1..c7 (stable order by service_code)
insert into tests.refs
select 'c' || row_number() over (order by service_code), id
from public.check_item where order_id = (select id from tests.refs where name='ord_main');

-- name mini checks
insert into tests.refs select 'm1a', id from public.check_item where order_id=(select id from tests.refs where name='m1') and service_code='C1-LR-01';
insert into tests.refs select 'm1b', id from public.check_item where order_id=(select id from tests.refs where name='m1') and service_code='C1-SG-02';
insert into tests.refs select 'm2a', id from public.check_item where order_id=(select id from tests.refs where name='m2') and service_code='C1-LR-01';
insert into tests.refs select 'm2b', id from public.check_item where order_id=(select id from tests.refs where name='m2') and service_code='C1-SG-02';
insert into tests.refs select 'm3a', id from public.check_item where order_id=(select id from tests.refs where name='m3') and service_code='C1-LR-01';
insert into tests.refs select 'm3b', id from public.check_item where order_id=(select id from tests.refs where name='m3') and service_code='C1-SG-02';
insert into tests.refs select 'm4a', id from public.check_item where order_id=(select id from tests.refs where name='m4') and service_code='C1-LR-01';
insert into tests.refs select 'm4b', id from public.check_item where order_id=(select id from tests.refs where name='m4') and service_code='C1-SG-02';
insert into tests.refs select 'ms1', id from public.check_item where order_id=(select id from tests.refs where name='ms') and service_code='C1-LR-01';
insert into tests.refs select 'ms2', id from public.check_item where order_id=(select id from tests.refs where name='ms') and service_code='C1-SG-02';
insert into tests.refs select 'me1', id from public.check_item where order_id=(select id from tests.refs where name='me') and service_code='C1-LR-01';
insert into tests.refs select 'me2', id from public.check_item where order_id=(select id from tests.refs where name='me') and service_code='C1-SG-02';
grant select on tests.refs to public;
commit;

create or replace function tests.ref(p text) returns uuid language sql stable as
  $$ select id from tests.refs where name = p $$;
grant execute on function tests.ref(text) to public;

-- ================================================================
-- 1 · ASSIGNMENT — Ops only; worker must hold a worker role
-- ================================================================
begin;
select tests.ok((select count(*) from public.check_item where order_id = tests.ref('ord_main')) = 7,
                'fan-out created 7 checks for the complete bundle');

select tests.impersonate(:rev);
select tests.throws($$ select public.assign_check(tests.ref('c1'), '00000000-0000-0000-0000-0000000000e1') $$,
                    'Reviewer cannot assign a check', 'Only Ops');
select tests.impersonate(:adm);
select tests.throws($$ select public.assign_check(tests.ref('c1'), '00000000-0000-0000-0000-0000000000e1') $$,
                    'Admin cannot assign a check', 'Only Ops');
select tests.impersonate(:cl_a);
select tests.throws($$ select public.assign_check(tests.ref('c1'), '00000000-0000-0000-0000-0000000000e1') $$,
                    'Client cannot assign a check');
select tests.impersonate(:ops);
select tests.throws($$ select public.assign_check(tests.ref('c1'), '00000000-0000-0000-0000-0000000000a1') $$,
                    'Assigning to a non-worker (client) is refused', 'partner or field_agent');
select tests.lives($$ select public.assign_check(tests.ref('c1'), '00000000-0000-0000-0000-0000000000e1') $$,
                   'Ops assigns c1 to Worker One');
select tests.god();
select tests.ok((select state='assigned' and assigned_partner_id='00000000-0000-0000-0000-0000000000e1'
                 from public.check_item where id=tests.ref('c1')),
                'c1 is assigned to W1');
commit;

-- ================================================================
-- 2 · START — assigned worker only; Ops/Admin have no worker powers
-- ================================================================
begin;
select tests.impersonate(:w2);
select tests.throws($$ select public.start_check(tests.ref('c1')) $$,
                    'Unassigned worker cannot start c1 (invisible under RLS)');
select tests.impersonate(:adm);
select tests.throws($$ update public.check_item set state='in_progress' where id=tests.ref('c1') $$,
                    'Admin raw-update cannot start a check', 'assigned worker');
select tests.impersonate(:ops);
select tests.throws($$ update public.check_item set state='in_progress' where id=tests.ref('c1') $$,
                    'Ops raw-update cannot start a check', 'assigned worker');
select tests.impersonate(:w1);
select tests.lives($$ select public.start_check(tests.ref('c1')) $$, 'Assigned worker starts c1');
select tests.god();
select tests.ok((select state='in_progress' and worked_by='00000000-0000-0000-0000-0000000000e1'
                 from public.check_item where id=tests.ref('c1')),
                'c1 in progress; worked_by stamped to W1 by the system');
select tests.impersonate(:w1);
select tests.throws($$ update public.check_item set worked_by='00000000-0000-0000-0000-0000000000e2' where id=tests.ref('c1') $$,
                    'worked_by cannot be set by callers', 'recorded by the system');
select tests.god();
commit;

-- ================================================================
-- 3 · EVIDENCE — assigned worker only, only while being worked;
--     findings carry their text and its exact hash
-- ================================================================
begin;
select tests.impersonate(:w1);
select tests.lives($$ select public.record_evidence(tests.ref('c1'), 'register_photo', md5('c1-photo'), 'sandbox://c1/photo', 6.45, 3.39, 8.0) $$,
                   'W1 records file evidence on c1');
select tests.god();
select tests.ok((select captured_by='00000000-0000-0000-0000-0000000000e1' and capture_channel='web'
                 from public.evidence_item where check_id=tests.ref('c1') limit 1),
                'evidence signed by W1, channel=web');

-- state gate: c2 is still initiated
select tests.impersonate(:ops);
select tests.lives($$ select public.assign_check(tests.ref('c2'), '00000000-0000-0000-0000-0000000000e1') $$, 'Ops assigns c2 to W1');
select tests.impersonate(:w1);
select tests.throws($$ select public.record_evidence(tests.ref('c2'), 'note', md5('too-early')) $$,
                    'Evidence refused while check is merely assigned', 'being worked');

select tests.impersonate(:w2);
select tests.throws($$ select public.record_evidence(tests.ref('c1'), 'note', md5('w2')) $$,
                    'Non-assigned worker cannot capture on c1');
select tests.impersonate(:rev);
select tests.throws($$ select public.record_evidence(tests.ref('c1'), 'note', md5('rev')) $$,
                    'Reviewer cannot capture evidence');
select tests.impersonate(:adm);
select tests.throws($$ select public.record_evidence(tests.ref('c1'), 'note', md5('adm')) $$,
                    'Admin cannot capture evidence (blanket staff path removed)');
select tests.impersonate(:cl_a);
select tests.throws($$ select public.record_evidence(tests.ref('c1'), 'note', md5('cl')) $$,
                    'Client cannot capture evidence');

select tests.impersonate(:w1);
select tests.throws($$ select public.record_findings(tests.ref('c1'), '   ') $$,
                    'Empty findings refused', 'nothing found');
select tests.lives($$ select public.record_findings(tests.ref('c1'), 'Registry search complete. Title chain consistent 1998-2024. No encumbrance noted.') $$,
                   'W1 writes the findings summary');
select tests.god();
select tests.ok((select content_hash = encode(extensions.digest(body_text,'sha256'),'hex')
                 from public.evidence_item where check_id=tests.ref('c1') and kind='findings_summary'),
                'findings content_hash is the SHA-256 of the findings text');
select tests.impersonate(:w1);
select tests.throws($$ select public.record_findings(tests.ref('c1'), 'second findings') $$,
                    'A second live findings summary is refused', 'already exists');
select tests.throws($$ select public.record_evidence(tests.ref('c1'), 'note', md5('mismatch'), null, null, null, null, null, null, 'note', 'body that does not hash to that') $$,
                    'body_text with mismatched hash refused', 'SHA-256 of body_text');
select tests.throws($$ insert into public.evidence_item(check_id, kind, content_hash, captured_by)
                       values (tests.ref('c1'), 'note', md5('spoof'), '00000000-0000-0000-0000-0000000000e2') $$,
                    'captured_by cannot be spoofed to another person', 'signed by the person');
select tests.god();
commit;

-- ================================================================
-- 4 · VOID MARKERS — capturer-only, reasoned, pre-seal, once
-- ================================================================
begin;
select tests.impersonate(:w1);
select tests.lives($$ select public.record_evidence(tests.ref('c1'), 'register_photo', md5('c1-blurry'), 'sandbox://c1/blurry') $$,
                   'W1 records a second (blurry) photo on c1');
select tests.god();
insert into tests.refs
  select 'c1_blurry', id from public.evidence_item where check_id=tests.ref('c1') and content_hash=md5('c1-blurry');

select tests.impersonate(:w2);
select tests.throws($$ select public.void_evidence(tests.ref('c1_blurry'), 'not my item but trying') $$,
                    'Another worker cannot void W1''s evidence');
select tests.impersonate(:rev);
select tests.throws($$ select public.void_evidence(tests.ref('c1_blurry'), 'reviewer attempting void') $$,
                    'Reviewer cannot void evidence (returns the check instead)');
select tests.impersonate(:w1);
select tests.throws($$ select public.void_evidence(tests.ref('c1_blurry'), 'bad') $$,
                    'Void reason must be substantive (>= 5 chars)');
select tests.lives($$ select public.void_evidence(tests.ref('c1_blurry'), 'Photo out of focus; replaced with a clear capture.') $$,
                   'W1 voids their blurry photo with a reason');
select tests.throws($$ select public.void_evidence(tests.ref('c1_blurry'), 'voiding it a second time') $$,
                    'An item can be voided only once');
select tests.ok((select voided and void_reason like 'Photo out of focus%'
                 from public.evidence_index where id=tests.ref('c1_blurry')),
                'evidence_index shows the void marker and its reason');
select tests.god();
select tests.ok(exists(select 1 from public.audit_event
                       where action='evidence_voided' and entity_id=tests.ref('c1_blurry')
                         and check_id=tests.ref('c1')),
                'void is written to the audit spine');
commit;

-- ================================================================
-- 5 · SUBMIT — needs live evidence AND live findings; the trigger is
--     the law (raw updates obey it too)
-- ================================================================
begin;
-- c3: bare check — start then try to submit with nothing
select tests.impersonate(:ops);
select tests.lives($$ select public.assign_check(tests.ref('c3'), '00000000-0000-0000-0000-0000000000e1') $$, 'Ops assigns c3 to W1');
select tests.impersonate(:w1);
select tests.lives($$ select public.start_check(tests.ref('c3')) $$, 'W1 starts c3');
select tests.throws($$ select public.submit_for_review(tests.ref('c3')) $$,
                    'Submit with no evidence at all refused', 'at least one');
select tests.lives($$ select public.record_evidence(tests.ref('c3'), 'register_photo', md5('c3-photo')) $$, 'W1 adds a photo to c3');
select tests.throws($$ update public.check_item set state='in_review' where id=tests.ref('c3') $$,
                    'Raw submit without findings refused by the FSM itself', 'findings summary');
select tests.lives($$ select public.record_findings(tests.ref('c3'), 'Search returned two instruments; both consistent with sale to current holder.') $$,
                   'W1 writes findings on c3');
select tests.lives($$ select public.submit_for_review(tests.ref('c3')) $$, 'W1 submits c3 for review');
select tests.god();
select tests.ok((select state='in_review' from public.check_item where id=tests.ref('c3')), 'c3 is in review');
commit;

-- ================================================================
-- 6 · RETURN-FOR-FIX — Reviewer only, reason mandatory (even raw)
-- ================================================================
begin;
select tests.impersonate(:ops);
select tests.throws($$ select public.return_for_fix(tests.ref('c3'), 'ops trying to return this check') $$,
                    'Ops cannot return a check for fix', 'Only a Reviewer');
select tests.impersonate(:rev);
select tests.throws($$ update public.check_item set state='returned_for_fix' where id=tests.ref('c3') $$,
                    'Reviewer raw return without a reason refused', 'requires a reason');
select tests.lives($$ select public.return_for_fix(tests.ref('c3'), 'Second instrument needs the CTC page photographed.') $$,
                   'Reviewer returns c3 with an actionable reason');
select tests.god();
select tests.ok((select state='returned_for_fix' from public.check_item where id=tests.ref('c3')), 'c3 returned for fix');
select tests.ok(exists(select 1 from public.audit_event
                       where check_id=tests.ref('c3') and action='state_change'
                         and from_state='in_review' and to_state='returned_for_fix'
                         and reason like 'Second instrument%'),
                'the return reason is on the audit spine');
select tests.impersonate(:w1);
select tests.lives($$ select public.record_evidence(tests.ref('c3'), 'register_photo', md5('c3-ctc')) $$,
                   'W1 can add evidence while the check is returned for fix');
select tests.lives($$ select public.submit_for_review(tests.ref('c3')) $$, 'W1 resubmits c3');
select tests.god();
commit;

-- ================================================================
-- 7 · SEALING — the six-role matrix, the ceremony doors, the record
-- ================================================================
begin;
select tests.impersonate(:cl_a);
select tests.throws($$ select public.seal_check(tests.ref('c1'), 'green', 'client seal attempt') $$,
                    'Client cannot seal', 'Only a Reviewer');
select tests.impersonate(:pr);
select tests.throws($$ select public.seal_check(tests.ref('c1'), 'green', 'partner seal attempt') $$,
                    'Partner cannot seal', 'Only a Reviewer');
select tests.impersonate(:w1);
select tests.throws($$ select public.seal_check(tests.ref('c1'), 'green', 'worker seal attempt') $$,
                    'Field agent cannot seal', 'Only a Reviewer');
select tests.impersonate(:ops);
select tests.throws($$ select public.seal_check(tests.ref('c1'), 'green', 'ops seal attempt') $$,
                    'Ops cannot seal', 'Only a Reviewer');
select tests.impersonate(:adm);
select tests.throws($$ select public.seal_check(tests.ref('c1'), 'green', 'admin seal attempt') $$,
                    'Admin cannot seal', 'Only a Reviewer');

-- c1 is still in_progress: the ceremony refuses the wrong state
select tests.impersonate(:rev);
select tests.throws($$ select public.seal_check(tests.ref('c1'), 'green', 'sealed from the wrong state') $$,
                    'Sealing from in_progress refused', 'from review only');

-- bring c1 to review properly
select tests.impersonate(:w1);
select tests.lives($$ select public.submit_for_review(tests.ref('c1')) $$, 'W1 submits c1 for review');

-- the two doors: no raw finalize, no direct verdicts — even for a Reviewer
select tests.impersonate(:rev);
select tests.throws($$ update public.check_item set state='finalized' where id=tests.ref('c1') $$,
                    'Reviewer raw-update cannot finalize (only seal_check)', 'sealing ceremony');
select tests.throws($$ insert into public.verdict(check_id, colour, explanation) values (tests.ref('c1'), 'green', 'direct verdict') $$,
                    'Direct verdict insert refused (only seal_check)', 'sealing ceremony');
select tests.throws($$ insert into public.commitment(check_id, content_hash) values (tests.ref('c1'), repeat('f', 64)) $$,
                    'Direct commitment insert refused (only seal_check)', 'sealing ceremony');
select tests.throws($$ select public.seal_check(tests.ref('c1'), 'green', '   ') $$,
                    'Sealing without an explanation refused', 'explanation');

select tests.lives($$ select public.seal_check(tests.ref('c1'), 'green', 'Title chain verified end to end; no encumbrance found as at today.') $$,
                   'Reviewer seals c1 GREEN');
select tests.god();
select tests.ok((select state='finalized' and is_finalized and sealed_at is not null
                        and sealed_by='00000000-0000-0000-0000-0000000000d1'
                        and worked_by='00000000-0000-0000-0000-0000000000e1'
                 from public.check_item where id=tests.ref('c1')),
                'c1 finalized: sealed_by=Reviewer, worked_by=W1, sealed_at set');
select tests.ok((select colour='green' from public.verdict where check_id=tests.ref('c1')),
                'verdict row exists: green');
select tests.ok((select prev_hash = repeat('0',64) from public.commitment where check_id=tests.ref('c1')),
                'first commitment chains from the genesis hash');
select tests.ok(exists(select 1 from public.audit_event
                       where check_id=tests.ref('c1') and action='sealed'
                         and (metadata->>'self_seal')='false'),
                'sealed audit row records self_seal=false');
commit;

-- ================================================================
-- 8 · THE FINGERPRINT — manifest correctness + recipe stability
-- ================================================================
begin;
select tests.god();
-- manifest covers exactly the live (non-voided) items
select tests.ok(
  (select count(*) from public.sealed_evidence se
    join public.commitment c on c.id=se.commitment_id where c.check_id=tests.ref('c1'))
  = (select count(*) from public.evidence_item e
      left join public.evidence_void vv on vv.evidence_id=e.id
      where e.check_id=tests.ref('c1') and vv.evidence_id is null),
  'sealed manifest lists exactly the non-voided items');
select tests.ok(
  not exists (select 1 from public.sealed_evidence se
              join public.commitment c on c.id=se.commitment_id
              where c.check_id=tests.ref('c1') and se.evidence_id=tests.ref('c1_blurry')),
  'the voided photo is NOT in the sealed manifest');

-- independent recompute (new recipe, over non-voided set) == stored hash
select tests.ok(
  (select c.content_hash = encode(extensions.digest(
     c.check_id::text || '|' || ci.service_code || '|' || v.colour::text || '|' || coalesce(v.explanation,'') || '|' ||
     coalesce((select string_agg(e.content_hash, ',' order by e.id)
               from public.evidence_item e
               left join public.evidence_void vv on vv.evidence_id = e.id
               where e.check_id=c.check_id and vv.evidence_id is null), '') || '|' || ci.order_id::text,
     'sha256'),'hex')
   from public.commitment c
   join public.check_item ci on ci.id=c.check_id
   join public.verdict v on v.check_id=c.check_id
   where c.check_id=tests.ref('c1')),
  'independent recompute of the canonical content matches the stored fingerprint');

-- and the void genuinely changed the content: the OLD recipe (all rows,
-- voided included) must NOT match, proving exclusion is real
select tests.ok(
  (select c.content_hash <> encode(extensions.digest(
     c.check_id::text || '|' || ci.service_code || '|' || v.colour::text || '|' || coalesce(v.explanation,'') || '|' ||
     coalesce((select string_agg(e.content_hash, ',' order by e.id)
               from public.evidence_item e
               where e.check_id=c.check_id), '') || '|' || ci.order_id::text,
     'sha256'),'hex')
   from public.commitment c
   join public.check_item ci on ci.id=c.check_id
   join public.verdict v on v.check_id=c.check_id
   where c.check_id=tests.ref('c1')),
  'a hash over the voided-inclusive set differs — voids genuinely leave the record');

-- RECIPE STABILITY REGRESSION: on a check with zero voids the amended
-- recipe must be byte-identical to the original one (all-items agg).
select tests.run_to_sealed(tests.ref('m1a'), '00000000-0000-0000-0000-0000000000e1',
                           '00000000-0000-0000-0000-0000000000c1',
                           '00000000-0000-0000-0000-0000000000d1', 'green');
select tests.ok(
  (select c.content_hash = encode(extensions.digest(
     c.check_id::text || '|' || ci.service_code || '|' || v.colour::text || '|' || coalesce(v.explanation,'') || '|' ||
     coalesce((select string_agg(e.content_hash, ',' order by e.id)
               from public.evidence_item e where e.check_id=c.check_id), '') || '|' || ci.order_id::text,
     'sha256'),'hex')
   from public.commitment c
   join public.check_item ci on ci.id=c.check_id
   join public.verdict v on v.check_id=c.check_id
   where c.check_id=tests.ref('m1a')),
  'zero-void seal: ORIGINAL recipe recomputes to the SAME hash (already-anchored records stay verifiable)');
commit;

-- ================================================================
-- 9 · AFTER THE SEAL — permanent immutability, even for superuser
-- ================================================================
begin;
select tests.impersonate(:w1);
select tests.throws($$ select public.record_evidence(tests.ref('c1'), 'note', md5('post-seal')) $$,
                    'Evidence cannot be attached to a sealed check', 'sealed');
select tests.throws($$ select public.void_evidence((select e.id from public.evidence_item e where e.check_id=tests.ref('c1') and e.kind='findings_summary'), 'attempting a post-seal void') $$,
                    'Evidence cannot be voided after sealing');
select tests.impersonate(:adm);
select tests.throws($$ update public.check_item set state='in_review' where id=tests.ref('c1') $$,
                    'Admin cannot reopen a sealed check', 'immutable');
select tests.god();
select tests.throws($$ update public.check_item set state='in_review' where id=tests.ref('c1') $$,
                    'Even superuser cannot alter a sealed check (trigger law)', 'immutable');
select tests.throws($$ update public.verdict set colour='red' where check_id=tests.ref('c1') $$,
                    'Verdicts are append-only, even for superuser', 'append-only');
select tests.throws($$ update public.commitment set content_hash=md5('tamper') where check_id=tests.ref('c1') $$,
                    'Commitment fingerprints are immutable, even for superuser', 'immutable');
select tests.throws($$ delete from public.sealed_evidence where commitment_id in (select id from public.commitment where check_id=tests.ref('c1')) $$,
                    'The sealed manifest is append-only, even for superuser', 'append-only');
select tests.throws($$ delete from public.evidence_item where check_id=tests.ref('c1') $$,
                    'Evidence rows can never be deleted', 'append-only');
select tests.throws($$ insert into public.commitment(check_id, content_hash) values (tests.ref('b1'), repeat('e', 64)) $$,
                    'Even superuser cannot insert a commitment outside the ceremony', 'sealing ceremony');
commit;

begin;
select tests.impersonate(:w1);
select tests.throws($$ insert into public.audit_event(entity_type, action) values ('check','forged') $$,
                    'Signed-in users cannot write the audit spine directly');
select tests.god();
commit;

-- ================================================================
-- 10 · SELF-SEAL (Decision D1) — allowed and flagged today; the
--      structural block works the moment it is switched on
-- ================================================================
begin;
-- the launch human (ops+reviewer+field_agent) works and seals their own check
select tests.impersonate(:solo);
select tests.lives($$ select public.assign_check(tests.ref('ms1'), '00000000-0000-0000-0000-000000000051') $$,
                   'Solo (as Ops) assigns a check to themselves (they hold field_agent)');
select tests.lives($$ select public.start_check(tests.ref('ms1')) $$, 'Solo starts their own check');
select tests.lives($$ select public.record_evidence(tests.ref('ms1'), 'register_photo', md5('solo-1')) $$, 'Solo records evidence');
select tests.lives($$ select public.record_findings(tests.ref('ms1'), 'Solo-run search; chain verified at the registry counter.') $$, 'Solo writes findings');
select tests.lives($$ select public.submit_for_review(tests.ref('ms1')) $$, 'Solo submits their own check');
select tests.lives($$ select public.seal_check(tests.ref('ms1'), 'green', 'Solo ceremony: verified and sealed.') $$,
                   'Self-seal succeeds while the block is OFF (launch reality)');
select tests.god();
select tests.ok(exists(select 1 from public.audit_event
                       where check_id=tests.ref('ms1') and action='sealed'
                         and (metadata->>'self_seal')='true'),
                'self-seal is honestly flagged in the audit spine');

-- flip the guard on: config is admin-only
select tests.impersonate(:ops);
select tests.throws($$ select public.set_desk_config(true) $$, 'Ops cannot change desk config', 'Admin only');
select tests.impersonate(:cl_a);
select tests.throws($$ select public.get_desk_config() $$, 'Clients cannot read desk config', 'Staff only');
select tests.impersonate(:adm);
select tests.lives($$ select public.set_desk_config(true) $$, 'Admin switches block_self_seal ON');

-- solo works a second check and now cannot seal it
select tests.impersonate(:solo);
select tests.lives($$ select public.assign_check(tests.ref('ms2'), '00000000-0000-0000-0000-000000000051') $$, 'Solo assigns second check to self');
select tests.lives($$ select public.start_check(tests.ref('ms2')) $$, 'Solo starts second check');
select tests.lives($$ select public.record_evidence(tests.ref('ms2'), 'register_photo', md5('solo-2')) $$, 'Solo records evidence (2)');
select tests.lives($$ select public.record_findings(tests.ref('ms2'), 'Second solo check; survey plan authenticated.') $$, 'Solo writes findings (2)');
select tests.lives($$ select public.submit_for_review(tests.ref('ms2')) $$, 'Solo submits second check');
select tests.throws($$ select public.seal_check(tests.ref('ms2'), 'green', 'attempted self-seal under block') $$,
                    'Self-seal is structurally blocked when the switch is ON', 'Decision D1');
-- an independent Reviewer can still seal it
select tests.impersonate(:rev);
select tests.lives($$ select public.seal_check(tests.ref('ms2'), 'green', 'Independent review; verified.') $$,
                   'A different Reviewer seals the same check under the block');
select tests.impersonate(:adm);
select tests.lives($$ select public.set_desk_config(false) $$, 'Admin switches block_self_seal back OFF (launch posture)');
select tests.god();
commit;

-- ================================================================
-- 11 · EXCEPTIONS — reasoned, retry-first, honest Unresolved exit
-- ================================================================
begin;
select tests.impersonate(:ops);
select tests.lives($$ select public.assign_check(tests.ref('me1'), '00000000-0000-0000-0000-0000000000e1') $$, 'Ops assigns exception-path check to W1');
select tests.impersonate(:w1);
select tests.lives($$ select public.start_check(tests.ref('me1')) $$, 'W1 starts it');
select tests.lives($$ select public.record_evidence(tests.ref('me1'), 'note', md5('attempt-1'), null, null, null, null, null, null, 'Attempt notes') $$,
                   'W1 records the attempt');
select tests.throws($$ update public.check_item set state='exception' where id=tests.ref('me1') $$,
                    'Raw exception without a reason refused', 'requires a reason');
select tests.throws($$ select public.flag_exception(tests.ref('me1'), 'bad') $$,
                    'Exception with a token reason refused');
select tests.lives($$ select public.flag_exception(tests.ref('me1'), 'Registry counter closed for the week; records office flooded.') $$,
                   'W1 flags a reasoned exception');
select tests.god();
select tests.ok(exists(select 1 from public.audit_event where check_id=tests.ref('me1')
                        and action='state_change' and to_state='exception'
                        and reason like 'Registry counter closed%'),
                'exception reason is on the audit spine');

select tests.impersonate(:ops);
select tests.throws($$ select public.escalate_exception(tests.ref('me1'), 'skipping straight to unresolved') $$,
                    'Escalation before any retry refused (retry-first)', 'Retry first');
select tests.impersonate(:w1);
select tests.throws($$ select public.retry_exception(tests.ref('me1')) $$,
                    'Worker cannot retry an exception (Ops decision)', 'Only Ops');
select tests.impersonate(:rev);
select tests.throws($$ select public.retry_exception(tests.ref('me1')) $$,
                    'Reviewer cannot retry an exception', 'Only Ops');
select tests.impersonate(:ops);
select tests.lives($$ select public.retry_exception(tests.ref('me1')) $$, 'Ops sends the check back for a retry');
select tests.impersonate(:w1);
select tests.lives($$ select public.flag_exception(tests.ref('me1'), 'Second visit: office still closed, no ETA from staff.') $$,
                   'W1 flags the exception again after the retry');
select tests.impersonate(:ops);
select tests.lives($$ select public.escalate_exception(tests.ref('me1'), 'Two attempts made; recommending an honest Unresolved.') $$,
                   'Ops escalates after a real retry');
select tests.impersonate(:rev);
select tests.lives($$ select public.seal_check(tests.ref('me1'), 'unresolved', 'Registry inaccessible after two documented attempts; Unresolved as at today. Re-verification advised when the office reopens.') $$,
                   'Reviewer seals an honest UNRESOLVED');
select tests.god();
select tests.ok((select colour='unresolved' from public.verdict where check_id=tests.ref('me1')),
                'the Unresolved verdict is sealed like any other');
commit;

-- ================================================================
-- 12 · ROLLUP + THE VERDICT-READY EMAIL — only when the LAST check seals
-- ================================================================
begin;
select tests.god();
-- main order: c1 sealed green; c3 is in_review; c2 assigned; c4..c7 initiated.
-- Finish c3 (reviewer), then run c2, c4..c6 through the ceremony: after the
-- 6th of 7 there must still be NO verdict_ready; after the 7th, exactly one.
select tests.impersonate(:rev);
select tests.lives($$ select public.seal_check(tests.ref('c3'), 'green', 'CTC page verified on resubmission; consistent.') $$,
                   'Reviewer seals c3 after the fix');
select tests.god();
select tests.run_to_sealed(tests.ref('c2'), '00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','green');
select tests.run_to_sealed(tests.ref('c4'), '00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','green');
select tests.run_to_sealed(tests.ref('c5'), '00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','green');
select tests.run_to_sealed(tests.ref('c6'), '00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','green');
select tests.ok((select count(*) from public.check_item where order_id=tests.ref('ord_main') and state='finalized') = 6,
                'six of seven main checks are sealed');
select tests.ok(not exists(select 1 from public.notification where order_id=tests.ref('ord_main') and event='verdict_ready'),
                'NO verdict_ready email while one check is still open');
select tests.run_to_sealed(tests.ref('c7'), '00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','green');
select tests.ok((select count(*) from public.notification where order_id=tests.ref('ord_main') and event='verdict_ready') = 1,
                'exactly ONE verdict_ready email when the last check seals');
select app.enqueue_notification('00000000-0000-0000-0000-0000000000a1', 'verdict_ready', tests.ref('ord_main'));
select tests.ok((select count(*) from public.notification where order_id=tests.ref('ord_main') and event='verdict_ready') = 1,
                'verdict_ready enqueue is idempotent (unique per order)');
select tests.ok(not exists (select 1 from information_schema.columns
                            where table_name='evidence_index' and column_name='body_text'),
                'evidence_index structurally never carries findings text (hashes only)');
commit;

-- ================================================================
-- 13 · HEADLINE PRECEDENCE (Decision D5): RED > AMBER > UNRESOLVED > GREEN
-- ================================================================
begin;
select tests.god();
-- m1: (green [m1a already], green) -> green
select tests.run_to_sealed(tests.ref('m1b'), '00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','green');
-- m2: (amber, unresolved) -> amber
select tests.run_to_sealed(tests.ref('m2a'), '00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','amber');
select tests.run_to_sealed(tests.ref('m2b'), '00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','unresolved');
-- m3: (red, amber) -> red
select tests.run_to_sealed(tests.ref('m3a'), '00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','red');
select tests.run_to_sealed(tests.ref('m3b'), '00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','amber');
-- m4: (green, unresolved) -> unresolved
select tests.run_to_sealed(tests.ref('m4a'), '00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','green');
select tests.run_to_sealed(tests.ref('m4b'), '00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','unresolved');

select tests.ok(app.order_headline_verdict(tests.ref('m1')) = 'green',      'headline: all green -> GREEN');
select tests.ok(app.order_headline_verdict(tests.ref('m2')) = 'amber',      'headline: amber+unresolved -> AMBER');
select tests.ok(app.order_headline_verdict(tests.ref('m3')) = 'red',        'headline: red beats amber -> RED');
select tests.ok(app.order_headline_verdict(tests.ref('m4')) = 'unresolved', 'headline: green+unresolved -> UNRESOLVED');
select tests.ok(app.order_headline_verdict(tests.ref('ord_main')) = 'green','headline: main order all green -> GREEN');

-- buyer-language projections stay honest
select tests.ok(app.buyer_state('exception') = 'In Progress' and app.buyer_state('returned_for_fix') = 'In Progress'
                and app.buyer_state('rejected') = 'Ready' and app.buyer_state('finalized') = 'Ready',
                'buyer_state projections unchanged (exception reads In Progress)');
commit;

-- ================================================================
-- 14 · THE BUYER'S VIEW + THE PUBLIC CERTIFICATE
-- ================================================================
begin;
select tests.impersonate(:cl_a);
select tests.ok(((public.order_tracking(tests.ref('ord_main')))->>'ready')::boolean,
                'buyer sees the main order Ready');
select tests.ok((select bool_and(x->>'status' = 'Ready')
                 from jsonb_array_elements((public.order_tracking(tests.ref('ord_main')))->'checks') x),
                'every check reads Ready in buyer language');
select tests.ok(exists(select 1 from jsonb_array_elements(public.my_orders()) o
                       where (o->>'order_id')::uuid = tests.ref('ord_main')
                         and (o->>'ready')::boolean and o->>'headline_verdict' = 'green'),
                'my_orders shows ready + green headline');
select tests.ok((select count(*) from public.notification) >= 1
                and not exists (select 1 from public.notification n
                                where n.user_id <> '00000000-0000-0000-0000-0000000000a1'
                                  and n.order_id = tests.ref('ord_main')),
                'verdict_ready email is addressed to the right client only');

-- clients read fingerprints via the index, never raw evidence rows
select tests.ok((select count(*) from public.evidence_item where check_id=tests.ref('c1')) = 0,
                'raw evidence rows are invisible to the buyer (RLS)');
select tests.ok((select count(*) > 0 from public.evidence_index where check_id=tests.ref('c1')),
                'the buyer sees the evidence index (hashes + void flags) for their check');

select tests.god();
select tests.ok((select (verify_certificate->>'valid')::boolean
                        and verify_certificate->>'content_hash' is not null
                        and verify_certificate::text not like '%Client A%'
                        and (verify_certificate->'property'->>'lga') = 'Eti-Osa'
                 from public.verify_certificate(tests.ref('c1'))),
                'public certificate verifies and carries no personal names');
commit;

-- ================================================================
-- 15 · CROSS-TENANT WALLS
-- ================================================================
begin;
select tests.impersonate(:cl_b);
select tests.ok((select count(*) from public.check_item where order_id=tests.ref('ord_main')) = 0,
                'Client B sees none of Client A''s checks');
select tests.ok(not exists (select 1 from public.notification where order_id=tests.ref('ord_main')),
                'Client B sees none of Client A''s notifications');
select tests.impersonate(:w2);
select tests.ok((select count(*) from public.check_item where assigned_partner_id <> '00000000-0000-0000-0000-0000000000e2') = 0,
                'a worker sees only checks assigned to them');
select tests.impersonate(:w1);
select tests.ok(not exists (select 1 from public.evidence_item e
                            join public.check_item c on c.id=e.check_id
                            where c.assigned_partner_id='00000000-0000-0000-0000-0000000000e2'
                              and e.captured_by <> '00000000-0000-0000-0000-0000000000e1'),
                'W1 cannot read W2''s evidence on W2''s checks');
select tests.god();
commit;

-- ================================================================
-- 16 · ASSIGNMENT INTEGRITY — audited reassignment, frozen identity
-- ================================================================
begin;
-- ord_b's two checks are still initiated; use them
select tests.god();
insert into tests.refs select 'b1', id from public.check_item where order_id=tests.ref('ord_b') and service_code='C1-LR-01';
insert into tests.refs select 'b2', id from public.check_item where order_id=tests.ref('ord_b') and service_code='C1-SG-02';

select tests.impersonate(:ops);
select tests.lives($$ select public.assign_check(tests.ref('b1'), '00000000-0000-0000-0000-0000000000e1') $$, 'Ops assigns b1 to W1');
select tests.lives($$ select public.assign_check(tests.ref('b1'), '00000000-0000-0000-0000-0000000000e2') $$, 'Ops reassigns b1 to W2 before work starts');
select tests.god();
select tests.ok(exists(select 1 from public.audit_event
                       where check_id=tests.ref('b1') and action='assignment_changed'
                         and (metadata->>'to_worker')::uuid = '00000000-0000-0000-0000-0000000000e2'),
                'reassignment leaves an audit row');
select tests.impersonate(:w2);
select tests.lives($$ select public.start_check(tests.ref('b1')) $$, 'W2 starts the reassigned check');
select tests.impersonate(:ops);
select tests.throws($$ update public.check_item set assigned_partner_id='00000000-0000-0000-0000-0000000000e1' where id=tests.ref('b1') $$,
                    'Reassignment after work has begun is refused', 'not supported');
select tests.throws($$ update public.check_item set service_code='C1-LR-02' where id=tests.ref('b1') $$,
                    'service_code is frozen for the life of a check', 'fixed for the life');
select tests.throws($$ update public.check_item set order_id=tests.ref('ord_main') where id=tests.ref('b1') $$,
                    'order_id is frozen for the life of a check', 'fixed for the life');
select tests.lives($$ select public.assign_check(tests.ref('b2'), '00000000-0000-0000-0000-0000000000e1') $$, 'Ops assigns b2 to W1');
select tests.throws($$ update public.check_item set assigned_partner_id=null where id=tests.ref('b2') $$,
                    'Un-assigning an assigned check is refused (reassign instead)', 'not supported');
select tests.god();
commit;

-- ================================================================
-- 17 · REJECT — Reviewer-only gate (terminal path exists, unused by
--       any surface; Ops and Admin must not reach it)
-- ================================================================
begin;
select tests.impersonate(:w1);
select tests.lives($$ select public.start_check(tests.ref('b2')) $$, 'W1 starts b2');
select tests.lives($$ select public.record_evidence(tests.ref('b2'), 'note', md5('b2-note')) $$, 'W1 records evidence on b2');
select tests.lives($$ select public.record_findings(tests.ref('b2'), 'Findings for the reject-gate scenario.') $$, 'W1 writes findings on b2');
select tests.lives($$ select public.submit_for_review(tests.ref('b2')) $$, 'W1 submits b2');
select tests.impersonate(:ops);
select tests.throws($$ update public.check_item set state='rejected' where id=tests.ref('b2') $$,
                    'Ops cannot reject a check (Reviewer-only)', 'Only a Reviewer');
select tests.impersonate(:adm);
select tests.throws($$ update public.check_item set state='rejected' where id=tests.ref('b2') $$,
                    'Admin cannot reject a check', 'Only a Reviewer');
select tests.god();
commit;

-- ================================================================
-- Summary
-- ================================================================
select 'ASSERTIONS PASSED: ' || passed as result from tests.tally;
