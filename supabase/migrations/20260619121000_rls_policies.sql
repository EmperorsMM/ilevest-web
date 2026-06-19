-- =============================================================================
-- 0010  Row-Level Security policies — the real permission boundary (Decision H)
-- =============================================================================
-- Least privilege for six roles. Policies target the `authenticated` role; the
-- bypass-RLS `service_role` is used only by trusted server/edge code, and `anon`
-- gets nothing in Phase 1 (the public verification endpoint comes later as a
-- SECURITY DEFINER function that exposes only the no-PII payload of Decision K).
--
-- Cross-table visibility is expressed through SECURITY DEFINER helpers so an inner
-- lookup is not itself filtered by the other table's RLS (which would under-match).

-- ---- visibility helpers (definer; bypass RLS for correct, non-recursive checks) ----
create or replace function app.owns_order(p_order uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.order_matter o
                where o.id=p_order and o.client_id=app.current_user_id());
$$;
create or replace function app.partner_on_order(p_order uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.check_item c
                where c.order_id=p_order and c.assigned_partner_id=app.current_user_id());
$$;
create or replace function app.owns_check(p_check uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.check_item c join public.order_matter o on o.id=c.order_id
                where c.id=p_check and o.client_id=app.current_user_id());
$$;
create or replace function app.partner_on_check(p_check uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.check_item c
                where c.id=p_check and c.assigned_partner_id=app.current_user_id());
$$;
create or replace function app.owns_property(p_prop uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.order_matter o
                where o.property_id=p_prop and o.client_id=app.current_user_id());
$$;
create or replace function app.partner_on_property(p_prop uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.order_matter o join public.check_item c on c.order_id=o.id
                where o.property_id=p_prop and c.assigned_partner_id=app.current_user_id());
$$;
create or replace function app.owns_party(p_party uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.order_matter o
                where o.party_id=p_party and o.client_id=app.current_user_id());
$$;
create or replace function app.owns_fee(p_fee uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.government_fee gf join public.order_matter o on o.id=gf.order_id
                where gf.id=p_fee and o.client_id=app.current_user_id());
$$;
create or replace function app.partner_on_fee(p_fee uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.government_fee gf join public.check_item c on c.id=gf.check_id
                where gf.id=p_fee and c.assigned_partner_id=app.current_user_id());
$$;

-- ============================ app_user =====================================
create policy app_user_select on public.app_user for select to authenticated
  using (id = app.current_user_id() or app.is_staff());
create policy app_user_insert on public.app_user for insert to authenticated
  with check (app.is_admin());
create policy app_user_update on public.app_user for update to authenticated
  using (id = app.current_user_id() or app.is_admin())
  with check (id = app.current_user_id() or app.is_admin());

-- ============================ user_role ====================================
create policy user_role_select on public.user_role for select to authenticated
  using (user_id = app.current_user_id() or app.is_staff());
create policy user_role_insert on public.user_role for insert to authenticated
  with check (app.is_admin());
create policy user_role_update on public.user_role for update to authenticated
  using (app.is_admin()) with check (app.is_admin());
create policy user_role_delete on public.user_role for delete to authenticated
  using (app.is_admin());

-- ========================== partner_profile ================================
create policy partner_profile_select on public.partner_profile for select to authenticated
  using (user_id = app.current_user_id() or app.is_staff());
create policy partner_profile_insert on public.partner_profile for insert to authenticated
  with check (app.is_ops());
create policy partner_profile_update on public.partner_profile for update to authenticated
  using (app.is_ops()) with check (app.is_ops());

-- ============================= property ====================================
create policy property_select on public.property for select to authenticated
  using (app.is_staff() or app.owns_property(id) or app.partner_on_property(id));
create policy property_insert on public.property for insert to authenticated
  with check (app.is_staff());
create policy property_update on public.property for update to authenticated
  using (app.is_staff()) with check (app.is_staff());

-- =========================== party_seller ==================================
create policy party_select on public.party_seller for select to authenticated
  using (app.is_staff() or app.owns_party(id));
