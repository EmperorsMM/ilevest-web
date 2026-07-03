-- =============================================================================
-- Ilevest — Increment 1 addendum: the commitment ceremony door.
-- Fingerprints are written only inside seal_check, exactly like verdicts and
-- the finalized state itself. A raw commitment insert (even by a Reviewer,
-- even by superuser-adjacent tooling) is refused, closing the last raw path
-- around the sealing ceremony. seal_check is re-issued with the ceremony
-- latch held until the fingerprint and manifest are written.
-- Apply once on dev after 20260703160000. Idempotent.
-- =============================================================================

create or replace function app.tg_commitment_via_seal()
 returns trigger language plpgsql
as $function$
begin
  if current_setting('app.sealing_check', true) is distinct from new.check_id::text then
    raise exception 'Commitments are recorded only through seal_check (the sealing ceremony).' using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

drop trigger if exists commitment_ceremony_door on public.commitment;
create trigger commitment_ceremony_door before insert on public.commitment
  for each row execute function app.tg_commitment_via_seal();

create or replace function public.seal_check(p_check uuid, p_colour verdict_colour, p_explanation text)
 returns jsonb language plpgsql security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_canon text; v_hash text; v_prev text; v_commit uuid;
  v_order uuid; v_service text; v_state check_state;
  v_worked uuid; v_self boolean;
begin
  if not app.is_reviewer() then
    raise exception 'Only a Reviewer may seal a check.' using errcode = 'check_violation';
  end if;

  select order_id, service_code, state, worked_by
    into v_order, v_service, v_state, v_worked
    from public.check_item where id = p_check;
  if not found then
    raise exception 'Check % not found.', p_check using errcode = 'no_data_found';
  end if;
  if v_state <> 'in_review' then
    raise exception 'A check is sealed from review only (current state: %).', v_state using errcode = 'check_violation';
  end if;
  if p_explanation is null or length(btrim(p_explanation)) = 0 then
    raise exception 'Sealing requires the Reviewer''s explanation — it becomes part of the sealed record.' using errcode = 'check_violation';
  end if;

  -- open the ceremony door for exactly this check
  perform set_config('app.sealing_check', p_check::text, true);

  insert into public.verdict(check_id, colour, explanation) values (p_check, p_colour, p_explanation);
  update public.check_item set state = 'finalized' where id = p_check;

  -- canonical content: same recipe as always, over the non-voided evidence set
  select p_check::text || '|' || coalesce(v_service,'') || '|' || p_colour::text || '|' || coalesce(p_explanation,'')
         || '|' || coalesce(string_agg(e.content_hash, ',' order by e.id), '')
         || '|' || coalesce(v_order::text,'')
    into v_canon
  from public.evidence_item e
  left join public.evidence_void vv on vv.evidence_id = e.id
  where e.check_id = p_check and vv.evidence_id is null;

  v_hash := encode(digest(v_canon, 'sha256'), 'hex');

  insert into public.commitment(check_id, content_hash) values (p_check, v_hash)
    returning id, prev_hash into v_commit, v_prev;

  -- the frozen manifest: exactly what this seal covers (D3)
  insert into public.sealed_evidence(commitment_id, position, evidence_id, content_hash)
  select v_commit, row_number() over (order by e.id), e.id, e.content_hash
  from public.evidence_item e
  left join public.evidence_void vv on vv.evidence_id = e.id
  where e.check_id = p_check and vv.evidence_id is null;

  -- ceremony complete: close the door
  perform set_config('app.sealing_check', '', true);

  -- honesty about who sealed what (D1)
  v_self := (v_worked is not null and v_worked = app.current_user_id())
            or exists (select 1 from public.evidence_item e
                       left join public.evidence_void vv on vv.evidence_id = e.id
                       where e.check_id = p_check and vv.evidence_id is null
                         and e.captured_by = app.current_user_id());
  perform app.write_audit('check', p_check, 'sealed', 'in_review', 'finalized', null, p_check,
    jsonb_build_object('verdict', p_colour, 'self_seal', v_self,
                       'worked_by', v_worked, 'sealed_by', app.current_user_id()));

  -- when the last check of the order is decided, the buyer's verdict is ready
  if not exists (select 1 from public.check_item
                 where order_id = v_order and state not in ('finalized','rejected')) then
    perform app.enqueue_notification(
      (select client_id from public.order_matter where id = v_order),
      'verdict_ready', v_order, '{}'::jsonb);
  end if;

  return jsonb_build_object('check_id', p_check, 'verdict', p_colour,
                            'content_hash', v_hash, 'prev_hash', v_prev,
                            'commitment_id', v_commit, 'self_seal', v_self);
end; $function$;

select app.write_audit('migration', null, 'applied', null, null,
  'Increment 1 addendum — commitment ceremony door: fingerprints are written only by seal_check; latch held through manifest');
