// POST /checks/{checkId}/evidence   (assigned worker or staff)
// Records one evidence item. The content hash is computed on the capturing device; the raw file
// (if any) is referenced in storage, never inlined. Only the assigned worker or staff may post —
// enforced by row-level security on the underlying table.
import { preflight } from "../_shared/cors.ts";
import { json, error, statusForDbError, resourceId } from "../_shared/http.ts";
import { userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return error("Method not allowed", 405);

  let b: any;
  try { b = await req.json(); } catch { return error("Invalid JSON body"); }
  const checkId = resourceId(req, "evidence", b.check_id);
  if (!checkId || !b.kind || !b.content_hash) return error("checkId, kind and content_hash are required");

  const supabase = userClient(req);
  const { data, error: e } = await supabase.rpc("record_evidence", {
    p_check: checkId, p_kind: b.kind, p_content_hash: b.content_hash,
    p_storage_ref: b.storage_ref ?? null,
    p_gps_lat: b.gps_lat ?? null, p_gps_lng: b.gps_lng ?? null, p_gps_accuracy: b.gps_accuracy ?? null,
    p_captured_at: b.captured_at ?? null, p_device_id: b.device_id ?? null,
  });
  if (e) return error("Could not record evidence", statusForDbError((e as any).code), e.message);
  return json({ evidence_id: data }, 201);
});
