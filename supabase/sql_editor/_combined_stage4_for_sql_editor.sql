-- =============================================================================
-- Ilevest — Build Stage 4 combined migration, part 1 (for the Supabase SQL Editor)
-- Apply AFTER Stages 1-3. NO stored prices (Ops invoices per request). Adds the buyer
-- status projection, the buyer-document store (allow-zero + encourage), and seeds the
-- per-service document checklist (Appendix A). Idempotent; one transaction; re-runnable —
-- including on an environment that has an earlier buyer-document shape.
-- =============================================================================
begin;

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

-- =============================================================================
-- 0012  Seed — per-service buyer-document checklist (Stage 4, Call 2)
-- =============================================================================
-- Source: Ilevest Buyer-Document Checklist v1.0 (Appendix A), drafted from the Service
-- Catalogue client inputs. Two tiers only (helpful / optional); NO 'required' tier — nothing
-- blocks submission. Tiers and labels are DATA: refine without code via this upsert.
-- Idempotent: re-running updates tier/sort in place.

insert into public.service_document_requirement (service_code, document_label, tier, sort) values
  ('C1-LR-01', 'Certificate of Occupancy (C of O), deed, or any title document the seller presented', 'helpful', 1),
  ('C1-LR-01', 'Seller''s name / details as presented', 'helpful', 2),
  ('C1-LR-01', 'Any known title or registration particulars (title number, page, volume)', 'optional', 3),
  ('C1-LR-01', 'Survey plan, if available', 'optional', 4),
  ('C1-LR-02', 'A clear scan/photo of the specific document to be authenticated (C of O / deed / consent)', 'helpful', 1),
  ('C1-LR-02', 'The parties and property as stated on that document', 'helpful', 2),
  ('C1-LR-03', 'Title or registration particulars (or the result of a prior title search)', 'helpful', 1),
  ('C1-LR-03', 'Registered owner''s name', 'helpful', 2),
  ('C1-LR-04', 'Copies of the prior deeds/instruments in the ownership chain', 'helpful', 1),
  ('C1-LR-04', 'Title particulars, if known', 'optional', 2),
  ('C1-LR-05', 'Survey plan or the land''s coordinates (most useful for this check)', 'helpful', 1),
  ('C1-LR-05', 'Property address and locality (LGA)', 'helpful', 2),
  ('C1-LR-06', 'Submission references / receipts from when the deed was lodged', 'helpful', 1),
  ('C1-LR-06', 'Deed details and parties', 'optional', 2),
  ('C1-LR-07', 'Particulars of the instrument whose certified true copy is wanted', 'helpful', 1),
  ('C1-LR-07', 'Property address and parties', 'optional', 2),
  ('C1-SG-01', 'A clear copy of the survey plan (front and back)', 'helpful', 1),
  ('C1-SG-01', 'Property location', 'helpful', 2),
  ('C1-SG-02', 'Survey plan and/or the land''s coordinates', 'helpful', 1),
  ('C1-SG-02', 'Location and approximate size', 'optional', 2),
  ('C1-SG-03', 'Survey plan showing coordinates', 'helpful', 1),
  ('C1-SG-03', 'Any competing/neighbouring plan you hold', 'optional', 2),
  ('C1-SG-04', 'The survey plan', 'helpful', 1),
  ('C1-SG-04', 'A site access arrangement or on-ground contact', 'optional', 2),
  ('C1-CT-01', 'The deceased owner''s full name', 'helpful', 1),
  ('C1-CT-01', 'Court division and probate reference, if known', 'optional', 2),
  ('C1-CT-01', 'Any grant or letters of administration the sellers presented', 'optional', 3),
  ('C1-CT-01', 'Names of the persons selling the property', 'helpful', 4),
  ('C1-CT-02', 'Property address/description', 'helpful', 1),
  ('C1-CT-02', 'Seller''s name and any known adverse-party names', 'helpful', 2),
  ('C1-CT-03', 'Property description', 'helpful', 1),
  ('C1-CT-03', 'Party names', 'helpful', 2),
  ('C1-CT-03', 'Any known suit references', 'optional', 3),
  ('C1-CT-04', 'Particulars of the court record wanted (suit/probate references, if known)', 'helpful', 1),
  ('C1-PE-01', 'Company name and RC number as presented', 'helpful', 1),
  ('C1-PE-01', 'Names of the individuals fronting the transaction', 'helpful', 2),
  ('C1-PE-01', 'Any marketing materials/receipts the company issued', 'optional', 3),
  ('C1-PE-02', 'Identity particulars presented (NIN and/or BVN reference, ID document)', 'helpful', 1),
  ('C1-PE-02', 'Consent of the person being verified, where required', 'helpful', 2),
  ('C1-PE-03', 'The professional''s name and claimed registration/enrolment particulars', 'helpful', 1),
  ('C1-PE-03', 'Their role in the transaction', 'optional', 2),
  ('C1-FD-01', 'Property location (address and/or coordinates)', 'helpful', 1),
  ('C1-FD-01', 'Survey plan, if available', 'optional', 2),
  ('C1-FD-01', 'A site access arrangement or local contact', 'optional', 3),
  ('C1-FD-01', 'Any specific questions you want the inspection to answer', 'optional', 4)
on conflict (service_code, document_label) do update
  set tier = excluded.tier, sort = excluded.sort;

commit;
