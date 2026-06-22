// POST /checks/{checkId}/seal   body: { colour, explanation }   (Reviewer / Ops)
// Finalises a check: records the verdict, finalises the check (immutable thereafter), computes a
// reproducible fingerprint from the verification's own facts, and appends a commitment to the
// proof-layer hash-chain. All of that happens atomically inside the database function.
import { preflight } from "../_shared/cors.ts";
import { json, error, statusForDbError, resourceId } from "../_shared/http.ts";
import { userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return error("Method not allowed", 405);

  let body: { check_id?: string; colour?: string; explanation?: string };
  try { body = await req.json(); } catch { return error("Invalid JSON body"); }
  const checkId = resourceId(req, "seal", body.check_id);
  if (!checkId || !body.colour || !body.explanation) return error("checkId, colour and explanation are required");

  const supabase = userClient(req);
  const { data, error: e } = await supabase.rpc("seal_check", {
    p_check: checkId, p_colour: body.colour, p_explanation: body.explanation,
  });
  if (e) return error("Could not seal check", statusForDbError((e as any).code), e.message);
  return json(data); // { check_id, verdict, content_hash, prev_hash, commitment_id }
});
