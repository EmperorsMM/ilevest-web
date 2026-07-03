-- =============================================================================
-- Ilevest — Build Stage 3 combined migration (for the Supabase SQL Editor)
-- Apply AFTER Stage 1 and Stage 2. Adds the proof-layer anchoring core: RFC 6962
-- Merkle root, the daily anchor_pending job, the write-once external-proof attach,
-- and the sealed / batched / publicly-anchored honest certificate. One transaction;
-- re-runnable. Safe to re-apply to refresh verify_certificate.
-- =============================================================================
begin;

-- =============================================================================
-- 0010  Proof Layer — Stage 3: daily Merkle anchoring (portable core)
-- =============================================================================
-- Builds the third proof layer ON the Stage 1 schema (commitment + anchor_batch):
--   * app.merkle_root         — RFC 6962 Merkle root (0x00 leaf / 0x01 node domain
--                               separation; a lone odd node is PROMOTED, not duplicated)
--   * public.anchor_pending   — the daily job's DB core: fold the day's unanchored
--                               fingerprints into one root, record one anchor_batch,
--                               stamp each commitment's batch_id exactly once
--   * verify_certificate      — enhanced to report "sealed vs anchored" honestly
-- The EXTERNAL anchor (OpenTimestamps + a public mirror log) is a deployed adapter that
-- fills anchor_batch.anchor_ref; it runs on the deployed schedule, not here. No PII ever
-- reaches this layer — leaves and root are hashes only.

-- ---- RFC 6962 Merkle root over an ordered list of fingerprint hex strings ----
create or replace function app.merkle_root(p_leaves text[])
returns text
language plpgsql
immutable
set search_path = public, extensions, pg_temp
as $$
declare
  lvl text[] := '{}';
  nxt text[];
  n   int;
  i   int;
begin
  n := coalesce(array_length(p_leaves, 1), 0);
  if n = 0 then
    return null;                          -- no leaves: the caller must not anchor an empty set
  end if;

  -- Level 0: leaf hash = SHA-256(0x00 || leaf_bytes)  [domain separation vs second-preimage]
  for i in 1 .. n loop
    lvl := lvl || encode(digest('\x00'::bytea || decode(p_leaves[i], 'hex'), 'sha256'), 'hex');
  end loop;

  -- Fold pairs up the tree: node = SHA-256(0x01 || left || right); a lone odd node is PROMOTED
  while array_length(lvl, 1) > 1 loop
    nxt := '{}';
    i := 1;
    while i <= array_length(lvl, 1) loop
      if i + 1 <= array_length(lvl, 1) then
        nxt := nxt || encode(digest('\x01'::bytea || decode(lvl[i], 'hex') || decode(lvl[i+1], 'hex'), 'sha256'), 'hex');
        i := i + 2;
      else
        nxt := nxt || lvl[i];             -- promote (do NOT duplicate) the odd node
        i := i + 1;
      end if;
    end loop;
    lvl := nxt;
  end loop;

  return lvl[1];
end;
$$;
comment on function app.merkle_root(text[]) is
  'RFC 6962 Merkle root over ordered fingerprint hexes. 0x00 leaf / 0x01 node domain separation; odd node promoted (not duplicated).';

