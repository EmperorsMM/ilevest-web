// Order detail view. Opens a dashboard card to the full picture: the property
// and seller, the plain-English headline verdict (one RED headlines all — the
// headline comes RED-dominant from the read-model), each check with its buyer
// status and verdict, the buyer's documents, the invoiced fees once Ops has
// quoted, and a public verification link per sealed check. Owner/staff-scoped
// by order_tracking; a non-owner is sent to a not-found.
import { notFound, redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../lib/supabase/server";
import PayButton from "./pay-button";

export const dynamic = "force-dynamic";

type Verdict = "green" | "amber" | "red" | "unresolved" | null;
type Check = { check_id: string; service_code: string; title: string; status: string; verdict: Verdict; sealed_at: string | null };
type Tracking = {
  visible: boolean;
  order_id: string;
  bundle: string;
  created_at: string;
  property: { state: string | null; state_code: string | null; lga: string | null; locality: string | null; identifying_details: string | null } | null;
  seller: string | null;
  headline_verdict: Verdict;
  ready: boolean;
  checks: Check[];
  documents: { label: string; doc_type: string; uploaded_at: string }[];
  fees: { service_fee: number; government_fee_total: number } | null;
};

type InvLine = { id: string; kind: "service_fee" | "government_fee"; description: string; amount: number; vat_treatment: string; vat_amount: number; line_total: number; requires_receipt: boolean };
type Invoice = { exists: boolean; status?: string; paid?: boolean; currency?: string; lines?: InvLine[]; service_subtotal?: number; government_subtotal?: number; vat_total?: number; grand_total?: number };

const BUNDLE_LABEL: Record<string, string> = {
  essential: "Essential Check",
  complete: "Complete Due Diligence",
  inheritance: "Inheritance & Family Land",
  diaspora: "Diaspora Package",
  ala_carte: "Custom Selection",
};

const UNRESOLVED = { c: "u", t: "Unresolved", line: "We could not fully resolve one or more checks. Treat this with caution and read the details." };
const VERDICT: Record<string, { c: string; t: string; line: string }> = {
  green: { c: "g", t: "Cleared", line: "We found no problems. Based on the checks you ordered, this is clear to proceed." },
  amber: { c: "a", t: "Proceed with care", line: "We found things you should weigh before proceeding. Read each check below carefully." },
  red: { c: "r", t: "Serious problem found", line: "We found a serious problem. Do not proceed without resolving it — a single red issue is enough to stop a purchase." },
  unresolved: UNRESOLVED,
};

function fmt(d: string) {
  return new Date(d).toLocaleDateString("en-NG", { day: "numeric", month: "short", year: "numeric" });
}
function naira(n: number) {
  return "\u20a6" + Number(n).toLocaleString("en-NG");
}

export default async function OrderDetail({ params }: { params: { id: string } }) {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect(`/signup?mode=signin&next=/client/orders/${params.id}`);

  const { data } = await supabase.rpc("order_tracking", { p_order: params.id });
  const t = (data ?? null) as Tracking | null;
  if (!t || !t.visible) notFound();

  const { data: invData } = await supabase.rpc("get_invoice", { p_order: params.id });
  const inv = (invData ?? null) as Invoice | null;
  const email = user.email ?? "";

  const label = BUNDLE_LABEL[t.bundle] ?? "Verification";
  const loc = t.property
    ? [t.property.locality, t.property.lga, t.property.state].filter(Boolean).join(", ")
    : "";

  return (
    <>
      <header className="topbar">
        <div className="wrap">
          <a className="brand" href="/start" style={{ textDecoration: "none" }}>ile<span>vest</span></a>
          <a className="signin" href="/client">My dashboard</a>
        </div>
      </header>

      <main className="wrap detail-wrap">
        <a href="/client" className="back-link">&larr; All verifications</a>

        <h1 className="detail-h1">{label}</h1>
        <p className="detail-meta">
          Placed {fmt(t.created_at)}
          {loc && <> &middot; {loc}</>}
          {t.seller && <> &middot; Seller: {t.seller}</>}
        </p>

        <VerdictBanner t={t} />

        <h2 className="detail-section">Checks</h2>
        {t.checks.length === 0 ? (
          <p className="detail-empty">No checks have started yet. They begin once your invoice is settled.</p>
        ) : (
          <div className="check-list">
            {t.checks.map((c) => <CheckRow key={c.check_id} c={c} />)}
          </div>
        )}

        {t.documents.length > 0 && (
          <>
            <h2 className="detail-section">Your documents</h2>
            <ul className="doc-list">
              {t.documents.map((d, i) => (
                <li key={i}><b>{d.label}</b> <span className="muted">&middot; uploaded {fmt(d.uploaded_at)}</span></li>
              ))}
            </ul>
          </>
        )}

        <h2 className="detail-section">Invoice</h2>
        <InvoiceBlock inv={inv} orderId={t.order_id} email={email} />
      </main>
    </>
  );
}

function VerdictBanner({ t }: { t: Tracking }) {
  if (t.ready && t.headline_verdict) {
    const v = VERDICT[t.headline_verdict] ?? UNRESOLVED;
    return (
      <section className={`verdict-banner ${v.c}`}>
        <div className="verdict-banner-head">
          <span className={`dot ${v.c}`} />
          <span className="verdict-banner-title">{v.t}</span>
        </div>
        <p className="verdict-banner-line">{v.line}</p>
      </section>
    );
  }
  const total = t.checks.length;
  const done = t.checks.filter((c) => c.status === "Ready").length;
  return (
    <section className="verdict-banner pending">
      <div className="verdict-banner-head">
        <span className="dot u" />
        <span className="verdict-banner-title">{total === 0 ? "Awaiting your quote" : "In progress"}</span>
      </div>
      <p className="verdict-banner-line">
        {total === 0
          ? "Your verification is placed. We're preparing your itemised quote — once it's settled, your checks begin and your verdict appears here."
          : `${done} of ${total} checks complete. Your overall verdict appears here once every check is done.`}
      </p>
    </section>
  );
}

function CheckRow({ c }: { c: Check }) {
  const v = c.verdict ? VERDICT[c.verdict] : null;
  return (
    <div className="check-row">
      <div className="check-main">
        <p className="check-title">{c.title}</p>
        <span className="check-status"><span className={`dot ${c.verdict ? "u" : statusDot(c.status)}`} />{c.status}</span>
      </div>
      <div className="check-side">
        {v && <span className={`verdict ${v.c}`}><span className={`dot ${v.c}`} /><b>{v.t}</b></span>}
        {c.sealed_at && (
          <a className="verify-link" href={`/verify/${c.check_id}`} target="_blank" rel="noopener noreferrer">
            Verify independently &rarr;
          </a>
        )}
      </div>
    </div>
  );
}

function InvoiceBlock({ inv, orderId, email }: { inv: Invoice | null; orderId: string; email: string }) {
  if (!inv || !inv.exists) {
    return <p className="detail-empty">We&rsquo;re preparing your itemised quote. You won&rsquo;t be charged until you&rsquo;ve seen it.</p>;
  }
  const lines = inv.lines ?? [];
  return (
    <div className="invoice-box">
      <div className="inv-lines">
        {lines.map((l) => (
          <div className="inv-line" key={l.id}>
            <div className="inv-line-main">
              <span className="inv-desc">{l.description}</span>
              <span className="inv-treat">{vatLabel(l)}</span>
            </div>
            <span className="inv-amt">{naira(l.line_total)}</span>
          </div>
        ))}
      </div>
      <div className="inv-totals">
        <div className="inv-trow"><span>Service fees</span><span>{naira(inv.service_subtotal ?? 0)}</span></div>
        <div className="inv-trow"><span>Government fees (at cost)</span><span>{naira(inv.government_subtotal ?? 0)}</span></div>
        <div className="inv-trow"><span>VAT</span><span>{naira(inv.vat_total ?? 0)}</span></div>
        <div className="inv-trow grand"><span>Total</span><span>{naira(inv.grand_total ?? 0)}</span></div>
      </div>
      {inv.paid ? (
        <p className="inv-paid">&#10003; Paid &mdash; your checks are underway.</p>
      ) : (
        <>
          <PayButton orderId={orderId} email={email} amountKobo={Math.round((inv.grand_total ?? 0) * 100)} />
          <p className="fees-note">Government fees are charged at cost with no markup &mdash; we provide a receipt for each, or refund it.</p>
        </>
      )}
    </div>
  );
}

function vatLabel(l: InvLine): string {
  if (l.vat_treatment === "apply") return `incl. VAT ${naira(l.vat_amount)}`;
  if (l.vat_treatment === "exempt") return "VAT exempt";
  return "no VAT";
}

// Status colour only matters while a check is still in motion; once a verdict
// exists the dot goes neutral so the verdict is the only colour on the row.
function statusDot(status: string): string {
  if (status === "Ready") return "g";
  if (status === "In Review") return "a";
  return "u";
}
