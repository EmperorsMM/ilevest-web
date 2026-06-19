# Migrations

Plain, portable PostgreSQL migrations. Applied in filename order (the timestamp prefix).

**Conventions:**
- One concern per migration file, `YYYYMMDDHHMMSS_short_description.sql`. Never edit a
  migration that has been applied to staging/production — add a new one.
- **Standard Postgres DDL only.** No Supabase-proprietary SQL in the core. The single
  Supabase touch-point is isolated behind `app.current_user_id()` (see `../../PORTABILITY.md`).
- RLS is enabled on every table **in the same migration that creates it** (invariant #2).
- Append-only / immutability and the audit spine are enforced by triggers (invariants #1, #5, #6).

## Stage 1 set (database foundation)

| File | What it adds |
| --- | --- |
| `…120100_extensions_and_app_shim.sql` | pgcrypto; `app` schema; enums; the `anon`/`authenticated`/`service_role` roles (guarded); the `app.current_user_id()` portability shim. |
| `…120200_users_roles_partner.sql` | `app_user`, `user_role` (multi-role join — Decision H), `partner_profile`; the RLS role predicates (`app.is_admin/is_staff/is_ops/is_reviewer/has_role`). |
| `…120300_audit_and_immutability.sql` | `audit_event` (the spine); the reusable append-only guard `app.tg_block_modification()`; `app.write_audit()`; role-grant auditing. |
| `…120400_property_party.sql` | `property` (Decision E) and `party_seller` (Decision F), both first-class. |
| `…120500_orders_checks_fsm.sql` | `order_matter` (parent) + `check_item` (child); the FSM trigger (legal transitions + per-transition role gate + finalized-immutability); derived `app.order_status()`. |
| `…120600_evidence.sql` | `evidence_item` — append-only; `content_hash` captured on-device (Decision P). |
| `…120700_money_payment_govfee.sql` | `payment`; `government_fee` (immutable core) + `government_fee_transition` (append-only held→paid_with_receipt→refunded ledger); derived `app.gov_fee_state()`. |
| `…120800_verdict.sql` | `verdict` — append-only, one per check; derived `app.order_headline_verdict()` (one RED dominates). |
| `…120900_commitment_hashchain.sql` | `commitment` (the seal + `prev_hash` chain) and `anchor_batch` (daily Merkle root + public anchor). Integrity fields immutable; anchor link fills once. |
| `…121000_rls_policies.sql` | All 37 Row-Level Security policies + the `SECURITY DEFINER` cross-table visibility helpers. |
| `…121100_grants.sql` | Command-level grants per role (append-only tables get no UPDATE/DELETE grant; no DELETE anywhere except admin-gated `user_role`). |
| `…121200_evidence_index.sql` | Buyer-facing `evidence_index` view — the evidence index (what was captured + its fingerprint) without the raw-file pointer (`storage_ref`). |

See `../tests/stage1_smoke.sql` for the behavioural proof (run after applying these).
