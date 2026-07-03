-- ================================================================
-- ILEVEST · INCREMENT 1 — THE FULFILMENT DESK (database layer)
-- Implements ratified Decisions D1–D5 of the Reviewer/Fulfilment
-- Desk design, and closes the gaps found by the read-first
-- introspection of 2 Jul 2026.
--
-- Apply once, in the Supabase SQL Editor, on ilevest-dev.
-- The whole file runs as one transaction.
-- ================================================================

set local check_function_bodies = off;

-- ----------------------------------------------------------------
-- 1 · Evidence kinds for the desk (additive; existing kinds keep working)
-- ----------------------------------------------------------------
alter type public.evidence_kind add value if not exists 'document';           -- generic uploaded file
alter type public.evidence_kind add value if not exists 'findings_summary';   -- the worker's written findings (D2)
alter type public.evidence_kind add value if not exists 'promoted_buyer_doc'; -- buyer doc promoted into evidence

-- ----------------------------------------------------------------
-- 2 · Evidence columns: channel honesty, findings text, display label
-- ----------------------------------------------------------------
alter table public.evidence_item
  add column if not exists capture_channel text not null default 'web'
    check (capture_channel in ('web','device')),
  add column if not exists body_text text,
  add column if not exists label text;

comment on column public.evidence_item.capture_channel is
  'How the item was captured: web (browser upload, hash recomputed server-side) or device (future Oracle app, device-attested). Honesty about provenance, not a trust downgrade.';
comment on column public.evidence_item.body_text is
  'For findings_summary (and optionally notes): the narrative itself. content_hash must be the SHA-256 of this text, so the sealed fingerprint covers the words the buyer will read.';

-- ----------------------------------------------------------------
-- 3 · Authorship on the check: who worked it, who sealed it (D1)
--     Stamped ONLY by the FSM trigger; caller-supplied changes refused.
-- ----------------------------------------------------------------
alter table public.check_item
  add column if not exists worked_by uuid references public.app_user(id),
  add column if not exists sealed_by uuid references public.app_user(id);

