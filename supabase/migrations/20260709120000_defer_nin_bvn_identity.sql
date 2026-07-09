-- =============================================================================
-- Defer C1-PE-02 (NIN/BVN Identity Verification) pending legal clearance
--
-- The CISO parked this service until counsel confirms NIN/BVN handling is
-- compliant (NIMC / CBN / NDPA rules on those sensitive national identifiers).
-- It was, however, silently ACTIVE: the service_catalogue.active column defaults
-- true and no row overrode it, and C1-PE-02 was part of the 'diaspora' bundle.
-- That meant ordering the Diaspora pack would create a NIN/BVN check line — i.e.
-- the system would begin handling the single most sensitive data type we touch,
-- before legal sign-off.
--
-- This migration closes that gap at the source:
--   1. Marks C1-PE-02 inactive, so it does not surface as a selectable check
--      (the /start custom list filters on active = true).
--   2. Removes C1-PE-02 from the 'diaspora' bundle, so ordering Diaspora no
--      longer creates a NIN/BVN line. The Diaspora pack still delivers its full
--      value via the site inspection and the complete check set.
--
-- To RE-ENABLE once counsel clears NIN/BVN handling: set active = true for
-- C1-PE-02 and re-insert ('diaspora','C1-PE-02') into bundle_service.
-- =============================================================================

-- 1. Switch the service off until legally cleared.
update public.service_catalogue
   set active = false
 where code = 'C1-PE-02';

-- 2. Remove it from the Diaspora bundle so no order can create a NIN/BVN line.
delete from public.bundle_service
 where bundle = 'diaspora' and service_code = 'C1-PE-02';

-- Record the decision in the audit spine.
select app.write_audit('service_catalogue', null, 'service_deferred', null, null,
  'C1-PE-02 (NIN/BVN Identity Verification) switched off and removed from Diaspora bundle pending legal clearance of NIN/BVN handling (NIMC/CBN/NDPA)');
