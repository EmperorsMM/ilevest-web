// Offline test of the notification copy + dispatch control flow (no network, no Deno).
// Run with: node --experimental-strip-types supabase/functions/_shared/notifications.test.ts
import {
  renderNotification, dispatchOnce, bundleLabel,
  type DispatchDeps, type PendingNotification,
} from "./notifications.ts";

let passed = 0;
function ok(cond: boolean, msg: string) {
  if (!cond) throw new Error("FAIL: " + msg);
  console.log("PASS: " + msg);
  passed++;
}

// ---- copy ----
{
  const r = renderNotification("order_received", { name: "Ada", bundleLabel: bundleLabel("complete"), orderUrl: "https://x/y" });
  ok(r.subject === "We've received your verification request", "order_received subject");
  ok(r.text.includes("Hi Ada,"), "greets by name");
  ok(r.text.includes("Complete Due Diligence"), "names the bundle");
  ok(/won't be charged/.test(r.text), "reassures on price");
  ok(r.text.includes("https://x/y"), "includes the order link");
  ok(r.html.includes("ile<span"), "html carries the brand");
}
{
  const r = renderNotification("quote_ready", { name: null, bundleLabel: bundleLabel("essential"), orderUrl: "https://x/q" });
  ok(r.subject === "Your itemised quote is ready", "quote_ready subject");
  ok(r.text.includes("Hi there,"), "falls back to 'there' with no name");
  ok(/itemised/.test(r.text), "quote mentions itemisation");
}
{
  const r = renderNotification("verdict_ready", { name: "Bola", bundleLabel: bundleLabel("inheritance"), orderUrl: "https://x/v" });
  ok(r.subject === "Your verification is ready", "verdict_ready subject");
  ok(!/green|amber|red|cleared|problem/i.test(r.subject), "verdict colour is NOT revealed in the subject");
  ok(/verify every sealed result independently/.test(r.text), "verdict invites independent verification");
}

// ---- dispatch ----
function makeDeps(pending: PendingNotification[], recipients: Record<string, { name: string | null; email: string | null } | null>, sendImpl?: (m: any) => Promise<any>) {
  const calls: { sent: string[]; failed: Array<[string, string]>; emails: any[] } = { sent: [], failed: [], emails: [] };
  const deps: DispatchDeps = {
    fetchPending: async () => pending,
    resolveRecipient: async (uid) => recipients[uid] ?? null,
    send: sendImpl ?? (async (m) => { calls.emails.push(m); return { ok: true, id: "prov_1" }; }),
    markSent: async (id) => { calls.sent.push(id); },
    markFailed: async (id, err) => { calls.failed.push([id, err]); },
    orderUrl: (oid) => `https://app/client/orders/${oid}`,
  };
  return { deps, calls };
}

// happy path: one good recipient
{
  const pending: PendingNotification[] = [{ id: "n1", user_id: "u1", event: "order_received", order_id: "o1", metadata: { bundle: "complete" } }];
  const { deps, calls } = makeDeps(pending, { u1: { name: "Ada", email: "ada@example.com" } });
  const s = await dispatchOnce(deps);
  ok(s.sent === 1 && s.failed === 0 && s.processed === 1, "one pending -> one sent");
  ok(calls.sent[0] === "n1", "markSent called with the row id");
  ok(calls.emails[0].to === "ada@example.com" && calls.emails[0].subject.length > 0, "email addressed + rendered");
}

// missing email -> failed, not sent
{
  const pending: PendingNotification[] = [{ id: "n2", user_id: "u2", event: "verdict_ready", order_id: "o2", metadata: {} }];
  const { deps, calls } = makeDeps(pending, { u2: { name: "NoEmail", email: null } });
  const s = await dispatchOnce(deps);
  ok(s.failed === 1 && s.sent === 0, "no email -> failed");
  ok(calls.failed[0][0] === "n2" && /no email/.test(calls.failed[0][1]), "markFailed records the reason");
}

// provider failure -> failed with provider error
{
  const pending: PendingNotification[] = [{ id: "n3", user_id: "u3", event: "quote_ready", order_id: "o3", metadata: { bundle: "diaspora" } }];
  const { deps, calls } = makeDeps(pending, { u3: { name: "X", email: "x@example.com" } }, async () => ({ ok: false, error: "provider 500" }));
  const s = await dispatchOnce(deps);
  ok(s.failed === 1 && calls.failed[0][1] === "provider 500", "provider failure -> markFailed with its error");
}

console.log(`\n${passed} assertions passed.`);