-- ----------------------------------------------------------------
-- 4 · Desk configuration singleton (billing_config pattern)
--     block_self_seal ships OFF; the structural guard exists from day one (D1).
-- ----------------------------------------------------------------
create table if not exists public.desk_config (
  id boolean primary key default true check (id),
  block_self_seal boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.desk_config default values on conflict (id) do nothing;
alter table public.desk_config enable row level security;  -- no policies: belt and braces
revoke all on public.desk_config from anon, authenticated;

create or replace function public.get_desk_config()
 returns jsonb language plpgsql stable security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare v jsonb;
begin
  if not app.is_staff() then raise exception 'Staff only.' using errcode = '42501'; end if;
  select jsonb_build_object('block_self_seal', block_self_seal, 'updated_at', updated_at)
    into v from public.desk_config where id;
  return v;
end; $function$;

create or replace function public.set_desk_config(p_block_self_seal boolean)
 returns void language plpgsql security definer
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
begin
  if not app.is_admin() then raise exception 'Admin only.' using errcode = '42501'; end if;
  update public.desk_config
     set block_self_seal = p_block_self_seal, updated_at = now()
   where id;
  perform app.write_audit('desk_config', null, 'config_changed',
    p_metadata => jsonb_build_object('block_self_seal', p_block_self_seal));
end; $function$;

-- ----------------------------------------------------------------
-- 5 · Pre-seal void markers (D3): append-only, capturer-only,
--     mandatory reason, visible forever. Never deletes evidence.
-- ----------------------------------------------------------------
create table if not exists public.evidence_void (
  id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null unique references public.evidence_item(id),
  check_id uuid not null references public.check_item(id),
  voided_by uuid not null default app.current_user_id() references public.app_user(id),
  reason text not null check (length(btrim(reason)) >= 5),
  created_at timestamptz not null default now()
);

create or replace function app.tg_evidence_void_rules()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare v_captured_by uuid; v_check uuid; v_state public.check_state; v_final boolean; v_worker uuid;
begin
  select e.captured_by, e.check_id into v_captured_by, v_check
    from public.evidence_item e where e.id = new.evidence_id;
  if not found then
    raise exception 'Evidence % not found.', new.evidence_id using errcode = 'no_data_found';
  end if;
  if new.check_id is distinct from v_check then
    raise exception 'Void marker must reference the evidence''s own check.' using errcode = 'check_violation';
  end if;
  select c.state, c.is_finalized, c.assigned_partner_id into v_state, v_final, v_worker
    from public.check_item c where c.id = v_check;
  if v_final then
    raise exception 'This check is sealed; its evidence can no longer be voided. Corrections require a superseding verification.' using errcode = 'check_violation';
  end if;
  if v_state not in ('in_progress','returned_for_fix') then
    raise exception 'Evidence can only be voided while the check is being worked (in progress / returned for fix); current state: %.', v_state using errcode = 'check_violation';
  end if;
  if new.voided_by is distinct from app.current_user_id() then
    raise exception 'A void marker is signed by the person creating it.' using errcode = 'check_violation';
  end if;
  if v_captured_by is distinct from app.current_user_id() then
    raise exception 'Only the worker who captured an item may void it (with a reason). Reviewers return the check instead.' using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

drop trigger if exists evidence_void_rules on public.evidence_void;
create trigger evidence_void_rules before insert on public.evidence_void
  for each row execute function app.tg_evidence_void_rules();

drop trigger if exists evidence_void_block_modification on public.evidence_void;
create trigger evidence_void_block_modification before delete or update on public.evidence_void
  for each row execute function app.tg_block_modification();

create or replace function app.tg_audit_evidence_void()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  perform app.write_audit('evidence', new.evidence_id, 'evidence_voided',
                          null, null, new.reason, new.check_id,
                          jsonb_build_object('voided_by', new.voided_by));
  return null;
end;
$function$;

drop trigger if exists evidence_void_audit on public.evidence_void;
create trigger evidence_void_audit after insert on public.evidence_void
  for each row execute function app.tg_audit_evidence_void();

alter table public.evidence_void enable row level security;
drop policy if exists evidence_void_insert on public.evidence_void;
create policy evidence_void_insert on public.evidence_void for insert to authenticated
  with check ((voided_by = app.current_user_id()) and app.partner_on_check(check_id));
drop policy if exists evidence_void_select on public.evidence_void;
create policy evidence_void_select on public.evidence_void for select to authenticated
  using (app.is_staff() or app.partner_on_check(check_id) or app.owns_check(check_id));
grant select, insert on public.evidence_void to authenticated;

-- ----------------------------------------------------------------
-- 6 · Sealed-evidence manifest (D3): the frozen list of exactly which
--     evidence items (and hashes) each seal covers. Append-only.
--     Written only inside seal_check; verification reads it.
-- ----------------------------------------------------------------
create table if not exists public.sealed_evidence (
  commitment_id uuid not null references public.commitment(id),
  position int not null,
  evidence_id uuid not null references public.evidence_item(id),
  content_hash text not null,
  primary key (commitment_id, position),
  unique (commitment_id, evidence_id)
);

drop trigger if exists sealed_evidence_block_modification on public.sealed_evidence;
create trigger sealed_evidence_block_modification before delete or update on public.sealed_evidence
  for each row execute function app.tg_block_modification();

alter table public.sealed_evidence enable row level security;
drop policy if exists sealed_evidence_select on public.sealed_evidence;
create policy sealed_evidence_select on public.sealed_evidence for select to authenticated
  using (exists (select 1 from public.commitment c
                 where c.id = sealed_evidence.commitment_id
                   and (app.is_staff() or app.owns_check(c.check_id) or app.partner_on_check(c.check_id))));
grant select on public.sealed_evidence to authenticated;
-- deliberately NO insert grant: rows are written only by seal_check (definer).

-- ----------------------------------------------------------------
-- 7 · Evidence capture rules (the invariant, on the table itself):
--     only the assigned worker, only while the check is being worked,
--     never after sealing; findings carry their own text and its hash.
-- ----------------------------------------------------------------
create or replace function app.tg_evidence_rules()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare v_state public.check_state; v_final boolean; v_worker uuid;
begin
  select c.state, c.is_finalized, c.assigned_partner_id
    into v_state, v_final, v_worker
    from public.check_item c where c.id = new.check_id;
  if not found then
    raise exception 'Check % not found.', new.check_id using errcode = 'no_data_found';
  end if;
  if v_final then
    raise exception 'This check is sealed and permanently immutable; evidence can no longer be attached.' using errcode = 'check_violation';
  end if;
  if v_state not in ('in_progress','returned_for_fix') then
    raise exception 'Evidence can only be captured while the check is being worked (in progress / returned for fix); current state: %.', v_state using errcode = 'check_violation';
  end if;

  new.captured_by := coalesce(new.captured_by, app.current_user_id());
  if new.captured_by is distinct from app.current_user_id() then
    raise exception 'Evidence is signed by the person capturing it; captured_by cannot be set to someone else.' using errcode = 'check_violation';
  end if;
  if v_worker is distinct from new.captured_by then
    raise exception 'Only the assigned worker may capture evidence on this check.' using errcode = 'check_violation';
  end if;

  if new.capture_channel is null then new.capture_channel := 'web'; end if;

  -- findings discipline (D2): the narrative is itself hashed evidence
  if new.body_text is not null then
    if new.content_hash is distinct from encode(extensions.digest(new.body_text, 'sha256'), 'hex') then
      raise exception 'content_hash must be the SHA-256 of body_text, so the sealed fingerprint covers the exact words shown.' using errcode = 'check_violation';
    end if;
  end if;
  if new.kind = 'findings_summary' then
    if new.body_text is null or length(btrim(new.body_text)) = 0 then
      raise exception 'A findings summary must contain the findings text ("nothing found" is itself a finding — write it up).' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.evidence_item e
               left join public.evidence_void vv on vv.evidence_id = e.id
               where e.check_id = new.check_id and e.kind = 'findings_summary' and vv.evidence_id is null) then
      raise exception 'A findings summary already exists for this check; void it (with a reason) to write a corrected one.' using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists evidence_item_rules on public.evidence_item;
