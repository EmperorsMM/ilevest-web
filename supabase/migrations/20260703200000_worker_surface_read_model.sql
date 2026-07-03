-- =============================================================================
-- Ilevest — Increment 2 · The worker surface (read model + evidence storage)
--
-- Two read RPCs shaped for the desk, and the first storage integration:
--
--   my_checks()            SECURITY INVOKER — the signed-in worker's caseload.
--                          RLS does all scoping (check_item, order_matter,
--                          property, evidence are each readable to the assigned
--                          worker under existing policies).
--
--   check_workspace(uuid)  SECURITY DEFINER, guarded — everything the assigned
--                          worker needs on one check: context, evidence index
--                          with void status, live findings text, and the last
--                          return/exception reason. The reason lives on the
--                          audit spine, which workers deliberately cannot read
--                          raw; this read-model hands back ONLY their own
--                          check's latest reason (the Stage-4 order_tracking
--                          pattern: definer + explicit ownership guard).
--
--   storage: bucket `evidence` (private) + path-scoped policies. Uploads go to
--   evidence/{check_id}/{file}; only that check's assigned worker may write,
--   worker + staff may read. No update/delete policies: objects are immutable
--   through the API, like everything else on this desk. The DB evidence row
--   remains the invariant — an object without a row is inert (never in any
--   canon or manifest).
--
--   PORTABILITY: the storage schema is Supabase-hosted. Every storage
--   statement is guarded on its existence, so this migration applies cleanly
--   on vanilla PostgreSQL (CI) — where the desk's law lives entirely in the
--   public schema — and does the real work on dev.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1 · my_checks(): the worker's caseload, actionable-first
-- ---------------------------------------------------------------------------
create or replace function public.my_checks()
 returns jsonb
 language plpgsql stable
 set search_path to ''
as $function$
declare uid uuid := app.current_user_id(); v jsonb;
begin
  if uid is null then return '[]'::jsonb; end if;

  select coalesce(jsonb_agg(s.row order by s.rank, s.updated_at desc nulls last, s.created_at), '[]'::jsonb)
  into v
  from (
    select
      jsonb_build_object(
        'check_id',      c.id,
        'service_code',  c.service_code,
        'title',         sc.title,
        'state',         c.state,
        'bundle',        o.bundle,
        'property',      nullif(concat_ws(', ', p.locality, p.lga, p.state), ''),
        'live_evidence', (select count(*) from public.evidence_item e
                          left join public.evidence_void vv on vv.evidence_id = e.id
                          where e.check_id = c.id and vv.evidence_id is null),
        'has_findings',  exists (select 1 from public.evidence_item e
                          left join public.evidence_void vv on vv.evidence_id = e.id
                          where e.check_id = c.id and e.kind = 'findings_summary'
                            and vv.evidence_id is null),
        'created_at',    c.created_at,
        'updated_at',    c.updated_at
      ) as row,
      case c.state
        when 'returned_for_fix' then 0   -- fix requests first
        when 'assigned'         then 1   -- then new work
        when 'in_progress'      then 2   -- then work in hand
        when 'exception'        then 3
        when 'in_review'        then 4
        else 5                            -- finalized / rejected history last
      end as rank,
      c.updated_at, c.created_at
    from public.check_item c
    join public.service_catalogue sc on sc.code = c.service_code
    join public.order_matter o       on o.id    = c.order_id
    left join public.property p      on p.id    = o.property_id
    where c.assigned_partner_id = uid
  ) s;

  return v;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2 · check_workspace(): one check, everything the worker needs
-- ---------------------------------------------------------------------------
create or replace function public.check_workspace(p_check uuid)
 returns jsonb
 language plpgsql stable security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v jsonb;
begin
  -- the guard: the assigned worker or staff, nobody else
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
    'i_am_worker',   (c.assigned_partner_id = app.current_user_id()),
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

grant execute on function public.my_checks() to authenticated;
grant execute on function public.check_workspace(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3 · Evidence storage (Supabase-hosted; guarded for vanilla PostgreSQL)
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not present (vanilla PostgreSQL) — skipping bucket + policies; the desk''s law lives in public.';
    return;
  end if;

  insert into storage.buckets (id, name, public)
  values ('evidence', 'evidence', false)
  on conflict (id) do nothing;

  -- uploads: only the assigned worker, only into their check's folder
  drop policy if exists evidence_objects_insert on storage.objects;
  create policy evidence_objects_insert on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'evidence'
      and app.partner_on_check(((storage.foldername(name))[1])::uuid)
    );

  -- reads: the assigned worker and staff (the buyer reads fingerprints, not files)
  drop policy if exists evidence_objects_select on storage.objects;
  create policy evidence_objects_select on storage.objects
    for select to authenticated
    using (
      bucket_id = 'evidence'
      and (app.is_staff() or app.partner_on_check(((storage.foldername(name))[1])::uuid))
    );

  -- deliberately NO update and NO delete policies: immutable through the API.
end $$;

select app.write_audit('migration', null, 'applied', null, null,
  'Increment 2 — worker surface read model (my_checks, check_workspace) + evidence bucket with worker-scoped, immutable storage policies');
