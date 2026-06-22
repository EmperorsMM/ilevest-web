# Edge Functions — the Stage 2 HTTP surface

Thin HTTP adapters over the database's portable RPC layer. Each function authenticates the
caller and delegates the actual state change to a PL/pgSQL function in the database, where the
invariants (state machine, row-level security, append-only money + verdict, the proof-layer
hash-chain) are enforced. This keeps the core portable and directly testable, and isolates the
parts that genuinely belong at the edge (signature verification, talking to the gateway, auth).

## Endpoints → contract → database function

| Function (folder)     | Contract path                  | Calls (DB)             | Auth                         |
|-----------------------|--------------------------------|------------------------|------------------------------|
| `assign-check`        | `POST /checks/{id}/assign`     | `assign_check`         | caller JWT (Ops gate)        |
| `record-evidence`     | `POST /checks/{id}/evidence`   | `record_evidence`      | caller JWT (assigned worker) |
| `seal-check`          | `POST /checks/{id}/seal`       | `seal_check`           | caller JWT (Reviewer/Ops)    |
| `paystack-webhook`    | `POST /webhooks/paystack`      | `confirm_payment`      | gateway signature → service  |
| `verify-certificate`  | `GET  /verify/{ref}`           | `verify_certificate`   | public (anon, no PII)        |

The full request/response shapes are in `packages/contract/openapi.yaml` (the source of truth).

## Auth model

- **Worker/staff actions** (`assign-check`, `record-evidence`, `seal-check`) forward the
  caller's Supabase JWT, so the database sees the real user and **row-level security + the
  state-machine gates are the real boundary** — the function adds no privilege of its own.
- **The webhook** verifies the gateway signature against the **raw** body *before* any state
  change, then acts with the service role to confirm the payment and fan out the order. It is
  **idempotent** — a duplicate webhook is a no-op.
- **Certificate verification** is public (anon) and returns **no personal data**.

## Provider-swappable payments (Ruling 2)

Paystack is the active provider. The receiver and its signature check live in `_shared/gateway.ts`
+ `_shared/paystack.ts`; swapping to Flutterwave later is a localised change there, with nothing
downstream affected.

## Secrets (set per environment before deploying)

```
supabase secrets set PAYSTACK_SECRET_KEY=sk_live_or_test_...
# optional: PAYMENT_PROVIDER=paystack   (default)
```
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

## Deploy

```
supabase functions deploy assign-check record-evidence seal-check verify-certificate
supabase functions deploy paystack-webhook --no-verify-jwt   # gateway calls it, not a user
```
Then set the Paystack dashboard webhook URL to the deployed `paystack-webhook` endpoint.

## Tests

The pure security logic (signature verification) has a unit test that runs in CI:
`node --experimental-strip-types _shared/paystack.test.ts`. The database functions these
adapters call are proven by `supabase/tests/stage2_smoke.sql`.