create trigger evidence_item_rules before insert on public.evidence_item
  for each row execute function app.tg_evidence_rules();

-- Tighten the insert policy: assigned worker only (staff blanket removed —
-- Admin could previously attach evidence to any check in any state).
drop policy if exists evidence_insert on public.evidence_item;
create policy evidence_insert on public.evidence_item for insert to authenticated
  with check (app.partner_on_check(check_id) and (captured_by = app.current_user_id() or captured_by is null));

-- ----------------------------------------------------------------
-- 8 · Verdicts are created only inside the sealing ceremony
-- ----------------------------------------------------------------
create or replace function app.tg_verdict_via_seal()
 returns trigger language plpgsql
as $function$
begin
  if current_setting('app.sealing_check', true) is distinct from new.check_id::text then
    raise exception 'Verdicts are recorded only through seal_check (the sealing ceremony).' using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

drop trigger if exists verdict_via_seal on public.verdict;
create trigger verdict_via_seal before insert on public.verdict
  for each row execute function app.tg_verdict_via_seal();

-- ----------------------------------------------------------------
-- 9 · The FSM, rewritten to the ratified transition/role matrix.
--     Every gate lives here, on the table, so raw updates obey the
--     same law as the functions.
--
--     initiated → assigned                 Ops
--     assigned → in_progress               assigned worker   (stamps worked_by)
--     assigned/in_progress → exception     assigned worker or Ops   (reason required)
--     in_progress → in_review              assigned worker   (needs live evidence + findings)
--     returned_for_fix → in_review         assigned worker   (same requirements)
--     exception → in_progress   (retry)    Ops
--     exception → in_review    (escalate)  Ops, only after ≥1 retry  (reason required)
--     in_review → returned_for_fix         Reviewer          (reason required)
--     in_review → finalized     (seal)     Reviewer, only via seal_check, verdict present
--     in_review → rejected                 Reviewer          (terminal)
--     exception → finalized                REMOVED (was a bypass of retry-first)
-- ----------------------------------------------------------------
create or replace function app.tg_check_fsm()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare
  v_t text;
  v_uid uuid := app.current_user_id();
  v_reason text := nullif(btrim(coalesce(current_setting('app.transition_reason', true), '')), '');
  v_live int; v_findings int; v_retries int;
  v_self boolean; v_block boolean;
