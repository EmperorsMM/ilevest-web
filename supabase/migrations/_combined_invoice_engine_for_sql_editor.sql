-- ============================================================================
-- COMBINED for Supabase SQL Editor — Ops invoice engine
-- (billing config, invoice + lines, per-line VAT, issue->payment+email, reads)
-- Idempotent. Safe to run on the live project.
-- ============================================================================
begin;

-- ============================================================================
-- Ops invoice engine
-- ----------------------------------------------------------------------------
-- Implements the locked fee model: an invoice per order with line items, each a
-- service fee or a government fee (at cost, no markup). Per-line VAT treatment
-- (apply / exempt / out_of_scope) with the service fee always applied and the
-- government-fee default coming from one configurable place (set by the tax
-- professional, never hard-coded). Government-fee lines carry the receipt
-- expectation (receipt-or-refund). VAT is computed per line and shown
-- transparently; no prices are stored on the catalogue.
--
-- Issuing an invoice creates the order's payment row (the fan-out trigger the
-- proven Paystack webhook verifies), flips the order out of "awaiting quote",
-- and fires the ratified "quote ready" email. Buyer then pays online (Paystack)
-- -> webhook -> confirm_payment -> fan-out into live checks.
-- ============================================================================

-- ---- one configurable place for VAT + the government-fee default ------------
create table if not exists public.billing_config (
  id          boolean primary key default true check (id),  -- singleton row
  vat_rate    numeric not null default 7.5,
  government_fee_default_treatment text not null default 'apply'
              check (government_fee_default_treatment in ('apply','exempt','out_of_scope')),
  updated_at  timestamptz not null default now()
);
insert into public.billing_config(id) values (true) on conflict (id) do nothing;

-- ---- record the VAT alongside the fees on the payment row -------------------
alter table public.payment add column if not exists vat_total numeric not null default 0;

-- ---- invoice + lines --------------------------------------------------------
create table if not exists public.invoice (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null unique references public.order_matter(id) on delete cascade,
  status      text not null default 'draft' check (status in ('draft','issued','paid','void')),
  currency    text not null default 'NGN',
  notes       text,
  issued_at   timestamptz,
  issued_by   uuid references public.app_user(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.invoice_line (
  id            uuid primary key default gen_random_uuid(),
  invoice_id    uuid not null references public.invoice(id) on delete cascade,
  kind          text not null check (kind in ('service_fee','government_fee')),
  service_code  text references public.service_catalogue(code),
  description   text not null,
  amount        numeric not null check (amount >= 0),
  vat_treatment text not null check (vat_treatment in ('apply','exempt','out_of_scope')),
  vat_rate      numeric not null default 0,            -- rate snapshot (0 unless 'apply')
  requires_receipt boolean not null default false,     -- receipt-or-refund (government fees)
  sort          int not null default 0,
  created_at    timestamptz not null default now()
);
create index if not exists invoice_line_invoice_idx on public.invoice_line (invoice_id);

alter table public.invoice      enable row level security;
alter table public.invoice_line enable row level security;

-- Buyers may read their own ISSUED invoice (drafts are Ops-only); staff read all.
drop policy if exists invoice_select on public.invoice;
create policy invoice_select on public.invoice for select to authenticated
  using (app.is_staff() or (status in ('issued','paid','void') and app.owns_order(order_id)));

drop policy if exists invoice_line_select on public.invoice_line;
create policy invoice_line_select on public.invoice_line for select to authenticated
  using (exists (
    select 1 from public.invoice i
    where i.id = invoice_line.invoice_id
      and (app.is_staff() or (i.status in ('issued','paid','void') and app.owns_order(i.order_id)))
  ));

grant select on public.invoice, public.invoice_line to authenticated;

-- ============================================================================
-- VAT math — one place. Per line: VAT only when treatment is 'apply'.
-- ============================================================================
create or replace function app.compute_invoice(p_invoice uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  with l as (
    select il.*,
           case when il.vat_treatment = 'apply'
                then round(il.amount * il.vat_rate / 100.0, 2)
                else 0 end as vat_amount
    from public.invoice_line il
    where il.invoice_id = p_invoice
  )
  select jsonb_build_object(
    'lines', coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'kind', l.kind, 'service_code', l.service_code, 'description', l.description,
        'amount', l.amount, 'vat_treatment', l.vat_treatment, 'vat_rate', l.vat_rate,
        'vat_amount', l.vat_amount, 'line_total', l.amount + l.vat_amount,
        'requires_receipt', l.requires_receipt
      ) order by l.sort, l.created_at), '[]'::jsonb),
    'service_subtotal',    coalesce(sum(l.amount) filter (where l.kind = 'service_fee'), 0),
    'government_subtotal', coalesce(sum(l.amount) filter (where l.kind = 'government_fee'), 0),
    'vat_total',           coalesce(sum(l.vat_amount), 0),
    'grand_total',         coalesce(sum(l.amount), 0) + coalesce(sum(l.vat_amount), 0)
  )
  from l;