create policy party_insert on public.party_seller for insert to authenticated
  with check (app.is_staff());
create policy party_update on public.party_seller for update to authenticated
  using (app.is_staff()) with check (app.is_staff());

-- =========================== order_matter ==================================
create policy order_select on public.order_matter for select to authenticated
  using (client_id = app.current_user_id() or app.is_staff() or app.partner_on_order(id));
create policy order_insert on public.order_matter for insert to authenticated
  with check ((client_id = app.current_user_id() and app.has_role('client')) or app.is_staff());
create policy order_update on public.order_matter for update to authenticated
  using (app.is_staff()) with check (app.is_staff());

-- ============================ check_item ===================================
create policy check_select on public.check_item for select to authenticated
  using (app.is_staff() or assigned_partner_id = app.current_user_id() or app.owns_order(order_id));
create policy check_insert on public.check_item for insert to authenticated
  with check (app.is_staff());
-- staff or the assigned partner may UPDATE; the FSM trigger decides WHICH transition each may run
create policy check_update on public.check_item for update to authenticated
  using (app.is_staff() or assigned_partner_id = app.current_user_id())
  with check (app.is_staff() or assigned_partner_id = app.current_user_id());

-- =========================== evidence_item =================================
create policy evidence_select on public.evidence_item for select to authenticated
  using (app.is_staff() or captured_by = app.current_user_id() or app.partner_on_check(check_id));
create policy evidence_insert on public.evidence_item for insert to authenticated
  with check (app.is_staff() or app.partner_on_check(check_id));
-- no update/delete policy: evidence is append-only

-- ============================== payment ====================================
create policy payment_select on public.payment for select to authenticated
  using (app.is_staff() or app.owns_order(order_id));
create policy payment_insert on public.payment for insert to authenticated
  with check (app.is_ops());
create policy payment_update on public.payment for update to authenticated
  using (app.is_ops()) with check (app.is_ops());

-- ========================== government_fee =================================
create policy gov_fee_select on public.government_fee for select to authenticated
  using (app.is_staff() or app.owns_order(order_id) or app.partner_on_check(check_id));
create policy gov_fee_insert on public.government_fee for insert to authenticated
  with check (app.is_ops());
-- no update/delete policy: core fee row is immutable

-- ===================== government_fee_transition ===========================
create policy gov_fee_txn_select on public.government_fee_transition for select to authenticated
  using (app.is_staff() or app.owns_fee(government_fee_id) or app.partner_on_fee(government_fee_id));
create policy gov_fee_txn_insert on public.government_fee_transition for insert to authenticated
  with check (app.is_ops());
-- no update/delete policy: ledger is append-only

-- ============================== verdict ====================================
create policy verdict_select on public.verdict for select to authenticated
  using (app.is_staff() or app.owns_check(check_id) or app.partner_on_check(check_id));
create policy verdict_insert on public.verdict for insert to authenticated
  with check (app.is_reviewer());
-- no update/delete policy: verdicts are append-only

-- ============================ commitment ===================================
create policy commitment_select on public.commitment for select to authenticated
  using (app.is_staff() or app.owns_check(check_id) or app.partner_on_check(check_id));
create policy commitment_insert on public.commitment for insert to authenticated
  with check (app.is_reviewer());
-- no update/delete policy for authenticated: anchoring runs as service_role; the guard
-- trigger still protects integrity fields even from service_role.

-- =========================== anchor_batch ==================================
-- public-by-design (no PII): any authenticated user may read the Merkle roots/anchor refs
create policy anchor_batch_select on public.anchor_batch for select to authenticated
  using (true);
-- no write policy: only the service-role anchoring job creates batches

-- ============================ audit_event ==================================
-- staff read everything; any user may read their own actions. No write policy:
-- audit rows are written only by SECURITY DEFINER triggers / service_role, so they
-- cannot be forged or suppressed by ordinary users.
create policy audit_select on public.audit_event for select to authenticated
  using (app.is_staff() or actor_id = app.current_user_id());
