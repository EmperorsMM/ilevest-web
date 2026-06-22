// GET /verify/{ref}   (public — no auth, no PII)
// Returns validity + verdict + property location + the fingerprint and its chain link. An
// unknown or unsealed reference returns { valid: false } rather than an error.
import { preflight } from "../_shared/cors.ts";
import { json, error } from "../_shared/http.ts";
import { anonClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "GET") return error("Method not allowed", 405);

  const url = new URL(req.url);
  const ref = url.searchParams.get("ref") ?? url.pathname.split("/").filter(Boolean).at(-1);
  if (!ref) return error("A certificate reference is required");

  const supabase = anonClient();
  const { data, error: e } = await supabase.rpc("verify_certificate", { p_check: ref });
  if (e) return error("Could not verify certificate", 400, e.message);
  return json(data ?? { valid: false });
});