-- ---- the daily anchoring job (DB core) --------------------------------------
-- Collects every commitment not yet anchored (batch_id is null), in chain order, folds them
-- into one Merkle root, records one anchor_batch for the date, and stamps each commitment's
-- batch_id (the Stage 1 guard permits null -> value exactly once). Idempotent per date:
-- one batch per day; commitments sealed after a run roll into the next day's batch.
create or replace function public.anchor_pending(p_batch_date date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_leaves text[];
  v_ids    uuid[];
  v_root   text;
  v_batch  uuid;
  v_count  int;
begin
  -- one batch per date (anchor_batch.batch_date is unique) — idempotent per day
  if exists (select 1 from public.anchor_batch where batch_date = p_batch_date) then
    return jsonb_build_object('anchored', false,
                              'reason', 'a batch already exists for this date',
                              'batch_date', p_batch_date);
  end if;

  select array_agg(content_hash order by seq), array_agg(id order by seq)
    into v_leaves, v_ids
  from public.commitment
  where batch_id is null;

  v_count := coalesce(array_length(v_ids, 1), 0);
  if v_count = 0 then
    return jsonb_build_object('anchored', false, 'reason', 'nothing pending', 'checks_anchored', 0);
  end if;

  v_root := app.merkle_root(v_leaves);

  insert into public.anchor_batch(batch_date, merkle_root)
  values (p_batch_date, v_root)
  returning id into v_batch;

  update public.commitment set batch_id = v_batch where id = any(v_ids);

  perform app.write_audit('anchor_batch', v_batch, 'anchored',
            p_metadata => jsonb_build_object('batch_date', p_batch_date,
                                             'merkle_root', v_root,
                                             'checks_anchored', v_count));

  return jsonb_build_object(
    'anchored',        true,
    'batch_id',        v_batch,
    'batch_date',      p_batch_date,
    'merkle_root',     v_root,
    'checks_anchored', v_count
  );
end;
$$;
comment on function public.anchor_pending(date) is
  'Daily anchoring (DB core): fold unanchored fingerprints into one Merkle root, record one anchor_batch, stamp batch_id once. Idempotent per date. The external OTS + mirror fills anchor_ref on the deployed schedule.';

-- ---- verify_certificate: now reports sealed-vs-anchored honestly --------------
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
       'anchored',             (c.batch_id is not null),
       'externally_witnessed', (ab.anchor_ref is not null),
       'anchored_at',          ab.anchored_at,
       'merkle_root',          ab.merkle_root,
       'anchor_ref',           ab.anchor_ref,
       'protection',   case
                         when c.id is null then null
                         when c.batch_id is null
                           then 'Sealed and protected by its fingerprint and the append-only chain; the public anchor is applied at the next daily batch.'
                         when ab.anchor_ref is null
                           then 'Sealed and committed to a daily Merkle root; the external public timestamp and mirror are being recorded.'
                         else 'Sealed and publicly anchored: fingerprint, append-only chain, and a daily Merkle root externally timestamped against public infrastructure. See anchor_ref for the witnesses.'
                       end
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

-- ---- let the external proof attach to the (otherwise immutable) batch, once ----
-- anchor_batch was fully immutable in Stage 1. The OTS + mirror proof only exists AFTER the
-- external submission, so anchor_ref must be fillable exactly once. This guard replaces the
-- blanket block: it permits anchor_ref null -> value a single time and freezes everything else.
create or replace function app.tg_anchor_ref_fill_once()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'anchor_batch is immutable (no delete)' using errcode = 'check_violation';
  end if;
  if new.id          is distinct from old.id
     or new.batch_date  is distinct from old.batch_date
     or new.merkle_root is distinct from old.merkle_root
     or new.anchored_at is distinct from old.anchored_at
     or new.created_at  is distinct from old.created_at then
    raise exception 'anchor_batch integrity fields are immutable' using errcode = 'check_violation';
  end if;
  if old.anchor_ref is not null and new.anchor_ref is distinct from old.anchor_ref then
    raise exception 'anchor_batch.anchor_ref is write-once' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
drop trigger if exists anchor_batch_block_modification on public.anchor_batch;
drop trigger if exists anchor_batch_guard on public.anchor_batch;
create trigger anchor_batch_guard
  before update or delete on public.anchor_batch
  for each row execute function app.tg_anchor_ref_fill_once();

-- the deployed adapter calls this AFTER submitting the root to OpenTimestamps + the mirror,
-- to attach the proof reference. Write-once; service_role only.
create or replace function public.record_anchor_proof(p_batch uuid, p_anchor_ref jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_updated int;
begin
  update public.anchor_batch
     set anchor_ref = p_anchor_ref::text
   where id = p_batch and anchor_ref is null;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    return jsonb_build_object('ok', false, 'reason', 'batch not found or proof already recorded', 'batch_id', p_batch);
  end if;
  perform app.write_audit('anchor_batch', p_batch, 'anchor_proof_recorded', p_metadata => p_anchor_ref);
  return jsonb_build_object('ok', true, 'batch_id', p_batch);
end;
$$;
comment on function public.record_anchor_proof(uuid, jsonb) is
  'Attach the external anchor reference (OpenTimestamps proof + mirror URL) to a batch, exactly once. Called by the deployed adapter after submission.';

-- ---- grants -----------------------------------------------------------------
revoke all on function public.anchor_pending(date) from public;
revoke all on function public.record_anchor_proof(uuid, jsonb) from public;
grant execute on function public.anchor_pending(date)            to service_role;   -- scheduled job only
grant execute on function public.record_anchor_proof(uuid, jsonb) to service_role;  -- scheduled job only
grant execute on function public.verify_certificate(uuid) to anon, authenticated, service_role;

commit;
