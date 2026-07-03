-- =============================================================================
-- worker_read_model_smoke.sql — Increment 2: my_checks() + check_workspace()
-- =============================================================================
-- Seed-based; fresh database with all migrations applied. Ids use the 77…
-- range so it can share a database with fulfilment_desk_smoke.sql.
-- =============================================================================
\set ON_ERROR_STOP on

reset role;
select set_config('app.user_id', '', false);

insert into public.app_user (id, name, email_or_phone) values
 ('77000000-0000-0000-0000-0000000000a1', 'WRM Client',   'wrm-a@test.ng'),
 ('77000000-0000-0000-0000-0000000000e1', 'WRM Worker 1', 'wrm-w1@test.ng'),
 ('77000000-0000-0000-0000-0000000000e2', 'WRM Worker 2', 'wrm-w2@test.ng'),
 ('77000000-0000-0000-0000-0000000000c1', 'WRM Ops',      'wrm-ops@test.ng'),
 ('77000000-0000-0000-0000-0000000000d1', 'WRM Reviewer', 'wrm-rev@test.ng')
on conflict do nothing;
insert into public.user_role (user_id, role) values
 ('77000000-0000-0000-0000-0000000000a1','client'),
 ('77000000-0000-0000-0000-0000000000e1','field_agent'),
 ('77000000-0000-0000-0000-0000000000e2','field_agent'),
 ('77000000-0000-0000-0000-0000000000c1','ops'),
 ('77000000-0000-0000-0000-0000000000d1','reviewer')
on conflict do nothing;

\set wclient  '''77000000-0000-0000-0000-0000000000a1'''
\set ww1      '''77000000-0000-0000-0000-0000000000e1'''
\set ww2      '''77000000-0000-0000-0000-0000000000e2'''
\set wops     '''77000000-0000-0000-0000-0000000000c1'''
\set wrev     '''77000000-0000-0000-0000-0000000000d1'''

-- an order with two checks; one assigned to each worker
set role authenticated; set app.user_id = :wclient;
select set_config('w.ord',
  public.create_order('ala_carte', array['C1-LR-01','C1-SG-02'], 'Lagos','Ikeja','Oregun','WRM plot',null,null)::text,
  false);
reset role; select set_config('app.user_id', '', false);
select public.fan_out_order(current_setting('w.ord')::uuid);
select set_config('w.k1',(select id::text from public.check_item where order_id=current_setting('w.ord')::uuid and service_code='C1-LR-01'),false);
select set_config('w.k2',(select id::text from public.check_item where order_id=current_setting('w.ord')::uuid and service_code='C1-SG-02'),false);

set role authenticated; set app.user_id = :wops;
select public.assign_check(current_setting('w.k1')::uuid, :ww1);
select public.assign_check(current_setting('w.k2')::uuid, :ww2);

-- worker 1 works k1 to review, reviewer returns it with a reason
set app.user_id = :ww1;
select public.start_check(current_setting('w.k1')::uuid);
select public.record_evidence(current_setting('w.k1')::uuid,'register_photo','h_wrm_photo','evidence/'||current_setting('w.k1')||'/reg.jpg');
select public.record_findings(current_setting('w.k1')::uuid,'WRM: register searched, chain consistent.');
select public.submit_for_review(current_setting('w.k1')::uuid);
set app.user_id = :wrev;
select public.return_for_fix(current_setting('w.k1')::uuid,'WRM: photograph the CTC endorsement page as well.');

-- ---------------------------------------------------------------------------
\echo '################ my_checks(): scoping + shape ################'
set app.user_id = :ww1;
do $$
declare v jsonb := public.my_checks(); r jsonb;
begin
  if jsonb_array_length(v) <> 1 then
    raise exception 'FAIL: worker 1 should see exactly their 1 check, saw %', jsonb_array_length(v);
  end if;
  r := v->0;
  if (r->>'check_id') is null or (r->>'title') is null or (r->>'state') <> 'returned_for_fix'
     or (r->>'property') not like '%Ikeja%'
     or (r->>'live_evidence')::int <> 2
     or not (r->>'has_findings')::boolean then
    raise exception 'FAIL: my_checks row shape wrong: %', r;
  end if;
  raise notice 'PASS: my_checks returns only the worker''s check, with title/state/property/counts';
end $$;

set app.user_id = :ww2;
do $$
declare v jsonb := public.my_checks();
begin
  if jsonb_array_length(v) <> 1 or (v->0->>'state') <> 'assigned' then
    raise exception 'FAIL: worker 2 should see exactly their 1 assigned check, got %', v;
  end if;
  raise notice 'PASS: caseloads are worker-scoped (worker 2 sees only their own)';
end $$;

set app.user_id = :wclient;
do $$
begin
  if jsonb_array_length(public.my_checks()) <> 0 then
    raise exception 'FAIL: a client has no worker caseload';
  end if;
  raise notice 'PASS: my_checks is empty for non-workers';
end $$;

-- ---------------------------------------------------------------------------
\echo '################ check_workspace(): the worker''s own check ################'
set app.user_id = :ww1;
do $$
declare v jsonb := public.check_workspace(current_setting('w.k1')::uuid);
begin
  if not (v->>'visible')::boolean then raise exception 'FAIL: workspace should be visible to the assigned worker'; end if;
  if not (v->>'i_am_worker')::boolean then raise exception 'FAIL: i_am_worker should be true'; end if;
  if (v->>'state') <> 'returned_for_fix' then raise exception 'FAIL: state should be returned_for_fix, got %', v->>'state'; end if;
  if (v->>'last_reason') not like 'WRM: photograph the CTC%' then
    raise exception 'FAIL: the return reason must reach the worker through the read model, got %', v->>'last_reason';
  end if;
  if jsonb_array_length(v->'evidence') <> 2 then raise exception 'FAIL: expected 2 evidence index rows'; end if;
  if (v->>'findings_text') not like 'WRM: register searched%' then raise exception 'FAIL: live findings text should be readable to its author'; end if;
  raise notice 'PASS: workspace carries context, evidence index, findings text and the return reason';
end $$;

-- the wall: another worker and the client get visible:false, nothing else
set app.user_id = :ww2;
do $$ begin
  if (public.check_workspace(current_setting('w.k1')::uuid)->>'visible')::boolean then
    raise exception 'FAIL: another worker must not see this workspace';
  end if;
  raise notice 'PASS: another worker is walled out (visible:false)';
end $$;
set app.user_id = :wclient;
do $$ begin
  if (public.check_workspace(current_setting('w.k1')::uuid)->>'visible')::boolean then
    raise exception 'FAIL: the buyer must not see the worker workspace';
  end if;
  raise notice 'PASS: the buyer is walled out (visible:false)';
end $$;

-- staff can look in (the Reviewer will need this surface in Increment 3)
set app.user_id = :wrev;
do $$
declare v jsonb := public.check_workspace(current_setting('w.k1')::uuid);
begin
  if not (v->>'visible')::boolean or (v->>'i_am_worker')::boolean then
    raise exception 'FAIL: staff should see the workspace with i_am_worker=false';
  end if;
  raise notice 'PASS: staff visibility works (i_am_worker=false)';
end $$;

reset role;
\echo ''
\echo 'ALL WORKER READ-MODEL ASSERTIONS PASSED'
