-- =============================================================================
-- Stage 2 / 0013  Service catalogue + bundle composition (data-driven fan-out)
-- =============================================================================
-- The Phase 1 service menu and which services each bundle includes. Fan-out reads these
-- so the catalogue is data, not code. Bundle compositions below are the design-team-ratified set;
-- they remain data, adjustable post-launch as real customer patterns emerge.

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

-- ---- seed: the locked Phase 1 Service Catalogue (single source — no inference) ----
-- Five desks: LR, SG, CT, PE, FD. Codes and titles are the design-team-locked catalogue.
-- Codes not in a launch bundle (LR-04/06/07, SG-03/04, CT-03/04) are seeded so they exist as
-- individual a-la-carte / Wave-2 selectable services.
insert into public.service_catalogue(code,title,category,sort) values
  -- Desk 1 — Lands Registries & Bureaus
  ('C1-LR-01','Title & Ownership Search','LR',10),
  ('C1-LR-02','Document Authenticity Check','LR',11),
  ('C1-LR-03','Encumbrance Search','LR',12),
  ('C1-LR-04','Consent & Stamping Status Check','LR',13),
  ('C1-LR-05','Acquisition / Excision / Gazette Status','LR',14),
  ('C1-LR-06','Deed Registration Tracking','LR',15),
  ('C1-LR-07','CTC Retrieval — Registry Instruments','LR',16),
  -- Desk 2 — Office of the Surveyor-General
  ('C1-SG-01','Survey Plan Authentication','SG',20),
  ('C1-SG-02','Charting / Land Status Report','SG',21),
  ('C1-SG-03','Coordinate & Overlap Check','SG',22),
  ('C1-SG-04','Plan-to-Ground Match','SG',23),
  -- Desk 3 — Courts & Probate Registries
  ('C1-CT-01','Probate / Letters of Administration Verification','CT',30),
  ('C1-CT-02','Litigation / Pending Suit Search','CT',31),
  ('C1-CT-03','Judgment Search','CT',32),
  ('C1-CT-04','CTC Retrieval — Court Records','CT',33),
  -- Desk 4 — Persons & Entities
  ('C1-PE-01','Corporate Seller Check','PE',40),
  ('C1-PE-02','Identity Verification (NIN/BVN consistency)','PE',41),
  ('C1-PE-03','Professional Licence Verification','PE',42),
  -- Field Services
  ('C1-FD-01','Physical Site Inspection','FD',50);

-- ---- seed: bundle compositions (against the locked codes) ----
-- Essential   = LR-01 (Title & Ownership) + SG-02 (Charting / Land Status)
-- Complete    = LR-01 + LR-02 + LR-03 + LR-05 + SG-01 + SG-02 + CT-02
--               (CT-01 Probate added per-order only when an estate/deceased owner is involved; PE situational)
-- Inheritance = LR-01 + CT-01 (Probate) + CT-02 (Litigation)   — Courts & Probate desk, no PE
-- Diaspora    = Complete's contents + FD-01 + PE-02
--               (Identity always applies; PE-01 Corporate Seller / PE-03 Licence added per case — FLAGGED below)
-- ala_carte / custom builds have no rows here (services are chosen individually via order_line).
insert into public.bundle_service(bundle,service_code) values
  ('essential','C1-LR-01'), ('essential','C1-SG-02'),
  ('complete','C1-LR-01'), ('complete','C1-LR-02'), ('complete','C1-LR-03'), ('complete','C1-LR-05'),
  ('complete','C1-SG-01'), ('complete','C1-SG-02'), ('complete','C1-CT-02'),
  ('inheritance','C1-LR-01'), ('inheritance','C1-CT-01'), ('inheritance','C1-CT-02'),
  ('diaspora','C1-LR-01'), ('diaspora','C1-LR-02'), ('diaspora','C1-LR-03'), ('diaspora','C1-LR-05'),
  ('diaspora','C1-SG-01'), ('diaspora','C1-SG-02'), ('diaspora','C1-CT-02'),
  ('diaspora','C1-FD-01'), ('diaspora','C1-PE-02');
-- FLAGGED interpretation: the ruling says Diaspora includes "C1-PE-01/02/03 as applicable". Identity
-- (PE-02) is seeded as always-included; Corporate Seller (PE-01) and Professional Licence (PE-03) are
-- treated as situational add-ons (added per order via order_line), mirroring how Complete handles
-- Probate/PE. If Diaspora's fixed SKU should always contain all three PE checks, that is a one-line change.

grant select on public.service_catalogue to authenticated, anon;
grant select on public.bundle_service   to authenticated;
