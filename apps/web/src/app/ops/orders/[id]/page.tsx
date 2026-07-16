"use client";

// Ops invoice builder. Add service-fee and government-fee lines, set each line's
// VAT treatment, watch the totals update live, save the draft, then issue.
// Issuing creates the payment row, fires the buyer's "quote ready" email, and
// hands them the Pay-now path. All gated server-side (Ops/Admin only).
import { useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "../../../../lib/supabase/client";

type Treatment = "apply" | "exempt" | "out_of_scope";
type Line = {
  kind: "service_fee" | "government_fee";
  service_code: string | null;
  description: string;
  amount: number | string;
  vat_treatment: Treatment;
  requires_receipt: boolean;
};

const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
const naira = (n: number) => "\u20a6" + Number(n || 0).toLocaleString("en-NG", { maximumFractionDigits: 2 });

export default function InvoiceBuilder() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const router = useRouter();
  const params = useParams();
  const orderId = (Array.isArray(params.id) ? params.id[0] : params.id) || "";

  const [loading, setLoading] = useState(true);
  const [forbidden, setForbidden] = useState(false);
  const [status, setStatus] = useState<string>("draft");
  const [vatRate, setVatRate] = useState(7.5);
  const [govDefault, setGovDefault] = useState<Treatment>("apply");
  const [lines, setLines] = useState<Line[]>([]);
  const [saving, setSaving] = useState(false);
  const [issuing, setIssuing] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      const cfg = await supabase.rpc("get_billing_config");
      if (cfg.error) { if (active) { setForbidden(true); setLoading(false); } return; }
      if (active && cfg.data) { setVatRate(Number(cfg.data.vat_rate) || 7.5); setGovDefault((cfg.data.government_fee_default_treatment as Treatment) || "apply"); }

      const inv = await supabase.rpc("get_invoice", { p_order: orderId });
      if (active && inv.data) {
        setStatus(inv.data.status ?? "draft");
        if (Array.isArray(inv.data.lines)) {
          setLines(inv.data.lines.map((l: any) => ({
            kind: l.kind, service_code: l.service_code ?? null, description: l.description ?? "",
            amount: l.amount ?? 0, vat_treatment: l.vat_treatment ?? "apply", requires_receipt: !!l.requires_receipt,
          })));
        }
      }
      if (active) setLoading(false);
    })();
    return () => { active = false; };
  }, [supabase, orderId]);

  const locked = status === "issued" || status === "paid";

  function addLine(kind: Line["kind"]) {
    setLines((ls) => [...ls, {
      kind, service_code: null, description: "",
      amount: "", vat_treatment: kind === "service_fee" ? "apply" : govDefault,
      requires_receipt: kind === "government_fee",
    }]);
  }
  function update(i: number, patch: Partial<Line>) {
    setLines((ls) => ls.map((l, idx) => (idx === i ? { ...l, ...patch } : l)));
  }
  function remove(i: number) {
    setLines((ls) => ls.filter((_, idx) => idx !== i));
  }

  const lineVat = (l: Line) => (l.vat_treatment === "apply" ? round2((Number(l.amount) || 0) * vatRate / 100) : 0);
  const serviceSubtotal = round2(lines.filter((l) => l.kind === "service_fee").reduce((a, l) => a + (Number(l.amount) || 0), 0));
  const govSubtotal = round2(lines.filter((l) => l.kind === "government_fee").reduce((a, l) => a + (Number(l.amount) || 0), 0));
  const vatTotal = round2(lines.reduce((a, l) => a + lineVat(l), 0));
  const grand = round2(serviceSubtotal + govSubtotal + vatTotal);

  async function save() {
    setSaving(true); setMsg(null);
    const payload = lines.map((l) => ({
      kind: l.kind, service_code: l.service_code, description: l.description,
      amount: Number(l.amount) || 0, vat_treatment: l.vat_treatment, requires_receipt: l.requires_receipt,
    }));
    const { error } = await supabase.rpc("ops_set_invoice_lines", { p_order: orderId, p_lines: payload });
    setSaving(false);
    setMsg(error ? `Couldn't save: ${error.message}` : "Draft saved.");
  }

  async function issue() {
    if (!confirm("Issue this invoice? The client will be emailed their quote and can pay immediately. Lines lock after issuing.")) return;
    setIssuing(true); setMsg(null);
    // save first so the issued invoice matches what's on screen
    const payload = lines.map((l) => ({
      kind: l.kind, service_code: l.service_code, description: l.description,
      amount: Number(l.amount) || 0, vat_treatment: l.vat_treatment, requires_receipt: l.requires_receipt,
    }));
    const saved = await supabase.rpc("ops_set_invoice_lines", { p_order: orderId, p_lines: payload });
    if (saved.error) { setIssuing(false); setMsg(`Couldn't save before issuing: ${saved.error.message}`); return; }
    const { error } = await supabase.rpc("ops_issue_invoice", { p_order: orderId });
    setIssuing(false);
    if (error) { setMsg(`Couldn't issue: ${error.message}`); return; }
    setStatus("issued");
    setMsg("Invoice issued — the client has been notified.");
  }

  return (
    <>

      <main className="wrap-work" style={{ padding: "28px 24px 80px", maxWidth: 760 }}>
        <a href="/ops" className="back-link">&larr; Order queue</a>
        <h1 className="detail-h1">Invoice</h1>

        {loading ? (
          <p className="detail-empty">Loading&hellip;</p>
        ) : forbidden ? (
          <p className="detail-empty">This area is for Ilevest operations staff.</p>
        ) : (
          <>
            {locked && (
              <div className="verdict-banner g" style={{ marginBottom: 20 }}>
                <div className="verdict-banner-head"><span className="dot g" /><span className="verdict-banner-title">{status === "paid" ? "Paid" : "Issued"}</span></div>
                <p className="verdict-banner-line">This invoice has been issued and its lines are locked.</p>
              </div>
            )}

            <p className="detail-meta">VAT rate {vatRate}% · government-fee default: {govDefault.replace("_", " ")}</p>

            <div className="builder">
              {lines.length === 0 && <p className="detail-empty">No lines yet. Add a service fee or a government fee below.</p>}
              {lines.map((l, i) => (
                <div className="bline" key={i}>
                  <div className="bline-top">
                    <span className={`badge ${l.kind === "service_fee" ? "issued" : "draft"}`}>{l.kind === "service_fee" ? "Service" : "Govt"}</span>
                    {!locked && <button className="bline-x" onClick={() => remove(i)} type="button">remove</button>}
                  </div>
                  <input className="bin" placeholder="Description (e.g. Title & Ownership Search)" value={l.description}
                    disabled={locked} onChange={(e) => update(i, { description: e.target.value })} />
                  <div className="bline-row">
                    <input className="bin amt" type="number" min="0" step="0.01" placeholder="Amount (₦)" value={l.amount}
                      disabled={locked} onChange={(e) => update(i, { amount: e.target.value })} />
                    <select className="bin" value={l.vat_treatment} disabled={locked}
                      onChange={(e) => update(i, { vat_treatment: e.target.value as Treatment })}>
                      <option value="apply">VAT {vatRate}%</option>
                      <option value="exempt">VAT exempt</option>
                      <option value="out_of_scope">Out of scope</option>
                    </select>
                    {l.kind === "government_fee" && (
                      <label className="brecpt">
                        <input type="checkbox" checked={l.requires_receipt} disabled={locked}
                          onChange={(e) => update(i, { requires_receipt: e.target.checked })} /> receipt
                      </label>
                    )}
                    <span className="bline-vat">{l.vat_treatment === "apply" ? `+${naira(lineVat(l))} VAT` : "no VAT"}</span>
                  </div>
                </div>
              ))}

              {!locked && (
                <div className="badd">
                  <button className="btn ghost" type="button" onClick={() => addLine("service_fee")}>+ Service fee</button>
                  <button className="btn ghost" type="button" onClick={() => addLine("government_fee")}>+ Government fee</button>
                </div>
              )}
            </div>

            <div className="inv-totals" style={{ marginTop: 20 }}>
              <div className="inv-trow"><span>Service fees</span><span>{naira(serviceSubtotal)}</span></div>
              <div className="inv-trow"><span>Government fees (at cost)</span><span>{naira(govSubtotal)}</span></div>
              <div className="inv-trow"><span>VAT</span><span>{naira(vatTotal)}</span></div>
              <div className="inv-trow grand"><span>Total</span><span>{naira(grand)}</span></div>
            </div>

            {msg && <p className="status-sub" style={{ marginTop: 14 }}>{msg}</p>}

            {!locked && (
              <div className="badd" style={{ marginTop: 18 }}>
                <button className="btn" onClick={save} disabled={saving || issuing}>{saving ? "Saving\u2026" : "Save draft"}</button>
                <button className="btn primary" onClick={issue} disabled={issuing || saving || lines.length === 0}>{issuing ? "Issuing\u2026" : "Issue invoice"}</button>
              </div>
            )}
          </>
        )}
      </main>
    </>
  );
}
