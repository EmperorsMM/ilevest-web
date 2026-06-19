# ilevest-web

The Ilevest **web monorepo**. One repository holding **one Next.js application** that serves
three role-gated surfaces:

- **Client Portal** — where buyers order verifications and read sealed reports.
- **Ops / Reviewer Console** — where the internal team assigns, reviews, and finalizes checks.
- **Admin Console** — user/role management and system administration.

They are **one app with role-based routing**, not three apps. The role boundary is enforced by
the database (Row-Level Security), not by this app — see the security note in `infra/README.md`.

This repo also contains (as documented folders, by design — see decisions in the build report):

- `packages/contract/` — the **OpenAPI API contract** (the single source of truth for the API;
  written in the next build stage). Both the web app and the Android Oracle app consume it.
- `supabase/migrations/` — the **database schema as plain, portable SQL** (written in build
  stage 1). This is the crown jewel and is deliberately kept vendor-neutral; see `PORTABILITY.md`.
- `infra/` — environments, deployment, and the **secrets policy** (the CISO-facing doc).

## What this repo is NOT (yet)
This is **Phase 1, Build Stage 0 — scaffolding only**. There are no product features, no schema,
and no Category 2 (Registration) functionality here yet. Folders are named so Category 2 can be
switched on later without restructuring, but nothing in it is built.

## Quick start (for a developer)
1. Install Node 20 (`nvm use` reads `.nvmrc`) and `pnpm` (`corepack enable`).
2. `pnpm install`
3. Copy `.env.example` to `apps/web/.env.local` and fill it from the team secret store
   (see `infra/README.md`). **Never commit `.env.local`.**
4. `pnpm dev`

See `infra/environments.md` for environments and `PORTABILITY.md` for the portability rules.

Live on Vercel as of June 2026
