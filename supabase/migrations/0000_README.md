# Migrations

Empty by design at Build Stage 0.

**Conventions (for Stage 1 onward):**
- One change per migration file, named `NNNN_short_description.sql` (or the CLI's timestamp
  form). Never edit a migration that has been applied to staging/production — add a new one.
- **Standard Postgres DDL only.** No Supabase-proprietary SQL in the core. Where a Supabase
  feature is unavoidable, isolate it and note it in `../../PORTABILITY.md`.
- RLS is enabled on tables **in the same migration that creates them** (invariant #2).
- Append-only / immutability and the audit log are introduced in the **first** real migration
  (invariants #1, #5, #6).
