-- =============================================================================
-- Ilevest — Build Stage 3 smoke test (proof-layer anchoring)
-- =============================================================================
-- Run as SUPERUSER against a DB with ALL migrations (Stage 1 + 2 + 3) applied.
-- PART A unit-tests the Merkle construction directly (no pipeline). PART B drives the
-- real pipeline to produce sealed fingerprints, then proves the daily anchoring job:
-- determinism / independent recomputation, tamper-breaks-it, one-batch-per-day idempotency,
-- write-once batch_id, no-PII, and honest sealed-vs-anchored certificate states.
\set ON_ERROR_STOP on
set client_min_messages = notice;
set search_path = public, extensions, pg_temp;          -- so digest() resolves in inline checks

\set ops      '''22222222-2222-2222-2222-222222222222'''
\set reviewer '''33333333-3333-3333-3333-333333333333'''
\set partner1 '''44444444-4444-4444-4444-444444444444'''
\set client1  '''66666666-6666-6666-6666-666666666666'''

\echo ''
\echo '################ PART A — RFC 6962 Merkle root (unit) ################'
do $$
declare
  d0 text := repeat('a',64); d1 text := repeat('b',64); d2 text := repeat('c',64);
  lh0 text; lh1 text; lh2 text; n01 text;
  got2 text; expect2 text; got1 text; got3 text; expect3 text;
begin
  -- leaf hashes (0x00 domain prefix), recomputed independently here
  lh0 := encode(digest('\x00'::bytea || decode(d0,'hex'),'sha256'),'hex');
  lh1 := encode(digest('\x00'::bytea || decode(d1,'hex'),'sha256'),'hex');
  lh2 := encode(digest('\x00'::bytea || decode(d2,'hex'),'sha256'),'hex');

  -- two leaves: root = node(lh0,lh1) with 0x01 prefix
  expect2 := encode(digest('\x01'::bytea || decode(lh0,'hex') || decode(lh1,'hex'),'sha256'),'hex');
  got2 := app.merkle_root(array[d0,d1]);
  if got2 <> expect2 then raise exception 'FAIL: 2-leaf root != independent recomputation'; end if;
  if got2 !~ '^[0-9a-f]{64}$' then raise exception 'FAIL: root is not 64 hex chars'; end if;
  if app.merkle_root(array[d0,d1]) <> got2 then raise exception 'FAIL: root is not deterministic'; end if;
  raise notice 'PASS: 2-leaf root matches independent recomputation and is a deterministic 64-hex digest';

  -- tamper / reorder must change the root
  if app.merkle_root(array[d0, repeat('f',64)]) = got2 then raise exception 'FAIL: tampering a leaf did not change the root'; end if;
  if app.merkle_root(array[d1, d0]) = got2 then raise exception 'FAIL: reordering leaves did not change the root'; end if;
  raise notice 'PASS: changing or reordering any leaf changes the root';

  -- single leaf: root == its leaf hash
  got1 := app.merkle_root(array[d0]);
  if got1 <> lh0 then raise exception 'FAIL: single-leaf root must equal the leaf hash'; end if;
  raise notice 'PASS: single-leaf root equals the leaf hash';

  -- three leaves: odd node promoted -> node( node(lh0,lh1), lh2 )
  n01 := encode(digest('\x01'::bytea || decode(lh0,'hex') || decode(lh1,'hex'),'sha256'),'hex');
  expect3 := encode(digest('\x01'::bytea || decode(n01,'hex') || decode(lh2,'hex'),'sha256'),'hex');
  got3 := app.merkle_root(array[d0,d1,d2]);
  if got3 <> expect3 then raise exception 'FAIL: 3-leaf (odd-promotion) root mismatch'; end if;
  raise notice 'PASS: with an odd leaf count the lone node is promoted (not duplicated)';
end $$;

