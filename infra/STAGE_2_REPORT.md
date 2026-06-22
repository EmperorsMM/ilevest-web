# Build Stage 2 — The Verification Workflow (engineering record)

**Status: complete and proven; awaiting design-team ratification before live apply.**

Built in a single pass per the two rulings (Field Agent dispatched directly by Ops; Paystack,
swappable). Architecture: invariant-critical state changes are portable PL/pgSQL functions in
`public` (access controlled by GRANTs); Edge Functions are thin HTTP adapters in front of them.

## Delivered
- **Migrations (3 new, 15 total)**
  - `20260622090100_service_catalogue.sql` — `service_catalogue` + `bundle_service` (seeded: 5 Phase 1 services; bundle compositions).
  - `20260622090200_order_line.sql` — `order_line` (the cart) + `app.add_order_lines_for_bundle`.
  - `20260622090300_stage2_rpcs.sql` — `public.fan_out_order`, `confirm_payment`, `assign_check`, `record_evidence`, `seal_check`, `verify_certificate`.
  - `_combined_stage2_for_sql_editor.sql` — the 3 above, one transaction, for the Supabase SQL Editor.
- **Edge Functions** (`supabase/functions/`) — `assign-check`, `record-evidence`, `seal-check`, `paystack-webhook`, `verify-certificate`, plus `_shared/` (cors, http, supabase clients, paystack signature, provider-swappable gateway).
- **Contract** — `packages/contract/openapi.yaml` rewritten to the real Stage 2 surface (OpenAPI 3.1, 6 paths).
- **Tests** — `supabase/tests/stage2_smoke.sql` (15 assertions); `supabase/functions/_shared/paystack.test.ts` (9 assertions).
- **CI** — `.github/workflows/db-test.yml` now runs Stage 1 + Stage 2 DB tests and the signature test.

## Proven
- All 15 migrations apply cleanly to a fresh DB.
- Stage 2 behavioural suite: **15/15** (fan-out + idempotency; a-la-carte field inspection; Ops-direct assignment + negatives; evidence intake + least-privilege; seal → verdict → hash-chain linkage + negatives; public verification with no PII).
- Paystack signature unit test: **9/9** (valid accepted; tampered/missing/wrong-secret rejected; constant-time).
- OpenAPI contract validates against the 3.1 schema.
- The combined Stage 2 file applies cleanly on top of a Stage-1-only database (live-apply rehearsal).

## Flagged for ratification / confirmation
1. The hybrid architecture (DB functions + thin Edge adapters).
2. Bundle compositions (defaults seeded; data, not code).
3. Two new tables: `service_catalogue` (+ `bundle_service`) and `order_line`.

## Remaining (on ratification)
- Apply `_combined_stage2_for_sql_editor.sql` to live `ilevest-dev` (one paste).
- Deploy the five functions; `supabase secrets set PAYSTACK_SECRET_KEY=...`; point the Paystack dashboard webhook at the deployed `paystack-webhook`.
- Re-confirm Paystack against the bank's preference when the corporate account / SCUML settlement is established (contained change — provider sits behind a boundary).

Production region/sovereignty remains with legal counsel; gates `ilevest-prod` only, not this stage.
