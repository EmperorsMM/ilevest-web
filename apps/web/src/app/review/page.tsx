// The Desk — staff queue. Three piles: Intake (Ops assigns), In review
// (the Reviewer's pile, oldest first), Exceptions (Ops decides retry or
// escalate). desk_queue() is SECURITY INVOKER: RLS grants staff the reads,
// and everyone else gets staff:false.
import { redirect } from "next/navigation";
import DeskShell from "../../components/desk-shell";
import { createSupabaseServerClient } from "../../lib/supabase/server";
import AssignToMe from "./assign-to-me";

export const dynamic = "force-dynamic";

type IntakeRow = { check_id: string; service_code: string; title: string; bundle: string | null; property: string | null; waiting_since: string };
type ReviewRow = IntakeRow & { worker: string | null; live_evidence: number };
type ExceptionRow = IntakeRow & { worker: string | null; reason: string | null; retries: number };
type Queue = { staff: boolean; intake: IntakeRow[]; in_review: ReviewRow[]; exceptions: ExceptionRow[] };

const since = (iso: string) => new Date(iso).toLocaleString();

export default async function DeskQueue() {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/signup?mode=signin&next=/review");

  const { data, error } = await supabase.rpc("desk_queue");
  const q = (!error && data ? data : { staff: false, intake: [], in_review: [], exceptions: [] }) as Queue;

  if (!q.staff) {
    return (
      <main className="wrap" style={{ padding: "60px 24px" }}>
        <h1 className="detail-h1">Staff only</h1>
        <p className="detail-empty">The desk is for Ilevest Ops and Reviewers.</p>
      </main>
    );
  }

  return (
    <>
      <DeskShell active="/review" />
      <main className="wrap" style={{ padding: "32px 24px 80px" }}>
        <h1 className="detail-h1" style={{ marginTop: 0 }}>The desk</h1>
        <p className="detail-meta">
          {q.in_review.length} in review · {q.exceptions.length} exception{q.exceptions.length === 1 ? "" : "s"} · {q.intake.length} in intake
        </p>

        <h2 style={{ marginTop: 28 }}>In review</h2>
        {q.in_review.length === 0 ? <p className="detail-empty">Nothing waiting for the Reviewer.</p> : (
          <div className="ops-table">
            <div className="ops-row ops-head"><span>Check</span><span>Property</span><span>Worker</span><span>Evidence</span><span></span></div>
            {q.in_review.map((r) => (
              <a className="ops-row" key={r.check_id} href={`/review/checks/${r.check_id}`}>
                <span><strong>{r.title}</strong><br /><small>{r.service_code} · waiting since {since(r.waiting_since)}</small></span>
                <span>{r.property ?? "—"}</span>
                <span>{r.worker ?? "—"}</span>
                <span>{r.live_evidence} item{r.live_evidence === 1 ? "" : "s"}</span>
                <span>&rarr;</span>
              </a>
            ))}
          </div>
        )}

        <h2 style={{ marginTop: 28 }}>Exceptions — with Ops</h2>
        {q.exceptions.length === 0 ? <p className="detail-empty">No blocked checks.</p> : (
          <div className="ops-table">
            <div className="ops-row ops-head"><span>Check</span><span>Reason</span><span>Worker</span><span>Retries</span><span></span></div>
            {q.exceptions.map((r) => (
              <a className="ops-row" key={r.check_id} href={`/review/checks/${r.check_id}`}>
                <span><strong>{r.title}</strong><br /><small>{r.service_code} · {r.property ?? "—"}</small></span>
                <span><small>{r.reason ?? "—"}</small></span>
                <span>{r.worker ?? "—"}</span>
                <span>{r.retries}</span>
                <span>&rarr;</span>
              </a>
            ))}
          </div>
        )}

        <h2 style={{ marginTop: 28 }}>Intake — unassigned</h2>
        <p className="detail-meta" style={{ marginTop: 2 }}>
          Assigning records the worker on the check; only Ops may assign, and only to
          someone holding a worker role.
        </p>
        {q.intake.length === 0 ? <p className="detail-empty">Every check has a worker.</p> : (
          <div className="ops-table">
            <div className="ops-row ops-head"><span>Check</span><span>Property</span><span>Bundle</span><span>Since</span><span></span></div>
            {q.intake.map((r) => (
              <div className="ops-row" key={r.check_id}>
                <span><strong>{r.title}</strong><br /><small>{r.service_code}</small></span>
                <span>{r.property ?? "—"}</span>
                <span>{r.bundle ?? "—"}</span>
                <span><small>{since(r.waiting_since)}</small></span>
                <span><AssignToMe checkId={r.check_id} /></span>
              </div>
            ))}
          </div>
        )}
      </main>
    </>
  );
}
