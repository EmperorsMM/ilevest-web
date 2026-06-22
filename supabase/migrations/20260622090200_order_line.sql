-- =============================================================================
-- Stage 2 / 0014  Order line (the selected services on an order — the "cart")
-- =============================================================================
-- An order's scope. Bundles expand into lines; a la carte adds lines directly. Fan-out
-- materialises one check per line. This is what makes the standalone field inspection
-- (C1-FD-01) and any a la carte selection first-class, alongside bundles.

create table public.order_line (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.order_matter(id) on delete restrict,
  service_code text not null references public.service_catalogue(code) on delete restrict,
  created_at   timestamptz not null default now(),
  unique (order_id, service_code)
);
comment on table public.order_line is 'Selected services on an order (the cart). Fan-out creates one check per line.';
create index order_line_order_idx on public.order_line (order_id);
alter table public.order_line enable row level security;

create policy order_line_select on public.order_line for select to authenticated
  using (app.is_staff() or app.owns_order(order_id) or app.partner_on_order(order_id));
create policy order_line_insert on public.order_line for insert to authenticated
  with check (app.owns_order(order_id) or app.is_staff());

grant select, insert on public.order_line to authenticated;

-- Expand a bundle into order lines (idempotent). INVOKER, so order_line RLS applies:
-- a client may only add lines to their own order; staff to any.
create or replace function app.add_order_lines_for_bundle(p_order uuid, p_bundle public.order_bundle)
returns integer language plpgsql security invoker set search_path = '' as $$
declare n int := 0;
begin
  insert into public.order_line(order_id, service_code)
  select p_order, bs.service_code
  from public.bundle_service bs
  where bs.bundle = p_bundle
    and not exists (select 1 from public.order_line ol where ol.order_id = p_order and ol.service_code = bs.service_code);
  get diagnostics n = row_count;
  return n;
end; $$;