begin
  if tg_op = 'INSERT' then
    if new.state <> 'initiated' then
      raise exception 'A new check must start in state initiated (got %).', new.state
        using errcode = 'check_violation';
    end if;
    new.is_finalized := false;
    new.worked_by := null;
    new.sealed_by := null;
    return new;
  end if;

  -- UPDATE ---------------------------------------------------------
  if old.is_finalized then
    raise exception 'Check % is finalized and permanently immutable; corrections require a superseding verification (Decision D).', old.id
      using errcode = 'check_violation';
  end if;
  if old.state = 'rejected' then
    raise exception 'Check % is rejected (terminal) and cannot change.', old.id
      using errcode = 'check_violation';
  end if;

  -- identity of a live check never changes
  if new.order_id is distinct from old.order_id
     or new.service_code is distinct from old.service_code
     or new.created_at is distinct from old.created_at then
    raise exception 'order_id, service_code and created_at are fixed for the life of a check.' using errcode = 'check_violation';
  end if;

  -- authorship is stamped only by this trigger
  if new.worked_by is distinct from old.worked_by
     or new.sealed_by is distinct from old.sealed_by then
    raise exception 'worked_by and sealed_by are recorded by the system, not set by callers.' using errcode = 'check_violation';
  end if;

  -- bookkeeping fields are outputs, not inputs
  new.is_finalized := old.is_finalized;
  new.sealed_at    := old.sealed_at;

  -- assignment changes: Ops only, and only before work begins
  if new.assigned_partner_id is distinct from old.assigned_partner_id then
    if not app.is_ops() then
      raise exception 'Only Ops may assign or reassign a check.' using errcode = 'check_violation';
    end if;
    if old.state not in ('initiated','assigned') then
      raise exception 'Reassignment after work has begun is not supported in this increment; use return-for-fix or exception first.' using errcode = 'check_violation';
    end if;
    if new.assigned_partner_id is null then
      raise exception 'Un-assigning a check is not supported; reassign it to another worker instead.' using errcode = 'check_violation';
    end if;
  end if;

  if new.state is distinct from old.state then
    v_t := old.state::text || '->' || new.state::text;

    if v_t not in (
      'initiated->assigned',
      'assigned->in_progress',
      'assigned->exception',
      'in_progress->in_review',
      'in_progress->exception',
      'exception->in_progress',
      'exception->in_review',
      'in_review->returned_for_fix',
      'in_review->finalized',
      'in_review->rejected',
      'returned_for_fix->in_review'
    ) then
      raise exception 'Illegal check state transition: %', v_t using errcode = 'check_violation';
    end if;

    if v_t = 'initiated->assigned' then
      if not app.is_ops() then
        raise exception 'Only Ops may assign a check.' using errcode = 'check_violation';
      end if;
      if new.assigned_partner_id is null then
        raise exception 'Assigning a check requires a worker.' using errcode = 'check_violation';
      end if;

    elsif v_t = 'assigned->in_progress' then
      if old.assigned_partner_id is null or old.assigned_partner_id <> v_uid then
        raise exception 'Only the assigned worker may start this check.' using errcode = 'check_violation';
      end if;
      new.worked_by := coalesce(old.worked_by, v_uid);

    elsif v_t in ('in_progress->in_review','returned_for_fix->in_review') then
      if old.assigned_partner_id is null or old.assigned_partner_id <> v_uid then
        raise exception 'Only the assigned worker may submit this check for review.' using errcode = 'check_violation';
      end if;
      select count(*) filter (where vv.evidence_id is null),
             count(*) filter (where vv.evidence_id is null and e.kind = 'findings_summary')
        into v_live, v_findings
        from public.evidence_item e
        left join public.evidence_void vv on vv.evidence_id = e.id
        where e.check_id = old.id;
      if coalesce(v_live, 0) < 1 then
        raise exception 'Cannot submit for review without at least one (non-voided) evidence item.' using errcode = 'check_violation';
      end if;
      if coalesce(v_findings, 0) < 1 then
        raise exception 'Cannot submit for review without a findings summary — "nothing found" is itself a finding; write it up.' using errcode = 'check_violation';
      end if;

    elsif v_t in ('assigned->exception','in_progress->exception') then
      if not (old.assigned_partner_id = v_uid or app.is_ops()) then
        raise exception 'Only the assigned worker or Ops may flag an exception.' using errcode = 'check_violation';
      end if;
      if v_reason is null then
        raise exception 'Flagging an exception requires a reason (what is blocking the check).' using errcode = 'check_violation';
      end if;

    elsif v_t = 'exception->in_progress' then
      if not app.is_ops() then
        raise exception 'Only Ops may retry an exception.' using errcode = 'check_violation';
      end if;

    elsif v_t = 'exception->in_review' then
      if not app.is_ops() then
        raise exception 'Only Ops may escalate an exception for an Unresolved decision.' using errcode = 'check_violation';
      end if;
      select count(*) into v_retries
        from public.audit_event a
        where a.check_id = old.id and a.action = 'state_change'
          and a.from_state = 'exception' and a.to_state = 'in_progress';
      if coalesce(v_retries, 0) < 1 then
        raise exception 'Retry first: an exception must be retried at least once before escalation (Decision D4).' using errcode = 'check_violation';
      end if;
      if v_reason is null then
        raise exception 'Escalating an exception requires a reason for the Reviewer.' using errcode = 'check_violation';
      end if;

    elsif v_t = 'in_review->returned_for_fix' then
      if not app.is_reviewer() then
        raise exception 'Only a Reviewer may return a check for fix.' using errcode = 'check_violation';
      end if;
      if v_reason is null then
        raise exception 'Returning a check requires a reason the worker can act on.' using errcode = 'check_violation';
      end if;

    elsif v_t = 'in_review->rejected' then
      if not app.is_reviewer() then
        raise exception 'Only a Reviewer may reject a check.' using errcode = 'check_violation';
      end if;

    elsif v_t = 'in_review->finalized' then
      if not app.is_reviewer() then
        raise exception 'Only a Reviewer may seal a check.' using errcode = 'check_violation';
      end if;
      if current_setting('app.sealing_check', true) is distinct from old.id::text then
        raise exception 'A check is finalized only through seal_check (the sealing ceremony).' using errcode = 'check_violation';
      end if;
      if not exists (select 1 from public.verdict v where v.check_id = old.id) then
        raise exception 'Sealing requires a verdict.' using errcode = 'check_violation';
      end if;
      new.sealed_by := v_uid;
      -- self-seal guard (Decision D1)
      v_self := (old.worked_by is not null and old.worked_by = v_uid)
                or exists (select 1 from public.evidence_item e
                           left join public.evidence_void vv on vv.evidence_id = e.id
                           where e.check_id = old.id and vv.evidence_id is null
                             and e.captured_by = v_uid);
      select block_self_seal into v_block from public.desk_config where id;
      if v_self and coalesce(v_block, false) then
        raise exception 'Self-seal is blocked by configuration: the sealing Reviewer worked or evidenced this check (Decision D1).' using errcode = 'check_violation';
      end if;
    end if;

    if new.state = 'finalized' then
      new.is_finalized := true;
      new.sealed_at := coalesce(new.sealed_at, now());
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

