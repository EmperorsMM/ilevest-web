"use client";

// The bench — where verdicts are born. The Reviewer reads the worker's
// findings and evidence (files open via short-lived signed URLs), then either
// returns the check with an actionable reason or performs the sealing
// ceremony: choose the colour, write the explanation that will live inside
// the sealed record forever, and type the colour word to confirm. Two steps,
// deliberately (ratified design): a verdict should cost a breath.
//
// Ops handles exceptions here too: retry first (structural, Decision D4),
// then escalate for an honest Unresolved. Buttons follow the caller's actual
// roles, but the database remains the only gate — refusals are shown verbatim.

import { useCallback, useEffect, useMemo, useState } from "react";
import Image from "next/image";
import { useParams } from "next/navigation";
import { createSupabaseBrowserClient } from "../../../../lib/supabase/client";
import { shortHash } from "../../../../lib/hash";

type EvidenceRow = {
  id: string; kind: string; label: string | null; content_hash: string;
  storage_ref: string | null; capture_channel: string; captured_at: string | null;
  voided: boolean; void_reason: string | null;
};
type Workspace = {
  visible: boolean; check_id?: string; service_code?: string; title?: string;
  state?: string; sealed_at?: string | null; updated_at?: string | null;
  i_am_worker?: boolean; worker?: { id: string; name: string | null } | null;
  bundle?: string | null;
  property?: { state?: string | null; lga?: string | null; locality?: string | null; identifying_details?: string | null } | null;
  buyer_documents?: { label: string; doc_type: string | null; uploaded_at: string }[];
  evidence?: EvidenceRow[];
  findings_text?: string | null;
  last_reason?: string | null;
  verdict?: string | null;
};

const COLOURS = ["green", "amber", "red", "unresolved"] as const;
type Colour = (typeof COLOURS)[number];

const COLOUR_HELP: Record<Colour, string> = {
  green: "Verified clean as at today.",
  amber: "Verified with cautions the buyer must read.",
  red: "A problem was found. Say it plainly.",
  unresolved: "Honestly could not be determined; the explanation says why and what to do next.",
};

