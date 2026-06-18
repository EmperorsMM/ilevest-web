# Environments & deployment

## Three environments, three Supabase projects
We run **development**, **staging**, and **production**, each backed by its **own Supabase
project** (its own database, auth, storage). We **never** test against live customer data.

| Environment | Purpose | Supabase project | Vercel |
|---|---|---|---|
| development | local + PR previews | `ilevest-dev` | Preview deployments |
| staging | integration / pre-prod, prod-like | `ilevest-staging` | Staging deploy (on merge to `main`) |
| production | live customer system | `ilevest-prod` | Production deploy (on release tag) |

> These three Supabase projects must be **created by a human** in the Supabase dashboard
> (one per environment). See the human-setup checklist at the root of the handoff bundle.

## Branch & deploy flow (matches the CI workflows in `.github/workflows/`)
- **Open a pull request →** GitHub Actions runs lint + typecheck + test + build + contract
  validation. Vercel posts a **Preview** deployment (pointed at the dev Supabase project).
- **Merge to `main` →** `deploy-staging.yml` applies DB migrations to **staging** and deploys
  the app to **staging**.
- **Publish a release / push a `v*` tag →** `deploy-production.yml` applies migrations to
  **production** and deploys to **production**. This runs in the gated `production`
  environment, so an Admin must approve it first.

`main` is a **protected branch**: no direct pushes; changes land via reviewed PRs.

## Decision flagged to the design team
Mapping a distinct **staging** tier onto Vercel can be done two ways: (a) one Vercel project
with controlled staging/production deploys driven by these Actions (what is scaffolded), or
(b) a dedicated staging Vercel project. (a) is simpler; both are fine. Please confirm.

## Open question: region & data residency
Supabase has no Nigeria region (it runs on cloud regions elsewhere). The **production region**
is a near-permanent choice and may interact with any Nigerian data-residency requirement for
property/PII data. Flagged for a ruling before the prod project is created. (I can pull the
current Supabase region list on request.)
