-- =============================================================================
-- Ilevest — chain repair: dev parity for the numbered migration chain.
-- Two drifts between the chain and the live database are closed here:
--
--  (1) Public menu: dev has svc_select / bundle_service_select open to anon
--      (applied via the SQL editor); the chain only had authenticated.
--  (2) pgcrypto location: Supabase hosts pgcrypto in the `extensions` schema;
--      the chain installed it into `public`. Increment 1 functions qualify
--      extensions.digest(...) (they run with an empty search_path), so the
--      chain now mirrors the platform: schema created, extension relocated.
--      Existing column defaults keep working (they bind by function OID),
--      and chain functions resolve digest via search_path either way.
--
-- Idempotent; every step is a no-op on the live database.
-- =============================================================================

drop policy if exists svc_select on public.service_catalogue;
create policy svc_select on public.service_catalogue
  for select to anon, authenticated using (true);

drop policy if exists bundle_service_select on public.bundle_service;
create policy bundle_service_select on public.bundle_service
  for select to anon, authenticated using (true);

grant select on public.bundle_service to anon;

create schema if not exists extensions;
do $$
begin
  if exists (select 1
             from pg_extension e
             join pg_namespace n on n.oid = e.extnamespace
             where e.extname = 'pgcrypto' and n.nspname <> 'extensions') then
    alter extension pgcrypto set schema extensions;
  end if;
end $$;
grant usage on schema extensions to anon, authenticated, service_role;
