// /about — reassures a frightened first-time buyer that a real, registered,
// serious company stands behind Ilevest. Understated and true, not inflated: no
// invented team, dates, or history. Built on the design system; global header +
// footer from the layout.

export const metadata = {
  title: "About — Ilevest",
  description:
    "Ilevest is independent property verification for Nigeria, operated by Ilevest Nigeria Ltd (RC 9622137). We replace the leap of faith in a land deal with evidence you — and anyone you choose — can verify.",
};

const values = [
  { t: "Evidence, not opinion", b: "You see the records behind every finding, not a bare yes or no." },
  { t: "Honesty, even when the news is bad", b: "If we find a serious problem, we say so plainly. If we genuinely cannot resolve a check, we mark it unresolved rather than guess." },
  { t: "No markup on government fees", b: "You pay our service fee plus any government fees at cost, with the official receipt captured. We never mark up a government charge." },
  { t: "Your privacy protected", b: "The public certificate that proves your result carries no personal information — not yours, not the seller's." },
  { t: "Verify without trusting us", b: "Every sealed result can be independently confirmed by anyone you share it with." },
];

export default function About() {
  return (
    <main className="wrap">
      <section className="hero">
        <div className="eyebrow">About Ilevest</div>
        <h1>Built so you never have to take property on trust.</h1>
        <p className="lede">
          Ilevest is independent property verification for Nigeria. We replace the leap of faith in
          a land deal with evidence you — and anyone you choose — can verify.
        </p>
      </section>

      <section className="section">
        <h2>The problem we exist for</h2>
        <p style={{ maxWidth: "64ch", color: "var(--ink-soft)", lineHeight: 1.7 }}>
          Buying land in Nigeria means trusting documents and people you have no easy way to check.
          Fake titles, disputed ownership, land already sold twice, government-acquired land quietly
          resold — these cost buyers everything. The information exists, scattered across registries,
          survey offices and courts, but an ordinary buyer cannot easily reach it, or trust what
          they are shown.
        </p>
      </section>

      <section className="section">
        <h2>What we do</h2>
        <p style={{ maxWidth: "64ch", color: "var(--ink-soft)", lineHeight: 1.7 }}>
          We commission the checks a careful buyer would want but cannot easily make alone — against
          the Lands Registry, the Surveyor-General, the Courts and Probate registries, checks on the
          people and entities involved, and, where needed, a physical inspection of the site. Vetted
          professionals do the work. We deliver one clear, plain-English verdict, backed by the
          evidence, and sealed so it cannot be quietly changed.
        </p>
      </section>

      <section className="section">
        <h2>How we&rsquo;re different</h2>
        <div className="grid">
          {values.map((v) => (
            <div key={v.t} className="card" style={{ cursor: "default" }}>
              <div className="name" style={{ fontSize: 17 }}>{v.t}</div>
              <div className="who" style={{ marginTop: 6, lineHeight: 1.6 }}>{v.b}</div>
            </div>
          ))}
        </div>
      </section>

      <section className="section">
        <div className="card" style={{ cursor: "default", background: "var(--surface)" }}>
          <div className="name" style={{ fontSize: 17 }}>The company</div>
          <div className="who" style={{ marginTop: 6, maxWidth: "64ch", lineHeight: 1.6 }}>
            Ilevest is operated by Ilevest Nigeria Ltd, a company registered in Nigeria
            (RC 9622137). We currently serve Lagos, Ogun and the Federal Capital Territory (Abuja),
            and we are expanding.
          </div>
        </div>
      </section>

      <section className="section" style={{ paddingBottom: 80 }}>
        <div className="rail" style={{ display: "flex", alignItems: "center",
              justifyContent: "space-between", flexWrap: "wrap", gap: 16 }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 19, letterSpacing: "-0.01em" }}>
              Ready to check a property?
            </div>
            <div className="muted" style={{ fontSize: 14, marginTop: 4 }}>
              It starts with a few details, and we prepare an itemised quote — no obligation.
            </div>
          </div>
          <a className="btn primary" href="/start" style={{ width: "auto" }}>Start a verification</a>
        </div>
      </section>
    </main>
  );
}
