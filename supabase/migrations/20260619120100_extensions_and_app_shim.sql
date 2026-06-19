-- =============================================================================
-- 0001  Extensions, app schema, enums, DB roles, and the portability shim
-- =============================================================================
-- Standard PostgreSQL only. No Supabase-proprietary SQL. (PORTABILITY.md)

create extension if not exists pgcrypto;  -- gen_random_uuid(), digest() for hashing

create schema if not exists app;
comment on schema app is
  'Ilevest internal helpers: RLS predicates, triggers, and the portability shim. Not exposed via the API.';

-- Database roles. On Supabase these already exist; the guard makes this safe to run anywhere
-- (self-hosted Postgres, CI, local). We never ALTER the platform-managed roles' privileges here.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

-- Enums live in public so PostgREST/the API can see them.
create type public.app_role      as enum ('client','partner','field_agent','ops','reviewer','admin');
create type public.check_state    as enum ('initiated','assigned','in_progress','in_review','returned_for_fix','exception','finalized','rejected');
create type public.verdict_colour as enum ('green','amber','red','unresolved');
create type public.gov_fee_state  as enum ('held','paid_with_receipt','refunded');
create type public.evidence_kind  as enum ('register_photo','receipt','coordinate','note');
create type public.order_bundle   as enum ('essential','complete','inheritance','diaspora','ala_carte');

-- ---------------------------------------------------------------------------
-- Portability shim (PORTABILITY.md): who is the current user?
--   * On Supabase the platform sets request.jwt.claims per request; 'sub' is the user id.
--   * On self-hosted Postgres and in tests:  SET app.user_id = '<uuid>';
-- RLS policies call app.current_user_id() and NEVER auth.uid() directly, so migrating off
-- Supabase means re-pointing this one function, not rewriting every policy.
-- ---------------------------------------------------------------------------
create or replace function app.current_user_id()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('app.user_id', true), '')::uuid,
    nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid
  );
$$;
comment on function app.current_user_id() is
  'Portability shim: current user id from the app.user_id GUC (tests/self-host) or the Supabase JWT claim.';
