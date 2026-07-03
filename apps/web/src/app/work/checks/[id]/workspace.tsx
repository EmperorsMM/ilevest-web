"use client";

// The worker's workspace for one check. Every action here is a thin hand on a
// database lever — the FSM trigger, the capture law, the void rules and the
// ceremony doors are the authority; this surface just makes them pleasant.
// Errors from the database are shown verbatim: they are written for humans.
//
// Capture flow (Decision D2/D3): pick a file -> SHA-256 in the browser
// (WebCrypto) -> upload to the private `evidence` bucket under this check's
// folder -> record_evidence with the hash, the storage path and a label.
// Findings are text -> record_findings hashes them server-side; correcting
// findings means voiding the old summary (with a reason) and writing anew.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams } from "next/navigation";
import { createSupabaseBrowserClient } from "../../../../lib/supabase/client";
import { sha256HexOfFile, shortHash } from "../../../../lib/hash";

type EvidenceRow = {
  id: string; kind: string; label: string | null; content_hash: string;
  capture_channel: string; captured_at: string | null;
  voided: boolean; void_reason: string | null;
};
type Workspace = {
  visible: boolean; check_id?: string; service_code?: string; title?: string;
  state?: string; is_finalized?: boolean; sealed_at?: string | null;
  i_am_worker?: boolean; bundle?: string | null;
  property?: { state?: string | null; lga?: string | null; locality?: string | null; identifying_details?: string | null } | null;
  buyer_documents?: { label: string; doc_type: string | null; uploaded_at: string }[];
  evidence?: EvidenceRow[];
  findings_text?: string | null;
  last_reason?: string | null;
  verdict?: string | null;
};

const KIND_OPTIONS = [
  { value: "register_photo", label: "Register / record photo" },
  { value: "document", label: "Document (PDF or image)" },
  { value: "receipt", label: "Official receipt" },
] as const;

