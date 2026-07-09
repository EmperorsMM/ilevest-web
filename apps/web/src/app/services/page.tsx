// /services — the verification packs and what each check protects a buyer from,
// in plain language. No prices (every quote is per-request). Grounded in the real
// service catalogue and the real bundle compositions from the database, so what a
// visitor reads here is exactly what they will get. Global header + footer come
// from the layout.

export const metadata = {
  title: "Services — What We Check — Ilevest",
  description:
    "Ilevest verification packs — Essential, Complete Due Diligence, Inheritance, Diaspora, or build your own. Each check explained in plain language: what it is and what it protects you from. No fixed prices; every quote is per-request.",
};

// The four real bundles with their real check lists, described by what they protect against.
const bundles = [
  {
    key: "essential",
    name: "Essential Check",
    who: "The two checks no purchase should skip.",
    for: "A first, fast sanity check before you go further on any property.",
    checks: [
      "Title & Ownership Search",
      "Charting / Land Status Report",
    ],
  },
  {
    key: "complete",
    name: "Complete Due Diligence",
    who: "Our most thorough pre-purchase review.",
    for: "When you are serious about a property and want the fullest picture before committing money.",
    checks: [
      "Title & Ownership Search",
      "Document Authenticity Check",
      "Encumbrance Search",
      "Acquisition / Excision / Gazette Status",
      "Survey Plan Authentication",
      "Charting / Land Status Report",
      "Litigation / Pending Suit Search",
    ],
  },
  {
    key: "inheritance",
    name: "Inheritance Property",
    who: "When the property is sold by heirs or an estate.",
    for: "Family land and estate sales, where the right to sell is the thing most likely to be in doubt.",
    checks: [
      "Title & Ownership Search",
      "Probate / Letters of Administration Verification",
      "Litigation / Pending Suit Search",
    ],
  },
  {
    key: "diaspora",
    name: "Diaspora Pack",
    who: "Buying from abroad — we become your eyes on the ground.",
    for: "Buyers overseas who cannot visit the registries or the site themselves. The broadest pack, including a physical inspection.",
    checks: [
      "Title & Ownership Search",
      "Document Authenticity Check",
      "Encumbrance Search",
      "Acquisition / Excision / Gazette Status",
      "Survey Plan Authentication",
      "Charting / Land Status Report",
      "Litigation / Pending Suit Search",
      "Identity Verification (NIN/BVN consistency)",
      "Physical Site Inspection",
    ],
  },
];

// The desks, and what each family of checks protects the buyer from.
const desks = [
  {
    name: "Lands Registry",
    protects: "Confirms who really owns the land, whether the title is genuine, and whether it is already mortgaged, pledged, or sitting under a government acquisition.",
    checks: [
      "Title & Ownership Search — is the seller actually the registered owner?",
      "Document Authenticity Check — is the C of O or title document real, not forged?",
      "Encumbrance Search — is the land already used as security for a loan?",
      "Consent & Stamping Status — were prior transfers properly consented and stamped?",
      "Acquisition / Excision / Gazette Status — is the land under government acquisition?",
      "Deed Registration Tracking — where does a pending registration actually stand?",
      "CTC Retrieval — certified true copies of the registry instruments.",
    ],
  },
  {
    name: "Surveyor-General",
    protects: "Confirms the survey plan is real and that the land on paper is the land on the ground — the right size, the right place, not overlapping someone else's.",
    checks: [
      "Survey Plan Authentication — is the survey plan genuine and registered?",
      "Charting / Land Status Report — what is the official status of this parcel?",
      "Coordinate & Overlap Check — does it overlap another registered survey?",
      "Plan-to-Ground Match — does the plan match the actual physical site?",
    ],
  },
  {
    name: "Courts & Probate",
    protects: "Confirms the property is not caught in a lawsuit, a judgment, or a disputed inheritance that could take it away from you after you buy.",
    checks: [
      "Probate / Letters of Administration — do the heirs actually have the right to sell?",
      "Litigation / Pending Suit Search — is the property subject to a live court case?",
      "Judgment Search — is there a judgment attached to the property or owner?",
      "CTC Retrieval — certified true copies of court records.",
    ],
  },
  {
    name: "Persons & Entities",
    protects: "Confirms the people and companies you are dealing with are who they claim to be.",
    checks: [
      "Corporate Seller Check — is the selling company real and in good standing?",
      "Identity Verification (NIN/BVN consistency) — do the seller's identities line up?",
      "Professional Licence Verification — is the agent or professional licensed?",
    ],
  },
  {
    name: "Field Services",
    protects: "Puts a person on the actual site — indispensable when you cannot go yourself.",
    checks: [
      "Physical Site Inspection — is the land really there, and does it match the papers?",
    ],
  },
];

