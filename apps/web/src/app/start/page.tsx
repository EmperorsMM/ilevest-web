"use client";

// Journey entry (public — no signup to browse). Pick an outcome bundle or build a custom
// selection from the live catalogue, see the documents that would help, and continue to sign up.
// No prices shown by design: Ilevest prepares an itemised quote for the specific property.
// All reads are anon RPCs already proven at the database (service_catalogue, bundle_service,
// document_checklist) with RLS as the real boundary.
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "../../lib/supabase/client";

type Service = { code: string; title: string; sort: number };
type ChecklistItem = { document_label: string; tier: "helpful" | "optional" };

const BUNDLES: { key: string; name: string; who: string }[] = [
  { key: "essential",   name: "Essential Check",        who: "The two checks no purchase should skip." },
  { key: "complete",    name: "Complete Due Diligence", who: "Our most thorough pre-purchase review." },
  { key: "inheritance", name: "Inheritance Property",   who: "When the property is sold by heirs or an estate." },
  { key: "diaspora",    name: "Diaspora Pack",          who: "Buying from abroad — we become your eyes on the ground." },
];

const DESKS: Record<string, string> = {
  LR: "Lands Registry",
  SG: "Surveyor-General",
  CT: "Courts & Probate",
  PE: "People & Companies",
  FD: "Field Inspection",
};
const deskOf = (code: string) => code.split("-")[1] ?? "";

