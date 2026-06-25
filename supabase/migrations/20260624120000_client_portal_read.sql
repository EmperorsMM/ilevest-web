-- =============================================================================
-- 0011  Client Portal — Stage 4 (part 1): buyer read-model + buyer documents
-- =============================================================================
-- Revised per design rulings: NO stored prices. The portal shows no prices at selection;
-- a selection routes to Ops, who issues an individually itemised invoice for that specific
-- request (real government fees vary by LGA / district / property type). So there is no
-- stored price column and no quote here. What this adds:
--   * buyer-facing status projection (internal FSM -> the four buyer states) + verdicts
--   * a buyer-document store: clients may proceed with ZERO documents (never blocked) but
--     are encouraged to upload; a per-service "typically needed" checklist drives that
-- RLS/ownership is the boundary throughout.

-- ---- undo the earlier priced approach, if it was ever applied (idempotent) ----
drop function if exists public.quote_selection(text[]);
alter table public.service_catalogue drop column if exists service_fee;
alter table public.service_catalogue drop column if exists government_fee_estimate;

-- ---- buyer-facing state projection (internal FSM -> the four buyer states) ----
create or replace function app.buyer_state(s public.check_state)
returns text language sql immutable as $$
  select case s
    when 'initiated'        then 'Assigned'
    when 'assigned'         then 'Assigned'
    when 'in_progress'      then 'In Progress'
    when 'returned_for_fix' then 'In Progress'
    when 'exception'        then 'In Progress'   -- being reviewed (quiet note), per ruling
    when 'in_review'        then 'In Review'
    when 'finalized'        then 'Ready'
    when 'rejected'         then 'Ready'         -- terminal; honest declined / Unresolved outcome
    else 'Assigned'
  end;
$$;
comment on function app.buyer_state(public.check_state) is
  'Projects the internal check FSM onto the four buyer-facing states: Assigned, In Progress, In Review, Ready.';

-- ---- per-service "documents typically needed" checklist (reference data) ----
-- Drives encouragement, never enforcement. The real per-service list is supplied by the team
-- (drafted from the Service Catalogue client inputs); seeded empty here.
-- reference data whose columns changed across drafts: drop & recreate so re-applying on an
-- environment that has the older shape migrates cleanly (it carries no dependent data).
drop table if exists public.service_document_requirement cascade;
create table public.service_document_requirement (
  service_code   text not null references public.service_catalogue(code) on delete cascade,
  document_label text not null,
  tier           text not null check (tier in ('helpful','optional')),  -- two tiers only; no "required"
  sort           int  not null default 0,
  primary key (service_code, document_label)
);
alter table public.service_document_requirement enable row level security;
drop policy if exists sdr_select on public.service_document_requirement;
create policy sdr_select on public.service_document_requirement for select to anon, authenticated using (true);
grant select on public.service_document_requirement to anon, authenticated;

-- the typically-needed documents for a selection (anon-callable; shown while browsing)
create or replace function public.document_checklist(p_codes text[])
returns jsonb language sql stable security definer set search_path = public, extensions, pg_temp as $$
  -- ONE consolidated, de-duplicated list across the selection (documents overlap across services);
  -- a document Helpful for any selected service is Helpful overall, and Helpful ranks first.
  select coalesce(jsonb_agg(jsonb_build_object('document_label', document_label, 'tier', tier)
                            order by tier_rank, document_label), '[]'::jsonb)
  from (
    select document_label,
           case when bool_or(tier = 'helpful') then 'helpful' else 'optional' end as tier,
           min(case when tier = 'helpful' then 0 else 1 end)                      as tier_rank
    from public.service_document_requirement
    where service_code = any(p_codes)
    group by document_label
  ) d;
$$;
grant execute on function public.document_checklist(text[]) to anon, authenticated, service_role;

-- ---- buyer-uploaded documents (NOT worker evidence; different trust model) ----
-- Clients may upload zero or more. Nothing here is ever required to place an order.
create table if not exists public.buyer_document (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.order_matter(id) on delete cascade,
  uploaded_by  uuid references public.app_user(id),
  doc_type     text,                                  -- optional; maps to the checklist
  label        text not null,
  storage_ref  text not null,                         -- Supabase Storage path (never shown to the buyer)
  content_type text,
  byte_size    bigint,
  uploaded_at  timestamptz not null default now()
);
alter table public.buyer_document enable row level security;
drop policy if exists bd_select on public.buyer_document;
drop policy if exists bd_insert on public.buyer_document;
drop policy if exists bd_delete on public.buyer_document;
-- the owner, staff, and a worker assigned to the order may see the documents
create policy bd_select on public.buyer_document for select to authenticated
  using (app.owns_order(order_id) or app.is_staff() or app.partner_on_order(order_id));
-- only the owner (as themselves) or staff may add documents
create policy bd_insert on public.buyer_document for insert to authenticated
  with check ((app.owns_order(order_id) and uploaded_by = app.current_user_id()) or app.is_staff());
-- the owner may remove their own upload (e.g. a mistake) before it matters
create policy bd_delete on public.buyer_document for delete to authenticated
  using (app.owns_order(order_id) and uploaded_by = app.current_user_id());
grant select, insert, delete on public.buyer_document to authenticated;

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
      ) order by sc.sort) filter (where ci.id is not null), '[]'::jsonb),
    -- the buyer's uploaded documents (no storage path) — informational, never a gate
    'documents', coalesce((select jsonb_agg(jsonb_build_object(
        'label', bd.label, 'doc_type', bd.doc_type, 'uploaded_at', bd.uploaded_at
      ) order by bd.uploaded_at) from public.buyer_document bd where bd.order_id = o.id), '[]'::jsonb),
    -- the actual invoiced fees once Ops has invoiced (from payment), else null
    'fees', (select jsonb_build_object('service_fee', p.service_fee,
                                       'government_fee_total', p.government_fee_total)
             from public.payment p where p.order_id = o.id)
  )
  into v
  from public.order_matter o
  left join public.check_item       ci on ci.order_id = o.id
  left join public.service_catalogue sc on sc.code    = ci.service_code
  left join public.verdict          vd on vd.check_id = ci.id
  where o.id = p_order
  group by o.id, o.bundle;

  return coalesce(v, jsonb_build_object('visible', true, 'order_id', p_order, 'checks', '[]'::jsonb, 'documents', '[]'::jsonb, 'ready', false));
end;
$$;
comment on function public.order_tracking(uuid) is
  'Buyer-facing order status: per-check buyer state and colour verdicts, the headline verdict, readiness, uploaded documents (no storage path), and the invoiced fees. Visible only to the owner or staff.';
grant execute on function public.order_tracking(uuid) to authenticated, service_role;
