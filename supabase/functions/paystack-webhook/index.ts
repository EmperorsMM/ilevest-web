// POST /webhooks/paystack
// Verify the gateway signature against the RAW body BEFORE doing anything, then confirm the
// payment and fan out the order — idempotently (a duplicate webhook is a no-op). System action:
// it uses the service role. The provider is swappable via the gateway module (Ruling 2).
import { preflight } from "../_shared/cors.ts";
import { json, error } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { ACTIVE_PROVIDER, verifyWebhook, extractCharge } from "../_shared/gateway.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return error("Method not allowed", 405);

  const raw = await req.text(); // raw body is required to verify the signature
  const ok = await verifyWebhook(ACTIVE_PROVIDER, raw, req.headers).catch(() => false);
  if (!ok) return error("Invalid or missing signature", 401);

  let event: any;
  try { event = JSON.parse(raw); } catch { return error("Invalid JSON body"); }

  const { success, orderId, reference } = extractCharge(ACTIVE_PROVIDER, event);
  if (!success || !orderId) return json({ received: true }); // ack non-charge events; do nothing

  const supabase = serviceClient();
  const { data, error: e } = await supabase.rpc("confirm_payment", {
    p_order: orderId, p_gateway_ref: reference ?? null,
  });
  if (e) return error("Could not confirm payment", 500, e.message);
  return json({ received: true, already_verified: data?.already_verified ?? false, checks_created: data?.checks_created ?? 0 });
});
