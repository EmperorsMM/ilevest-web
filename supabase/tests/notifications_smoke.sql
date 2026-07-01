-- ============================================================================
-- Notifications spine smoke test (self-contained; rolled back)
--   - order_received is enqueued when an order is created (status pending)
--   - enqueue is idempotent (one row per event+order) and validates the event
--   - verdict_ready fires ONLY when the last check of an order is sealed
--     (driven through the real seal_check), not before
--   - a buyer reads only their own notifications (RLS)
-- Run against a DB built from migrations.
-- ============================================================================
\set ON_ERROR_STOP on
begin;

insert into public.app_user(id, name, email_or_phone) values
  ('a0000000-0000-0000-0000-0000000000e1','Client E','e1@test'),
  ('a0000000-0000-0000-0000-0000000000e2','Reviewer E','e2@test'),
  ('a0000000-0000-0000-0000-0000000000e3','Other E','e3@test');
insert into public.user_role(user_id, role) values
  ('a0000000-0000-0000-0000-0000000000e1','client'),
  ('a0000000-0000-0000-0000-0000000000e2','reviewer'),
  ('a0000000-0000-0000-0000-0000000000e3','client');

-- 1) order_received on creation + idempotency + validation
do $$
declare oid uuid; n int;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000e1', true);
  oid := public.create_order('essential', null, 'Lagos', 'Eti-Osa', 'Ikoyi', null, 'LA', null);

  select count(*) into n from public.notification
   where event='order_received' and order_id=oid and user_id='a0000000-0000-0000-0000-0000000000e1' and status='pending';
  if n <> 1 then raise exception 'expected 1 order_received pending, got %', n; end if;

  -- idempotent: re-enqueue same event+order changes nothing
  perform app.enqueue_notification('a0000000-0000-0000-0000-0000000000e1','order_received', oid, '{}'::jsonb);
  select count(*) into n from public.notification where event='order_received' and order_id=oid;
  if n <> 1 then raise exception 'enqueue not idempotent: % rows', n; end if;

  -- bad event refused
  begin
    perform app.enqueue_notification('a0000000-0000-0000-0000-0000000000e1','launch_rockets', oid, '{}'::jsonb);
    raise exception 'FAIL: unknown event should be refused';
  exception when others then
    if sqlerrm not like '%unknown notification event%' then raise exception 'wrong error: %', sqlerrm; end if;
  end;

  -- null recipient is a no-op
  perform app.enqueue_notification(null,'order_received', oid, '{}'::jsonb);

  raise notice 'PASS: order_received enqueued on creation; enqueue idempotent + validated';
end $$;

-- 2) verdict_ready fires only when the LAST check is sealed
do $$
declare oid uuid;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000e1', true);
  oid := public.create_order('essential', null, 'Lagos', 'Ikeja', 'GRA', null, 'LA', null);

  -- seed two checks in 'in_review' so the reviewer can seal them (FSM guards off for the seed)
  execute 'alter table public.check_item disable trigger user';
  insert into public.check_item(id, order_id, service_code, state) values
    ('e1110000-0000-0000-0000-000000000001', oid, 'C1-LR-01', 'in_review'),
    ('e1110000-0000-0000-0000-000000000002', oid, 'C1-SG-02', 'in_review');
  execute 'alter table public.check_item enable trigger user';

  -- seal as the reviewer
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000e2', true);

  perform public.seal_check('e1110000-0000-0000-0000-000000000001', 'green', 'no issues');
  if exists (select 1 from public.notification where event='verdict_ready' and order_id=oid) then
    raise exception 'verdict_ready fired too early (only 1 of 2 sealed)';
  end if;

  perform public.seal_check('e1110000-0000-0000-0000-000000000002', 'red', 'pending suit found');
  if not exists (select 1 from public.notification where event='verdict_ready' and order_id=oid
                 and user_id='a0000000-0000-0000-0000-0000000000e1') then
    raise exception 'verdict_ready did not fire after the last check sealed';
  end if;

  raise notice 'PASS: verdict_ready fires only when the last check is sealed (for the order owner)';
end $$;

-- 3) RLS: a buyer reads only their own notifications
do $$
declare seen_own int; seen_other int;
begin
  set local role authenticated;

  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000e1', true);
  select count(*) into seen_own from public.notification;

  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000e3', true);
  select count(*) into seen_other from public.notification;

  reset role;

  if seen_own < 1 then raise exception 'owner should see their notifications, saw %', seen_own; end if;
  if seen_other <> 0 then raise exception 'a different client must see none, saw %', seen_other; end if;
  raise notice 'PASS: notifications are owner-scoped (owner sees %, other sees 0)', seen_own;
end $$;

rollback;
