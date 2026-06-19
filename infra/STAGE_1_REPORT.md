# Ilevest — Build Stage 1 report (database foundation)

**Status: complete and verified green.** All twelve migrations apply cleanly to a fresh
PostgreSQL 16, and a 28-assertion behavioural test passes (exit 0) proving the locked
invariants hold as real users, not just that the SQL parses.

This is the schema where the trust model lives: the six roles, Row-Level Security as the real
permission boundary, the append-only money and verdict history, the audit spine, and the
proof-layer hash-chain.

---

## What was built

Twelve ordered, plain-SQL migrations under `supabase/migrations/` (see that folder's README
for the per-file table) and a behavioural test at `supabase/tests/stage1_smoke.sql`.

Fifteen tables — the twelve entities from the ERD, plus three implementation tables the locked
invariants require (explained under "Decisions" below): `user_role`, `government_fee_transition`,
and `anchor_batch`. **Every table has RLS enabled** (verified: zero public tables without it),
behind **37 policies**.

The invariants, and how each is enforced in the database itself (not left to app code):

- **Six roles, least privilege (Decision H).** A user holds roles via the `user_role` join
  table, so one person can be Ops *and* Reviewer today and be split later with no schema change.
  RLS policies scope every table to the right role and the right rows.
- **RLS is the real boundary (invariant #2).** Enabled on the first table and every table after.
  Proven: a client sees only their own order; a second client sees none of it; a partner sees
  only their assigned checks and the evidence on them; a second partner sees nothing.
- **Append-only money and verdicts (Decision G).** Government-fee state is an append-only
  ledger (held → paid_with_receipt → refunded); a refund *adds* a state, it never erases "held".
  Verdicts and the audit log are insert-only. Enforced by triggers that block UPDATE/DELETE —
  proven to hold even against a bypass-RLS superuser, so they hold against everyone.
- **The FSM, in the database (Decisions A–D).** A trigger permits only the legal state
  transitions, gates each transition to the right role (Ops assigns; the assigned partner does
  the field steps; a Reviewer/Ops finalizes, rejects, or closes), and makes a finalized check
  permanently immutable. Proven: illegal jumps and wrong-role moves are rejected.
- **Finalized is immutable; corrections supersede (Decision D).** A finalized check cannot
  change; a correction is a new verification whose commitment points back via `supersedes_id`,
  with both preserved.
- **The audit spine (invariant #6).** Every check creation, state change, and role grant/revoke
  writes an immutable audit row automatically. Audit rows cannot be forged or suppressed by
  ordinary users — only the database's own triggers and trusted server code write them.
- **The proof layer (Section 14).** Each finalized check seals a `commitment` carrying its
  content fingerprint and a `prev_hash` link to the one before it — an append-only chain in
  Postgres. The daily Merkle root + public anchor reference live on `anchor_batch`. **No PII is
  ever on this layer** (Decision N) — only hashes. Proven: genesis → linked → superseded chain,
  with integrity fields immutable and the anchor link fillable exactly once.
- **Evidence integrity (Decision P).** Evidence is append-only and carries the `content_hash`
  computed on the partner's device at capture.
- **Portability (PORTABILITY.md).** The only Supabase-specific touch-point is wrapped in one
  function, `app.current_user_id()`. Everything else is standard PostgreSQL. Migrating off
  Supabase means re-pointing that one function, not rewriting 37 policies.

---

## Decisions I made (flagged for the design team to ratify)

These honour the locked invariants where the simplified ERD picture would have conflicted with
them. None changes the product; all are reversible on paper.

1. **Government-fee state is an append-only ledger, not a column.** The ERD draws `state` as a
   field on the fee row. Decision G says money history is *never overwritten* — a refund "adds a
   state on top of held." A mutable column would overwrite. So the fee's core row is immutable
   and its lifecycle is a `government_fee_transition` ledger; current state is derived. This is a
   faithful implementation of the ERD's intent **plus** the invariant.
2. **The daily Merkle root / anchor reference live on `anchor_batch`, not on every commitment.**
   The ERD draws `merkle_root` on `commitment`, but it is identical for every seal in a day's
   batch — storing it per-row would duplicate it. A one-row-per-day `anchor_batch` is the correct
   normalisation and keeps the chain append-only (a commitment links to its batch once).
3. **Roles via a `user_role` join table, not a single column.** Decision H requires Ops+Reviewer
   on one person now, separable later "with no rebuild." A join table delivers exactly that.
4. **Money stored as `numeric(14,2)`, not Postgres's `money` type** — exact and locale-independent.
5. **Order status and headline verdict are derived (functions), never stored** — matching "Ready
   when all children Finalized" and "one RED dominates," with no column to drift out of sync.
6. **An internal enum was named `app_role`** (the table is `user_role`) to avoid a name clash;
   purely internal, no product impact.

## Open questions for the design team

- **Client visibility of raw evidence.** In Stage 1 a client sees their order, checks, verdicts,
  payment and fee states, but **not** raw evidence rows (those are staff + the capturing partner).
  The public/most-protective default. Confirm whether clients should see evidence in the report,
  or only the sealed certificate.
- **Field Agent vs Partner.** Both roles exist. Stage 1 scopes field work to the *assigned
  partner*; the partner→field-agent org relationship isn't modelled yet. Confirm whether a field
  agent operates under a partner (a hierarchy to add) or is assigned checks directly.

---

## Verification (the production-grade bar)

Run against a real PostgreSQL 16 — fresh database, all eleven migrations applied in order, then
`stage1_smoke.sql`:

- migrations: **all 12 applied green**
- tables without RLS: **0**
- RLS policies: **37**
- smoke test: **exit 0 — 28/28 assertions passed, 0 failures**

The test and how to run it are documented in `supabase/tests/README.md`.

---

## Post-ratification refinements folded in

- **Buyer-facing evidence index** (`evidence_index`, migration 0012). Per the ratified answer,
  the buyer now sees the index of evidence on their own checks — kind, fingerprint, capture
  metadata — so they can see what was found and re-verify the hash, while the raw-file pointer
  (`storage_ref`) is excluded from the view entirely and raw `evidence_item` stays staff/assignee
  only. Proven by test: buyer sees the index (2 rows) but not the raw rows (0), and the view does
  not expose `storage_ref`.
- **Field Agent scope kept adjustable.** Access to do field work and capture evidence keys off
  the check's *assignment* (`assigned_partner_id`), not off the role label — so a check assigned
  directly by Ops to a field agent already grants exactly the right scope, and the model can be
  adjusted when the operational ruling lands, without touching the schema.

## Region (for creating the Supabase projects)

Supabase runs on AWS, one primary region per project. The established European exact regions are
**Frankfurt (eu-central-1)**, **Ireland (eu-west-1)**, and **London (eu-west-2)**; you can also
pick the "EMEA" general region and let Supabase place it. (The live list is in the New Project
form / the docs and can change.) For Lagos latency, all three are the closest mature options;
London/Ireland sit marginally closer by network path, but the difference is small.

For the **dev** project: pick any European region (e.g. Frankfurt) and move on — low stakes.

For the **production** region (the careful, near-permanent one), one honest caveat for legal
counsel: choosing an EU region solves data **residency**, but Supabase is a US-incorporated
company, so the data may still fall under US legal reach (e.g. the CLOUD Act) regardless of
where it is hosted. That is a data-**sovereignty** question, separate from residency, and worth
a deliberate call with counsel against the NDPA before the prod project is created. It does not
block dev.
