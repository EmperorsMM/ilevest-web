-- ============================================================================
-- create_order() smoke test (self-contained; transaction rolled back at the end)
--   - a named bundle expands to its locked composition as order_line rows
--   - a custom (ala_carte) selection de-duplicates the chosen codes
--   - the new order is owned by the caller and appears on their dashboard
--     (my_orders) as awaiting-quote (unpaid, no checks yet)
--   - sparse intake works: an order with no property details still creates
--   - bad input is refused: empty custom selection, unknown code, no identity
-- Run against a DB already built from migrations.
-- ============================================================================
\set ON_ERROR_STOP on
begin;

insert into public.app_user(id, name, email_or_phone) values
  ('a0000000-0000-0000-0000-0000000000c1','Buyer','buyer@test');
insert into public.user_role(user_id, role) values
  ('a0000000-0000-0000-0000-0000000000c1','client');

-- ---------- 1) named bundle expands to its locked composition ----------
do $$
declare oid uuid; nlines int; expected int;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000c1', true);
  oid := public.create_order('complete', null, 'Lagos', 'Eti-Osa', 'Ikoyi', 'Plot 5, off Glover Road');

  select count(*) into nlines  from public.order_line   where order_id = oid;
  select count(*) into expected from public.bundle_service where bundle = 'complete';
  if nlines <> expected then raise exception 'complete bundle: % lines, expected %', nlines, expected; end if;

  -- owned by caller, bundle + property recorded
  perform 1 from public.order_matter o
    join public.property p on p.id = o.property_id
   where o.id = oid
     and o.client_id = 'a0000000-0000-0000-0000-0000000000c1'
     and o.bundle = 'complete'
     and p.state = 'Lagos' and p.locality = 'Ikoyi'
     and p.identifying_details = 'Plot 5, off Glover Road';
  if not found then raise exception 'order/property not recorded as expected'; end if;

  raise notice 'PASS: named bundle expands to % lines, owned by caller, property captured', nlines;
end $$;

-- ---------- 2) custom selection de-duplicates ----------
do $$
declare oid uuid; nlines int;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000c1', true);
  -- C1-LR-01 given twice on purpose
  oid := public.create_order('ala_carte', array['C1-LR-01','C1-SG-02','C1-LR-01'], 'Ogun', 'Abeokuta South', null, null);
  select count(*) into nlines from public.order_line where order_id = oid;
  if nlines <> 2 then raise exception 'custom de-dup: % lines, expected 2', nlines; end if;
  perform 1 from public.order_matter where id = oid and bundle = 'ala_carte';
  if not found then raise exception 'custom order should be bundle ala_carte'; end if;
  raise notice 'PASS: custom selection de-duplicated to 2 lines (ala_carte)';
end $$;

-- ---------- 3) appears on the caller's dashboard as awaiting-quote ----------
do $$
declare res jsonb; first jsonb;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000c1', true);
  res := public.my_orders();
  if jsonb_array_length(res) <> 2 then raise exception 'buyer should now see 2 orders, saw %', jsonb_array_length(res); end if;
  -- every order is unpaid with no checks yet (awaiting quote)
  perform 1 from jsonb_array_elements(res) e
    where (e->>'paid')::bool is true or (e->>'total_checks')::int <> 0;
  if found then raise exception 'new orders should be unpaid with 0 checks'; end if;
  raise notice 'PASS: new orders show on dashboard as awaiting-quote (unpaid, 0 checks)';
end $$;

-- ---------- 4) sparse intake: no property details at all ----------
do $$
declare oid uuid;
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000c1', true);
  oid := public.create_order('essential', null, null, null, null, null);
  perform 1 from public.order_matter where id = oid and property_id is null;
  if not found then raise exception 'sparse order should have null property_id'; end if;
  raise notice 'PASS: sparse intake creates an order with no property (never blocks)';
end $$;

-- ---------- 5) bad input is refused ----------
do $$
begin
  perform set_config('app.user_id','a0000000-0000-0000-0000-0000000000c1', true);

  begin
    perform public.create_order('ala_carte', '{}'::text[], null, null, null, null);
    raise exception 'FAIL: empty custom selection should have been refused';
  exception when others then
    if sqlerrm not like '%no services%' then raise exception 'wrong error for empty selection: %', sqlerrm; end if;
  end;

  begin
    perform public.create_order('ala_carte', array['C1-XX-99'], null, null, null, null);
    raise exception 'FAIL: unknown code should have been refused';
  exception when others then
    if sqlerrm not like '%unknown service code%' then raise exception 'wrong error for unknown code: %', sqlerrm; end if;
  end;

  raise notice 'PASS: empty selection and unknown code both refused';
end $$;

-- ---------- 6) no identity is refused ----------
do $$
begin
  perform set_config('app.user_id','', true);
  begin
    perform public.create_order('essential', null, null, null, null, null);
    raise exception 'FAIL: unauthenticated create_order should have been refused';
  exception when others then
    if sqlerrm not like '%not authenticated%' then raise exception 'wrong error for no identity: %', sqlerrm; end if;
  end;
  raise notice 'PASS: unauthenticated caller refused';
end $$;

rollback;
