-- =============================================================================
-- 0012  Buyer-facing evidence index (ratified refinement to Decision on visibility)
-- =============================================================================
-- The buyer sees the INDEX of evidence on their own checks — what was captured and its
-- fingerprint (content_hash) — so they can see what was found and independently re-check the
-- hash. They do NOT get the raw-file pointer (storage_ref): turning that into a signed URL is a
-- separate, server-mediated, access-controlled step. The public verification link (Decision K)
-- still exposes none of this — only validity, verdict, and integrity proof.
--
-- Mechanism: an owner-run view whose WHERE clause is the access control (using the same
-- SECURITY DEFINER visibility helpers as the policies). storage_ref and operational fields
-- (captured_by, device_id) are simply not selected, so they can never leak through this view.
-- Raw evidence_item keeps its stricter RLS (staff + the assigned/capturing party only).

create view public.evidence_index as
  select e.id,
         e.check_id,
         e.kind,
         e.content_hash,          -- the on-device fingerprint (buyer can re-verify it)
         e.gps_lat,
         e.gps_lng,
         e.gps_accuracy,
         e.captured_at,
         e.synced_at
  from public.evidence_item e
  where app.is_staff()
     or app.partner_on_check(e.check_id)
     or app.owns_check(e.check_id);

comment on view public.evidence_index is
  'Buyer/staff-facing evidence index. Excludes storage_ref (the raw-file pointer) and operational fields. Visibility enforced in the view; the public link (Decision K) still shows none of this.';

grant select on public.evidence_index to authenticated;
