// My Checks — the worker's caseload. Server component; my_checks() is
// SECURITY INVOKER, so Row-Level Security scopes the list to the signed-in
// worker. Fix requests surface first, then new work, then work in hand.
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../lib/supabase/server";

export const dynamic = "force-dynamic";

type CaseRow = {
  check_id: string; service_code: string; title: string;
  state: "initiated" | "assigned" | "in_progress" | "in_review" | "returned_for_fix" | "exception" | "finalized" | "rejected";
  bundle: string | null; property: string | null;
  live_evidence: number; has_findings: boolean;
  created_at: string; updated_at: string | null;
};

const STATE_LABEL: Record<CaseRow["state"], string> = {
  initiated: "New", assigned: "Assigned to you", in_progress: "In progress",
  in_review: "With the Reviewer", returned_for_fix: "Returned — fix requested",
  exception: "Exception — with Ops", finalized: "Sealed", rejected: "Closed",
};

export default async function MyChecks() {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/signup?mode=signin&next=/work");

  const { data, error } = await supabase.rpc("my_checks");
  const rows = (!error && Array.isArray(data) ? data : []) as CaseRow[];
  const open = rows.filter((r) => !["finalized", "rejected"].includes(r.state));
  const done = rows.filter((r) => ["finalized", "rejected"].includes(r.state));

  return (
    <>
      <main className="wrap-work" style={{ padding: "32px 24px 80px" }}>
        <h1 className="detail-h1" style={{ marginTop: 0 }}>My checks</h1>
        <p className="detail-meta">
          {open.length} open · {done.length} completed
        </p>

        {rows.length === 0 ? (
          <p className="detail-empty">
            No checks are assigned to you yet. This area is for Ilevest verification
            workers; Ops assigns each check to its worker.
          </p>
        ) : (
          <div className="ops-table">
            <div className="ops-row ops-head">
              <span>Check</span><span>Property</span><span>Status</span><span>Evidence</span><span></span>
            </div>
            {[...open, ...done].map((r) => (
              <a className="ops-row" key={r.check_id} href={`/work/checks/${r.check_id}`}>
                <span>
                  <strong>{r.title}</strong>
                  <br /><small>{r.service_code}</small>
                </span>
                <span>{r.property ?? "—"}</span>
                <span>
                  <span className="badge">{STATE_LABEL[r.state]}</span>
                </span>
                <span>
                  {r.live_evidence} item{r.live_evidence === 1 ? "" : "s"}
                  {r.has_findings ? " · findings ✓" : " · findings pending"}
                </span>
                <span>&rarr;</span>
              </a>
            ))}
          </div>
        )}
      </main>
    </>
  );
}
