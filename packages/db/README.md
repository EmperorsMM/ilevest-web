# @ilevest/db — database types & access conventions

This package will hold **generated TypeScript types** for the database (produced from the
schema) and shared DB access helpers, so the web app is type-safe against the real tables.

- The **schema itself is NOT here** — it lives as plain, portable SQL in `../../supabase/migrations/`
  (see `PORTABILITY.md`). This package only holds the generated *types* and helpers.
- Types are generated in **Build Stage 1**, after the schema exists.