-- ----------------------------------------------------------------
-- 10 · Audit trigger: keep state changes, add the reason (when one
--      was supplied through a desk action) and assignment changes.
-- ----------------------------------------------------------------
create or replace function app.tg_audit_check_state()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' then
    perform app.write_audit('check', new.id, 'created', null, new.state::text, null, new.id);
    return null;
  end if;
  if new.state is distinct from old.state then
    perform app.write_audit('check', new.id, 'state_change', old.state::text, new.state::text,
                            nullif(btrim(coalesce(current_setting('app.transition_reason', true), '')), ''),
                            new.id);
  end if;
  if new.assigned_partner_id is distinct from old.assigned_partner_id then
    perform app.write_audit('check', new.id, 'assignment_changed',
                            old.assigned_partner_id::text, new.assigned_partner_id::text, null, new.id,
                            jsonb_build_object('from_worker', old.assigned_partner_id,
                                               'to_worker',   new.assigned_partner_id));
  end if;
  return null;
end;
$function$;

-- ----------------------------------------------------------------
-- 11 · seal_check: the two-step ceremony's server half, amended.
--      Reviewer-only (message now matches the gate), in_review only,
--      explanation required, voided evidence excluded, manifest
--      written, self-seal recorded honestly. The canonical recipe
--      is byte-identical to the original for checks with no voids,
--      so every already-anchored record still verifies.
-- ----------------------------------------------------------------
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

  perform set_config('app.sealing_check', '', true);

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