export default function StartPage() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const router = useRouter();
  const [catalogue, setCatalogue] = useState<Service[]>([]);
  const [composition, setComposition] = useState<Record<string, string[]>>({});
  const [mode, setMode] = useState<"bundles" | "custom">("bundles");
  const [bundle, setBundle] = useState<string | null>(null);
  const [custom, setCustom] = useState<string[]>([]);
  const [checklist, setChecklist] = useState<ChecklistItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [authed, setAuthed] = useState<boolean | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setAuthed(!!data.user)).catch(() => setAuthed(false));
  }, [supabase]);

  // load the catalogue and bundle compositions once
  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const [cat, bs] = await Promise.all([
          supabase.from("service_catalogue").select("code,title,sort").eq("active", true).order("sort"),
          supabase.from("bundle_service").select("bundle,service_code"),
        ]);
        if (cat.error) throw cat.error;
        if (bs.error) throw bs.error;
        if (!live) return;
        setCatalogue((cat.data ?? []) as Service[]);
        const comp: Record<string, string[]> = {};
        for (const row of (bs.data ?? []) as { bundle: string; service_code: string }[]) {
          (comp[row.bundle] ??= []).push(row.service_code);
        }
        setComposition(comp);
      } catch {
        if (live) setError("We couldn't load the list of checks just now. Please refresh to try again.");
      } finally {
        if (live) setLoading(false);
      }
    })();
    return () => { live = false; };
  }, [supabase]);

  const selectedCodes = useMemo(
    () => (mode === "bundles" ? (bundle ? composition[bundle] ?? [] : []) : custom),
    [mode, bundle, custom, composition],
  );

  // refresh the consolidated, de-duplicated checklist whenever the selection changes
  useEffect(() => {
    if (selectedCodes.length === 0) { setChecklist([]); return; }
    let live = true;
    (async () => {
      const { data, error } = await supabase.rpc("document_checklist", { p_codes: selectedCodes });
      if (!live) return;
      if (error) { setChecklist([]); return; }
      setChecklist((data ?? []) as ChecklistItem[]);
    })();
    return () => { live = false; };
  }, [supabase, selectedCodes]);

  const titleOf = (code: string) => catalogue.find((s) => s.code === code)?.title ?? code;
  const toggle = (code: string) =>
    setCustom((c) => (c.includes(code) ? c.filter((x) => x !== code) : [...c, code]));

  const byDesk = useMemo(() => {
    const groups: Record<string, Service[]> = {};
    for (const s of catalogue) (groups[deskOf(s.code)] ??= []).push(s);
    return groups;
  }, [catalogue]);

  function continueToOrder() {
    try {
      localStorage.setItem("ilevest.selection", JSON.stringify({ mode, bundle, custom, codes: selectedCodes }));
    } catch {
      // basket carry is best-effort; never block the journey
    }
    router.push(authed ? "/new" : "/signup?next=/new");
  }

  return (
    <>
      <header className="topbar">
        <div className="wrap">
          <div className="brand">ile<span>vest</span></div>
          {authed ? (
            <a className="signin" href="/client">My dashboard</a>
          ) : (
            <a className="signin" href="/signup?mode=signin">Sign in</a>
          )}
        </div>
      </header>

      <main>
        <section className="hero">
          <div className="wrap">
            <div className="eyebrow">Independent property verification · Lagos · Ogun · FCT</div>
            <h1>Know exactly what you’re buying before you pay for it.</h1>
            <p className="lede">
              Land fraud, fake titles, and disputed ownership cost Nigerian buyers everything. We check the
              property against the registries, the survey records, and the courts, then give you a clear,
              evidence-backed verdict you can verify yourself.
            </p>
            <div className="verdicts" aria-label="How we report a verdict">
              <span className="verdict g"><span className="dot g" /> <b>Green</b> — clear to proceed</span>
              <span className="verdict"><span className="dot a" /> <b>Amber</b> — proceed with care</span>
              <span className="verdict"><span className="dot r" /> <b>Red</b> — a serious problem</span>
            </div>
          </div>
        </section>

        <div className="wrap layout2">
          <section className="section">
            <h2>Choose how to start</h2>
            <div className="tabs" role="tablist">
              <button role="tab" aria-selected={mode === "bundles"} className={mode === "bundles" ? "active" : ""}
                onClick={() => setMode("bundles")}>Choose a bundle</button>
              <button role="tab" aria-selected={mode === "custom"} className={mode === "custom" ? "active" : ""}
                onClick={() => setMode("custom")}>Build your own</button>
            </div>

            {loading && <div className="statebox">Loading the available checks…</div>}
            {error && !loading && <div className="statebox">{error}</div>}

            {!loading && !error && mode === "bundles" && (
              <div className="grid">
                {BUNDLES.filter((b) => composition[b.key]?.length).map((b) => {
                  const codes = composition[b.key] ?? [];
                  const isSel = bundle === b.key;
                  return (
                    <button key={b.key} className={`card${isSel ? " selected" : ""}`} aria-pressed={isSel}
                      onClick={() => setBundle(isSel ? null : b.key)}>
                      <div className="name">{b.name}</div>
                      <div className="who">{b.who}</div>
                      <ul className="incl">
                        <div className="muted" style={{ marginBottom: 6 }}>
                          Includes <span className="count">{codes.length}</span> {codes.length === 1 ? "check" : "checks"}
                        </div>
                        {codes.slice(0, 4).map((c) => <li key={c}>• {titleOf(c)}</li>)}
                        {codes.length > 4 && <li className="muted">+ {codes.length - 4} more</li>}
                      </ul>
                    </button>
                  );
                })}
              </div>
            )}

            {!loading && !error && mode === "custom" && (
              <div>
                {Object.keys(DESKS).filter((d) => byDesk[d]?.length).map((d) => (
                  <div className="desk" key={d}>
                    <h3>{DESKS[d]}</h3>
                    {(byDesk[d] ?? []).map((s) => {
                      const on = custom.includes(s.code);
                      return (
                        <label key={s.code} className={`svc${on ? " on" : ""}`}>
                          <input type="checkbox" checked={on} onChange={() => toggle(s.code)} />
                          <span>{s.title}</span>
                        </label>
                      );
                    })}
                  </div>
                ))}
              </div>
            )}
          </section>

          <aside className="section">
            <h2>Your selection</h2>
            <div className="rail">
              {selectedCodes.length === 0 ? (
                <p className="muted" style={{ margin: 0 }}>
                  Pick a bundle or choose individual checks. You’ll see the documents that help, and we’ll
                  prepare your quote next.
                </p>
              ) : (
                <>
                  <div style={{ fontWeight: 800, marginBottom: 10 }}>
                    <span className="count">{selectedCodes.length}</span>{" "}
                    {selectedCodes.length === 1 ? "check selected" : "checks selected"}
                  </div>
                  <div className="note">
                    No price yet — and that’s deliberate. Government fees depend on the exact location and
                    property, so we prepare an <strong>itemised quote</strong> for your property, with the
                    official fees passed through at cost.
                  </div>

                  <div style={{ margin: "16px 0 8px", fontWeight: 700, fontSize: 14 }}>
                    Documents that help{" "}
                    <span className="muted" style={{ fontWeight: 400 }}>· bring what you have</span>
                  </div>
                  {checklist.length === 0 ? (
                    <p className="muted" style={{ fontSize: 13.5, margin: 0 }}>
                      You can proceed with no documents at all. We’ll tell you if anything specific would help.
                    </p>
                  ) : (
                    <ul className="chk" style={{ listStyle: "none", padding: 0, margin: 0 }}>
                      {checklist.map((c, i) => (
                        <li key={i}>
                          <span className={`tier ${c.tier}`}>{c.tier}</span>
                          <span>{c.document_label}</span>
                        </li>
                      ))}
                    </ul>
                  )}
                  <p className="muted" style={{ fontSize: 13, margin: "12px 0 16px" }}>
                    Don’t have these? You can still proceed — the more you share, the more thorough we can be.
                  </p>
                  <button className="btn primary" onClick={continueToOrder}>{authed ? "Continue" : "Continue — create your account"}</button>
                </>
              )}
            </div>
          </aside>
        </div>
      </main>

      <footer className="foot">
        <div className="wrap">
          Every finished report is sealed and timestamped against public infrastructure, so anyone can verify
          it independently — even without Ilevest.
        </div>
      </footer>
    </>
  );
}
