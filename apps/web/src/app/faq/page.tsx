// /faq — answers the real questions and fears in a nervous buyer's head before
// they order, in plain honest language. Every answer is TRUE and promises only
// what we deliver. The turnaround answer's figures come directly from the locked
// Service Catalogue's Typical SLAs, framed with the catalogue's own qualifiers.
// CRITICAL: no answer presents NIN/BVN identity verification as a current service
// (it is deferred pending legal clearance).

export const metadata = {
  title: "Frequently Asked Questions — Ilevest",
  description:
    "Honest answers to the real questions about verifying a Nigerian property with Ilevest — what happens if we find a problem, what it costs, how long it takes, and how you can independently verify the result.",
};

const faqs = [
  {
    q: "How do I know this is real, and not just another person telling me to \u201Ctrust them\u201D?",
    a: "Because we don\u2019t ask you to trust us. Every verdict is backed by the actual records and documents we retrieved, and every sealed result comes with a public certificate that anyone \u2014 a bank, a lawyer, your family \u2014 can independently confirm is genuine. You see the evidence, and the proof stands on its own.",
  },
  {
    q: "What happens if you find a problem with the property?",
    a: "We tell you plainly. Every check ends in a clear verdict \u2014 Cleared, Proceed with care, Serious problem found, or Unresolved \u2014 in plain English, with the findings behind it. A single serious problem headlines your whole result, because one serious issue is enough to stop a purchase. You make your decision with the full picture in front of you.",
  },
  {
    q: "What does it cost?",
    a: "There are no fixed prices, because government fees vary by location and property. When you choose your checks, we prepare an itemised quote \u2014 our service fee, plus any government fees at cost with no markup. You are not charged anything until you\u2019ve seen exactly what your verification covers and what it costs.",
  },
  {
    q: "How long does a verification take?",
    a: "It depends on the checks you select and how quickly the relevant registries, courts, and offices respond. As a guide: core registry and court searches \u2014 like title, ownership, and litigation searches, and corporate checks \u2014 typically take 3\u20137 working days; more involved checks like document and survey-plan authentication, charting, and probate verification typically take 5\u201310 working days; and physical site inspections or certified-copy retrievals can take longer \u2014 often 7\u201315 working days, depending on site access and how quickly the office issues records. Most common pre-purchase checks fall within about 3 to 10 working days. These are typical timeframes, not guarantees \u2014 some records simply take longer by their nature \u2014 and we keep you updated at every step, so you can see your verification\u2019s progress at any time.",
  },
  {
    q: "Can I really verify the result myself?",
    a: "Yes. Every sealed result has a public certificate at a web address you can share. Anyone you give it to can confirm it\u2019s genuine and unaltered \u2014 and it carries no personal information about you or the seller.",
  },
  {
    q: "Do you handle the government fees for me?",
    a: "Yes. Where a check involves an official government fee, we collect it at cost, pay it, and capture the official receipt \u2014 with nothing marked up. Our own service fee is separate and clearly itemised.",
  },
  {
    q: "What if I don\u2019t have any documents from the seller?",
    a: "You can proceed with none. Missing or questionable paperwork is exactly the kind of gap our verification is designed to close. If you do have documents, uploading them helps \u2014 but it\u2019s never required.",
  },
  {
    q: "Which areas do you cover?",
    a: "We currently serve Lagos, Ogun, and the Federal Capital Territory (Abuja), and we\u2019re expanding.",
  },
  {
    q: "Is my personal information safe?",
    a: "Yes. We collect only what we need to provide your verification, and we protect it. Importantly, the public certificate that proves your result contains no personal information at all \u2014 not your name, not the seller\u2019s, not your documents. (See our Privacy Policy for the full detail.)",
  },
  {
    q: "What if you can\u2019t get a definitive answer on something?",
    a: "We tell you honestly. If we genuinely attempt a check but cannot obtain a conclusive answer, we mark it \u201CUnresolved\u201D and say so plainly, rather than guess or pretend. Honesty about what we could and couldn\u2019t determine is part of how we work.",
  },
];

export default function FAQ() {
  return (
    <main className="wrap">
      <section className="hero">
        <div className="eyebrow">Frequently asked questions</div>
        <h1>The questions a careful buyer asks first.</h1>
        <p className="lede">
          Plain, honest answers about how verification works, what it costs, and what happens when
          we find something. If your question isn&rsquo;t here, get in touch.
        </p>
      </section>

      <section className="section" style={{ paddingBottom: 80 }}>
        <div style={{ display: "grid", gap: 14 }}>
          {faqs.map((f, i) => (
            <div key={i} className="card" style={{ cursor: "default" }}>
              <div className="name" style={{ fontSize: 17, marginBottom: 8 }}>{f.q}</div>
              <div className="who" style={{ lineHeight: 1.65, fontSize: 15 }}>{f.a}</div>
            </div>
          ))}
        </div>

        <div className="rail" style={{ display: "flex", alignItems: "center",
              justifyContent: "space-between", flexWrap: "wrap", gap: 16, marginTop: 28 }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 19, letterSpacing: "-0.01em" }}>
              Still have a question?
            </div>
            <div className="muted" style={{ fontSize: 14, marginTop: 4 }}>
              Start a verification and we&rsquo;ll quote your exact property — or reach out first.
            </div>
          </div>
          <a className="btn primary" href="/start" style={{ width: "auto" }}>Start a verification</a>
        </div>
      </section>
    </main>
  );
}
