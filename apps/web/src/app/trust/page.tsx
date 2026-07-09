// /trust — the differentiator page. Every competitor says "trust me, I checked."
// This page explains why an Ilevest result can be believed WITHOUT trusting
// Ilevest: evidence you can see, a result sealed so it cannot be quietly changed,
// and a public certificate anyone can confirm — with none of your personal
// information exposed. Grounded in the real three-layer proof mechanism.
//
// CISO steer honoured: institutional and credible, NOT crypto-flashy. The
// audience is a nervous buyer, a bank, a lawyer — the mechanism is explained in
// terms of what it GUARANTEES, not in terms of the cryptography for its own sake.

export const metadata = {
  title: "Trust & Verification — Ilevest",
  description:
    "Why an Ilevest verdict can be trusted without trusting Ilevest: every finding is evidence-backed, each result is sealed so it cannot be altered after the fact, and every certificate can be independently confirmed — with no personal information exposed.",
};

const pillars = [
  {
    title: "You see the evidence",
    body:
      "A verdict is only as good as what sits behind it. Every check we run is backed by the actual documents and records we retrieved — certified copies, search results, inspection findings. You do not get a bare yes or no; you get the reasoning and the proof. There are no trust-me verdicts here.",
  },
  {
    title: "The result is sealed",
    body:
      "The moment a reviewer issues a verdict, the full report and its evidence are fingerprinted and sealed. That seal is linked in an unbroken chain to every seal before it, so a result cannot be edited, back-dated, or quietly swapped afterwards without the tampering being obvious. Once we say it, it is fixed.",
  },
  {
    title: "Anyone can confirm it",
    body:
      "Every sealed result gets a public certificate at a web address you can share with a bank, a lawyer, or your family. They do not have to take your word, or ours — they can confirm the certificate is genuine themselves. And it carries no personal information: no buyer, no seller, no private details. Verifiable, without being exposed.",
  },
];

const steps = [
  {
    n: "1",
    label: "Fingerprinted",
    text: "When a check is finalized, its report and evidence are reduced to a unique fingerprint. Change a single detail and the fingerprint changes completely — so the fingerprint is proof of exactly what was sealed.",
  },
  {
    n: "2",
    label: "Chained",
    text: "Each fingerprint is added to an append-only chain, each entry locked to the one before it. Nothing can be inserted, removed, or reordered without breaking the chain — the record's integrity protects itself.",
  },
  {
    n: "3",
    label: "Anchored",
    text: "Once a day, the day's sealed results are anchored to public, independent infrastructure. From that point the result is provably no younger than its anchor and provably unchanged since — a timestamp no one, including us, can forge or move.",
  },
];

export default function Trust() {
  return (
    <main className="wrap">
      <section className="hero">
        <div className="eyebrow">Trust &amp; verification</div>
        <h1>Trust the verdict without having to trust us.</h1>
        <p className="lede">
          Anyone can say they checked a property. The hard part is proving it — and proving the
          answer has not been changed since. Ilevest is built so that the result stands on
          evidence you can see, is sealed so it cannot be altered, and can be confirmed by anyone
          you choose, with none of your personal information exposed.
        </p>
      </section>

      <section className="section">
        <div className="grid">
          {pillars.map((p) => (
            <div key={p.title} className="card" style={{ cursor: "default" }}>
              <div className="name" style={{ fontSize: 18 }}>{p.title}</div>
              <div className="who" style={{ marginTop: 6, lineHeight: 1.6 }}>{p.body}</div>
            </div>
          ))}
        </div>
      </section>

      <section className="section">
        <h2>How a result is sealed</h2>
        <p className="muted" style={{ maxWidth: "62ch", marginTop: 4 }}>
          Three quiet steps turn a finished verification into a record that cannot be tampered with.
          You never have to think about them — but they are why the certificate means something.
        </p>
        <ol style={{ listStyle: "none", padding: 0, margin: "20px 0 0", display: "grid", gap: 16 }}>
          {steps.map((s) => (
            <li key={s.n} className="card" style={{ cursor: "default", display: "grid",
                  gridTemplateColumns: "auto 1fr", gap: 20, alignItems: "start" }}>
              <div aria-hidden="true" style={{ fontFamily: "var(--serif)", fontSize: 30,
                    fontWeight: 600, lineHeight: 1, color: "var(--green)", minWidth: 36 }}>
                {s.n}
              </div>
              <div>
                <div className="name" style={{ fontSize: 17, marginBottom: 6 }}>{s.label}</div>
                <div className="who" style={{ fontSize: 15, lineHeight: 1.6 }}>{s.text}</div>
              </div>
            </li>
          ))}
        </ol>
      </section>

      <section className="section">
        <div className="card" style={{ cursor: "default", background: "var(--surface)" }}>
          <div className="name" style={{ fontSize: 17 }}>What a certificate shows — and what it never shows</div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 24, marginTop: 12 }}>
            <div>
              <div className="muted" style={{ fontSize: 12.5, fontWeight: 700, textTransform: "uppercase",
                    letterSpacing: "0.06em", marginBottom: 8 }}>Shows</div>
              <ul style={{ margin: 0, paddingLeft: 0, listStyle: "none", display: "grid", gap: 7 }}>
                {["The verdict", "What was checked", "The property location", "The integrity record and its anchor status"].map((x) => (
                  <li key={x} style={{ fontSize: 14, display: "flex", gap: 8, alignItems: "baseline" }}>
                    <span className="dot g" style={{ flex: "0 0 auto" }} /><span>{x}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <div className="muted" style={{ fontSize: 12.5, fontWeight: 700, textTransform: "uppercase",
                    letterSpacing: "0.06em", marginBottom: 8 }}>Never shows</div>
              <ul style={{ margin: 0, paddingLeft: 0, listStyle: "none", display: "grid", gap: 7 }}>
                {["Who ordered the verification", "The seller's identity", "The exact address or your documents", "Any personal or private detail"].map((x) => (
                  <li key={x} style={{ fontSize: 14, display: "flex", gap: 8, alignItems: "baseline",
                        color: "var(--ink-soft)" }}>
                    <span aria-hidden="true" style={{ color: "var(--muted)", flex: "0 0 auto" }}>—</span><span>{x}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="card" style={{ cursor: "default" }}>
          <div className="name" style={{ fontSize: 17 }}>A note on honesty</div>
          <div className="who" style={{ marginTop: 6, maxWidth: "64ch", lineHeight: 1.6 }}>
            A verification is professional due diligence, not a guarantee, and we never pretend
            otherwise. If we cannot fully resolve a check, we say so plainly and mark it unresolved
            rather than guessing. And a single serious problem is enough for us to tell you to stop —
            we would rather lose a sale than let you walk into one.
          </div>
        </div>
      </section>

      <section className="section" style={{ paddingBottom: 80 }}>
        <div className="rail" style={{ display: "flex", alignItems: "center",
              justifyContent: "space-between", flexWrap: "wrap", gap: 16 }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 19, letterSpacing: "-0.01em" }}>
              See it for yourself.
            </div>
            <div className="muted" style={{ fontSize: 14, marginTop: 4 }}>
              Start a verification, or confirm an existing certificate you have been given.
            </div>
          </div>
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
            <a className="btn primary" href="/start" style={{ width: "auto" }}>Start a verification</a>
            <a className="btn" href="/verify" style={{ width: "auto", border: "1px solid var(--line)",
                  color: "var(--ink)" }}>Verify a certificate</a>
          </div>
        </div>
      </section>
    </main>
  );
}
