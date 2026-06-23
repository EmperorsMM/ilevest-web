-- =============================================================================
-- Ilevest — Stage 2 catalogue RESEED to the locked Phase 1 Service Catalogue
-- (for the Supabase SQL Editor). Replaces the service catalogue + bundle
-- compositions with the locked single-source list. One transaction; re-runnable.
-- DEV reseed: clears reference data only. The service_catalogue delete will FAIL
-- SAFELY (and roll back) if any order_line still references a code — i.e. do not
-- run this blindly on an environment that already has real orders.
-- =============================================================================
begin;
delete from public.bundle_service;
delete from public.service_catalogue;

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

insert into public.bundle_service(bundle,service_code) values
  ('essential','C1-LR-01'), ('essential','C1-SG-02'),
  ('complete','C1-LR-01'), ('complete','C1-LR-02'), ('complete','C1-LR-03'), ('complete','C1-LR-05'),
  ('complete','C1-SG-01'), ('complete','C1-SG-02'), ('complete','C1-CT-02'),
  ('inheritance','C1-LR-01'), ('inheritance','C1-CT-01'), ('inheritance','C1-CT-02'),
  ('diaspora','C1-LR-01'), ('diaspora','C1-LR-02'), ('diaspora','C1-LR-03'), ('diaspora','C1-LR-05'),
  ('diaspora','C1-SG-01'), ('diaspora','C1-SG-02'), ('diaspora','C1-CT-02'),
  ('diaspora','C1-FD-01'), ('diaspora','C1-PE-02');
commit;
