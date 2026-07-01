-- ============================================================================
-- Order detail additions smoke test (self-contained; rolled back)
--   - create_order stores state_code, and creates+links a seller only when given
--   - order_tracking exposes check_id per check (the public verify handle),
--     plus property, seller, and created_at for the detail header
--   - a non-owner still sees { visible: false }
-- Run against a DB built from migrations.
-- ============================================================================
\set ON_ERROR_STOP on
begin;

insert into public.app_user(id, name, email_or_phone) values
  ('a0000000-0000-0000-0000-0000000000d1','Buyer D','d@test'),
  ('b0000000-0000-0000-0000-0000000000d2','Other D','o@test');
insert into public.user_role(user_id, role) values
  ('a0000000-0000-0000-0000-0000000000d1','client'),
  ('b0000000-0000-0000-0000-0000000000d2','client');

-- 1) with seller + state_code
do $$
declare oid uuid; t jsonb; pid uuid;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000d1', true);
  oid := public.create_order('essential', null, 'Lagos', 'Eti-Osa', 'Ikoyi', 'Plot 5', 'LA', 'Adebayo Holdings Ltd');

  select property_id into pid from public.order_matter where id = oid;
  perform 1 from public.property where id = pid and state_code = 'LA';
  if not found then raise exception 'state_code not stored'; end if;

  perform 1 from public.order_matter o join public.party_seller ps on ps.id = o.party_id
    where o.id = oid and ps.name = 'Adebayo Holdings Ltd';
  if not found then raise exception 'seller not created/linked'; end if;

  raise notice 'PASS: create_order stored state_code and linked the seller';
end $$;

-- 2) without seller -> no party linked
do $$
declare oid uuid;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000d1', true);
  oid := public.create_order('essential', null, 'Ogun', 'Abeokuta South', null, null, 'OG', null);
  perform 1 from public.order_matter where id = oid and party_id is null;
  if not found then raise exception 'order without seller should have null party_id'; end if;
  raise notice 'PASS: omitting the seller leaves party unset (never required)';
end $$;

-- 3) order_tracking enrichment: check_id present, property + seller in header
do $$
declare oid uuid; t jsonb; chk jsonb;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000d1', true);
  oid := public.create_order('essential', null, 'Lagos', 'Ikeja', 'GRA', null, 'LA', 'Mrs Okafor');

  -- seed one check directly so checks[] is non-empty (read-model test, FSM guards off)
  alter table public.check_item disable trigger user;
  insert into public.check_item(id, order_id, service_code, state, sealed_at)
  values ('d1110000-0000-0000-0000-000000000001', oid, 'C1-LR-01', 'finalized', now());
  alter table public.check_item enable trigger user;

  t := public.order_tracking(oid);
  if (t->>'visible')::bool is not true then raise exception 'owner should see order'; end if;
  if t->'property'->>'state_code' <> 'LA' then raise exception 'property.state_code missing in tracking'; end if;
  if t->>'seller' <> 'Mrs Okafor' then raise exception 'seller missing in tracking'; end if;
  if t->>'created_at' is null then raise exception 'created_at missing in tracking'; end if;

  select e into chk from jsonb_array_elements(t->'checks') e limit 1;
  if chk->>'check_id' <> 'd1110000-0000-0000-0000-000000000001' then
    raise exception 'check_id (public verify handle) missing from checks[]: %', chk;
  end if;

  raise notice 'PASS: order_tracking exposes check_id + property + seller + created_at to the owner';
end $$;

-- 4) non-owner sees nothing
do $$
declare oid uuid; t jsonb;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000d1', true);
  oid := public.create_order('essential', null, null, null, null, null, null, null);

  perform set_config('app.user_id','b0000000-0000-0000-0000-0000000000d2', true);
  t := public.order_tracking(oid);
  if (t->>'visible')::bool is not false then raise exception 'non-owner must not see the order'; end if;
  raise notice 'PASS: a different client sees { visible: false }';
end $$;

rollback;
