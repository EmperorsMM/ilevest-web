-- =============================================================================
-- 0012  Seed — per-service buyer-document checklist (Stage 4, Call 2)
-- =============================================================================
-- Source: Ilevest Buyer-Document Checklist v1.0 (Appendix A), drafted from the Service
-- Catalogue client inputs. Two tiers only (helpful / optional); NO 'required' tier — nothing
-- blocks submission. Tiers and labels are DATA: refine without code via this upsert.
-- Idempotent: re-running updates tier/sort in place.

insert into public.service_document_requirement (service_code, document_label, tier, sort) values
  ('C1-LR-01', 'Certificate of Occupancy (C of O), deed, or any title document the seller presented', 'helpful', 1),
  ('C1-LR-01', 'Seller''s name / details as presented', 'helpful', 2),
  ('C1-LR-01', 'Any known title or registration particulars (title number, page, volume)', 'optional', 3),
  ('C1-LR-01', 'Survey plan, if available', 'optional', 4),
  ('C1-LR-02', 'A clear scan/photo of the specific document to be authenticated (C of O / deed / consent)', 'helpful', 1),
  ('C1-LR-02', 'The parties and property as stated on that document', 'helpful', 2),
  ('C1-LR-03', 'Title or registration particulars (or the result of a prior title search)', 'helpful', 1),
  ('C1-LR-03', 'Registered owner''s name', 'helpful', 2),
  ('C1-LR-04', 'Copies of the prior deeds/instruments in the ownership chain', 'helpful', 1),
  ('C1-LR-04', 'Title particulars, if known', 'optional', 2),
  ('C1-LR-05', 'Survey plan or the land''s coordinates (most useful for this check)', 'helpful', 1),
  ('C1-LR-05', 'Property address and locality (LGA)', 'helpful', 2),
  ('C1-LR-06', 'Submission references / receipts from when the deed was lodged', 'helpful', 1),
  ('C1-LR-06', 'Deed details and parties', 'optional', 2),
  ('C1-LR-07', 'Particulars of the instrument whose certified true copy is wanted', 'helpful', 1),
  ('C1-LR-07', 'Property address and parties', 'optional', 2),
  ('C1-SG-01', 'A clear copy of the survey plan (front and back)', 'helpful', 1),
  ('C1-SG-01', 'Property location', 'helpful', 2),
  ('C1-SG-02', 'Survey plan and/or the land''s coordinates', 'helpful', 1),
  ('C1-SG-02', 'Location and approximate size', 'optional', 2),
  ('C1-SG-03', 'Survey plan showing coordinates', 'helpful', 1),
  ('C1-SG-03', 'Any competing/neighbouring plan you hold', 'optional', 2),
  ('C1-SG-04', 'The survey plan', 'helpful', 1),
  ('C1-SG-04', 'A site access arrangement or on-ground contact', 'optional', 2),
  ('C1-CT-01', 'The deceased owner''s full name', 'helpful', 1),
  ('C1-CT-01', 'Court division and probate reference, if known', 'optional', 2),
  ('C1-CT-01', 'Any grant or letters of administration the sellers presented', 'optional', 3),
  ('C1-CT-01', 'Names of the persons selling the property', 'helpful', 4),
  ('C1-CT-02', 'Property address/description', 'helpful', 1),
  ('C1-CT-02', 'Seller''s name and any known adverse-party names', 'helpful', 2),
  ('C1-CT-03', 'Property description', 'helpful', 1),
  ('C1-CT-03', 'Party names', 'helpful', 2),
  ('C1-CT-03', 'Any known suit references', 'optional', 3),
  ('C1-CT-04', 'Particulars of the court record wanted (suit/probate references, if known)', 'helpful', 1),
  ('C1-PE-01', 'Company name and RC number as presented', 'helpful', 1),
  ('C1-PE-01', 'Names of the individuals fronting the transaction', 'helpful', 2),
  ('C1-PE-01', 'Any marketing materials/receipts the company issued', 'optional', 3),
  ('C1-PE-02', 'Identity particulars presented (NIN and/or BVN reference, ID document)', 'helpful', 1),
  ('C1-PE-02', 'Consent of the person being verified, where required', 'helpful', 2),
  ('C1-PE-03', 'The professional''s name and claimed registration/enrolment particulars', 'helpful', 1),
  ('C1-PE-03', 'Their role in the transaction', 'optional', 2),
  ('C1-FD-01', 'Property location (address and/or coordinates)', 'helpful', 1),
  ('C1-FD-01', 'Survey plan, if available', 'optional', 2),
  ('C1-FD-01', 'A site access arrangement or local contact', 'optional', 3),
  ('C1-FD-01', 'Any specific questions you want the inspection to answer', 'optional', 4)
on conflict (service_code, document_label) do update
  set tier = excluded.tier, sort = excluded.sort;
