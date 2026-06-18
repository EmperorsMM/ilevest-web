# supabase/ — local dev config + the schema (as portable SQL)

We use the **Supabase CLI** for local development and for applying migrations to each
environment. The important rule:

> **Migrations are plain, standard PostgreSQL `.sql` files.** They are applied with the
> Supabase CLI today, but they would run unchanged on any Postgres. This is the backbone
> of our portability principle (see `../PORTABILITY.md`) and of our audit story (the whole
> schema history lives in Git).

## Layout
- `config.toml` — Supabase CLI config for **local** dev (ports, etc.). A starter; normally
  produced by `supabase init`. The real per-environment projects are referenced via secrets
  in CI (`SUPABASE_DB_URL`, project refs), never hard-coded here.
- `migrations/` — numbered `.sql` migrations. The **first real migration arrives in Build
  Stage 1** (audit log + roles + RLS scaffolding). Nothing schema-related is built yet.
- `seed.sql` — local-only seed data (empty placeholder).

## Common commands (for a developer)
- `supabase start` — run the local stack (Postgres, Auth, Storage, Studio).
- `supabase db diff -f <name>` — generate a migration from local changes.
- `supabase db push` — apply migrations to the linked remote project (used by CI per env).
