-- =============================================================================
-- Ilevest — Build Stage 2 combined migration (for the Supabase SQL Editor)
-- Apply AFTER Stage 1 is already in place. Adds: service catalogue + bundle
-- composition, order_line (the cart), and the public RPC layer + the swappable
-- payment path. Wrapped in a single transaction — all or nothing.
-- =============================================================================
begin;

-- ----- 20260622090100_service_catalogue.sql -----
-- =============================================================================
-- Stage 2 / 0013  Service catalogue + bundle composition (data-driven fan-out)
-- =============================================================================
-- The Phase 1 service menu and which services each bundle includes. Fan-out reads these
-- so the catalogue is data, not code. Bundle compositions below are the design-team-ratified set;
-- they remain data, adjustable post-launch as real customer patterns emerge.

create table public.service_catalogue (
  code       text primary key,                 -- e.g. C1-LR-01
  title      text not null,
  category   text not null,                     -- LR | SG | CT | PE | FD | KY (maps to partner desks)
  active     boolean not null default true,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);
comment on table public.service_catalogue is 'Phase 1 service menu. Read-mostly reference data; managed via migrations / service role.';
alter table public.service_catalogue enable row level security;
create policy svc_select on public.service_catalogue for select to authenticated using (true);

create table public.bundle_service (
  bundle       public.order_bundle not null,
  service_code text not null references public.service_catalogue(code) on delete restrict,
  primary key (bundle, service_code)
);
comment on table public.bundle_service is 'Which services each bundle expands to. ala_carte has no rows (services chosen individually).';
alter table public.bundle_service enable row level security;
create policy bundle_service_select on public.bundle_service for select to authenticated using (true);

-- ---- seed: Phase 1 catalogue ----
-- NOTE: C1-KY-01 (Persons & Entities / KYC) is added per the design-team bundle ruling.
-- Its exact code/title should be reconciled against the locked Service Catalogue (PRD 8.2);
-- it is reference data, changed without code if the canonical code differs.
insert into public.service_catalogue(code,title,category,sort) values
  ('C1-LR-01','Land Registry title search','LR',10),
  ('C1-SG-01','Surveyor-General chart & plan check','SG',20),
  ('C1-CT-01','Court records search (litigation / encumbrance)','CT',30),
  ('C1-PE-01','Probate & estate check','PE',40),
  ('C1-FD-01','Field inspection (site visit)','FD',50),
  ('C1-KY-01','Persons & Entities (KYC) check','KY',60);

-- ---- seed: bundle compositions (ratified by the design team) ----
-- Essential   = Land Registry + Surveyor-General
-- Complete    = Land Registry + Surveyor-General + Court (standard; Probate/KYC are situational add-ons)
-- Inheritance = Land Registry + Court + Probate
-- Diaspora    = Complete's contents + Field inspection + Persons/Entities (KYC)
-- ala_carte / custom builds have no rows here (services are chosen individually via order_line).
insert into public.bundle_service(bundle,service_code) values
  ('essential','C1-LR-01'), ('essential','C1-SG-01'),
  ('complete','C1-LR-01'), ('complete','C1-SG-01'), ('complete','C1-CT-01'),
  ('inheritance','C1-LR-01'), ('inheritance','C1-CT-01'), ('inheritance','C1-PE-01'),
  ('diaspora','C1-LR-01'), ('diaspora','C1-SG-01'), ('diaspora','C1-CT-01'), ('diaspora','C1-FD-01'), ('diaspora','C1-KY-01');

grant select on public.service_catalogue to authenticated, anon;
grant select on public.bundle_service   to authenticated;

-- ----- 20260622090200_order_line.sql -----
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

-- ----- 20260622090300_stage2_rpcs.sql -----
-- =============================================================================
-- Stage 2 / 0015  RPC layer — the portable core the Edge Functions call
-- =============================================================================
-- Auth model:
--   * SYSTEM actions (service_role only): fan_out_order, confirm_payment.
--   * USER actions (authenticated; enforced by the Stage 1 RLS policies + FSM trigger):
--       assign_check, record_evidence (INVOKER), seal_check (DEFINER + reviewer guard).
--   * PUBLIC: verify_certificate (anon) — returns the no-PII payload (Decision K).

