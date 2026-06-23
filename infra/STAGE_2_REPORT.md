# Build Stage 2 — The Verification Workflow (engineering record)

**Status: complete and proven; awaiting design-team ratification before live apply.**

Built in a single pass per the two rulings (Field Agent dispatched directly by Ops; Paystack,
swappable). Architecture: invariant-critical state changes are portable PL/pgSQL functions in
`public` (access controlled by GRANTs); Edge Functions are thin HTTP adapters in front of them.

## Delivered
- **Migrations (3 new, 15 total)**
  - `20260622090100_service_catalogue.sql` — `service_catalogue` + `bundle_service` (seeded: 6 Phase 1 services incl. Persons/Entities KYC; design-team-ratified bundle compositions).
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

## Ratified by the design team
1. The hybrid architecture (DB functions + thin Edge adapters) — endorsed without reservation.
2. The payment webhook — signature-verified on the raw body, idempotent, constant-time (CISO commended).
3. Two new tables: `service_catalogue` (+ `bundle_service`) and `order_line`.
4. Bundle compositions, with one correction applied to match the locked catalogue (PRD 8.2):
   Essential = LR+SG; **Complete = LR+SG+CT** (Probate/KYC are situational add-ons, not standard);
   Inheritance = LR+CT+Probate; **Diaspora = LR+SG+CT+FD+KYC**. A sixth service, `C1-KY-01`
   (Persons & Entities / KYC), was added — its canonical code is to be reconciled against PRD 8.2.
5. Custom (build-your-own) bundles — added as a first-class option. **No backend change required:**
   `order_line` is the cart, `fan_out_order` creates one check per line regardless of source, the
   verdict rollup (one RED → headline RED) covers exactly the selected checks, and government fees are
   already per-check. The only open item is the per-service **price-display source** (the catalogue has
   no price column; pricing is manual at launch per PRD 10.3) — a small forthcoming decision, not a blocker.

## Remaining (on ratification)
- Apply `_combined_stage2_for_sql_editor.sql` to live `ilevest-dev` (one paste).
- Deploy the five functions; `supabase secrets set PAYSTACK_SECRET_KEY=...`; point the Paystack dashboard webhook at the deployed `paystack-webhook`.
- Re-confirm Paystack against the bank's preference when the corporate account / SCUML settlement is established (contained change — provider sits behind a boundary).

Production region/sovereignty remains with legal counsel; gates `ilevest-prod` only, not this stage.
