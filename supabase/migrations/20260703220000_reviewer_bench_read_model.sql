-- =============================================================================
-- Ilevest — Increment 3 · The Reviewer bench (read model)
--
--   desk_queue()   SECURITY INVOKER, staff-gated. The desk's three piles:
--                    intake      — unassigned checks (Ops assigns from here;
--                                  pulled forward from the Ops increment so the
--                                  desk works end-to-end for the launch human)
--                    in_review   — waiting for the Reviewer, oldest first
--                    exceptions  — with Ops for retry-or-escalate, reason shown
--                  Row-Level Security does the reads (staff see all checks,
--                  workers' names, and the audit spine); non-staff get
--                  staff:false and empty piles.
--
--   check_workspace()  amended (additive): now also returns the worker's
--                  identity ({id, name}) and updated_at, so the bench can say
--                  who did the work — Decision D1's honesty depends on the
--                  Reviewer seeing authorship plainly. Payload shape is a
--                  superset of Increment 2's; nothing existing changes.
-- =============================================================================

create or replace function public.desk_queue()
 returns jsonb
 language plpgsql stable
 set search_path to ''
as $function$
declare v_intake jsonb; v_review jsonb; v_exc jsonb;
begin
  if not app.is_staff() then
    return jsonb_build_object('staff', false,
      'intake', '[]'::jsonb, 'in_review', '[]'::jsonb, 'exceptions', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'check_id', c.id, 'service_code', c.service_code, 'title', sc.title,
           'bundle', o.bundle,
           'property', nullif(concat_ws(', ', p.locality, p.lga, p.state), ''),
           'waiting_since', c.created_at
         ) order by c.created_at), '[]'::jsonb)
    into v_intake
  from public.check_item c
  join public.service_catalogue sc on sc.code = c.service_code
  join public.order_matter o on o.id = c.order_id
  left join public.property p on p.id = o.property_id
  where c.state = 'initiated';

  select coalesce(jsonb_agg(jsonb_build_object(
           'check_id', c.id, 'service_code', c.service_code, 'title', sc.title,
           'bundle', o.bundle,
           'property', nullif(concat_ws(', ', p.locality, p.lga, p.state), ''),
           'worker', w.name,
           'live_evidence', (select count(*) from public.evidence_item e
                             left join public.evidence_void vv on vv.evidence_id = e.id
                             where e.check_id = c.id and vv.evidence_id is null),
           'waiting_since', c.updated_at
         ) order by c.updated_at asc nulls last), '[]'::jsonb)
    into v_review
  from public.check_item c
  join public.service_catalogue sc on sc.code = c.service_code
  join public.order_matter o on o.id = c.order_id
  left join public.property p on p.id = o.property_id
  left join public.app_user w on w.id = c.assigned_partner_id
  where c.state = 'in_review';

  select coalesce(jsonb_agg(jsonb_build_object(
           'check_id', c.id, 'service_code', c.service_code, 'title', sc.title,
           'bundle', o.bundle,
           'property', nullif(concat_ws(', ', p.locality, p.lga, p.state), ''),
           'worker', w.name,
           'reason', (select a.reason from public.audit_event a
                      where a.check_id = c.id and a.action = 'state_change'
                        and a.to_state = 'exception' and a.reason is not null
                      order by a.occurred_at desc limit 1),
           'retries', (select count(*) from public.audit_event a
                       where a.check_id = c.id and a.action = 'state_change'
                         and a.from_state = 'exception' and a.to_state = 'in_progress'),
           'waiting_since', c.updated_at
         ) order by c.updated_at asc nulls last), '[]'::jsonb)
    into v_exc
  from public.check_item c
  join public.service_catalogue sc on sc.code = c.service_code
  join public.order_matter o on o.id = c.order_id
  left join public.property p on p.id = o.property_id
  left join public.app_user w on w.id = c.assigned_partner_id
  where c.state = 'exception';

  return jsonb_build_object('staff', true,
    'intake', v_intake, 'in_review', v_review, 'exceptions', v_exc);
end;
$function$;

grant execute on function public.desk_queue() to authenticated;

-- ---------------------------------------------------------------------------
-- check_workspace: additive amendment (worker identity + updated_at)
-- ---------------------------------------------------------------------------
create or replace function public.check_workspace(p_check uuid)
 returns jsonb
 language plpgsql stable security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v jsonb;
begin
  if not (app.partner_on_check(p_check) or app.is_staff()) then
    return jsonb_build_object('visible', false);
  end if;

  select jsonb_build_object(
    'visible',       true,
    'check_id',      c.id,
    'service_code',  c.service_code,
    'title',         sc.title,
    'state',         c.state,
    'is_finalized',  c.is_finalized,
    'sealed_at',     c.sealed_at,
    'updated_at',    c.updated_at,
    'i_am_worker',   (c.assigned_partner_id = app.current_user_id()),
    'worker',        (select jsonb_build_object('id', w.id, 'name', w.name)
                      from public.app_user w where w.id = c.assigned_partner_id),
    'bundle',        o.bundle,
    'property',      (select jsonb_build_object(
                        'state', p.state, 'lga', p.lga, 'locality', p.locality,
                        'identifying_details', p.identifying_details)
                      from public.property p where p.id = o.property_id),
    'buyer_documents', coalesce((select jsonb_agg(jsonb_build_object(
                        'label', bd.label, 'doc_type', bd.doc_type,
                        'uploaded_at', bd.uploaded_at) order by bd.uploaded_at)
                      from public.buyer_document bd where bd.order_id = o.id), '[]'::jsonb),
    'evidence', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', e.id, 'kind', e.kind, 'label', e.label,
                        'content_hash', e.content_hash,
                        'storage_ref', e.storage_ref,
                        'capture_channel', e.capture_channel,
                        'captured_at', coalesce(e.captured_at, e.synced_at),
                        'voided', (vv.evidence_id is not null),
                        'void_reason', vv.reason
                      ) order by e.created_at)
                      from public.evidence_item e
                      left join public.evidence_void vv on vv.evidence_id = e.id
                      where e.check_id = c.id), '[]'::jsonb),
    'findings_text', (select e.body_text from public.evidence_item e
                      left join public.evidence_void vv on vv.evidence_id = e.id
                      where e.check_id = c.id and e.kind = 'findings_summary'
                        and vv.evidence_id is null
                      order by e.created_at desc limit 1),
    'last_reason',   (select a.reason from public.audit_event a
                      where a.check_id = c.id and a.action = 'state_change'
                        and a.to_state in ('returned_for_fix','exception')
                        and a.reason is not null
                      order by a.occurred_at desc limit 1),
    'verdict',       (select vd.colour from public.verdict vd where vd.check_id = c.id)
  )
  into v
  from public.check_item c
  join public.service_catalogue sc on sc.code = c.service_code
  join public.order_matter o       on o.id    = c.order_id
  where c.id = p_check;

  return coalesce(v, jsonb_build_object('visible', false));
end;
$function$;

select app.write_audit('migration', null, 'applied', null, null,
  'Increment 3 — Reviewer bench read model: desk_queue (intake / in review / exceptions); check_workspace + worker identity, storage_ref, updated_at');
