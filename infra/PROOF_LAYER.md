# Proof Layer — the external anchor (Build Stage 3 design)

This is the design the Stage 3 build is held to. It turns on the third and final proof layer:
the **external, public anchor** that lets anyone verify a sealed report *without trusting Ilevest*,
even if Ilevest disappears. Layers 1 and 2 already exist (Stage 1); Stage 3 adds Layer 3.

## The three layers (where Stage 3 fits)

1. **Fingerprint (live).** Every finalized check is sealed into a reproducible SHA-256 `content_hash`
   over its canonical verdict + sorted evidence hashes. Change anything and the fingerprint changes.
2. **Append-only hash-chain (live).** Each fingerprint links to the one before it (`prev_hash`,
   genesis = 64 zeros), serialised by an advisory lock. You cannot quietly reorder or rewrite history
   inside the database.
3. **External anchor (THIS STAGE).** Once a day, the day's fingerprints are reduced to a single
   **Merkle root**, which is (a) timestamped against public infrastructure nobody controls and
   (b) mirrored to a public append-only log. After that, the record's existence and content at that
   date can be proven against evidence outside Ilevest's control.

The schema for this is already in place: `anchor_batch` (one immutable row per day: `batch_date`,
`merkle_root`, `anchor_ref`) and `commitment.batch_id` (filled exactly once when the daily job
anchors a fingerprint — the integrity guard already enforces null → value, once).

## The daily anchoring job

1. **Collect the leaves.** Select every `commitment` with `batch_id IS NULL`, ordered by `seq`
   (the chain order). Their `content_hash` values are the leaves. Ordering by `seq` makes the
   result deterministic and independently recomputable.
2. **Build the Merkle root** using the RFC 6962 (Certificate Transparency) construction:
   - leaf hash = `SHA-256(0x00 || content_hash_bytes)`
   - node hash = `SHA-256(0x01 || left || right)`
   - domain-separation prefixes (`0x00` leaf, `0x01` node) prevent second-preimage attacks; a lone
     odd node is **promoted** up a level (not duplicated), avoiding the known duplication weakness.
3. **Record the batch.** Insert one `anchor_batch` row for the day (`batch_date`, `merkle_root`).
4. **Link the leaves.** Set `batch_id` on each included commitment (the guard permits this once).
5. **Anchor externally (two independent anchors):**
   - **(a) Public timestamp** — submit the `merkle_root` to an OpenTimestamps-style service
     (Bitcoin-calendar backed). This yields a proof that the root existed at/by a point in time,
     verifiable by anyone against the public chain, with no trust in Ilevest.
   - **(b) Public mirror** — append `(batch_date, merkle_root)` to a public, append-only log as a
     second, independent witness.
   - Both references are stored together in `anchor_batch.anchor_ref` as structured JSON
     (`{ "ots": ..., "mirror": ... }`).

Steps 1–4 are the **portable core** (standard PostgreSQL) and are fully testable offline.
Step 5 is the **external** part and is exercised on deploy (see network boundary below).

## The provider boundary (same discipline as payments)

The specific timestamp service and mirror log sit behind an **anchor adapter**, selected by an
`ANCHOR_PROVIDER` setting (default: OpenTimestamps + a chosen mirror). Switching providers is a
contained change, never a rebuild — exactly how the payment provider is isolated. The database
core never knows or cares which external service produced the proof; it only stores the reference.

## Honesty in the certificate (sealed vs anchored)

`verify_certificate` will report **both** times truthfully:

- `sealed_at` — always present once the check is finalized.
- `anchored` / `anchored_at` / `merkle_root` / `anchor_ref` — present **only once the daily batch
  has run** (i.e. the commitment has a `batch_id`).
- **Between sealing and the next daily anchor**, the certificate states plainly that the record is
  already protected by the fingerprint and the append-only chain (Layers 1–2) and **will be publicly
  anchored at the next daily batch**. It never implies an anchor exists before it does.

## Invariants reaffirmed

- **No personal data ever touches the anchor.** Leaves are hashes; the root is a hash; `anchor_ref`
  is proof metadata. There is nothing personal in `anchor_batch` or in any externally published
  artifact — by construction.
- **Anchored rows are immutable.** `anchor_batch` is append-only (block-modification trigger);
  a commitment's `batch_id` is filled once and can never change.

## How Stage 3 is proven (automated tests)

1. **Determinism + independent recomputation** — the job's Merkle root for a known leaf set equals a
   root recomputed by an independent implementation (the test rebuilds it from the ordered hashes).
2. **Tamper breaks it** — altering a leaf (or its order) yields a different root; a fingerprint that
   doesn't match its sealed inputs fails verification.
3. **Chain links** — genesis link is 64 zeros; each `prev_hash` equals the previous head.
4. **The job anchors correctly and is idempotent** — all unanchored commitments get a `batch_id` and
   land under one `anchor_batch` row; a second run anchors nothing new (no duplicate batch).
5. **Anchor link is write-once** — attempting to re-point a commitment's `batch_id` is rejected.
6. **No PII in anchored artifacts** — the batch row and leaves contain only hashes.
7. **Certificate honesty** — verification shows `anchored=false` before the batch and the full anchor
   detail after, with `sealed_at` correct throughout.

## Network boundary (stated up front, per our Definition of Done)

The actual OpenTimestamps submission and the mirror push reach **external services on the public
internet**, which the build/test sandbox cannot call. So the external step is verified on the
**deployed** environment (the scheduled Edge job), exactly as the Paystack webhook's real delivery
was — not in the sandbox. Everything that does *not* require the outside network (the leaf selection,
the Merkle root, the batch row, the `batch_id` linkage, the verification states, the no-PII property)
is proven green in the sandbox and in CI.

## Build sequence for Stage 3

1. Portable DB core: Merkle-root function + the daily `anchor_pending` function (selects unanchored
   leaves → root → `anchor_batch` → fills `batch_id`), with the offline test suite above.
2. `verify_certificate` enhancement: add the honest sealed-vs-anchored fields + tests.
3. The swappable anchor adapter + a scheduled Edge job that calls the DB core, then submits the root
   to OpenTimestamps and the mirror, and writes `anchor_ref` back.
4. Deploy + live confirmation (the external anchor proven on the deployed schedule).
