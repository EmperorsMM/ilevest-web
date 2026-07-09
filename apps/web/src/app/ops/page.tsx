// Ops order queue. Staff-only landing for operations: every order with its
// client, what they asked for, and where it stands (no invoice yet / draft /
// issued / paid). Each row opens the invoice builder. Gated by ops_order_queue
// (staff-only); a non-staff caller gets a clear "not authorised".
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../lib/supabase/server";

export const dynamic = "force-dynamic";

type QueueRow = {
  order_id: string; created_at: string; bundle: string;
  client: string | null; client_contact: string | null;
  property: string | null; seller: string | null;
  invoice_status: "none" | "draft" | "issued" | "paid" | "void";
  paid: boolean; line_count: number;
};

const BUNDLE_LABEL: Record<string, string> = {
  essential: "Essential Check", complete: "Complete Due Diligence",
  inheritance: "Inheritance & Family Land", diaspora: "Diaspora Package", ala_carte: "Custom Selection",
};

export default async function OpsQueue() {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/signup?mode=signin&next=/ops");

  const { data, error } = await supabase.rpc("ops_order_queue");
  if (error) {
    return (
      <main className="wrap" style={{ padding: "60px 24px" }}>
        <h1 className="detail-h1">Not authorised</h1>
        <p className="detail-empty">This area is for Ilevest operations staff.</p>
        <a className="back-link" href="/client">&larr; Back to your dashboard</a>
      </main>
    );
  }
  const rows = (Array.isArray(data) ? data : []) as QueueRow[];

  return (
    <>
      <main className="wrap" style={{ padding: "32px 24px 80px" }}>
        <h1 className="detail-h1" style={{ marginTop: 0 }}>Order queue</h1>
        <p className="detail-meta">{rows.length} order{rows.length === 1 ? "" : "s"}</p>

        {rows.length === 0 ? (
          <p className="detail-empty">No orders yet.</p>
        ) : (
          <div className="ops-table">
            <div className="ops-row ops-head">
              <span>Order</span><span>Client</span><span>Checks</span><span>Status</span><span></span>
            </div>
            {rows.map((r) => (
              <a className="ops-row" key={r.order_id} href={`/ops/orders/${r.order_id}`}>
                <span>
                  <b>{BUNDLE_LABEL[r.bundle] ?? "Verification"}</b>
                  <span className="ops-sub">{r.property || "\u2014"}{r.seller ? ` \u00b7 ${r.seller}` : ""}</span>
                </span>
                <span>
                  {r.client || "\u2014"}
                  <span className="ops-sub">{r.client_contact || ""}</span>
                </span>
                <span>{r.line_count}</span>
                <span><StatusBadge status={r.invoice_status} paid={r.paid} /></span>
                <span className="ops-go">Open &rarr;</span>
              </a>
            ))}
          </div>
        )}
      </main>
    </>
  );
}

function StatusBadge({ status, paid }: { status: string; paid: boolean }) {
  if (paid) return <span className="badge paid">Paid</span>;
  if (status === "issued") return <span className="badge issued">Issued \u00b7 awaiting payment</span>;
  if (status === "draft") return <span className="badge draft">Draft</span>;
  return <span className="badge none">Needs invoice</span>;
}
