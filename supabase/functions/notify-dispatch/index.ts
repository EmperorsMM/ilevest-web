// Notification dispatch worker (deploy-verified — the build sandbox cannot reach the
// email provider). Intended to run on a short pg_cron schedule. Orchestration + copy live
// in ../_shared/notifications.ts (unit-tested offline); this file supplies the real database
// reads/writes and the swappable email provider.
//
// Auth: scheduler-only. Gated by a shared secret header (x-notify-secret); deploy with
// --no-verify-jwt. Never exposed to browsers. Uses the service role to read the outbox and
// update delivery status (the worker is a verified system action, not a user).
import { serviceClient } from "../_shared/supabase.ts";
import { json, error } from "../_shared/http.ts";
import { dispatchOnce, type DispatchDeps, type OutgoingEmail, type PendingNotification } from "../_shared/notifications.ts";

const APP_BASE_URL = Deno.env.get("APP_BASE_URL") ?? "https://ilevest.com";
const MAIL_PROVIDER = Deno.env.get("MAIL_PROVIDER") ?? "resend";
const MAIL_FROM = Deno.env.get("MAIL_FROM") ?? "Ilevest <noreply@ilevest.com>";

// ---- swappable email provider (same discipline as the payment/anchor providers) ----
// Email today; a WhatsApp adapter would implement the same send() shape and be chosen by
// the notification's channel. Default is Resend; set MAIL_PROVIDER=none to stage without sending.
async function sendEmail(msg: OutgoingEmail): Promise<{ ok: boolean; id?: string; error?: string }> {
  if (MAIL_PROVIDER === "none") return { ok: false, error: "email disabled (MAIL_PROVIDER=none)" };
  if (MAIL_PROVIDER === "resend") {
    const key = Deno.env.get("RESEND_API_KEY");
    if (!key) return { ok: false, error: "RESEND_API_KEY not configured" };
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify({ from: MAIL_FROM, to: msg.to, subject: msg.subject, html: msg.html, text: msg.text }),
    });
    if (!res.ok) return { ok: false, error: `resend ${res.status}` };
    const data = await res.json().catch(() => ({} as any));
    return { ok: true, id: data?.id };
  }
  return { ok: false, error: `unknown MAIL_PROVIDER: ${MAIL_PROVIDER}` };
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("NOTIFY_TRIGGER_SECRET") ?? "";
  if (!secret || req.headers.get("x-notify-secret") !== secret) {
    return error("unauthorized", 401);
  }
  try {
    const sb = serviceClient();
    const deps: DispatchDeps = {
      fetchPending: async () => {
        const { data, error: e } = await sb
          .from("notification")
          .select("id,user_id,event,order_id,metadata")
          .eq("status", "pending")
          .order("created_at", { ascending: true })
          .limit(50);
        if (e) throw e;
        return (data ?? []) as PendingNotification[];
      },
      resolveRecipient: async (userId) => {
        const { data, error: e } = await sb
          .from("app_user")
          .select("name,email_or_phone")
          .eq("id", userId)
          .maybeSingle();
        if (e) throw e;
        if (!data) return null;
        return { name: (data as any).name ?? null, email: (data as any).email_or_phone ?? null };
      },
      send: sendEmail,
      markSent: async (id, providerId) => {
        const { error: e } = await sb
          .from("notification")
          .update({ status: "sent", sent_at: new Date().toISOString(), last_error: providerId ? `provider_id:${providerId}` : null })
          .eq("id", id);
        if (e) throw e;
      },
      markFailed: async (id, errMsg) => {
        const { error: e } = await sb
          .from("notification")
          .update({ status: "failed", last_error: errMsg })
          .eq("id", id);
        if (e) throw e;
      },
      orderUrl: (orderId) => (orderId ? `${APP_BASE_URL}/client/orders/${orderId}` : `${APP_BASE_URL}/client`),
    };

    const summary = await dispatchOnce(deps);
    return json(summary);
  } catch (e) {
    return error("dispatch failed", 500, String((e as Error)?.message ?? e));
  }
});
