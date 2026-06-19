-- =============================================================================
-- 0007  Payment + Government Fee (append-only three-state ledger)
-- =============================================================================
-- Section 10 + Decision G/J-3. Money type is numeric(14,2) (portable and exact) rather
-- than the locale-dependent `money` type. Government-fee STATE is modelled as an append-only
-- transition ledger, NOT a mutable column: the locked invariant says a refund "adds a state
-- on top of held" and "never erases history". The ERD shows state as a column; honouring
-- Decision G requires the ledger, so current state is DERIVED. (Flagged for ratification.)

-- PAYMENT (one per order) ----------------------------------------------------
create table public.payment (
  id                   uuid primary key default gen_random_uuid(),
  order_id             uuid not null unique references public.order_matter(id) on delete restrict,
  currency             text not null default 'NGN',
  service_fee          numeric(14,2) not null default 0,   -- non-refundable once work begins
  government_fee_total numeric(14,2) not null default 0,   -- itemised total (informational; see government_fee)
  gateway_ref          text,
  webhook_verified     boolean not null default false,     -- set by signature-verified, idempotent webhook
  paid_at              timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz
);
comment on table public.payment is 'Split payment per order (Section 10). Confirmation flips webhook_verified via a verified, idempotent webhook (service role).';
alter table public.payment enable row level security;

-- GOVERNMENT_FEE core (immutable once created) -------------------------------
create table public.government_fee (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.order_matter(id) on delete restrict,
  check_id         uuid references public.check_item(id) on delete restrict,
  process          text not null,                 -- e.g. "Lagos Lands Registry CTC fee"
  amount_estimated numeric(14,2),
  currency         text not null default 'NGN',
  created_at       timestamptz not null default now()
);
comment on table public.government_fee is 'One official fee. Core row is immutable; its lifecycle lives in government_fee_transition (Decision G).';
create index gov_fee_order_idx on public.government_fee (order_id);
alter table public.government_fee enable row level security;
-- core is immutable: edits would be "overwriting" money records
create trigger government_fee_block_modification
  before update or delete on public.government_fee
  for each row execute function app.tg_block_modification();

-- GOVERNMENT_FEE_TRANSITION (the append-only three-state ledger) --------------
create table public.government_fee_transition (
  id                  uuid primary key default gen_random_uuid(),
  seq                 bigint generated always as identity,
  government_fee_id   uuid not null references public.government_fee(id) on delete restrict,
  to_state            public.gov_fee_state not null,
  amount              numeric(14,2),                          -- amount disbursed/refunded for this transition
  receipt_evidence_id uuid references public.evidence_item(id),  -- required for paid_with_receipt
  reason              text,
  actor_id            uuid default app.current_user_id(),
  occurred_at         timestamptz not null default now()
);
comment on table public.government_fee_transition is 'Append-only ledger: held -> paid_with_receipt | refunded. No fourth state; terminal once paid or refunded.';
create index gov_fee_txn_fee_idx on public.government_fee_transition (government_fee_id, seq);
alter table public.government_fee_transition enable row level security;

-- Enforce the three-state rule and append-only nature in the database.
create or replace function app.tg_gov_fee_transition()
returns trigger language plpgsql security definer set search_path = '' as $$
declare last_state public.gov_fee_state;
begin
  select t.to_state into last_state
  from public.government_fee_transition t
  where t.government_fee_id = new.government_fee_id
  order by t.seq desc
  limit 1;

  if last_state is null then
    if new.to_state <> 'held' then
      raise exception 'A government fee must first be recorded as held.' using errcode = 'check_violation';
    end if;
  else
    if last_state in ('paid_with_receipt','refunded') then
      raise exception 'Government fee is terminal (%) and cannot transition further.', last_state using errcode = 'check_violation';
    end if;
    if last_state = 'held' and new.to_state not in ('paid_with_receipt','refunded') then
      raise exception 'From held a government fee may only move to paid_with_receipt or refunded.' using errcode = 'check_violation';
    end if;
  end if;

  if new.to_state = 'paid_with_receipt' and new.receipt_evidence_id is null then
    raise exception 'paid_with_receipt requires the official receipt (receipt_evidence_id).' using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger gov_fee_transition_rules
  before insert on public.government_fee_transition
  for each row execute function app.tg_gov_fee_transition();

create trigger gov_fee_transition_block_modification
  before update or delete on public.government_fee_transition
  for each row execute function app.tg_block_modification();

-- DERIVED current state of a government fee (latest transition).
create or replace function app.gov_fee_state(p_fee uuid)
returns public.gov_fee_state language sql stable security definer set search_path = '' as $$
  select t.to_state
  from public.government_fee_transition t
  where t.government_fee_id = p_fee
  order by t.seq desc
  limit 1;
$$;