\echo ''
\echo '################ PART B — seed + seal three real fingerprints ################'
reset role;
insert into public.app_user(id,name,email_or_phone) values
  ('22222222-2222-2222-2222-222222222222','Ops','o@x'),
  ('33333333-3333-3333-3333-333333333333','Reviewer','r@x'),
  ('44444444-4444-4444-4444-444444444444','Partner One','p1@x'),
  ('66666666-6666-6666-6666-666666666666','Client One','c1@x');
insert into public.user_role(user_id,role) values
  ('22222222-2222-2222-2222-222222222222','ops'),
  ('33333333-3333-3333-3333-333333333333','reviewer'),
  ('44444444-4444-4444-4444-444444444444','partner'),
  ('66666666-6666-6666-6666-666666666666','client');

set app.user_id = :ops;
insert into public.property(id,lga,state,locality) values ('aa000000-0000-0000-0000-0000000000a1','Eti-Osa','Lagos','Ikoyi');
insert into public.order_matter(id,client_id,property_id,bundle) values ('cc000000-0000-0000-0000-0000000000b1',:client1,'aa000000-0000-0000-0000-0000000000a1','ala_carte');
insert into public.order_line(order_id,service_code) values
  ('cc000000-0000-0000-0000-0000000000b1','C1-LR-01'),
  ('cc000000-0000-0000-0000-0000000000b1','C1-LR-02'),
  ('cc000000-0000-0000-0000-0000000000b1','C1-LR-03');
insert into public.payment(order_id,service_fee,government_fee_total) values ('cc000000-0000-0000-0000-0000000000b1', 60000, 0);
reset role;
select public.confirm_payment('cc000000-0000-0000-0000-0000000000b1','ref_anchor');

select set_config('t.k1',(select id::text from public.check_item where order_id='cc000000-0000-0000-0000-0000000000b1' and service_code='C1-LR-01'),false);
select set_config('t.k2',(select id::text from public.check_item where order_id='cc000000-0000-0000-0000-0000000000b1' and service_code='C1-LR-02'),false);
select set_config('t.k3',(select id::text from public.check_item where order_id='cc000000-0000-0000-0000-0000000000b1' and service_code='C1-LR-03'),false);

-- seal k1 (green), k2 (amber), k3 (green): Ops assigns -> assigned worker progresses -> Reviewer seals
-- [2026-07-03 · Increment 1] each submission now carries evidence + a findings summary
set app.user_id = :ops;      select public.assign_check(current_setting('t.k1')::uuid, :partner1);
set app.user_id = :partner1; update public.check_item set state='in_progress' where id=current_setting('t.k1')::uuid;
select public.record_evidence(current_setting('t.k1')::uuid,'register_photo','h_k1_photo');
select public.record_findings(current_setting('t.k1')::uuid,'LR-01 register searched; entries clear.');
                             update public.check_item set state='in_review'  where id=current_setting('t.k1')::uuid;
set app.user_id = :reviewer; select public.seal_check(current_setting('t.k1')::uuid,'green','LR-01 clear');

set app.user_id = :ops;      select public.assign_check(current_setting('t.k2')::uuid, :partner1);
set app.user_id = :partner1; update public.check_item set state='in_progress' where id=current_setting('t.k2')::uuid;
select public.record_evidence(current_setting('t.k2')::uuid,'register_photo','h_k2_photo');
select public.record_findings(current_setting('t.k2')::uuid,'LR-02 instrument located; minor variance noted.');
                             update public.check_item set state='in_review'  where id=current_setting('t.k2')::uuid;
set app.user_id = :reviewer; select public.seal_check(current_setting('t.k2')::uuid,'amber','LR-02 minor');

set app.user_id = :ops;      select public.assign_check(current_setting('t.k3')::uuid, :partner1);
set app.user_id = :partner1; update public.check_item set state='in_progress' where id=current_setting('t.k3')::uuid;
select public.record_evidence(current_setting('t.k3')::uuid,'register_photo','h_k3_photo');
select public.record_findings(current_setting('t.k3')::uuid,'LR-03 register searched; entries clear.');
                             update public.check_item set state='in_review'  where id=current_setting('t.k3')::uuid;
