-- ============================================================================
-- COMBINED for Supabase SQL Editor — Order detail additions
-- (state_code column, create_order seller+state_code, order_tracking enrichment)
-- Idempotent. Safe to run on the live project.
-- ============================================================================
begin;

-- ============================================================================
-- Order detail additions
--   1. property.state_code  — store the canonical state code (LA/OG/FC) for
--      clean routing and reporting (e.g. all orders in a state). Ratified.
--   2. create_order()       — accept an OPTIONAL seller name (feeds the
--      Corporate Seller / Identity checks when present, blocks nothing when
--      absent) and the state_code. Seller is stored as a party_seller linked to
--      the order; never required.
--   3. order_tracking()     — enrich for the buyer's detail view: add per-check
--      check_id (the public verification handle), plus property, seller, and
--      created_at for the header. Still owner/staff-scoped; the public
--      certificate (verify_certificate) continues to expose no PII.
-- ============================================================================

-- 1) state_code ---------------------------------------------------------------
alter table public.property add column if not exists state_code text;
comment on column public.property.state_code is 'Canonical state code (e.g. LA, OG, FC) from the location reference, for routing/reporting.';

-- 2) create_order: optional seller + state_code -------------------------------
-- Replace the previous signature (added params would otherwise create an
-- ambiguous overload for named-argument calls).
drop function if exists public.create_order(text, text[], text, text, text, text);

create or replace function public.create_order(
  p_bundle     text,
  p_services   text[] default null,
  p_state      text   default null,
  p_lga        text   default null,
  p_locality   text   default null,
  p_details    text   default null,
  p_state_code text   default null,
  p_seller     text   default null
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
  v_party  uuid;
  v_order  uuid;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  v_bundle := p_bundle::order_bundle;

  if v_bundle = 'ala_carte' then
    select array_agg(distinct c) into v_codes
    from unnest(coalesce(p_services, '{}'::text[])) as c;
  else
    select array_agg(service_code) into v_codes
    from public.bundle_service where bundle = v_bundle;
  end if;

  if v_codes is null or cardinality(v_codes) = 0 then
    raise exception 'no services selected';
  end if;

  if exists (
    select 1 from unnest(v_codes) as c
    where not exists (select 1 from public.service_catalogue s where s.code = c)
  ) then
    raise exception 'unknown service code in selection';
  end if;

  if coalesce(p_state, p_state_code, p_lga, p_locality, p_details) is not null then
    insert into public.property(state, state_code, lga, locality, identifying_details)
    values (
      nullif(btrim(p_state), ''),
      nullif(btrim(p_state_code), ''),
      nullif(btrim(p_lga), ''),
      nullif(btrim(p_locality), ''),
      nullif(btrim(p_details), '')
    )
    returning id into v_prop;
  end if;

  -- optional seller: only when a name was given (never required)
  if nullif(btrim(p_seller), '') is not null then
    insert into public.party_seller(name) values (btrim(p_seller)) returning id into v_party;
  end if;

  insert into public.order_matter(client_id, property_id, party_id, bundle)
  values (uid, v_prop, v_party, v_bundle)
  returning id into v_order;

  insert into public.order_line(order_id, service_code)
  select v_order, c from unnest(v_codes) as c;

  perform app.write_audit(
    p_entity_type => 'order',
    p_entity_id   => v_order,
    p_action      => 'created',
    p_metadata    => jsonb_build_object('bundle', v_bundle, 'service_count', cardinality(v_codes), 'has_seller', v_party is not null)
  );

  return v_order;
end;
$$;

revoke all on function public.create_order(text, text[], text, text, text, text, text, text) from public;
grant execute on function public.create_order(text, text[], text, text, text, text, text, text) to authenticated;

comment on function public.create_order(text, text[], text, text, text, text, text, text) is
  'Creates an order owned by the caller from a bundle or custom selection plus optional property + optional seller. Intake never blocks; no payment is created.';

-- 3) order_tracking: enrich for the detail view -------------------------------
create or replace function public.order_tracking(p_order uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare v jsonb;
begin
  if not (app.owns_order(p_order) or app.is_staff()) then
    return jsonb_build_object('visible', false);
  end if;

  select jsonb_build_object(
    'visible',          true,
    'order_id',         o.id,
    'bundle',           o.bundle,
    'created_at',       o.created_at,
    'property', (select jsonb_build_object(
                   'state', p.state, 'state_code', p.state_code,
                   'lga', p.lga, 'locality', p.locality,
                   'identifying_details', p.identifying_details)
                 from public.property p where p.id = o.property_id),
    'seller',  (select ps.name from public.party_seller ps where ps.id = o.party_id),
    'headline_verdict', app.order_headline_verdict(p_order),
    'ready',            (count(*) filter (where ci.state <> 'finalized') = 0 and count(*) > 0),
    'checks', coalesce(jsonb_agg(jsonb_build_object(
        'check_id',     ci.id,
        'service_code', ci.service_code,
        'title',        sc.title,
        'status',       app.buyer_state(ci.state),
        'verdict',      vd.colour,
        'sealed_at',    ci.sealed_at
      ) order by sc.sort) filter (where ci.id is not null), '[]'::jsonb),
    'documents', coalesce((select jsonb_agg(jsonb_build_object(
        'label', bd.label, 'doc_type', bd.doc_type, 'uploaded_at', bd.uploaded_at
      ) order by bd.uploaded_at) from public.buyer_document bd where bd.order_id = o.id), '[]'::jsonb),
    'fees', (select jsonb_build_object('service_fee', p.service_fee,
                                       'government_fee_total', p.government_fee_total)
             from public.payment p where p.order_id = o.id)
  )
  into v
  from public.order_matter o
  left join public.check_item        ci on ci.order_id = o.id
  left join public.service_catalogue sc on sc.code    = ci.service_code
  left join public.verdict           vd on vd.check_id = ci.id
  where o.id = p_order
  group by o.id, o.bundle, o.created_at, o.property_id, o.party_id;

  return coalesce(v, jsonb_build_object('visible', true, 'order_id', p_order, 'checks', '[]'::jsonb, 'documents', '[]'::jsonb, 'ready', false));
end;
$$;

commit;
