-- =============================================================================
-- 0011  Client Portal — Stage 4 (part 1): the buyer read-model
-- =============================================================================
-- Read-only surface the portal renders. No new trust surface; RLS/ownership is the
-- boundary. Adds: a per-service price source (values are the team's to supply), a
-- quote that sums any selection (bundle or custom), a buyer-facing status projection
-- of the internal FSM, and the four buyer states the team named.
--   * prices seed empty (NULL) — the team supplies them as data; the quote coalesces to 0
--   * gov fees are shown as ESTIMATES; the itemised manual invoice fixes them (PRD 10.3)

-- ---- per-service price source (display / estimate; not the invoice) ----
alter table public.service_catalogue add column if not exists service_fee            numeric(12,2);
alter table public.service_catalogue add column if not exists government_fee_estimate numeric(12,2);
comment on column public.service_catalogue.service_fee is
  'Display service fee for this service (NGN). Non-refundable once work begins. Values supplied by the team; invoicing is manual at launch.';
comment on column public.service_catalogue.government_fee_estimate is
  'Zero-markup ESTIMATE of the official government fee(s) for this service (NGN). Fixed by the itemised invoice.';

-- ---- buyer-facing state projection (internal FSM -> the four buyer states) ----
create or replace function app.buyer_state(s public.check_state)
returns text language sql immutable as $$
  select case s
    when 'initiated'        then 'Assigned'
    when 'assigned'         then 'Assigned'
    when 'in_progress'      then 'In Progress'
    when 'returned_for_fix' then 'In Progress'
    when 'exception'        then 'In Progress'   -- being reviewed (flagged for design confirmation)
    when 'in_review'        then 'In Review'
    when 'finalized'        then 'Ready'
    when 'rejected'         then 'Ready'         -- terminal; carries an honest declined/Unresolved outcome
    else 'Assigned'
  end;
$$;
comment on function app.buyer_state(public.check_state) is
  'Projects the internal check FSM onto the four buyer-facing states: Assigned, In Progress, In Review, Ready.';

-- ---- quote: sum any selection of services into the two-part fee (anon-callable) ----
create or replace function public.quote_selection(p_codes text[])
returns jsonb
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select jsonb_build_object(
    'currency', 'NGN',
    'service_fee_total',             coalesce(sum(coalesce(sc.service_fee, 0)), 0),
    'government_fee_estimate_total', coalesce(sum(coalesce(sc.government_fee_estimate, 0)), 0),
    'lines', coalesce(jsonb_agg(jsonb_build_object(
        'service_code',            sc.code,
        'title',                   sc.title,
        'service_fee',             sc.service_fee,
        'government_fee_estimate', sc.government_fee_estimate
      ) order by sc.sort), '[]'::jsonb),
    'note', 'Government fees are zero-markup estimates and are fixed by the itemised invoice. The service fee is non-refundable once work begins.'
  )
  from public.service_catalogue sc
  where sc.code = any(p_codes) and sc.active;
$$;
comment on function public.quote_selection(text[]) is
  'Two-part fee for any selection of service codes (bundle or custom). Anon-callable so the fee shows during browsing.';

-- ---- buyer-facing order tracking (ownership-scoped projection) ----
create or replace function public.order_tracking(p_order uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare v jsonb;
begin
  -- ownership is the boundary: the buyer who owns it, or staff. Otherwise nothing is revealed.
  if not (app.owns_order(p_order) or app.is_staff()) then
    return jsonb_build_object('visible', false);
  end if;

  select jsonb_build_object(
    'visible',          true,
    'order_id',         o.id,
    'bundle',           o.bundle,
    'headline_verdict', app.order_headline_verdict(p_order),
    'ready',            (count(*) filter (where ci.state <> 'finalized') = 0 and count(*) > 0),
    'checks', coalesce(jsonb_agg(jsonb_build_object(
        'service_code', ci.service_code,
        'title',        sc.title,
        'status',       app.buyer_state(ci.state),
        'verdict',      vd.colour,
        'sealed_at',    ci.sealed_at
      ) order by sc.sort), '[]'::jsonb),
    'fees', (select jsonb_build_object('service_fee', p.service_fee,
                                       'government_fee_total', p.government_fee_total)
             from public.payment p where p.order_id = o.id)
  )
  into v
  from public.order_matter o
  left join public.check_item      ci on ci.order_id = o.id
  left join public.service_catalogue sc on sc.code   = ci.service_code
  left join public.verdict         vd on vd.check_id = ci.id
  where o.id = p_order
  group by o.id, o.bundle;

  return coalesce(v, jsonb_build_object('visible', true, 'order_id', p_order, 'checks', '[]'::jsonb, 'ready', false));
end;
$$;
comment on function public.order_tracking(uuid) is
  'Buyer-facing order status: per-check buyer state, the colour verdicts, the headline verdict, readiness, and the paid fees. Visible only to the owner or staff.';

-- ---- grants ----
grant execute on function public.quote_selection(text[]) to anon, authenticated, service_role;
grant execute on function public.order_tracking(uuid)    to authenticated, service_role;
