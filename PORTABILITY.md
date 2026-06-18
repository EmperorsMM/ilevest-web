# Portability — keeping the core vendor-neutral

**Locked architectural principle:** the database, schema, and proof layer must stay
standard PostgreSQL so the system could be moved to self-hosted Postgres (or another host)
as a *planned option*, never an emergency. This file records how we honor that and exactly
where we knowingly touch a Supabase-specific feature.

## The backbone: schema lives as plain SQL migrations
The schema is authored as ordinary, version-controlled `.sql` files in `supabase/migrations/`.
They use standard Postgres DDL only. They are applied with the Supabase CLI today, but they
would run unchanged against any Postgres via `psql` or any standard migration runner. The
*location* of these files does not bind us to Supabase; the SQL inside them is what matters,
and it stays portable. (This also serves the trust model: the schema is auditable in Git.)

## Convention set now, used from Stage 1: the auth shim
Supabase RLS policies typically call `auth.uid()`, which reads the user id from the Supabase
JWT. That function is **Supabase-specific**. To keep policies portable, our RLS will reference
a thin wrapper (e.g. a SQL function `app.current_user_id()`), which on Supabase returns
`auth.uid()` but elsewhere could read a session setting (`current_setting('app.user_id')`).
Net effect: if we migrate, we re-point one small function instead of rewriting every policy.

## Known Supabase-specific touchpoints and the standard-Postgres fallback
| Supabase feature | Why we use it | Portability stance / fallback |
|---|---|---|
| **Supabase Auth** (`auth.users`) | Managed auth, sessions, JWTs | Our domain tables live in `public` and reference `auth.users(id)` by UUID only. On migration, swap the identity source and keep domain tables. The auth shim above isolates the coupling. |
| **`auth.uid()` in RLS** | Identifies caller in policies | Wrapped behind `app.current_user_id()` (see above). |
| **Supabase Storage** (evidence files) | Object storage for captured evidence | Postgres stores only the object **key/path + content hash**, never Storage internals. Any S3-compatible store can replace it. |
| **Edge Functions** (Deno) | Webhook receivers, light glue | Kept as **thin adapters** only. Business rules live in Postgres (functions/triggers) and the Next.js server. An Edge Function can be re-hosted as a Next.js route handler or a DigitalOcean job. |
| **Supabase Realtime** | (not used yet) | Avoid coupling domain logic to it. |

## Rule of thumb
If a standard-Postgres equivalent exists, use it in the **core**. Where a Supabase feature is
used, keep it at the **edge** and document it here.