set app.user_id = :reviewer; select public.seal_check(current_setting('t.k3')::uuid,'green','LR-03 clear');
reset role;
\echo 'three checks sealed (3 commitments on the chain)'

\echo ''
\echo '################ PART B1 — certificate BEFORE the daily anchor (honest) ################'
set role anon;
select set_config('t.cb', coalesce(public.verify_certificate(current_setting('t.k1')::uuid)::text,'{"valid":false}'), false);
do $$ declare res jsonb := current_setting('t.cb')::jsonb; begin
  if not (res->>'valid')::boolean then raise exception 'FAIL: a sealed check should verify as valid'; end if;
  if (res->>'anchored')::boolean then raise exception 'FAIL: before the batch, anchored must be false'; end if;
  if (res->'merkle_root') is distinct from 'null'::jsonb and (res->>'merkle_root') is not null then raise exception 'FAIL: no merkle_root before anchoring'; end if;
  if (res->>'protection') not ilike '%next daily batch%' then raise exception 'FAIL: certificate must state the public anchor is pending'; end if;
  raise notice 'PASS: before anchoring, certificate is valid, anchored=false, and states the anchor is pending';
end $$;
reset role;

\echo ''
\echo '################ PART B2 — run the daily anchoring job ################'
select set_config('t.ab', public.anchor_pending('2026-06-23')::text, false);
do $$
declare res jsonb := current_setting('t.ab')::jsonb; v_leaves text[]; n int;
begin
  if not (res->>'anchored')::boolean then raise exception 'FAIL: anchor_pending should anchor the pending fingerprints'; end if;
  if (res->>'checks_anchored')::int <> 3 then raise exception 'FAIL: expected 3 anchored, got %', res->>'checks_anchored'; end if;
  if (res->>'merkle_root') !~ '^[0-9a-f]{64}$' then raise exception 'FAIL: batch merkle_root is not 64 hex'; end if;
  -- independent cross-check: stored root == merkle_root over the fingerprints in chain order
  select array_agg(content_hash order by seq) into v_leaves from public.commitment;
  if (res->>'merkle_root') <> app.merkle_root(v_leaves) then raise exception 'FAIL: stored root != root recomputed over the leaves'; end if;
  -- every fingerprint now linked to exactly this one batch
  select count(*) into n from public.commitment where batch_id = (res->>'batch_id')::uuid;
  if n <> 3 then raise exception 'FAIL: all 3 fingerprints should link to the batch, got %', n; end if;
  raise notice 'PASS: the job folded 3 fingerprints into one daily root and linked them to one batch';
end $$;

\echo ''
\echo '################ PART B3 — idempotency, write-once link, no PII ################'
-- second run on the same date must NOT create a second batch
select set_config('t.ab2', public.anchor_pending('2026-06-23')::text, false);
do $$ declare res jsonb := current_setting('t.ab2')::jsonb; nb int; begin
  if (res->>'anchored')::boolean then raise exception 'FAIL: a second same-date run must not anchor again'; end if;
  select count(*) into nb from public.anchor_batch;
  if nb <> 1 then raise exception 'FAIL: there should be exactly one batch, got %', nb; end if;
  raise notice 'PASS: a second anchor run on the same date is a no-op (one batch per day)';
end $$;

-- an already-anchored fingerprint cannot be re-pointed to a different batch
do $$ begin
  begin
    update public.commitment set batch_id = gen_random_uuid() where batch_id is not null;
  exception when sqlstate '23514' then
    raise notice 'PASS: an anchored fingerprint cannot be re-pointed to another batch (write-once)';
    return;
  end;
  raise exception 'FAIL: was able to change an anchored fingerprint''s batch_id';
end $$;

