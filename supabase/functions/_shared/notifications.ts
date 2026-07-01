// Notifications — PURE and dependency-injected, so both the message copy and the
// dispatch control flow are unit-testable offline (no Deno, no network, no Supabase
// import here). The Edge handler wires the real database reads/writes and the email
// provider into these injection points. The channel adapter is swappable: email today,
// WhatsApp later behind the same send() shape.

export type NotificationEvent = "order_received" | "quote_ready" | "verdict_ready";

const BUNDLE_LABELS: Record<string, string> = {
  essential: "Essential Check",
  complete: "Complete Due Diligence",
  inheritance: "Inheritance & Family Land",
  diaspora: "Diaspora Package",
  ala_carte: "your selected checks",
};

export function bundleLabel(code: string | null | undefined): string {
  if (!code) return "your verification";
  return BUNDLE_LABELS[code] ?? "your verification";
}

export interface RenderData {
  name?: string | null;
  bundleLabel: string;
  orderUrl: string;
}

export interface RenderedMessage {
  subject: string;
  text: string;
  html: string;
}

// ---- the copy ---------------------------------------------------------------
// Calm, honest, plain. We never deliver a verdict colour in an email — the result
// deserves its plain-English explanation and guidance in the portal, not a stark
// word in a subject line. We always reassure on price (no charge before the quote).
export function renderNotification(event: NotificationEvent, data: RenderData): RenderedMessage {
  const name = (data.name && data.name.trim()) || "there";
  const b = data.bundleLabel;
  const url = data.orderUrl;

  let subject = "";
  let paras: string[] = [];

  if (event === "order_received") {
    subject = "We've received your verification request";
    paras = [
      `Hi ${name},`,
      `Thank you — we've received your request for ${b}. We're now preparing your itemised quote, including any government fees at cost, with no markup.`,
      `You'll hear from us the moment your quote is ready, and you won't be charged anything until you've seen exactly what your verification covers.`,
      `You can view your request any time:`,
    ];
  } else if (event === "quote_ready") {
    subject = "Your itemised quote is ready";
    paras = [
      `Hi ${name},`,
      `Your quote for ${b} is ready. It lists each check and its cost — our service fee and any government fees, itemised — so you can see exactly what you're paying for before you decide.`,
      `Review it and continue when you're ready:`,
    ];
  } else {
    subject = "Your verification is ready";
    paras = [
      `Hi ${name},`,
      `We've completed the checks for ${b}, and your result is ready to view.`,
      `Each check has a clear, plain-English finding with the evidence behind it. Please read it in full before making any decision. You — or anyone you choose — can verify every sealed result independently, even without an Ilevest account.`,
      `View your verification:`,
    ];
  }

  const text = `${paras.join("\n\n")}\n\n${url}\n\n— Ilevest`;
  const html = renderHtml(subject, paras, url);
  return { subject, text, html };
}

function renderHtml(subject: string, paras: string[], url: string): string {
  const body = paras
    .map((p) => `<p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#2A3850;">${escapeHtml(p)}</p>`)
    .join("");
  return [
    `<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:520px;margin:0 auto;padding:8px 4px;">`,
    `<div style="font-size:20px;font-weight:800;letter-spacing:-0.02em;color:#0E1A2B;margin:0 0 20px;">ile<span style="color:#1E7A46;">vest</span></div>`,
    body,
    `<a href="${escapeAttr(url)}" style="display:inline-block;margin:6px 0 24px;background:#0E1A2B;color:#fff;text-decoration:none;font-weight:700;font-size:15px;padding:12px 22px;border-radius:10px;">View in Ilevest</a>`,
    `<p style="font-size:12px;color:#5A6573;border-top:1px solid #E1E6EC;padding-top:14px;margin:0;">Independent property verification · Lagos · Ogun · FCT</p>`,
    `</div>`,
  ].join("");
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
function escapeAttr(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/"/g, "&quot;");
}

// ---- dispatch (dependency-injected) ----------------------------------------
export interface OutgoingEmail {
  to: string;
  subject: string;
  text: string;
  html: string;
}

export interface PendingNotification {
  id: string;
  user_id: string;
  event: NotificationEvent;
  order_id: string | null;
  metadata: Record<string, unknown>;
}

export interface DispatchDeps {
  fetchPending: () => Promise<PendingNotification[]>;
  resolveRecipient: (userId: string) => Promise<{ name: string | null; email: string | null } | null>;
  send: (msg: OutgoingEmail) => Promise<{ ok: boolean; id?: string; error?: string }>;
  markSent: (id: string, providerId?: string) => Promise<void>;
  markFailed: (id: string, error: string) => Promise<void>;
  orderUrl: (orderId: string | null) => string;
}

export interface DispatchSummary {
  processed: number;
  sent: number;
  failed: number;
}

function looksLikeEmail(v: string | null | undefined): boolean {
  return !!v && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v);
}

export async function dispatchOnce(deps: DispatchDeps): Promise<DispatchSummary> {
  const pending = await deps.fetchPending();
  let sent = 0;
  let failed = 0;

  for (const row of pending) {
    try {
      const recipient = await deps.resolveRecipient(row.user_id);
      if (!recipient || !looksLikeEmail(recipient.email)) {
        await deps.markFailed(row.id, "no email address on file for recipient");
        failed++;
        continue;
      }

      const msg = renderNotification(row.event, {
        name: recipient.name,
        bundleLabel: bundleLabel(row.metadata?.bundle as string | undefined),
        orderUrl: deps.orderUrl(row.order_id),
      });

      const res = await deps.send({ to: recipient.email!, subject: msg.subject, text: msg.text, html: msg.html });
      if (res.ok) {
        await deps.markSent(row.id, res.id);
        sent++;
      } else {
        await deps.markFailed(row.id, res.error ?? "send failed");
        failed++;
      }
    } catch (err) {
      await deps.markFailed(row.id, (err as Error)?.message ?? "unexpected error");
      failed++;
    }
  }

  return { processed: pending.length, sent, failed };
}
