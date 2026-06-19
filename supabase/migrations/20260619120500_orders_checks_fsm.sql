-- =============================================================================
-- 0005  Order/Matter (parent) + Check/Milestone (child, runs the FSM)
-- =============================================================================
-- Decision A: the order/Matter is a parent container; the check/milestone is the child
-- that moves through the FSM. The parent is "Ready" only when all children are Finalized
-- (status is DERIVED, never stored — see app.order_status()).

-- ORDER / MATTER -------------------------------------------------------------
create table public.order_matter (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references public.app_user(id) on delete restrict,
  property_id uuid references public.property(id) on delete restrict,
  party_id    uuid references public.party_seller(id) on delete restrict,
  bundle      public.order_bundle,
  created_at  timestamptz not null default now()
);
comment on table public.order_matter is 'Parent container (Category 1 Order / Category 2 Matter). Status is derived from children, never stored.';
create index order_client_idx on public.order_matter (client_id);
alter table public.order_matter enable row level security;

-- CHECK / MILESTONE ----------------------------------------------------------
create table public.check_item (
  id                  uuid primary key default gen_random_uuid(),
  order_id            uuid not null references public.order_matter(id) on delete restrict,
  assigned_partner_id uuid references public.app_user(id) on delete restrict,
  service_code        text not null,        -- C1-LR-01 ... C1-FD-01 (catalogue may grow; kept as text)
  state               public.check_state not null default 'initiated',
  is_finalized        boolean not null default false,
  sealed_at           timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz
);
comment on table public.check_item is 'The child that runs the FSM (Decision A). Finalized is permanent and immutable (Decision D).';
create index check_order_idx   on public.check_item (order_id);
create index check_partner_idx on public.check_item (assigned_partner_id);
alter table public.check_item enable row level security;

-- Now that check_item exists, attach the convenience FK from the audit spine.
alter table public.audit_event
  add constraint audit_event_check_fk foreign key (check_id) references public.check_item(id);

-- ---------------------------------------------------------------------------
-- FSM enforcement: legal transitions, role-gating per transition, and the
-- permanent immutability of a finalized check. Enforced in the database so a bug
-- (or a malicious actor) in app code cannot drive an illegal or unauthorised state move.
-- Legal transitions (from the locked FSM / Mermaid diagram):
--   initiated -> assigned
--   assigned -> in_progress
--   in_progress -> in_review | exception
--   exception -> in_progress (retry first) | finalized (Unresolved, human Ops give-up)
--   in_review -> returned_for_fix | finalized | rejected
--   returned_for_fix -> in_review
--   finalized, rejected = terminal
-- ---------------------------------------------------------------------------
create or replace function app.tg_check_fsm()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  v_t text;
begin
  if tg_op = 'INSERT' then
    -- every check enters through the front door
    if new.state <> 'initiated' then
      raise exception 'A new check must start in state initiated (got %).', new.state
        using errcode = 'check_violation';
    end if;
    new.is_finalized := false;
    return new;
  end if;

  -- UPDATE
  if old.is_finalized then
    raise exception 'Check % is finalized and permanently immutable; corrections require a superseding verification (Decision D).', old.id
      using errcode = 'check_violation';
  end if;
  if old.state = 'rejected' then
    raise exception 'Check % is rejected (terminal) and cannot change.', old.id
      using errcode = 'check_violation';
  end if;

  if new.state is distinct from old.state then
    v_t := old.state::text || '->' || new.state::text;

    -- 1) transition must be legal
    if v_t not in (
      'initiated->assigned','assigned->in_progress',
      'in_progress->in_review','in_progress->exception',
      'exception->in_progress','exception->finalized',
      'in_review->returned_for_fix','in_review->finalized','in_review->rejected',
      'returned_for_fix->in_review'
    ) then
      raise exception 'Illegal check state transition: %', v_t using errcode = 'check_violation';
    end if;

    -- 2) the right role must perform it (the corruption-gap separation, in the DB)
    if v_t = 'initiated->assigned' then
      if not app.is_ops() then
        raise exception 'Only Ops/Admin may assign a check.' using errcode = 'check_violation';
      end if;
    elsif v_t in ('assigned->in_progress','in_progress->in_review','in_progress->exception',
                  'exception->in_progress','returned_for_fix->in_review') then
      if not (old.assigned_partner_id = app.current_user_id() or app.is_staff()) then
        raise exception 'Only the assigned partner (or staff) may perform: %', v_t using errcode = 'check_violation';
      end if;
    elsif v_t in ('in_review->returned_for_fix','in_review->finalized','in_review->rejected','exception->finalized') then
      if not app.is_reviewer() and not app.is_ops() then
        raise exception 'Only a Reviewer/Ops/Admin may review, finalize, reject, or close: %', v_t using errcode = 'check_violation';
      end if;
    end if;

    -- 3) finalize bookkeeping (one-way: the row becomes immutable hereafter)
    if new.state = 'finalized' then
      new.is_finalized := true;
      new.sealed_at := coalesce(new.sealed_at, now());
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger check_item_fsm
  before insert or update on public.check_item
  for each row execute function app.tg_check_fsm();

-- Audit every check creation and state change to the spine.
create or replace function app.tg_audit_check_state()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform app.write_audit('check', new.id, 'created', null, new.state::text, null, new.id);
  elsif new.state is distinct from old.state then
    perform app.write_audit('check', new.id, 'state_change', old.state::text, new.state::text, null, new.id);
  end if;
  return null;
end;
$$;

create trigger check_item_audit
  after insert or update on public.check_item
  for each row execute function app.tg_audit_check_state();

-- DERIVED order status (never stored). Ready only when all children are Finalized.
create or replace function app.order_status(p_order uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when not exists (select 1 from public.check_item c where c.order_id = p_order) then 'initiated'
    when bool_and(c.state = 'finalized') then 'ready'
    when bool_or(c.state in ('in_review','returned_for_fix')) then 'in_review'
    when bool_or(c.state in ('assigned','in_progress','exception')) then 'in_progress'
    else 'assigned'
  end
  from public.check_item c where c.order_id = p_order;
$$;

-- NOTE: app.order_headline_verdict() depends on the verdict table and is defined in 0008.
