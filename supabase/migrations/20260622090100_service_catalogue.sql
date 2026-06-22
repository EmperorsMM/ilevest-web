-- =============================================================================
-- Stage 2 / 0013  Service catalogue + bundle composition (data-driven fan-out)
-- =============================================================================
-- The Phase 1 service menu and which services each bundle includes. Fan-out reads these
-- so the catalogue is data, not code. (Bundle compositions below are sensible defaults —
-- flagged for the design team to confirm against the canonical Phase 1 catalogue.)

create table public.service_catalogue (
  code       text primary key,                 -- e.g. C1-LR-01
  title      text not null,
  category   text not null,                     -- LR | SG | CT | PE | FD (maps to partner desks)
  active     boolean not null default true,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);
comment on table public.service_catalogue is 'Phase 1 service menu. Read-mostly reference data; managed via migrations / service role.';
alter table public.service_catalogue enable row level security;
create policy svc_select on public.service_catalogue for select to authenticated using (true);

create table public.bundle_service (
  bundle       public.order_bundle not null,
  service_code text not null references public.service_catalogue(code) on delete restrict,
  primary key (bundle, service_code)
);
comment on table public.bundle_service is 'Which services each bundle expands to. ala_carte has no rows (services chosen individually).';
alter table public.bundle_service enable row level security;
create policy bundle_service_select on public.bundle_service for select to authenticated using (true);

-- ---- seed: Phase 1 catalogue (five desks) ----
insert into public.service_catalogue(code,title,category,sort) values
  ('C1-LR-01','Land Registry title search','LR',10),
  ('C1-SG-01','Surveyor-General chart & plan check','SG',20),
  ('C1-CT-01','Court records search (litigation / encumbrance)','CT',30),
  ('C1-PE-01','Probate & estate check','PE',40),
  ('C1-FD-01','Field inspection (site visit)','FD',50);

-- ---- seed: bundle compositions (defaults — confirm with design team) ----
insert into public.bundle_service(bundle,service_code) values
  ('essential','C1-LR-01'), ('essential','C1-SG-01'),
  ('complete','C1-LR-01'), ('complete','C1-SG-01'), ('complete','C1-CT-01'), ('complete','C1-PE-01'), ('complete','C1-FD-01'),
  ('inheritance','C1-LR-01'), ('inheritance','C1-CT-01'), ('inheritance','C1-PE-01'),
  ('diaspora','C1-LR-01'), ('diaspora','C1-SG-01'), ('diaspora','C1-CT-01'), ('diaspora','C1-PE-01'), ('diaspora','C1-FD-01');

grant select on public.service_catalogue to authenticated, anon;
grant select on public.bundle_service   to authenticated;