-- the anchor batch holds only hashes/dates — no PII or location text
do $$ declare t text; begin
  select to_jsonb(ab)::text into t from public.anchor_batch ab limit 1;
  if t ilike '%Client One%' or t ilike '%Ikoyi%' or t ilike '%Eti-Osa%' then
    raise exception 'FAIL: the anchor batch leaked PII or location';
  end if;
  raise notice 'PASS: the anchor batch contains only hashes and dates — no PII, no location';
end $$;

\echo ''
\echo '################ PART B4 — certificate after batching, before the external proof ################'
set role anon;
select set_config('t.ca', coalesce(public.verify_certificate(current_setting('t.k1')::uuid)::text,'{"valid":false}'), false);
do $$ declare res jsonb := current_setting('t.ca')::jsonb; begin
  if not (res->>'anchored')::boolean then raise exception 'FAIL: after the batch, anchored must be true'; end if;
  if (res->>'merkle_root') !~ '^[0-9a-f]{64}$' then raise exception 'FAIL: anchored certificate must carry the merkle_root'; end if;
  if (res->>'anchored_at') is null then raise exception 'FAIL: anchored certificate must carry anchored_at'; end if;
  if (res->>'externally_witnessed')::boolean then raise exception 'FAIL: not externally witnessed until the proof is recorded'; end if;
  if (res->>'protection') not ilike '%being recorded%' then raise exception 'FAIL: pre-proof, certificate should state the external proof is being recorded'; end if;
  raise notice 'PASS: batched but pre-proof, certificate is anchored=true, externally_witnessed=false, proof being recorded (honest)';
end $$;
reset role;

\echo ''
\echo '################ PART B5 — attach the external anchor proof (write-once) ################'
-- the adapter records the OTS + mirror references onto the immutable batch, exactly once
select set_config('t.rp', public.record_anchor_proof((current_setting('t.ab')::jsonb->>'batch_id')::uuid,
       '{"ots":"ots-proof-stub","mirror":"https://mirror.example/log/2026-06-23"}'::jsonb)::text, false);
do $$ declare res jsonb := current_setting('t.rp')::jsonb; begin
  if not (res->>'ok')::boolean then raise exception 'FAIL: recording the anchor proof should succeed once'; end if;
  raise notice 'PASS: the external anchor proof (OTS + mirror) attaches to the batch once';
end $$;
-- a second proof write is refused (write-once, handled gracefully by the function)
do $$ declare res jsonb; begin
  res := public.record_anchor_proof((current_setting('t.ab')::jsonb->>'batch_id')::uuid, '{"ots":"different"}'::jsonb);
  if (res->>'ok')::boolean then raise exception 'FAIL: anchor_ref must be write-once'; end if;
  raise notice 'PASS: a second proof write is refused (anchor_ref is write-once)';
end $$;
-- every other field of the batch stays immutable
do $$ begin
  begin
    update public.anchor_batch set merkle_root = repeat('0',64) where anchor_ref is not null;
  exception when sqlstate '23514' then raise notice 'PASS: the rest of the batch remains immutable'; return; end;
  raise exception 'FAIL: was able to alter an immutable batch field';
end $$;
-- the certificate now surfaces the external anchor reference and flips to publicly anchored
set role anon;
select set_config('t.cr', public.verify_certificate(current_setting('t.k1')::uuid)::text, false);
do $$ declare res jsonb := current_setting('t.cr')::jsonb; begin
  if not (res->>'externally_witnessed')::boolean then raise exception 'FAIL: should be externally witnessed once the proof is recorded'; end if;
  if (res->>'anchor_ref') is null or (res->>'anchor_ref') not ilike '%mirror%' then
    raise exception 'FAIL: certificate should carry the anchor_ref once recorded'; end if;
  if (res->>'protection') not ilike '%publicly anchored%' then raise exception 'FAIL: certificate should now state it is publicly anchored'; end if;
  raise notice 'PASS: once the proof is recorded, certificate is externally_witnessed=true and publicly anchored (OTS + mirror)';
end $$;
reset role;

\echo ''
\echo '################ ALL STAGE 3 ASSERTIONS PASSED ################'