$$;
revoke all on function app.compute_invoice(uuid) from public;

-- ============================================================================
-- Ops write paths (is_ops-gated)
-- ============================================================================
create or replace function public.ops_create_invoice(p_order uuid)
returns uuid
language plpgsql security definer set search_path = public, extensions, pg_temp
as $$
declare v uuid;
begin
  if not app.is_ops() then raise exception 'Only Ops/Admin may create invoices.' using errcode = '42501'; end if;
  insert into public.invoice(order_id) values (p_order) on conflict (order_id) do nothing;
  select id into v from public.invoice where order_id = p_order;
  return v;
end; $$;

-- Replace the draft invoice's lines with the provided set (the builder sends the whole set).
create or replace function public.ops_set_invoice_lines(p_order uuid, p_lines jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp
as $$
declare v_inv uuid; v_status text; v_rate numeric; v_gov_default text; r jsonb; i int := 0;
begin
  if not app.is_ops() then raise exception 'Only Ops/Admin may edit invoices.' using errcode = '42501'; end if;

  select id, status into v_inv, v_status from public.invoice where order_id = p_order;
  if v_inv is null then
    insert into public.invoice(order_id) values (p_order) returning id into v_inv;
    v_status := 'draft';
  end if;
  if v_status <> 'draft' then raise exception 'Invoice is already issued; its lines are locked.'; end if;

  select vat_rate, government_fee_default_treatment into v_rate, v_gov_default from public.billing_config where id;

  delete from public.invoice_line where invoice_id = v_inv;

  for r in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    declare
      v_kind  text    := r->>'kind';
      v_treat text    := coalesce(nullif(r->>'vat_treatment',''),
                                  case when r->>'kind' = 'service_fee' then 'apply' else v_gov_default end);
      v_recpt boolean := coalesce((r->>'requires_receipt')::boolean, r->>'kind' = 'government_fee');
    begin
      if v_kind not in ('service_fee','government_fee') then raise exception 'bad line kind: %', v_kind; end if;
      if v_treat not in ('apply','exempt','out_of_scope') then raise exception 'bad vat treatment: %', v_treat; end if;
      insert into public.invoice_line(invoice_id, kind, service_code, description, amount, vat_treatment, vat_rate, requires_receipt, sort)
      values (v_inv, v_kind, nullif(r->>'service_code',''),
              coalesce(nullif(r->>'description',''), '(unnamed)'),
              coalesce((r->>'amount')::numeric, 0), v_treat,
              case when v_treat = 'apply' then v_rate else 0 end, v_recpt, i);
      i := i + 1;
    end;
  end loop;

  return app.compute_invoice(v_inv);
end; $$;

-- Issue: lock the invoice, create the payment row (fan-out trigger), notify the buyer.
create or replace function public.ops_issue_invoice(p_order uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp
as $$
declare v_inv uuid; v_status text; v jsonb; v_svc numeric; v_gov numeric; v_vat numeric;
begin
  if not app.is_ops() then raise exception 'Only Ops/Admin may issue invoices.' using errcode = '42501'; end if;

  select id, status into v_inv, v_status from public.invoice where order_id = p_order;
  if v_inv is null then raise exception 'No invoice for this order.'; end if;
  if v_status <> 'draft' then raise exception 'Invoice has already been issued.'; end if;
  if not exists (select 1 from public.invoice_line where invoice_id = v_inv) then
    raise exception 'Cannot issue an empty invoice.';
  end if;

  v := app.compute_invoice(v_inv);
  v_svc := (v->>'service_subtotal')::numeric;
  v_gov := (v->>'government_subtotal')::numeric;
  v_vat := (v->>'vat_total')::numeric;

  insert into public.payment(order_id, currency, service_fee, government_fee_total, vat_total, webhook_verified)
  values (p_order, 'NGN', v_svc, v_gov, v_vat, false)
  on conflict (order_id) do update set
    service_fee = excluded.service_fee,
    government_fee_total = excluded.government_fee_total,
    vat_total = excluded.vat_total,
    updated_at = now();

  update public.invoice
     set status = 'issued', issued_at = now(), issued_by = app.current_user_id(), updated_at = now()
   where id = v_inv;

  perform app.enqueue_quote_ready(p_order);  -- fires the "quote ready" email

  return v || jsonb_build_object('status', 'issued');
end; $$;

-- ============================================================================
-- Reads
-- ============================================================================
-- Buyer (own, issued only) or staff (any): the invoice with computed VAT + totals.
create or replace function public.get_invoice(p_order uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp
as $$
declare v_inv uuid; v_status text; v_issued timestamptz; v_paid boolean; v jsonb; v_staff boolean := app.is_staff();
begin
  if not (app.owns_order(p_order) or v_staff) then
    return jsonb_build_object('exists', false, 'visible', false);
  end if;
  select id, status, issued_at into v_inv, v_status, v_issued from public.invoice where order_id = p_order;
  if v_inv is null then return jsonb_build_object('exists', false); end if;
  if v_status = 'draft' and not v_staff then return jsonb_build_object('exists', false); end if;

  select webhook_verified into v_paid from public.payment where order_id = p_order;
  v := app.compute_invoice(v_inv);
  return v || jsonb_build_object(
    'exists', true, 'status', v_status, 'issued_at', v_issued,
    'paid', coalesce(v_paid, false), 'currency', 'NGN'
  );
end; $$;

-- Staff: the order queue with each order's invoice + payment state.
create or replace function public.ops_order_queue()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp
as $$
declare v jsonb;
begin
  if not app.is_staff() then raise exception 'Staff only.' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'order_id', o.id, 'created_at', o.created_at, 'bundle', o.bundle,
    'client', au.name, 'client_contact', au.email_or_phone,
    'property', (select coalesce(p.locality || ', ', '') || coalesce(p.lga, '') from public.property p where p.id = o.property_id),
    'seller', (select ps.name from public.party_seller ps where ps.id = o.party_id),
    'invoice_status', coalesce(i.status, 'none'),
    'paid', coalesce(pay.webhook_verified, false),
    'line_count', (select count(*) from public.order_line ol where ol.order_id = o.id)
  ) order by o.created_at desc), '[]'::jsonb) into v
  from public.order_matter o
  left join public.app_user au  on au.id = o.client_id
  left join public.invoice i    on i.order_id = o.id
  left join public.payment pay  on pay.order_id = o.id;
  return v;