export default function ReviewBench() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const params = useParams();
  const checkId = (Array.isArray(params.id) ? params.id[0] : params.id) || "";

  const [ws, setWs] = useState<Workspace | null>(null);
  const [roles, setRoles] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);

  const [colour, setColour] = useState<Colour>("green");
  const [explanation, setExplanation] = useState("");
  const [confirmWord, setConfirmWord] = useState("");
  const [sealed, setSealed] = useState<{ content_hash: string; self_seal: boolean } | null>(null);

  const load = useCallback(async () => {
    const [wsRes, rolesRes] = await Promise.all([
      supabase.rpc("check_workspace", { p_check: checkId }),
      supabase.from("user_role").select("role"),
    ]);
    setWs((wsRes.error || !wsRes.data ? { visible: false } : wsRes.data) as Workspace);
    setRoles((rolesRes.data ?? []).map((r: { role: string }) => r.role));
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

  const viewFile = async (ref: string) => {
    const path = ref.startsWith("evidence/") ? ref.slice("evidence/".length) : ref;
    const { data, error } = await supabase.storage.from("evidence").createSignedUrl(path, 300); // 5-minute TTL — evidence files are sensitive (checklist 2.1)
    if (error || !data?.signedUrl) { setMsg({ kind: "err", text: error?.message ?? "Could not open the file." }); return; }
    window.open(data.signedUrl, "_blank", "noopener");
  };

  const returnForFix = async () => {
    const reason = window.prompt("What must the worker fix or add? They will read exactly this.");
    if (reason === null) return;
    if (reason.trim().length < 5) { setMsg({ kind: "err", text: "A return needs a reason the worker can act on." }); return; }
    await act(() => supabase.rpc("return_for_fix", { p_check: checkId, p_reason: reason.trim() }),
              "Returned — the worker sees your reason on their check.");
  };

  const seal = async () => {
    setBusy(true); setMsg(null);
    const { data, error } = await supabase.rpc("seal_check", {
      p_check: checkId, p_colour: colour, p_explanation: explanation.trim(),
    });
    if (error) setMsg({ kind: "err", text: error.message });
    else {
      setSealed({ content_hash: data.content_hash as string, self_seal: !!data.self_seal });
      setConfirmWord(""); setExplanation("");
      await load();
    }
    setBusy(false);
  };

  const retry = () =>
    act(() => supabase.rpc("retry_exception", { p_check: checkId }),
        "Sent back for another attempt — the worker has it again.");

  const escalate = async () => {
    const reason = window.prompt("Why should this become an honest Unresolved? The Reviewer will read this.");
    if (reason === null) return;
    if (reason.trim().length < 5) { setMsg({ kind: "err", text: "An escalation needs a real reason." }); return; }
    await act(() => supabase.rpc("escalate_exception", { p_check: checkId, p_reason: reason.trim() }),
              "Escalated — it lands on the Reviewer's pile for an Unresolved decision.");
  };

  if (loading) return <main className="wrap" style={{ padding: "60px 24px" }}><p className="detail-meta">Loading…</p></main>;

  if (!ws?.visible) {
    return (
      <main className="wrap" style={{ padding: "60px 24px" }}>
        <h1 className="detail-h1">Not visible</h1>
        <p className="detail-empty">The bench is for desk staff and the check&rsquo;s assigned worker.</p>
        <a className="back-link" href="/review">&larr; Back to the desk</a>
      </main>
    );
  }

  const isReviewer = roles.includes("reviewer");
  const isOps = roles.includes("ops");
  const propertyLine = [ws.property?.locality, ws.property?.lga, ws.property?.state].filter(Boolean).join(", ");
  const confirmed = confirmWord.trim().toLowerCase() === colour;
  const liveEvidence = (ws.evidence ?? []).filter((e) => !e.voided && e.kind !== "findings_summary");

  return (
    <>
      <header className="topbar">
        <div className="wrap">
          <a className="brand" href="/review" aria-label="Ilevest">
            {/* logo lockup on desktop, seal on mobile */}
            <Image className="brand-logo" src="/logo.png" alt="Ilevest" width={1046} height={346} style={{ height: 40, width: "auto" }} priority />
            <Image className="brand-seal" src="/seal.png" alt="Ilevest" width={40} height={40} style={{ height: 34, width: "auto" }} priority />
          </a>
          <span className="ops-tag" style={{ marginLeft: 10 }}>Desk</span>
        </div>
      </header>
      <main className="wrap" style={{ padding: "32px 24px 80px", maxWidth: 760 }}>
        <a className="back-link" href="/review">&larr; The desk</a>
        <h1 className="detail-h1" style={{ marginBottom: 4 }}>{ws.title}</h1>
        <p className="detail-meta">
          {ws.service_code} · <span className="badge">{ws.state?.replace(/_/g, " ")}</span>
          {propertyLine ? <> · {propertyLine}</> : null}
          {ws.worker?.name ? <> · worked by <strong>{ws.worker.name}</strong></> : null}
        </p>

        {msg && <p className={msg.kind === "ok" ? "auth-ok" : "auth-err"} style={{ marginTop: 12 }}>{msg.text}</p>}

        {sealed && (
          <div className="card" style={{ marginTop: 16, borderLeft: "4px solid #16a34a" }}>
            <strong>Sealed.</strong>
            <p style={{ margin: "6px 0 0" }}>
              Fingerprint <code>{shortHash(sealed.content_hash)}</code> is on the chain and joins tonight&rsquo;s
              anchor batch. <a href={`/verify/${checkId}`}>Public certificate &rarr;</a>
            </p>
            {sealed.self_seal && (
              <p className="detail-meta" style={{ marginTop: 6 }}>
                Recorded honestly as a self-seal: you also worked or evidenced this check (Decision D1).
              </p>
            )}
          </div>
        )}

        {ws.state === "exception" && (
          <div className="card" style={{ marginTop: 16, borderLeft: "4px solid #6b7280" }}>
            <strong>Exception</strong>
            {ws.last_reason && <p style={{ margin: "6px 0 0" }}>{ws.last_reason}</p>}
            {isOps ? (
              <div style={{ display: "flex", gap: 8, marginTop: 12, flexWrap: "wrap" }}>
                <button className="btn" disabled={busy} onClick={retry}>Send back for retry</button>
                <button className="btn" disabled={busy} onClick={escalate}
                        style={{ background: "transparent", color: "inherit", border: "1px solid currentColor" }}>
                  Escalate for Unresolved
                </button>
              </div>
            ) : (
              <p className="detail-meta" style={{ marginTop: 8 }}>Retry-or-escalate is an Ops decision.</p>
            )}
          </div>
        )}

        <div className="card" style={{ marginTop: 16 }}>
          <strong>The worker&rsquo;s findings</strong>
          {ws.findings_text ? (
            <p style={{ whiteSpace: "pre-wrap", margin: "8px 0 0" }}>{ws.findings_text}</p>
          ) : (
            <p className="detail-empty" style={{ marginTop: 8 }}>No findings summary on this check.</p>
          )}
        </div>

        <div className="card" style={{ marginTop: 16 }}>
          <strong>Evidence on the record</strong>
          {(ws.evidence ?? []).length === 0 ? (
            <p className="detail-empty" style={{ marginTop: 8 }}>Nothing captured.</p>
          ) : (
            <ul style={{ listStyle: "none", padding: 0, margin: "10px 0 0" }}>
              {(ws.evidence ?? []).map((e) => (
                <li key={e.id} style={{ padding: "8px 0", borderTop: "1px solid rgba(0,0,0,0.08)", opacity: e.voided ? 0.6 : 1 }}>
                  <span style={{ textDecoration: e.voided ? "line-through" : "none" }}>
                    <strong>{e.label ?? e.kind}</strong> <small>({e.kind.replace(/_/g, " ")} · {e.capture_channel})</small>
                  </span>
                  {e.storage_ref && !e.voided ? (
                    <> · <button className="btn" style={{ padding: "1px 8px", fontSize: 12 }} disabled={busy}
                                 onClick={() => viewFile(e.storage_ref as string)}>view</button></>
                  ) : null}
                  <br />
                  <small>fingerprint {shortHash(e.content_hash)}{e.captured_at ? ` · ${new Date(e.captured_at).toLocaleString()}` : ""}</small>
                  {e.voided && <><br /><small><em>Voided: {e.void_reason}</em></small></>}
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

        {ws.state === "in_review" && isReviewer && !sealed && (
          <>
            <div className="card" style={{ marginTop: 16 }}>
              <strong>Not satisfied?</strong>
              <p className="detail-meta" style={{ margin: "6px 0 12px" }}>
                Return it with a reason the worker can act on. The reason goes on the audit spine
                and onto the worker&rsquo;s screen.
              </p>
              <button className="btn" disabled={busy} onClick={returnForFix}
                      style={{ background: "transparent", color: "inherit", border: "1px solid currentColor" }}>
                Return for fix
              </button>
            </div>

            <div className="card" style={{ marginTop: 16, borderLeft: "4px solid #111" }}>
              <strong>The sealing ceremony</strong>
              <p className="detail-meta" style={{ margin: "6px 0 12px" }}>
                {liveEvidence.length} live evidence item{liveEvidence.length === 1 ? "" : "s"} and the findings above
                will be sealed under this verdict — permanently, immutably, publicly verifiable.
              </p>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 10 }}>
                {COLOURS.map((c) => (
                  <label key={c} style={{ border: "1px solid rgba(0,0,0,0.2)", borderRadius: 8, padding: "6px 12px",
                                          cursor: "pointer", background: colour === c ? "rgba(0,0,0,0.06)" : "transparent" }}>
                    <input type="radio" name="colour" value={c} checked={colour === c}
                           onChange={() => { setColour(c); setConfirmWord(""); }} style={{ marginRight: 6 }} />
                    {c.toUpperCase()}
                  </label>
                ))}
              </div>
              <p className="detail-meta" style={{ margin: "0 0 10px" }}>{COLOUR_HELP[colour]}</p>
              <textarea
                value={explanation}
                onChange={(e) => setExplanation(e.target.value)}
                rows={4}
                style={{ width: "100%", boxSizing: "border-box" }}
                placeholder="The explanation the buyer reads and the seal fingerprints — e.g. Title chain verified end to end at Alausa; no encumbrance entries as at today."
                disabled={busy}
              />
              <div style={{ display: "flex", gap: 8, alignItems: "center", marginTop: 12, flexWrap: "wrap" }}>
                <input
                  value={confirmWord}
                  onChange={(e) => setConfirmWord(e.target.value)}
                  placeholder={`Type ${colour.toUpperCase()} to confirm`}
                  disabled={busy}
                  style={{ padding: "6px 10px" }}
                />
                <button className="btn" disabled={busy || !confirmed || explanation.trim().length === 0} onClick={seal}>
                  Seal this verdict
                </button>
              </div>
            </div>
          </>
        )}

        {ws.state === "in_review" && !isReviewer && (
          <div className="card" style={{ marginTop: 16 }}>
            <p className="detail-meta" style={{ margin: 0 }}>Sealing and returning are Reviewer actions.</p>
          </div>
        )}
      </main>
    </>
  );
}