-- ----------------------------------------------------------------
-- 12 · record_evidence: same front door, three new optional fields
--      (label, body_text, capture_channel). Old callers keep working;
--      the capture rules trigger enforces the law either way.
-- ----------------------------------------------------------------
drop function if exists public.record_evidence(uuid, evidence_kind, text, text, double precision, double precision, double precision, timestamptz, text);

create or replace function public.record_evidence(
  p_check uuid, p_kind evidence_kind, p_content_hash text,
  p_storage_ref text default null,
  p_gps_lat double precision default null, p_gps_lng double precision default null,
  p_gps_accuracy double precision default null,
  p_captured_at timestamptz default null, p_device_id text default null,
  p_label text default null, p_body_text text default null,
  p_capture_channel text default 'web')
 returns uuid language plpgsql set search_path to ''
as $function$
declare v_id uuid;
begin
  insert into public.evidence_item(check_id, kind, content_hash, storage_ref,
                                   gps_lat, gps_lng, gps_accuracy, captured_at, device_id,
                                   label, body_text, capture_channel)
  values (p_check, p_kind, p_content_hash, p_storage_ref,
          p_gps_lat, p_gps_lng, p_gps_accuracy, p_captured_at, p_device_id,
          p_label, p_body_text, coalesce(p_capture_channel, 'web'))
  returning id into v_id;
  return v_id;
end; $function$;

-- ----------------------------------------------------------------
-- 13 · Findings: written server-side so the hash discipline is automatic
-- ----------------------------------------------------------------
create or replace function public.record_findings(p_check uuid, p_text text)
 returns uuid language plpgsql set search_path to ''
as $function$
declare v_id uuid;
begin
  if p_text is null or length(btrim(p_text)) = 0 then
    raise exception 'Findings cannot be empty — "nothing found" is itself a finding; write it up.' using errcode = 'check_violation';
  end if;
  insert into public.evidence_item(check_id, kind, content_hash, body_text, capture_channel, label)
  values (p_check, 'findings_summary',
          encode(extensions.digest(p_text, 'sha256'), 'hex'),
          p_text, 'web', 'Findings summary')
  returning id into v_id;
  return v_id;
end; $function$;

-- ----------------------------------------------------------------
-- 14 · Thin desk actions: friendly names over the FSM. The trigger is
--      the law; these set the reason and give clear errors.
-- ----------------------------------------------------------------
create or replace function public.start_check(p_check uuid)
 returns void language plpgsql set search_path to ''
as $function$
begin
  update public.check_item set state = 'in_progress' where id = p_check;
  if not found then
    raise exception 'Check % not found or not visible.', p_check using errcode = 'no_data_found';
  end if;
end; $function$;

create or replace function public.submit_for_review(p_check uuid)
 returns void language plpgsql set search_path to ''
as $function$
begin
  update public.check_item set state = 'in_review' where id = p_check;
  if not found then
    raise exception 'Check % not found or not visible.', p_check using errcode = 'no_data_found';
  end if;
end; $function$;

create or replace function public.return_for_fix(p_check uuid, p_reason text)
 returns void language plpgsql set search_path to ''
as $function$
begin
  if p_reason is null or length(btrim(p_reason)) < 5 then
    raise exception 'Returning a check requires a reason the worker can act on.' using errcode = 'check_violation';
  end if;
  perform set_config('app.transition_reason', p_reason, true);
  update public.check_item set state = 'returned_for_fix' where id = p_check;
  perform set_config('app.transition_reason', '', true);
  if not found then
    raise exception 'Check % not found or not visible.', p_check using errcode = 'no_data_found';
  end if;
end; $function$;

create or replace function public.flag_exception(p_check uuid, p_reason text)
 returns void language plpgsql set search_path to ''
