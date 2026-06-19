-- =============================================================================
-- 0009  Commitment (PostgreSQL hash-chain) + Anchor Batch (Section 14)
-- =============================================================================
-- Layer 1 fingerprint (content_hash) + Layer 2 append-only hash-chain (prev_hash linkage)
-- + Layer 3 independent anchor (daily Merkle root, public timestamp + mirror). NO PII ever
-- lives here (Decision N) — only hashes. The per-batch Merkle root and anchor reference live
-- on anchor_batch (one row per daily batch), not duplicated on every commitment; a commitment
-- links to its batch once, when the daily job anchors it.

-- ANCHOR_BATCH: one immutable row per daily anchored batch ---------------------
create table public.anchor_batch (
  id          uuid primary key default gen_random_uuid(),
  batch_date  date not null unique,
  merkle_root text not null,
  anchor_ref  text,                      -- public timestamp proof + mirror-log reference
  anchored_at timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
comment on table public.anchor_batch is 'One immutable row per daily Merkle anchor (Decision I/J). Public-by-design (no PII).';
alter table public.anchor_batch enable row level security;
create trigger anchor_batch_block_modification
  before update or delete on public.anchor_batch
  for each row execute function app.tg_block_modification();

-- COMMITMENT: the seal + its position in the append-only chain -----------------
create table public.commitment (
  id            uuid primary key default gen_random_uuid(),
  seq           bigint generated always as identity,         -- chain order
  check_id      uuid not null unique references public.check_item(id) on delete restrict,
  content_hash  text not null,                                -- fingerprint of the finalized report+evidence
  prev_hash     text not null,                                -- chain link (set by trigger; genesis = 64 zeros)
  supersedes_id uuid references public.commitment(id),        -- null unless this corrects a prior verification
  batch_id      uuid references public.anchor_batch(id),      -- filled once when the daily batch anchors it
  sealed_at     timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
comment on table public.commitment is 'Finalized-check seal + append-only hash-chain position (Section 14). Integrity fields immutable; only batch_id is filled once.';
create index commitment_batch_idx on public.commitment (batch_id);
alter table public.commitment enable row level security;

-- BEFORE INSERT: link this commitment to the current chain head. An advisory lock serialises
-- appends so two concurrent seals cannot fork the chain.
create or replace function app.tg_commitment_chain()
returns trigger language plpgsql security definer set search_path = '' as $$
declare head_hash text;
begin
  perform pg_advisory_xact_lock(hashtext('ilevest.commitment_chain'));
  select c.content_hash into head_hash
  from public.commitment c
  order by c.seq desc
  limit 1;
  new.prev_hash := coalesce(head_hash, repeat('0', 64));  -- genesis link for the first commitment
  return new;
end;
$$;
create trigger commitment_chain
  before insert on public.commitment
  for each row execute function app.tg_commitment_chain();

-- Integrity guard: the fingerprint and chain fields can never change; the row can never be
-- deleted; only batch_id may be filled exactly once (null -> value) by the anchoring job.
create or replace function app.tg_commitment_guard()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Commitments are append-only and cannot be deleted.' using errcode = 'check_violation';
  end if;
  if new.content_hash  is distinct from old.content_hash
  or new.prev_hash     is distinct from old.prev_hash
  or new.seq           is distinct from old.seq
  or new.check_id      is distinct from old.check_id
  or new.sealed_at     is distinct from old.sealed_at
  or new.supersedes_id is distinct from old.supersedes_id then
    raise exception 'Commitment integrity fields are immutable; only the anchor batch may be filled once.'
      using errcode = 'check_violation';
  end if;
  if old.batch_id is not null and new.batch_id is distinct from old.batch_id then
    raise exception 'Commitment is already anchored to a batch; the anchor link cannot change.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger commitment_guard
  before update or delete on public.commitment
  for each row execute function app.tg_commitment_guard();
