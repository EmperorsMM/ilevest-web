-- ============================================================================
-- my_orders() smoke test  (self-contained; wraps in a transaction and rolls back)
--   - owner sees only their own orders, with correct counts / paid / ready / verdict
--   - a different client sees only THEIR own order (never the first client's)
--   - an unauthenticated caller (no app.user_id) sees an empty list
-- Run against a DB already built from migrations.
-- ============================================================================
\set ON_ERROR_STOP on
begin;

-- ---------- seed ----------
insert into public.app_user(id, name, email_or_phone) values
  ('a0000000-0000-0000-0000-000000000001','Client A','a@test'),
  ('b0000000-0000-0000-0000-000000000002','Client B','b@test');
insert into public.user_role(user_id, role) values
  ('a0000000-0000-0000-0000-000000000001','client'),
  ('b0000000-0000-0000-0000-000000000002','client');

insert into public.property(id, lga, state, locality) values
  ('c0000000-0000-0000-0000-000000000001','Eti-Osa','Lagos','Ikoyi');

-- A has three orders: O1 in-progress (paid), O2 awaiting quote (no checks/payment), O3 complete (paid, RED)
insert into public.order_matter(id, client_id, property_id, bundle) values
  ('11110000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','complete'),
  ('22220000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','essential'),
  ('33330000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','inheritance');
-- B has one order — must never appear for A
insert into public.order_matter(id, client_id, property_id, bundle) values
  ('44440000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000001','essential');

-- States are seeded directly (this is a read-model test, not an FSM test): disable the
-- state-machine guards on these two tables for the seed only. FK constraints stay on.
alter table public.check_item disable trigger user;
alter table public.verdict     disable trigger user;

-- O1: three checks, two finalized (green), one still in progress
insert into public.check_item(id, order_id, service_code, state) values
  ('a1110000-0000-0000-0000-000000000001','11110000-0000-0000-0000-000000000001','C1-LR-01','finalized'),
  ('a1110000-0000-0000-0000-000000000002','11110000-0000-0000-0000-000000000001','C1-LR-02','finalized'),
  ('a1110000-0000-0000-0000-000000000003','11110000-0000-0000-0000-000000000001','C1-LR-03','in_progress');
insert into public.verdict(check_id, colour) values
  ('a1110000-0000-0000-0000-000000000001','green'),
  ('a1110000-0000-0000-0000-000000000002','green');

-- O3: two checks finalized, one RED one green -> headline RED, order ready
insert into public.check_item(id, order_id, service_code, state) values
  ('c3330000-0000-0000-0000-000000000001','33330000-0000-0000-0000-000000000003','C1-LR-01','finalized'),
  ('c3330000-0000-0000-0000-000000000002','33330000-0000-0000-0000-000000000003','C1-CT-02','finalized');
insert into public.verdict(check_id, colour) values
  ('c3330000-0000-0000-0000-000000000001','red'),
  ('c3330000-0000-0000-0000-000000000002','green');

alter table public.verdict     enable trigger user;
alter table public.check_item  enable trigger user;

-- payments: O1 and O3 paid; O2 not
insert into public.payment(order_id, currency, service_fee, government_fee_total, webhook_verified) values
  ('11110000-0000-0000-0000-000000000001','NGN',0,0,true),
  ('33330000-0000-0000-0000-000000000003','NGN',0,0,true);

-- ---------- assertions ----------
do $$
declare res jsonb; o1 jsonb; o2 jsonb; o3 jsonb;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-000000000001', true);
  res := public.my_orders();

  if jsonb_array_length(res) <> 3 then
    raise exception 'A should see 3 orders, saw %', jsonb_array_length(res);
  end if;

  select e into o1 from jsonb_array_elements(res) e where e->>'order_id'='11110000-0000-0000-0000-000000000001';
  select e into o2 from jsonb_array_elements(res) e where e->>'order_id'='22220000-0000-0000-0000-000000000002';
  select e into o3 from jsonb_array_elements(res) e where e->>'order_id'='33330000-0000-0000-0000-000000000003';

  -- O1 in progress
  if (o1->>'paid')::bool is not true        then raise exception 'O1 should be paid'; end if;
  if (o1->>'total_checks')::int <> 3        then raise exception 'O1 total_checks=%',(o1->>'total_checks'); end if;
  if (o1->>'ready_checks')::int <> 2        then raise exception 'O1 ready_checks=%',(o1->>'ready_checks'); end if;
  if (o1->>'ready')::bool is not false      then raise exception 'O1 ready should be false'; end if;

  -- O2 awaiting quote
  if (o2->>'paid')::bool is not false       then raise exception 'O2 should be unpaid'; end if;
  if (o2->>'total_checks')::int <> 0        then raise exception 'O2 should have 0 checks'; end if;
  if (o2->>'ready')::bool is not false      then raise exception 'O2 ready should be false'; end if;

  -- O3 complete, RED
  if (o3->>'ready')::bool is not true       then raise exception 'O3 ready should be true'; end if;
  if (o3->>'headline_verdict') <> 'red'     then raise exception 'O3 verdict should be red, got %',(o3->>'headline_verdict'); end if;
  if (o3->>'total_checks')::int <> 2 or (o3->>'ready_checks')::int <> 2 then raise exception 'O3 counts wrong'; end if;

  raise notice 'PASS: owner sees own 3 orders with correct paid/counts/ready/verdict';
end $$;

do $$
declare res jsonb;
begin
  perform set_config('app.user_id','b0000000-0000-0000-0000-000000000002', true);
  res := public.my_orders();
  if jsonb_array_length(res) <> 1 then
    raise exception 'B should see exactly 1 (their own), saw %', jsonb_array_length(res);
  end if;
  if (res->0->>'order_id') <> '44440000-0000-0000-0000-000000000004' then
    raise exception 'B is seeing the wrong order: %', (res->0->>'order_id');
  end if;
  raise notice 'PASS: a different client sees only their own order, never A''s';
end $$;

do $$
declare res jsonb;
begin
  perform set_config('app.user_id','', true);
  res := public.my_orders();
  if jsonb_array_length(res) <> 0 then
    raise exception 'no identity should see 0 orders, saw %', jsonb_array_length(res);
  end if;
  raise notice 'PASS: no identity -> empty list';
end $$;

rollback;