as $function$
begin
  if p_reason is null or length(btrim(p_reason)) < 5 then
    raise exception 'Flagging an exception requires a reason (what is blocking the check).' using errcode = 'check_violation';
  end if;
  perform set_config('app.transition_reason', p_reason, true);
  update public.check_item set state = 'exception' where id = p_check;
  perform set_config('app.transition_reason', '', true);
  if not found then
    raise exception 'Check % not found or not visible.', p_check using errcode = 'no_data_found';
  end if;
end; $function$;

create or replace function public.retry_exception(p_check uuid)
 returns void language plpgsql set search_path to ''
as $function$
begin
  update public.check_item set state = 'in_progress' where id = p_check;
  if not found then
    raise exception 'Check % not found or not visible.', p_check using errcode = 'no_data_found';
  end if;
end; $function$;

create or replace function public.escalate_exception(p_check uuid, p_reason text)
 returns void language plpgsql set search_path to ''
as $function$
begin
  if p_reason is null or length(btrim(p_reason)) < 5 then
    raise exception 'Escalating an exception requires a reason for the Reviewer.' using errcode = 'check_violation';
  end if;
  perform set_config('app.transition_reason', p_reason, true);
  update public.check_item set state = 'in_review' where id = p_check;
  perform set_config('app.transition_reason', '', true);
  if not found then
    raise exception 'Check % not found or not visible.', p_check using errcode = 'no_data_found';
  end if;
end; $function$;

create or replace function public.void_evidence(p_evidence uuid, p_reason text)
 returns uuid language plpgsql set search_path to ''
as $function$
declare v_id uuid;
begin
  insert into public.evidence_void(evidence_id, check_id, reason)
  select e.id, e.check_id, p_reason
  from public.evidence_item e where e.id = p_evidence
  returning id into v_id;
  if v_id is null then
    raise exception 'Evidence % not found or not visible.', p_evidence using errcode = 'no_data_found';
  end if;
  return v_id;
end; $function$;

-- ----------------------------------------------------------------
-- 15 · assign_check: unchanged behaviour, honest message (gate was
--      always Ops via the FSM; the text used to say "Ops/Admin").
-- ----------------------------------------------------------------
create or replace function public.assign_check(p_check uuid, p_worker uuid)
 returns void language plpgsql set search_path to ''
as $function$
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
end; $function$;

-- ----------------------------------------------------------------
-- 16 · Evidence index: now shows channel, label and void status
--      (hashes and metadata only — never raw content).
-- ----------------------------------------------------------------
create or replace view public.evidence_index as
 select e.id,
        e.check_id,
        e.kind,
        e.content_hash,
        e.gps_lat,
        e.gps_lng,
        e.gps_accuracy,
        e.captured_at,
        e.synced_at,
        e.capture_channel,
        e.label,
        (vv.evidence_id is not null) as voided,
        vv.reason as void_reason
   from public.evidence_item e
   left join public.evidence_void vv on vv.evidence_id = e.id
  where app.is_staff() or app.partner_on_check(e.check_id) or app.owns_check(e.check_id);

-- ----------------------------------------------------------------
-- 17 · Grants for the new functions
-- ----------------------------------------------------------------
grant execute on function public.get_desk_config() to authenticated;
grant execute on function public.set_desk_config(boolean) to authenticated;
grant execute on function public.record_evidence(uuid, evidence_kind, text, text, double precision, double precision, double precision, timestamptz, text, text, text, text) to authenticated;
grant execute on function public.record_findings(uuid, text) to authenticated;
grant execute on function public.start_check(uuid) to authenticated;
grant execute on function public.submit_for_review(uuid) to authenticated;
grant execute on function public.return_for_fix(uuid, text) to authenticated;
grant execute on function public.flag_exception(uuid, text) to authenticated;
grant execute on function public.retry_exception(uuid) to authenticated;
grant execute on function public.escalate_exception(uuid, text) to authenticated;
grant execute on function public.void_evidence(uuid, text) to authenticated;
grant select on public.evidence_index to authenticated;

-- ----------------------------------------------------------------
-- 18 · Leave a mark in the audit spine
-- ----------------------------------------------------------------
select app.write_audit('migration', null, 'applied', null, null,
  'Increment 1 — Fulfilment Desk: FSM tightened to ratified matrix, sealing ceremony door, void markers, sealed-evidence manifest, findings discipline, worked_by/sealed_by, desk_config (block_self_seal off)');
