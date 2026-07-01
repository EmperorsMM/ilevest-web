-- ============================================================================
-- Order creation: create_order()
-- ----------------------------------------------------------------------------
-- Turns a buyer's selection (a bundle, or a custom set of checks) plus whatever
-- property details they chose to give into a real order: a property row (only
-- if anything was supplied), an order_matter owned by the caller, and one
-- order_line per selected service. fan_out reads order_line (never the bundle),
-- so the lines are the source of truth and are written here.
--
-- Intake never blocks (ruling): every property field is optional; a buyer can
-- create an order knowing only the bundle. No payment is created here — at
-- launch Ops issues the itemised invoice afterwards, so the new order shows as
-- "awaiting quote" on the dashboard until then.
--
-- SECURITY DEFINER (like the other write paths) but it only ever writes an order
-- owned by app.current_user_id(); an unauthenticated caller is refused.
-- ============================================================================

create or replace function public.create_order(
  p_bundle   text,
  p_services text[] default null,
  p_state    text   default null,
  p_lga      text   default null,
  p_locality text   default null,
  p_details  text   default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  uid      uuid := app.current_user_id();
  v_bundle order_bundle;
  v_codes  text[];
  v_prop   uuid;
  v_order  uuid;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  v_bundle := p_bundle::order_bundle;   -- raises if not a valid bundle value

  if v_bundle = 'ala_carte' then
    -- custom selection: de-duplicate the provided codes
    select array_agg(distinct c) into v_codes
    from unnest(coalesce(p_services, '{}'::text[])) as c;
  else
    -- named bundle: expand its locked composition
    select array_agg(service_code) into v_codes
    from public.bundle_service where bundle = v_bundle;
  end if;

  if v_codes is null or cardinality(v_codes) = 0 then
    raise exception 'no services selected';
  end if;

  -- every selected code must be a real catalogue service
  if exists (
    select 1 from unnest(v_codes) as c
    where not exists (select 1 from public.service_catalogue s where s.code = c)
  ) then
    raise exception 'unknown service code in selection';
  end if;

  -- property is created only if the buyer gave anything; otherwise the order
  -- simply has no property yet (intake never blocks).
  if coalesce(p_state, p_lga, p_locality, p_details) is not null then
    insert into public.property(state, lga, locality, identifying_details)
    values (
      nullif(btrim(p_state), ''),
      nullif(btrim(p_lga), ''),
      nullif(btrim(p_locality), ''),
      nullif(btrim(p_details), '')
    )
    returning id into v_prop;
  end if;

  insert into public.order_matter(client_id, property_id, bundle)
  values (uid, v_prop, v_bundle)
  returning id into v_order;

  insert into public.order_line(order_id, service_code)
  select v_order, c from unnest(v_codes) as c;

  perform app.write_audit(
    p_entity_type => 'order',
    p_entity_id   => v_order,
    p_action      => 'created',
    p_metadata    => jsonb_build_object('bundle', v_bundle, 'service_count', cardinality(v_codes))
  );

  return v_order;
end;
$$;

revoke all on function public.create_order(text, text[], text, text, text, text) from public;
grant execute on function public.create_order(text, text[], text, text, text, text) to authenticated;

comment on function public.create_order(text, text[], text, text, text, text) is
  'Creates an order owned by the caller from a bundle or custom selection plus optional property details. Intake never blocks; no payment is created (Ops invoices afterwards).';
