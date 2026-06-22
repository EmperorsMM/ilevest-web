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
