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