end; $$;

-- Staff: current billing config (for the Ops builder to show the VAT rate + default).
create or replace function public.get_billing_config()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions, pg_temp
as $$
declare v jsonb;
begin
  if not app.is_staff() then raise exception 'Staff only.' using errcode = '42501'; end if;
  select jsonb_build_object('vat_rate', vat_rate, 'government_fee_default_treatment', government_fee_default_treatment)
    into v from public.billing_config where id;
  return v;
end; $$;

-- Admin: set the VAT rate + government-fee default (the tax professional's settings).
create or replace function public.set_billing_config(p_vat_rate numeric, p_gov_default text)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp
as $$
begin
  if not app.is_admin() then raise exception 'Admin only.' using errcode = '42501'; end if;
  if p_gov_default not in ('apply','exempt','out_of_scope') then raise exception 'bad treatment: %', p_gov_default; end if;
  update public.billing_config set vat_rate = p_vat_rate, government_fee_default_treatment = p_gov_default, updated_at = now() where id;
end; $$;

revoke all on function public.ops_create_invoice(uuid)        from public;
revoke all on function public.ops_set_invoice_lines(uuid, jsonb) from public;
revoke all on function public.ops_issue_invoice(uuid)         from public;
revoke all on function public.get_invoice(uuid)               from public;
revoke all on function public.ops_order_queue()               from public;
revoke all on function public.get_billing_config()            from public;
revoke all on function public.set_billing_config(numeric, text) from public;

grant execute on function public.ops_create_invoice(uuid)        to authenticated;
grant execute on function public.ops_set_invoice_lines(uuid, jsonb) to authenticated;
grant execute on function public.ops_issue_invoice(uuid)         to authenticated;
grant execute on function public.get_invoice(uuid)               to authenticated;
grant execute on function public.ops_order_queue()               to authenticated;
grant execute on function public.get_billing_config()            to authenticated;
grant execute on function public.set_billing_config(numeric, text) to authenticated;

commit;
