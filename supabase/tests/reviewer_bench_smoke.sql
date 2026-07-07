-- =============================================================================
-- reviewer_bench_smoke.sql — Increment 3: desk_queue() + amended check_workspace()
-- =============================================================================
-- Seed-based; ids use the 88… range so it can share a database with the other
-- desk suites. Run after fulfilment_desk_smoke and worker_read_model_smoke.
-- =============================================================================
\set ON_ERROR_STOP on

reset role;
select set_config('app.user_id', '', false);

insert into public.app_user (id, name, email_or_phone) values
 ('88000000-0000-0000-0000-0000000000a1', 'RB Client',   'rb-a@test.ng'),
 ('88000000-0000-0000-0000-0000000000e1', 'RB Worker',   'rb-w1@test.ng'),
 ('88000000-0000-0000-0000-0000000000c1', 'RB Ops',      'rb-ops@test.ng'),
 ('88000000-0000-0000-0000-0000000000d1', 'RB Reviewer', 'rb-rev@test.ng')
on conflict do nothing;
insert into public.user_role (user_id, role) values
 ('88000000-0000-0000-0000-0000000000a1','client'),
 ('88000000-0000-0000-0000-0000000000e1','field_agent'),
 ('88000000-0000-0000-0000-0000000000c1','ops'),
 ('88000000-0000-0000-0000-0000000000d1','reviewer')
on conflict do nothing;

\set rbclient '''88000000-0000-0000-0000-0000000000a1'''
\set rbw1     '''88000000-0000-0000-0000-0000000000e1'''
\set rbops    '''88000000-0000-0000-0000-0000000000c1'''
\set rbrev    '''88000000-0000-0000-0000-0000000000d1'''

-- an order with three checks: one left in intake, one driven to review,
-- one flagged as an exception
set role authenticated; set app.user_id = :rbclient;
select set_config('rb.ord',
  public.create_order('ala_carte', array['C1-LR-01','C1-SG-02','C1-CT-02'], 'Lagos','Ikeja','Agidingbi','RB plot',null,null)::text,
  false);
reset role; select set_config('app.user_id', '', false);
select public.fan_out_order(current_setting('rb.ord')::uuid);
select set_config('rb.k1',(select id::text from public.check_item where order_id=current_setting('rb.ord')::uuid and service_code='C1-LR-01'),false);
select set_config('rb.k2',(select id::text from public.check_item where order_id=current_setting('rb.ord')::uuid and service_code='C1-SG-02'),false);
-- C1-CT-02 stays in intake untouched

set role authenticated; set app.user_id = :rbops;
select public.assign_check(current_setting('rb.k1')::uuid, :rbw1);
select public.assign_check(current_setting('rb.k2')::uuid, :rbw1);
set app.user_id = :rbw1;
select public.start_check(current_setting('rb.k1')::uuid);
select public.record_evidence(current_setting('rb.k1')::uuid,'register_photo','h_rb_k1','evidence/'||current_setting('rb.k1')||'/reg.jpg');
select public.record_findings(current_setting('rb.k1')::uuid,'RB: register searched; chain clear.');
select public.submit_for_review(current_setting('rb.k1')::uuid);
select public.start_check(current_setting('rb.k2')::uuid);
select public.flag_exception(current_setting('rb.k2')::uuid,'RB: survey office closed for stock-taking.');

-- ---------------------------------------------------------------------------
\echo '################ desk_queue(): gate + the three piles ################'
set app.user_id = :rbclient;
do $$
declare v jsonb := public.desk_queue();
begin
  if (v->>'staff')::boolean then raise exception 'FAIL: a client is not desk staff'; end if;
  if jsonb_array_length(v->'intake') + jsonb_array_length(v->'in_review') + jsonb_array_length(v->'exceptions') <> 0 then
    raise exception 'FAIL: non-staff must see empty piles';
  end if;
  raise notice 'PASS: non-staff get staff:false and empty piles';
end $$;

set app.user_id = :rbrev;
do $$
declare v jsonb := public.desk_queue(); r jsonb;
begin
  if not (v->>'staff')::boolean then raise exception 'FAIL: reviewer is staff'; end if;
  if not exists (select 1 from jsonb_array_elements(v->'intake') x
                 where (x->>'check_id')::uuid in
                   (select id from public.check_item where order_id=current_setting('rb.ord')::uuid and state='initiated')) then
    raise exception 'FAIL: the untouched check must sit in intake';
  end if;
  select x into r from jsonb_array_elements(v->'in_review') x
   where (x->>'check_id') = current_setting('rb.k1') limit 1;
  if r is null then raise exception 'FAIL: k1 must sit in the in_review pile'; end if;
  if (r->>'worker') <> 'RB Worker' or (r->>'live_evidence')::int <> 2 or (r->>'title') is null then
    raise exception 'FAIL: in_review row shape wrong: %', r;
  end if;
  select x into r from jsonb_array_elements(v->'exceptions') x
   where (x->>'check_id') = current_setting('rb.k2') limit 1;
  if r is null then raise exception 'FAIL: k2 must sit in the exceptions pile'; end if;
  if (r->>'reason') not like 'RB: survey office closed%' or (r->>'retries')::int <> 0 then
    raise exception 'FAIL: exception row must carry the reason and retry count: %', r;
  end if;
  raise notice 'PASS: staff see intake / in_review / exceptions with worker, counts, reason';
end $$;

-- ---------------------------------------------------------------------------
\echo '################ check_workspace(): worker identity for the bench ################'
set app.user_id = :rbrev;
do $$
declare v jsonb := public.check_workspace(current_setting('rb.k1')::uuid);
begin
  if not (v->>'visible')::boolean or (v->>'i_am_worker')::boolean then
    raise exception 'FAIL: reviewer sees the workspace with i_am_worker=false';
  end if;
  if (v->'worker'->>'name') <> 'RB Worker' then
    raise exception 'FAIL: the bench must see who did the work, got %', v->'worker';
  end if;
  if (v->'evidence'->0->>'storage_ref') is null then
    raise exception 'FAIL: staff workspace must carry storage_ref for evidence viewing';
  end if;
  raise notice 'PASS: workspace names the worker and carries storage refs for review';
end $$;

-- retry count climbs with the audit spine (retry-first is visible)
set app.user_id = :rbops;
select public.retry_exception(current_setting('rb.k2')::uuid);
set app.user_id = :rbw1;
select public.flag_exception(current_setting('rb.k2')::uuid,'RB: second visit — still shut.');
set app.user_id = :rbrev;
do $$
declare r jsonb;
begin
  select x into r from jsonb_array_elements(public.desk_queue()->'exceptions') x
   where (x->>'check_id') = current_setting('rb.k2') limit 1;
  if (r->>'retries')::int <> 1 or (r->>'reason') not like 'RB: second visit%' then
    raise exception 'FAIL: retries must count from the audit spine and reason must be latest: %', r;
  end if;
  raise notice 'PASS: the exceptions pile shows retries=1 and the latest reason';
end $$;

reset role;
\echo ''
\echo 'ALL REVIEWER BENCH ASSERTIONS PASSED'
