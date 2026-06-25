# Client Portal — Tunde's experience (Build Stage 4 design)

The first user-facing surface, on the locked stack (Next.js on Vercel, talking to the live Supabase
DB, RPCs, Edge Functions, Storage, and Auth). This pins down how the locked user journey maps onto
what already exists, what new backend it needs, the genuine design calls for the team, and the build
order. The standard holds: prove behaviour, with RLS intact throughout.

## The journey, mapped to what exists vs. what's new

| Journey step | Backing | Status |
|---|---|---|
| Browse services + bundles without signup | `service_catalogue`, `bundle_service` (anon-readable) | **built** |
| Choose an outcome bundle OR build a custom bundle | `order_line` cart; fan-out reads the lines | **built** |
| See the two-part fee (service + estimated gov fees, no markup) | needs a per-service price source + a quote | **NEW (this stage)** |
| Sign up only at payment | Supabase Auth → an `app_user` (client) linked to the order | **NEW — design call** |
| Upload available documents; flag gaps loudly | a buyer-document store (NOT worker evidence) | **NEW — design call** |
| Pay (manual invoice flow at launch) | Paystack live; per PRD 10.3 Ops raises the itemised invoice | **built (manual)** |
| Track status: Assigned → In Progress → In Review → Ready | a buyer-facing projection of the internal FSM | **NEW (this stage)** |
| Proactive notifications | a channel + a trigger off the audit spine | **NEW — design call** |
| Colour-coded verdict (one RED headlines all) + plain English | `order_headline_verdict`, the per-check verdicts | **built** |
| PDF certificate + shareable public verification link | `verify_certificate` (data live); PDF rendering is new | **partly built** |

## Decisions I am making (engineering's to make)

- **Read model in the database, thin pages on top.** The portal's truth — quote, order status, verdict
  — comes from RPCs/views that enforce RLS, not from logic in the browser. Same two-layer discipline as
  before. The Next.js pages render what those return.
- **Buyer-facing status is a projection, not the raw FSM.** The internal states stay; the buyer sees the
  four the team named. Proposed mapping: `initiated`,`assigned` → **Assigned**; `in_progress`,
  `returned_for_fix` → **In Progress**; `in_review` → **In Review**; `finalized` → **Ready**. Two edges
  I am flagging rather than guessing: `exception` and `rejected` (below).
- **Quote before signup.** The quote RPC is anon-callable so the fee shows during browsing; nothing
  personal is involved. Signup happens only at payment.
- **The certificate PDF is a rendering of data that is already live and proven.** No new trust surface —
  it just formats `verify_certificate` output and embeds the public verification link/QR.

## Design calls for the team (these gate parts of the build)

1. **Prices.** The portal must show the two-part fee, so the catalogue needs a per-service `service_fee`
   and a `government_fee_estimate` (zero-markup, an estimate refined at the manual invoice per PRD 10.3).
   I will add those columns and a quote that sums any selection — but the **values are the team's**.
   Please confirm the structure and supply prices (even rough launch numbers), and confirm gov fees are
   shown as *estimates* until the itemised invoice fixes them.
2. **Buyer-uploaded documents.** These are NOT worker-captured evidence (different trust model — evidence
   is hashed on-device by field agents). I propose an order-level **buyer-document** store (Supabase
   Storage + a table, RLS-scoped to the buyer and the assigned workers), with a per-service "documents
   typically needed" checklist so gaps are flagged loudly. Confirm the model, and tell us the
   typically-needed documents per service so the gap-flagging is real.
3. **Notifications.** What channel at launch — email, SMS, WhatsApp, in-app? The audit spine already
   records every state change, so the clean shape is a notification row written off those transitions and
   delivered by a channel adapter (swappable, like the others). I need the channel choice to build it.
4. **Signup-at-payment linkage.** Supabase Auth issues an identity; the portable design keeps `app_user`
   decoupled from `auth.users`. Proposed: on signup, create an `app_user` whose id equals the auth uid
   with the `client` role, and attach the in-progress order to it. Confirm this is acceptable (it keeps
   the core portable while using Supabase Auth).
5. **The two FSM edges.** Buyer-facing, how should `exception` (a problem being worked) and `rejected`
   (a check that could not be completed) read? Proposed: `exception` → **In Progress** with a quiet "being
   reviewed" note; `rejected` → **Ready** carrying an honest Unresolved/declined outcome. Confirm or adjust.

## Build sequence

1. **Buyer read-model (this stage, no team input needed):** the quote (price columns + a sum-any-selection
   RPC) and the buyer-facing order-status projection (minimal states + headline verdict + fee summary),
   RLS-scoped, proven green. *(Prices seed empty; the team supplies values as data.)*
2. **Buyer documents + signup linkage** once the team confirms the model (item 2) and the auth linkage
   (item 4).
3. **The Next.js pages:** browse → select/build → quote → sign-up-at-payment → upload → status → verdict →
   certificate + verification link, each rendering the read-model.
4. **Notifications** once the channel is chosen (item 3).
5. **The certificate PDF** rendering `verify_certificate`, with the public verification link/QR.

Category 2 (Registration) stays switched off; this is all Category 1 (Verification), buyer-facing.
