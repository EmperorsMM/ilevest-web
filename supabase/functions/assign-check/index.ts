// POST /checks/{checkId}/assign   body: { worker_id }   (Ops only)
// Dispatches a check directly to a worker (partner or field_agent). Runs as the caller, so the
// database's row-level security and the state-machine's Ops-only gate are what enforce this.
import { preflight } from "../_shared/cors.ts";
import { json, error, statusForDbError, resourceId } from "../_shared/http.ts";
import { userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return error("Method not allowed", 405);

  let body: { check_id?: string; worker_id?: string };
  try { body = await req.json(); } catch { return error("Invalid JSON body"); }
  const checkId = resourceId(req, "assign", body.check_id);
  if (!checkId || !body.worker_id) return error("checkId and worker_id are required");

  const supabase = userClient(req);
  const { error: e } = await supabase.rpc("assign_check", { p_check: checkId, p_worker: body.worker_id });
  if (e) return error("Could not assign check", statusForDbError((e as any).code), e.message);
  return json({ check_id: checkId, assigned_to: body.worker_id, state: "assigned" });
});
