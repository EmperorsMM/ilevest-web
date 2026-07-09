"use client";

// Order-creation step. Arrives carrying the selection (saved on /start). Shows
// what the buyer is about to verify, collects whatever property location they
// have via a state -> LGA/Area Council cascade (controlled values, not free
// text), and creates the order via create_order(), then lands them on their
// dashboard where it shows as "awaiting your quote". No payment here.
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "../../lib/supabase/client";
import { STATES, stateCode, subdivisionLabel, subdivisionsFor, districtsFor, usesDistricts } from "../../lib/locations";

type Selection = { mode: "bundles" | "custom"; bundle: string | null; custom: string[]; codes: string[] };
type Service = { code: string; title: string };

const BUNDLE_LABEL: Record<string, string> = {
  essential: "Essential Check",
  complete: "Complete Due Diligence",
  inheritance: "Inheritance & Family Land",
  diaspora: "Diaspora Package",
};

export default function NewOrderPage() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const router = useRouter();

  const [ready, setReady] = useState(false);
  const [sel, setSel] = useState<Selection | null>(null);
  const [titles, setTitles] = useState<Record<string, string>>({});

  const [stateName, setStateName] = useState("");
  const [subdivision, setSubdivision] = useState("");
  const [district, setDistrict] = useState("");
  const [locality, setLocality] = useState("");
  const [details, setDetails] = useState("");
  const [seller, setSeller] = useState("");

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const showDistrict = !!stateName && usesDistricts(stateName, subdivision);

  // Guard: must be signed in and must have a selection to act on.
  useEffect(() => {
    let active = true;
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!active) return;
      if (!user) { router.replace("/signup?next=/new"); return; }

      let parsed: Selection | null = null;
      try { parsed = JSON.parse(localStorage.getItem("ilevest.selection") || "null"); } catch { /* ignore */ }
      if (!parsed || !parsed.codes || parsed.codes.length === 0) { router.replace("/start"); return; }
      setSel(parsed);

      const { data } = await supabase.from("service_catalogue").select("code,title");
      if (!active) return;
      const map: Record<string, string> = {};
      for (const r of (data ?? []) as Service[]) map[r.code] = r.title;
      setTitles(map);
      setReady(true);
    })();
    return () => { active = false; };
  }, [supabase, router]);

  async function createOrder() {
    if (!sel) return;
    if (!stateName) {
      setError("Please choose the state \u2014 it's how we route your checks. Everything else is optional.");
      return;
    }
    setSubmitting(true);
    setError(null);

    const isCustom = sel.mode === "custom" || !sel.bundle;
    const args = {
      p_bundle: isCustom ? "ala_carte" : sel.bundle,
      p_services: isCustom ? sel.codes : null,
      p_state: stateName || null,
      p_lga: subdivision || null,
      p_locality: (showDistrict ? district : locality) || null,
      p_details: details || null,
      p_state_code: stateCode(stateName),
      p_seller: seller || null,
    };

    const { error } = await supabase.rpc("create_order", args);
    if (error) {
      setError("We couldn't create your verification just now. Please try again.");
      setSubmitting(false);
      return;
    }
    try { localStorage.removeItem("ilevest.selection"); } catch { /* ignore */ }
    router.push("/client");
  }

  const heading = sel
    ? sel.mode === "custom" || !sel.bundle
      ? "Custom selection"
      : BUNDLE_LABEL[sel.bundle] ?? "Your verification"
    : "";

  return (
    <>

      <main className="wrap new-wrap">
        {!ready ? (
          <p className="dash-reassure" style={{ textAlign: "center", marginTop: 48 }}>Loading&hellip;</p>
        ) : (
          <div className="new-grid">
            <section>
              <p className="dash-kicker">Tell us about the property</p>
              <h1 className="new-h1">Start with what you know.</h1>
              <p className="new-lead">
                You don&rsquo;t need every detail to begin &mdash; give us what you have and we&rsquo;ll flag anything
                missing. You won&rsquo;t pay anything until we&rsquo;ve sent you an itemised quote.
              </p>

              {error && <div className="auth-err">{error}</div>}

              <div className="field">
                <label htmlFor="state">State</label>
                <select id="state" value={stateName}
                  onChange={(e) => { setStateName(e.target.value); setSubdivision(""); setDistrict(""); }}>
                  <option value="">Select a state</option>
                  {STATES.map((s) => <option key={s.code} value={s.name}>{s.name}</option>)}
                </select>
              </div>

              {stateName && (
                <div className="field">
                  <label htmlFor="sub">
                    {subdivisionLabel(stateName)} <span className="opt">(recommended)</span>
                  </label>
                  <select id="sub" value={subdivision}
                    onChange={(e) => { setSubdivision(e.target.value); setDistrict(""); }}>
                    <option value="">Select {subdivisionLabel(stateName).toLowerCase()}</option>
                    {subdivisionsFor(stateName).map((s) => <option key={s} value={s}>{s}</option>)}
                  </select>
                </div>
              )}

              {showDistrict && (
                <div className="field">
                  <label htmlFor="district">District <span className="opt">(optional)</span></label>
                  <input id="district" list="amac-districts" value={district}
                    onChange={(e) => setDistrict(e.target.value)} placeholder="e.g. Maitama, Asokoro" />
                  <datalist id="amac-districts">
                    {districtsFor(stateName).map((d) => <option key={d} value={d} />)}
                  </datalist>
                  <p className="field-hint">In Abuja, property is usually known by its district &mdash; pick one or type another.</p>
                </div>
              )}

              {stateName && !showDistrict && (
                <div className="field">
                  <label htmlFor="locality">Area / neighbourhood <span className="opt">(optional)</span></label>
                  <input id="locality" type="text" value={locality}
                    onChange={(e) => setLocality(e.target.value)} placeholder="e.g. Ikoyi, Lekki Phase 1" />
                </div>
              )}

              <div className="field">
                <label htmlFor="details">Anything that helps us find it <span className="opt">(optional)</span></label>
                <textarea id="details" value={details} onChange={(e) => setDetails(e.target.value)} rows={3}
                  placeholder="Street, plot number, landmark, survey plan number, or how the seller described it" />
              </div>

              <div className="field">
                <label htmlFor="seller">Seller&rsquo;s name <span className="opt">(optional)</span></label>
                <input id="seller" type="text" value={seller} onChange={(e) => setSeller(e.target.value)}
                  placeholder="Person or company selling the property" />
                <p className="field-hint">If you know the name of the person or company selling, it helps us check who you&rsquo;re dealing with. Leave it blank if you&rsquo;re not sure yet.</p>
              </div>

              <button className="btn primary lg" onClick={createOrder} disabled={submitting} style={{ marginTop: 8 }}>
                {submitting ? "Creating\u2026" : "Create my verification"}
              </button>
            </section>

            <aside className="new-summary">
              <p className="dash-kicker">You&rsquo;re verifying</p>
              <h2 className="new-summary-h">{heading}</h2>
              <ul className="new-checks">
                {sel?.codes.map((c) => <li key={c}>{titles[c] ?? c}</li>)}
              </ul>
              <p className="new-summary-note">
                {sel?.codes.length} {sel && sel.codes.length === 1 ? "check" : "checks"} &middot; we&rsquo;ll itemise the
                cost &mdash; including any government fees &mdash; in your quote.
              </p>
            </aside>
          </div>
        )}
      </main>
    </>
  );
}