-- ---- FAN-OUT: a paid order spawns its checks (idempotent) -------------------
create or replace function public.fan_out_order(p_order uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare n int := 0; r record;
begin
  for r in
    select ol.service_code
    from public.order_line ol
    where ol.order_id = p_order
      and not exists (select 1 from public.check_item c
                      where c.order_id = p_order and c.service_code = ol.service_code)
  loop
    insert into public.check_item(order_id, service_code) values (p_order, r.service_code);
    n := n + 1;
  end loop;
  return n;
end; $$;

-- ---- CONFIRM PAYMENT: idempotent; verifies then fans out, atomically -------
create or replace function public.confirm_payment(p_order uuid, p_gateway_ref text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare already boolean; created int;
begin
  select webhook_verified into already from public.payment where order_id = p_order for update;
  if not found then
    raise exception 'No payment row for order %.', p_order using errcode = 'no_data_found';
  end if;
  if already then
    return jsonb_build_object('order_id', p_order, 'already_verified', true, 'checks_created', 0);
  end if;
  update public.payment
     set webhook_verified = true,
         paid_at     = coalesce(paid_at, now()),
         gateway_ref = coalesce(gateway_ref, p_gateway_ref),
         updated_at  = now()
   where order_id = p_order;
  created := public.fan_out_order(p_order);
  perform app.write_audit('payment', p_order, 'payment_verified', null, 'verified', p_gateway_ref, null,
                          jsonb_build_object('gateway_ref', p_gateway_ref));
  return jsonb_build_object('order_id', p_order, 'already_verified', false, 'checks_created', created);
end; $$;

-- ---- ASSIGN: Ops dispatches a check directly to a worker (Ruling 1) --------
create or replace function public.assign_check(p_check uuid, p_worker uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if not exists (select 1 from public.user_role ur
                 where ur.user_id = p_worker and ur.role in ('partner','field_agent')) then
    raise exception 'Worker % must hold the partner or field_agent role to receive a check.', p_worker
      using errcode = 'check_violation';
  end if;
  update public.check_item set assigned_partner_id = p_worker, state = 'assigned' where id = p_check;
  if not found then
    raise exception 'Check % not found or not visible.', p_check using errcode = 'no_data_found';
  end if;
end; $$;

-- ---- EVIDENCE INTAKE: assigned worker (or staff) posts evidence ------------
create or replace function public.record_evidence(
  p_check uuid, p_kind public.evidence_kind, p_content_hash text,
  p_storage_ref text default null,
  p_gps_lat double precision default null, p_gps_lng double precision default null,
  p_gps_accuracy double precision default null,
  p_captured_at timestamptz default null, p_device_id text default null
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_id uuid;
begin
  insert into public.evidence_item(check_id, kind, content_hash, storage_ref,
                                   gps_lat, gps_lng, gps_accuracy, captured_at, device_id)
  values (p_check, p_kind, p_content_hash, p_storage_ref,
          p_gps_lat, p_gps_lng, p_gps_accuracy, p_captured_at, p_device_id)
  returning id into v_id;
  return v_id;
end; $$;

-- ---- SEAL: finalize -> verdict -> reproducible fingerprint -> commitment ----
-- DEFINER (with an explicit reviewer guard) so the SHA-256 (pgcrypto digest) resolves
-- whether pgcrypto lives in public or the extensions schema. The fingerprint is built
-- in the database from the verification's own facts, so it is reproducible and not
-- client-asserted.
create or replace function public.seal_check(p_check uuid, p_colour public.verdict_colour, p_explanation text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_canon text; v_hash text; v_prev text; v_commit uuid; v_order uuid; v_service text;
begin
  if not app.is_reviewer() then
    raise exception 'Only a Reviewer/Ops/Admin may seal a check.' using errcode = 'check_violation';
  end if;
  select order_id, service_code into v_order, v_service from public.check_item where id = p_check;
  if not found then raise exception 'Check % not found.', p_check using errcode = 'no_data_found'; end if;

  insert into public.verdict(check_id, colour, explanation) values (p_check, p_colour, p_explanation);
  update public.check_item set state = 'finalized' where id = p_check;  -- FSM trigger validates reviewer/ops

  select p_check::text || '|' || coalesce(v_service,'') || '|' || p_colour::text || '|' || coalesce(p_explanation,'')
         || '|' || coalesce(string_agg(e.content_hash, ',' order by e.id), '')
         || '|' || coalesce(v_order::text,'')
    into v_canon
  from public.evidence_item e where e.check_id = p_check;

  v_hash := encode(digest(v_canon, 'sha256'), 'hex');

  insert into public.commitment(check_id, content_hash) values (p_check, v_hash)
    returning prev_hash into v_prev;
  select id into v_commit from public.commitment where check_id = p_check;

  return jsonb_build_object('check_id', p_check, 'verdict', p_colour,
                            'content_hash', v_hash, 'prev_hash', v_prev, 'commitment_id', v_commit);
end; $$;

-- ---- PUBLIC VERIFICATION: validity + verdict + integrity, no PII (Decision K)
-- Always returns a definite object. An unknown or unsealed check yields {"valid": false}
-- rather than NULL — a public endpoint must never hand back nothing.
create or replace function public.verify_certificate(p_check uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object(
       'valid',        (c.id is not null),
       'verdict',      v.colour,
       'check_state',  ci.state,
       'service_code', ci.service_code,
       'property',     jsonb_build_object('lga', p.lga, 'state', p.state, 'locality', p.locality),
       'sealed_at',    ci.sealed_at,
       'content_hash', c.content_hash,
       'prev_hash',    c.prev_hash,
       'anchored',     (c.batch_id is not null),
       'anchor_ref',   ab.anchor_ref
     )
     from public.check_item ci
     left join public.verdict      v  on v.check_id  = ci.id
     left join public.commitment   c  on c.check_id  = ci.id
     left join public.anchor_batch ab on ab.id       = c.batch_id
     left join public.order_matter o  on o.id        = ci.order_id
     left join public.property     p  on p.id        = o.property_id
     where ci.id = p_check),
    jsonb_build_object('valid', false)
  );
$$;

-- ---- grants: lock the system functions to service_role; expose the rest ----
revoke execute on function public.fan_out_order(uuid)        from public;
revoke execute on function public.confirm_payment(uuid,text) from public;
grant  execute on function public.fan_out_order(uuid)        to service_role;
grant  execute on function public.confirm_payment(uuid,text) to service_role;

grant execute on function public.assign_check(uuid,uuid)                                   to authenticated, service_role;
grant execute on function public.record_evidence(uuid,public.evidence_kind,text,text,double precision,double precision,double precision,timestamptz,text) to authenticated, service_role;
grant execute on function public.seal_check(uuid,public.verdict_colour,text)               to authenticated, service_role;
grant execute on function app.add_order_lines_for_bundle(uuid,public.order_bundle)      to authenticated, service_role;
grant execute on function public.verify_certificate(uuid)                                  to anon, authenticated, service_role;

commit;
