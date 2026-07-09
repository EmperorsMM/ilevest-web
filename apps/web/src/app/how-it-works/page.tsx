// /how-it-works — the page a nervous first-time buyer reaches for right after
// the landing. Its whole job is to demystify: show the journey step by step, in
// plain language, so pressing "Start a verification" stops feeling like a leap.
// Built on the shared design system; the global header + footer come from the
// layout. Copy is grounded in what Ilevest actually does (real verdicts, real
// desks, real flow) — no invented process.

export const metadata = {
  title: "How It Works — Ilevest",
  description:
    "How Ilevest verifies a Nigerian property before you buy: choose your checks, we verify against the registries, survey records and courts, then seal a plain-English verdict anyone can independently confirm.",
};

const steps = [
  {
    n: "1",
    title: "Tell us about the property",
    body:
      "Start a verification and describe the property — the state, the LGA or Area Council, and the address. Choose a ready-made pack or build your own set of checks. If you have documents from the seller (a title, a survey plan, a receipt), you can upload them — but you never have to. Missing paperwork is exactly the kind of gap we are here to close, so nothing stops you from ordering.",
  },
  {
    n: "2",
    title: "We prepare an itemised quote",
    body:
      "There are no fixed prices, because every property is different. Our team reviews what you have asked for and sends back an itemised invoice — the Ilevest service fee, plus any government fees at cost, with nothing marked up. You see exactly what you are paying for before you pay a naira. You pay securely by card through Paystack.",
  },
  {
    n: "3",
    title: "We do the verification",
    body:
      "Once you have paid, the work begins across our desks — the Lands Registry, the Surveyor-General, the Courts and Probate registries, checks on the people and entities involved, and, where needed, a physical inspection of the site. Every finding is captured as evidence and fingerprinted, so the result rests on what we actually saw, not on anyone's word.",
  },
  {
    n: "4",
    title: "A reviewer seals a plain-English verdict",
    body:
      "A senior reviewer reads all the evidence and issues one clear verdict in language you do not need a lawyer to understand. The result is then sealed with tamper-evident cryptographic proof and anchored daily to public infrastructure — so once it is issued, it cannot be quietly changed.",
  },
  {
    n: "5",
    title: "You get your result — and anyone can verify it",
    body:
      "You receive your verdict and the findings behind each check. Every sealed result also gets a public certificate you can share with a bank, a lawyer, or your family — and they can confirm it is genuine themselves, with no personal information of yours exposed. Trust that does not depend on trusting us.",
  },
];

export default function HowItWorks() {
  return (
    <main className="wrap">
      <section className="hero">
        <div className="eyebrow">How it works · Lagos · Ogun · FCT</div>
        <h1>From &ldquo;I&rsquo;m not sure&rdquo; to a verdict you can trust.</h1>
        <p className="lede">
          Buying land in Nigeria means trusting documents and people you have no easy way to
          check. Ilevest replaces that leap of faith with evidence. Here is exactly what happens
          from the moment you start a verification to the moment you — and anyone you choose —
          can confirm the result.
        </p>
      </section>

      <section className="section">
        <ol style={{ listStyle: "none", padding: 0, margin: 0, display: "grid", gap: 20 }}>
          {steps.map((s) => (
            <li key={s.n} className="card" style={{ cursor: "default", display: "grid",
                  gridTemplateColumns: "auto 1fr", gap: 20, alignItems: "start" }}>
              <div aria-hidden="true" style={{ fontFamily: "var(--serif)", fontSize: 34,
                    fontWeight: 600, lineHeight: 1, color: "var(--green)", minWidth: 40 }}>
                {s.n}
              </div>
              <div>
                <div className="name" style={{ fontSize: 19, marginBottom: 6 }}>{s.title}</div>
                <div className="who" style={{ fontSize: 15.5, lineHeight: 1.6 }}>{s.body}</div>
              </div>
            </li>
          ))}
        </ol>
      </section>

      <section className="section">
        <h2>What the verdict means</h2>
        <p className="muted" style={{ maxWidth: "60ch", marginTop: 4 }}>
          Every verification ends in one of four plain-English verdicts. There is no jargon, and
          nothing is hidden — if there is a problem, we say so directly.
        </p>
        <div style={{ display: "grid", gap: 12, marginTop: 20 }}>
          <div className="verdict g" style={{ display: "block", padding: "14px 16px" }}>
            <span className="dot g" /> <b>Cleared</b> — we found no problems. Based on the checks
            you ordered, this is clear to proceed.
          </div>
          <div className="verdict a" style={{ display: "block", padding: "14px 16px" }}>
            <span className="dot a" /> <b>Proceed with care</b> — we found things you should weigh
            before proceeding. Read each check carefully.
          </div>
          <div className="verdict r" style={{ display: "block", padding: "14px 16px" }}>
            <span className="dot r" /> <b>Serious problem found</b> — do not proceed without
            resolving it. A single red issue is enough to stop a purchase.
          </div>
          <div className="verdict u" style={{ display: "block", padding: "14px 16px" }}>
            <span className="dot u" /> <b>Unresolved</b> — we could not fully resolve one or more
            checks. Treat this with caution and read the details.
          </div>
        </div>
      </section>

      <section className="section">
        <h2>Why this is different</h2>
        <div className="grid">
          <div className="card" style={{ cursor: "default" }}>
            <div className="name">Evidence, not opinion</div>
            <div className="who">
              Every finding is captured and fingerprinted. You see what we saw — there are no
              trust-me verdicts.
            </div>
          </div>
          <div className="card" style={{ cursor: "default" }}>
            <div className="name">Sealed and tamper-evident</div>
            <div className="who">
              Results are cryptographically sealed and anchored daily to public infrastructure, so
              a verdict cannot be altered after the fact.
            </div>
          </div>
          <div className="card" style={{ cursor: "default" }}>
            <div className="name">Independently verifiable</div>
            <div className="who">
              Anyone you share the certificate with can confirm it is genuine themselves — with
              none of your personal information exposed.
            </div>
          </div>
          <div className="card" style={{ cursor: "default" }}>
            <div className="name">No markup on government fees</div>
            <div className="who">
              You pay our service fee plus any government fees at cost. What the registry charges is
              what you pay — nothing added.
            </div>
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
              It starts with a few details. We prepare an itemised quote for your specific property —
              no obligation.
            </div>
          </div>
          <a className="btn primary" href="/start" style={{ width: "auto" }}>Start a verification</a>
        </div>
      </section>
    </main>
  );
}
