-- =============================================================================
-- Ilevest — Build Stage 4 smoke test (Client Portal: buyer read-model)
-- =============================================================================
-- Run as SUPERUSER against a DB with ALL migrations applied. Proves the quote sums the
-- two-part fee (anon-callable), and the buyer order-tracking projection shows the right
-- buyer states + verdicts, readiness, and — critically — only to the owner or staff.
\set ON_ERROR_STOP on
set client_min_messages = notice;
set search_path = public, extensions, pg_temp;

\set ops      '''22222222-2222-2222-2222-222222222222'''
\set reviewer '''33333333-3333-3333-3333-333333333333'''
\set partner1 '''44444444-4444-4444-4444-444444444444'''
\set client1  '''66666666-6666-6666-6666-666666666666'''
\set client2  '''77777777-7777-7777-7777-777777777777'''

\echo ''
\echo '################ PART A — quote_selection (two-part fee, anon) ################'
-- known prices on three services to verify summation (real values are the team's to supply)
update public.service_catalogue set service_fee=25000, government_fee_estimate=10000 where code='C1-LR-01';
update public.service_catalogue set service_fee=15000, government_fee_estimate=0     where code='C1-LR-02';
update public.service_catalogue set service_fee=20000, government_fee_estimate=5000  where code='C1-LR-03';

set role anon;
select set_config('t.q', public.quote_selection(array['C1-LR-01','C1-LR-02','C1-LR-03'])::text, false);
do $$ declare q jsonb := current_setting('t.q')::jsonb; begin
  if (q->>'service_fee_total')::numeric <> 60000 then raise exception 'FAIL: service fee total should be 60000, got %', q->>'service_fee_total'; end if;
  if (q->>'government_fee_estimate_total')::numeric <> 15000 then raise exception 'FAIL: gov estimate total should be 15000, got %', q->>'government_fee_estimate_total'; end if;
  if jsonb_array_length(q->'lines') <> 3 then raise exception 'FAIL: quote should list 3 lines'; end if;
  raise notice 'PASS: quote sums the two-part fee across a custom selection (service 60000 + gov est 15000)';
end $$;
-- unknown codes are simply not priced, not an error
select set_config('t.q2', public.quote_selection(array['C1-LR-01','NOPE-99'])::text, false);
do $$ declare q jsonb := current_setting('t.q2')::jsonb; begin
  if jsonb_array_length(q->'lines') <> 1 then raise exception 'FAIL: only the known code should be quoted'; end if;
  if (q->>'service_fee_total')::numeric <> 25000 then raise exception 'FAIL: an unknown code must not add fee'; end if;
  raise notice 'PASS: unknown codes are ignored in the quote, not errored';
end $$;
reset role;

\echo ''
\echo '################ PART B — order_tracking (buyer status, ownership-scoped) ################'
reset role;
insert into public.app_user(id,name,email_or_phone) values
  ('22222222-2222-2222-2222-222222222222','Ops','o@x'),
  ('33333333-3333-3333-3333-333333333333','Reviewer','r@x'),
  ('44444444-4444-4444-4444-444444444444','Partner One','p1@x'),
  ('66666666-6666-6666-6666-666666666666','Client One','c1@x'),
  ('77777777-7777-7777-7777-777777777777','Client Two','c2@x');
insert into public.user_role(user_id,role) values
  ('22222222-2222-2222-2222-222222222222','ops'),
  ('33333333-3333-3333-3333-333333333333','reviewer'),
  ('44444444-4444-4444-4444-444444444444','partner'),
  ('66666666-6666-6666-6666-666666666666','client'),
  ('77777777-7777-7777-7777-777777777777','client');
set app.user_id = :ops;
insert into public.property(id,lga,state,locality) values ('aa000000-0000-0000-0000-0000000000e1','Eti-Osa','Lagos','Ikoyi');
insert into public.order_matter(id,client_id,property_id,bundle) values ('cc000000-0000-0000-0000-0000000000e1',:client1,'aa000000-0000-0000-0000-0000000000e1','ala_carte');
insert into public.order_line(order_id,service_code) values
  ('cc000000-0000-0000-0000-0000000000e1','C1-LR-01'),
  ('cc000000-0000-0000-0000-0000000000e1','C1-LR-02'),
  ('cc000000-0000-0000-0000-0000000000e1','C1-LR-03');
insert into public.payment(order_id,service_fee,government_fee_total) values ('cc000000-0000-0000-0000-0000000000e1', 60000, 15000);
reset role;
select public.confirm_payment('cc000000-0000-0000-0000-0000000000e1','ref_portal');

select set_config('t.c1',(select id::text from public.check_item where order_id='cc000000-0000-0000-0000-0000000000e1' and service_code='C1-LR-01'),false);
select set_config('t.c2',(select id::text from public.check_item where order_id='cc000000-0000-0000-0000-0000000000e1' and service_code='C1-LR-02'),false);

-- LR-01 -> sealed (Ready, green);  LR-02 -> in_progress (In Progress);  LR-03 -> left initiated (Assigned)
set app.user_id = :ops;      select public.assign_check(current_setting('t.c1')::uuid, :partner1);
set app.user_id = :partner1; update public.check_item set state='in_progress' where id=current_setting('t.c1')::uuid;
                             update public.check_item set state='in_review'  where id=current_setting('t.c1')::uuid;
set app.user_id = :reviewer; select public.seal_check(current_setting('t.c1')::uuid,'green','clear');
set app.user_id = :ops;      select public.assign_check(current_setting('t.c2')::uuid, :partner1);
set app.user_id = :partner1; update public.check_item set state='in_progress' where id=current_setting('t.c2')::uuid;
reset role;

-- the OWNER sees the full picture
set app.user_id = :client1;
select set_config('t.ot', public.order_tracking('cc000000-0000-0000-0000-0000000000e1')::text, false);
do $$ declare r jsonb := current_setting('t.ot')::jsonb; m jsonb; begin
  if not (r->>'visible')::boolean then raise exception 'FAIL: the owner should see the order'; end if;
  if (r->>'ready')::boolean then raise exception 'FAIL: not all checks finalized -> ready must be false'; end if;
  if jsonb_array_length(r->'checks') <> 3 then raise exception 'FAIL: should list 3 checks'; end if;
  select jsonb_object_agg(c->>'service_code', c->>'status') into m from jsonb_array_elements(r->'checks') c;
  if m->>'C1-LR-01' <> 'Ready'       then raise exception 'FAIL: LR-01 should read Ready, got %', m->>'C1-LR-01'; end if;
  if m->>'C1-LR-02' <> 'In Progress' then raise exception 'FAIL: LR-02 should read In Progress, got %', m->>'C1-LR-02'; end if;
  if m->>'C1-LR-03' <> 'Assigned'    then raise exception 'FAIL: LR-03 should read Assigned, got %', m->>'C1-LR-03'; end if;
  raise notice 'PASS: owner sees the buyer states (Ready / In Progress / Assigned) and ready=false';
end $$;
do $$ declare r jsonb := current_setting('t.ot')::jsonb; c jsonb; begin
  select cc into c from jsonb_array_elements(r->'checks') cc where cc->>'service_code'='C1-LR-01';
  if c->>'verdict' <> 'green' then raise exception 'FAIL: the sealed LR-01 should surface a green verdict'; end if;
  raise notice 'PASS: the sealed check surfaces its colour verdict to the buyer (green)';
end $$;
reset role;

-- a DIFFERENT client cannot see this order
set app.user_id = :client2;
select set_config('t.ot2', public.order_tracking('cc000000-0000-0000-0000-0000000000e1')::text, false);
do $$ declare r jsonb := current_setting('t.ot2')::jsonb; begin
  if (r->>'visible')::boolean then raise exception 'FAIL: a non-owner must NOT see the order'; end if;
  raise notice 'PASS: a different client cannot see someone else''s order (ownership boundary holds)';
end $$;
reset role;

-- staff CAN see it (for support)
set app.user_id = :ops;
select set_config('t.ot3', public.order_tracking('cc000000-0000-0000-0000-0000000000e1')::text, false);
do $$ declare r jsonb := current_setting('t.ot3')::jsonb; begin
  if not (r->>'visible')::boolean then raise exception 'FAIL: staff should see the order'; end if;
  raise notice 'PASS: staff can see the order';
end $$;
reset role;

\echo ''
\echo '################ ALL STAGE 4 ASSERTIONS PASSED ################'
