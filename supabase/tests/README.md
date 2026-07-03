# Database tests

## `stage1_smoke.sql`

A behavioural proof of the Stage 1 invariants, run as the six roles against a real
PostgreSQL with all migrations applied. It is **seed-based** (inserts fixed-id rows), so it
runs against a **fresh** database, not a populated one.

```bash
# from a machine with PostgreSQL available
createdb ilevest_test
for f in ../migrations/2026*.sql; do psql -v ON_ERROR_STOP=1 -d ilevest_test -f "$f"; done
psql -v ON_ERROR_STOP=1 -d ilevest_test -f stage1_smoke.sql   # exit 0 = all assertions passed
dropdb ilevest_test
```

What it asserts (25 checks): the full FSM happy path by-role; illegal transitions blocked;
finalized checks immutable; per-transition role gating; append-only immutability of audit /
evidence / verdict / commitment / government-fee (proven against the bypass-RLS superuser, so
it holds against everyone); the government-fee three-state ledger (held-first, paid-needs-
receipt, terminal); the proof-layer hash-chain (genesis → linked → superseded, integrity
fields immutable, anchor link fills once); and RLS tenant isolation + least-privilege writes.

> Note: it uses `SET ROLE authenticated` + `SET app.user_id = '<uuid>'`. RLS can only be
> tested as a non-superuser role, because a Postgres superuser bypasses RLS.

## `fulfilment_desk_smoke.sql`  *(Increment 1, 2026-07-03)*

The Fulfilment Desk proven end to end (~152 executed assertions), as real signed-in
callers via the portability shim. Covers: the ratified FSM matrix by role; the three
ceremony doors (finalized state, verdicts, and commitments exist only via `seal_check`);
the evidence capture law (assigned worker, working states only, findings hashed to their
own text); pre-seal void markers and the frozen sealed-evidence manifest; canonical-recipe
stability (zero-void seals recompute under the original recipe, so already-anchored records
stay verifiable); the self-seal guard OFF/ON (D1); retry-first escalation (D4); headline
precedence (D5); verdict_ready firing only on the last seal; cross-tenant RLS; tamper-proof
authorship stamps; audited, work-frozen reassignment. Superuser tamper attempts are
deliberate and prove the trigger law is role-blind.