export default function Services() {
  return (
    <main className="wrap">
      <section className="hero">
        <div className="eyebrow">Services · what we check</div>
        <h1>Every check exists to protect you from a specific way to lose money.</h1>
        <p className="lede">
          Choose a ready-made pack or build your own. Each check answers one question a buyer
          cannot easily answer alone — is the title real, is the land really there, is anyone
          allowed to sell it. There are no fixed prices: we prepare an itemised quote for your
          exact property, with government fees passed through at cost.
        </p>
      </section>

      <section className="section">
        <h2>Verification packs</h2>
        <p className="muted" style={{ maxWidth: "60ch", marginTop: 4 }}>
          A pack is simply a sensible set of checks for a common situation. You can add to any pack
          or build a custom selection when you start.
        </p>
        <div className="grid" style={{ marginTop: 20 }}>
          {bundles.map((b) => (
            <div key={b.key} className="card" style={{ cursor: "default", display: "flex",
                  flexDirection: "column", gap: 10 }}>
              <div>
                <div className="name" style={{ fontSize: 19 }}>{b.name}</div>
                <div className="who" style={{ marginTop: 4 }}>{b.who}</div>
              </div>
              <div className="muted" style={{ fontSize: 13.5, lineHeight: 1.5 }}>{b.for}</div>
              <ul style={{ margin: "4px 0 0", paddingLeft: 0, listStyle: "none",
                    display: "grid", gap: 6 }}>
                {b.checks.map((c) => (
                  <li key={c} style={{ fontSize: 13.5, display: "flex", gap: 8, alignItems: "baseline" }}>
                    <span className="dot g" style={{ flex: "0 0 auto" }} />
                    <span>{c}</span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </section>

      <section className="section">
        <h2>What each desk checks</h2>
        <p className="muted" style={{ maxWidth: "62ch", marginTop: 4 }}>
          Behind the packs are five desks, each responsible for one kind of risk. This is the full
          range you can draw on when you build your own verification.
        </p>
        <div style={{ display: "grid", gap: 16, marginTop: 20 }}>
          {desks.map((d) => (
            <div key={d.name} className="card" style={{ cursor: "default" }}>
              <div className="name" style={{ fontSize: 18 }}>{d.name}</div>
              <div className="who" style={{ margin: "6px 0 12px" }}>{d.protects}</div>
              <ul style={{ margin: 0, paddingLeft: 0, listStyle: "none", display: "grid", gap: 7 }}>
                {d.checks.map((c) => (
                  <li key={c} style={{ fontSize: 14, lineHeight: 1.5, display: "flex", gap: 8,
                        alignItems: "baseline", color: "var(--ink-soft)" }}>
                    <span aria-hidden="true" style={{ color: "var(--green)", flex: "0 0 auto" }}>›</span>
                    <span>{c}</span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </section>

      <section className="section">
        <div className="card" style={{ cursor: "default", background: "var(--surface)" }}>
          <div className="name" style={{ fontSize: 17 }}>How pricing works</div>
          <div className="who" style={{ marginTop: 6, maxWidth: "64ch" }}>
            We do not publish fixed prices because the work varies by property, location, and which
            checks you choose. When you start a verification, our team reviews your request and sends
            an itemised invoice: the Ilevest service fee, plus any government fees at cost — never
            marked up. You approve it before you pay anything.
          </div>
        </div>
      </section>

      <section className="section" style={{ paddingBottom: 80 }}>
        <div className="rail" style={{ display: "flex", alignItems: "center",
              justifyContent: "space-between", flexWrap: "wrap", gap: 16 }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 19, letterSpacing: "-0.01em" }}>
              Not sure which checks you need?
            </div>
            <div className="muted" style={{ fontSize: 14, marginTop: 4 }}>
              Start with a pack — you can always add checks. We will quote your exact property before
              you commit.
            </div>
          </div>
          <a className="btn primary" href="/start" style={{ width: "auto" }}>Start a verification</a>
        </div>
      </section>
    </main>
  );
}