export default function CheckWorkspace() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const params = useParams();
  const checkId = (Array.isArray(params.id) ? params.id[0] : params.id) || "";

  const [ws, setWs] = useState<Workspace | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);

  const [kind, setKind] = useState<(typeof KIND_OPTIONS)[number]["value"]>("register_photo");
  const fileRef = useRef<HTMLInputElement | null>(null);
  const [findings, setFindings] = useState("");
  const [editingFindings, setEditingFindings] = useState(false);

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc("check_workspace", { p_check: checkId });
    if (error || !data) { setWs({ visible: false }); setLoading(false); return; }
    setWs(data as Workspace);
    setLoading(false);
  }, [supabase, checkId]);

  useEffect(() => { void load(); }, [load]);

  const act = useCallback(async (fn: () => PromiseLike<{ error: { message: string } | null }>, okText: string): Promise<boolean> => {
    setBusy(true); setMsg(null);
    const { error } = await fn();
    if (error) setMsg({ kind: "err", text: error.message });
    else { setMsg({ kind: "ok", text: okText }); await load(); }
    setBusy(false);
    return !error;
  }, [load]);

  const startCheck = () =>
    act(() => supabase.rpc("start_check", { p_check: checkId }), "Check started — capture as you go.");

  const captureFile = async () => {
    const file = fileRef.current?.files?.[0];
    if (!file) { setMsg({ kind: "err", text: "Choose a file first." }); return; }
    setBusy(true); setMsg(null);
    try {
      const hash = await sha256HexOfFile(file);
      const ext = file.name.includes(".") ? file.name.split(".").pop() : "bin";
      const path = `${checkId}/${crypto.randomUUID()}.${ext}`;
      const up = await supabase.storage.from("evidence").upload(path, file, {
        contentType: file.type || "application/octet-stream", upsert: false,
      });
      if (up.error) { setMsg({ kind: "err", text: up.error.message }); setBusy(false); return; }
      const rec = await supabase.rpc("record_evidence", {
        p_check: checkId, p_kind: kind, p_content_hash: hash,
        p_storage_ref: `evidence/${path}`, p_label: file.name, p_capture_channel: "web",
      });
      if (rec.error) setMsg({ kind: "err", text: rec.error.message });
      else {
        setMsg({ kind: "ok", text: `Captured and fingerprinted (${shortHash(hash)}).` });
        if (fileRef.current) fileRef.current.value = "";
        await load();
      }
    } catch (e) {
      setMsg({ kind: "err", text: e instanceof Error ? e.message : "Capture failed." });
    }
    setBusy(false);
  };

  const saveFindings = async () => {
    const ok = await act(() => supabase.rpc("record_findings", { p_check: checkId, p_text: findings }),
                         "Findings written and fingerprinted.");
    if (ok) { setEditingFindings(false); setFindings(""); }
  };

  const voidItem = async (id: string, what: string) => {
    const reason = window.prompt(`Why are you voiding this ${what}? The item and your reason stay visible forever.`);
    if (reason === null) return;
    if (reason.trim().length < 5) { setMsg({ kind: "err", text: "A void needs a real reason (at least 5 characters)." }); return; }
    await act(() => supabase.rpc("void_evidence", { p_evidence: id, p_reason: reason.trim() }),
              "Voided — the marker and reason are on the record.");
  };

  const submitForReview = () =>
    act(() => supabase.rpc("submit_for_review", { p_check: checkId }),
        "Submitted — the Reviewer takes it from here.");

  const flagException = async () => {
    const reason = window.prompt("What is blocking this check? Ops will decide the retry.");
    if (reason === null) return;
    if (reason.trim().length < 5) { setMsg({ kind: "err", text: "An exception needs a real reason (at least 5 characters)." }); return; }
    await act(() => supabase.rpc("flag_exception", { p_check: checkId, p_reason: reason.trim() }),
              "Exception flagged — Ops has it.");
  };

  if (loading) return <main className="wrap" style={{ padding: "60px 24px" }}><p className="detail-meta">Loading…</p></main>;

  if (!ws?.visible) {
    return (
      <main className="wrap" style={{ padding: "60px 24px" }}>
        <h1 className="detail-h1">Not your check</h1>
        <p className="detail-empty">This workspace belongs to the worker assigned to the check.</p>
        <a className="back-link" href="/work">&larr; Back to my checks</a>
      </main>
    );
  }

  const workable = !!ws.i_am_worker && (ws.state === "in_progress" || ws.state === "returned_for_fix");
  const liveFindings = (ws.evidence ?? []).find((e) => e.kind === "findings_summary" && !e.voided);
  const propertyLine = [ws.property?.locality, ws.property?.lga, ws.property?.state].filter(Boolean).join(", ");

  return (
    <>
      <header className="topbar">
        <div className="wrap">
          <span className="brand">ile<span>vest</span> <span className="ops-tag">Work</span></span>
        </div>
      </header>
      <main className="wrap" style={{ padding: "32px 24px 80px", maxWidth: 760 }}>
        <a className="back-link" href="/work">&larr; My checks</a>
        <h1 className="detail-h1" style={{ marginBottom: 4 }}>{ws.title}</h1>
        <p className="detail-meta">
          {ws.service_code} · <span className="badge">{ws.state?.replace(/_/g, " ")}</span>
          {propertyLine ? <> · {propertyLine}</> : null}
        </p>
        {ws.property?.identifying_details ? (
          <p className="detail-meta" style={{ marginTop: 2 }}>{ws.property.identifying_details}</p>
        ) : null}

        {msg && <p className={msg.kind === "ok" ? "auth-ok" : "auth-err"} style={{ marginTop: 12 }}>{msg.text}</p>}

        {ws.state === "returned_for_fix" && ws.last_reason && (
          <div className="card" style={{ marginTop: 16, borderLeft: "4px solid #d97706" }}>
            <strong>Returned by the Reviewer</strong>
            <p style={{ margin: "6px 0 0" }}>{ws.last_reason}</p>
          </div>
        )}
        {ws.state === "exception" && (
          <div className="card" style={{ marginTop: 16 }}>
            <strong>Exception — with Ops</strong>
            {ws.last_reason && <p style={{ margin: "6px 0 0" }}>{ws.last_reason}</p>}
            <p className="detail-meta" style={{ marginTop: 6 }}>Ops decides the next step: retry, or escalate for an honest Unresolved.</p>
          </div>
        )}
        {ws.state === "in_review" && (
          <div className="card" style={{ marginTop: 16 }}>
            <strong>With the Reviewer</strong>
            <p className="detail-meta" style={{ marginTop: 6 }}>Nothing more to do here unless it comes back.</p>
          </div>
        )}
        {ws.state === "finalized" && (
          <div className="card" style={{ marginTop: 16, borderLeft: "4px solid #16a34a" }}>
            <strong>Sealed{ws.verdict ? ` — ${ws.verdict.toUpperCase()}` : ""}</strong>
            <p className="detail-meta" style={{ marginTop: 6 }}>
              Permanently immutable. <a href={`/verify/${ws.check_id}`}>Public certificate &rarr;</a>
            </p>
          </div>
        )}

        {ws.i_am_worker && ws.state === "assigned" && (
          <div className="card" style={{ marginTop: 16 }}>
            <strong>Ready to begin?</strong>
            <p className="detail-meta" style={{ margin: "6px 0 12px" }}>
              Starting records you as the worker on this check.
            </p>
            <button className="btn" disabled={busy} onClick={startCheck}>Start this check</button>
          </div>
        )}

        {workable && (
          <>
            <div className="card" style={{ marginTop: 16 }}>
              <strong>Capture evidence</strong>
              <p className="detail-meta" style={{ margin: "6px 0 12px" }}>
                The file is fingerprinted in your browser before upload; the fingerprint is what gets sealed.
              </p>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                <select value={kind} onChange={(e) => setKind(e.target.value as typeof kind)} disabled={busy}>
                  {KIND_OPTIONS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}
                </select>
                <input ref={fileRef} type="file" accept="image/*,.pdf" disabled={busy} />
                <button className="btn" disabled={busy} onClick={captureFile}>Add to record</button>
              </div>
            </div>

            <div className="card" style={{ marginTop: 16 }}>
              <strong>Findings summary</strong>
              <p className="detail-meta" style={{ margin: "6px 0 12px" }}>
                What you found, in plain words — &ldquo;nothing found&rdquo; is itself a finding. The text is
                hashed and sealed with the verdict.
              </p>
              {liveFindings && !editingFindings ? (
                <>
                  <p style={{ whiteSpace: "pre-wrap", margin: "0 0 12px" }}>{ws.findings_text}</p>
                  <button
                    className="btn"
                    disabled={busy}
                    onClick={async () => {
                      const reason = window.prompt("Voiding the current findings to rewrite them — why? The old text stays on the record.");
                      if (reason === null) return;
                      if (reason.trim().length < 5) { setMsg({ kind: "err", text: "A void needs a real reason (at least 5 characters)." }); return; }
                      setFindings(ws.findings_text ?? "");
                      await act(() => supabase.rpc("void_evidence", { p_evidence: liveFindings.id, p_reason: reason.trim() }),
                                "Old findings voided — write the corrected summary.");
                      setEditingFindings(true);
                    }}
                  >
                    Void &amp; rewrite
                  </button>
                </>
              ) : (
                <>
                  <textarea
                    value={findings}
                    onChange={(e) => setFindings(e.target.value)}
                    rows={6}
                    style={{ width: "100%", boxSizing: "border-box" }}
                    placeholder="e.g. Register searched 1998–2024 at Alausa; title chain consistent; no encumbrance entries as at today."
                    disabled={busy}
                  />
                  <div style={{ marginTop: 10 }}>
                    <button className="btn" disabled={busy || findings.trim().length === 0} onClick={saveFindings}>
                      Save findings
                    </button>
                  </div>
                </>
              )}
            </div>

            <div className="card" style={{ marginTop: 16 }}>
              <strong>Finish</strong>
              <p className="detail-meta" style={{ margin: "6px 0 12px" }}>
                Submitting hands the check to the Reviewer. Flag an exception if something outside your
                control is blocking the work.
              </p>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                <button className="btn" disabled={busy} onClick={submitForReview}>Submit for review</button>
                <button className="btn" disabled={busy} onClick={flagException} style={{ background: "transparent", color: "inherit", border: "1px solid currentColor" }}>
                  Flag an exception
                </button>
              </div>
            </div>
          </>
        )}

        <div className="card" style={{ marginTop: 16 }}>
          <strong>Evidence on the record</strong>
          {(ws.evidence ?? []).length === 0 ? (
            <p className="detail-empty" style={{ marginTop: 8 }}>Nothing captured yet.</p>
          ) : (
            <ul style={{ listStyle: "none", padding: 0, margin: "10px 0 0" }}>
              {(ws.evidence ?? []).map((e) => (
                <li key={e.id} style={{ padding: "8px 0", borderTop: "1px solid rgba(0,0,0,0.08)", opacity: e.voided ? 0.6 : 1 }}>
                  <span style={{ textDecoration: e.voided ? "line-through" : "none" }}>
                    <strong>{e.label ?? e.kind}</strong> <small>({e.kind.replace(/_/g, " ")} · {e.capture_channel})</small>
                  </span>
                  <br />
                  <small>fingerprint {shortHash(e.content_hash)}{e.captured_at ? ` · ${new Date(e.captured_at).toLocaleString()}` : ""}</small>
                  {e.voided ? (
                    <><br /><small><em>Voided: {e.void_reason}</em></small></>
                  ) : workable && e.kind !== "findings_summary" ? (
                    <> · <button className="btn" style={{ padding: "1px 8px", fontSize: 12 }} disabled={busy} onClick={() => voidItem(e.id, "item")}>void</button></>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </div>

        {(ws.buyer_documents ?? []).length > 0 && (
          <div className="card" style={{ marginTop: 16 }}>
            <strong>Documents the buyer provided</strong>
            <ul style={{ margin: "10px 0 0", paddingLeft: 18 }}>
              {(ws.buyer_documents ?? []).map((d, i) => (
                <li key={i}><small>{d.label}{d.doc_type ? ` (${d.doc_type})` : ""}</small></li>
              ))}
            </ul>
          </div>
        )}
      </main>
    </>
  );
}
