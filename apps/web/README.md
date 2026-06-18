# @ilevest/web

The single Next.js (App Router) application that serves all three role-gated surfaces.

## Routing model
URL segments map to surfaces, each gated by `middleware.ts`:

- `/client/*` — Client Portal (role: Client)
- `/ops/*`    — Ops / Reviewer Console (roles: Ops, Reviewer)
- `/admin/*`  — Admin Console (role: Admin)
- `/`         — entry point; redirects a signed-in user to their surface

> **Security note:** `middleware.ts` is for routing/UX and defense-in-depth only.
> It is **not** the security boundary. The authoritative permission engine is
> **Row-Level Security in PostgreSQL** (invariant #2). Never rely on middleware to
> keep data safe — RLS decides what any role can read or write.

## Note on versions
Dependency versions in `package.json` are sensible starting points. Run `pnpm install`
to lock them; bump to current as the team prefers.
