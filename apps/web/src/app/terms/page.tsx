// /terms — the Terms of Service. Content is the lawyer-approved interim text,
// transcribed verbatim (legal substance unchanged); only laid out on the design
// system. No internal scaffolding appears here. The liability and "what this is
// / is not" sections are the load-bearing clauses. Global header + footer from
// the layout.

export const metadata = {
  title: "Terms of Service — Ilevest",
  description:
    "The terms governing your use of Ilevest's independent property verification services — what our verification is and is not, fees, verdicts, your responsibilities, and the limitation of liability.",
};

const sections = [
  {
    h: "1. What Ilevest is — and is not",
    body: [
      "Ilevest provides independent, evidence-backed due-diligence checks on land and property, performed by vetted professionals, and delivers a clear verdict with the evidence behind it, sealed so that anyone can verify it. Our verification is professional due diligence — a careful, honest assessment of the records and facts we are able to examine. It is NOT a legal guarantee of title, a warranty that a property is safe to buy, an insurance policy, or legal advice. A verification informs your decision; it does not make the decision for you, and it cannot certify facts that are not discoverable through the checks you selected.",
    ],
  },
  {
    h: "2. Our fees and payment",
    body: [
      "Because government and official fees vary by location and property, we do not display fixed prices. When you select checks, we prepare an itemised invoice showing our service fee and any government fees separately. Government fees are passed on at cost, with no mark-up, and we capture the official receipt for each. Our service fee attracts VAT as required by law; the VAT treatment of each line is shown on the invoice. Our service fee is non-refundable once verification work has begun. Any government fee we have collected but not yet paid out is refundable; once paid to a government account it cannot be refunded.",
    ],
  },
  {
    h: "3. Verdicts and what they mean",
    body: [
      "Each check receives a plain-English verdict: Cleared, Proceed with care, Serious problem found, or Unresolved. A single serious problem headlines your whole order. \u201CUnresolved\u201D means we genuinely attempted a check but could not obtain a definitive answer, and we say so honestly rather than guess. You should read every finding in full before making any decision. A \u201CCleared\u201D result means our checks did not surface a problem within their scope — it is not a promise that no problem could ever exist.",
    ],
  },
  {
    h: "4. Your responsibilities",
    list: [
      "You are responsible for the accuracy of the information you give us (property details, seller name, documents).",
      "You make your own final decision about any property transaction. We strongly recommend you also take independent legal advice before completing a purchase.",
      "You must not misuse the service, attempt to access data that is not yours, or use Ilevest for any unlawful purpose.",
    ],
  },
  {
    h: "5. Limitation of liability",
    body: [
      "We perform our checks with professional care. To the fullest extent permitted by Nigerian law, Ilevest\u2019s liability arising from a verification is limited to the service fee paid for, and we are not liable for indirect or consequential losses, for facts genuinely undiscoverable through the selected checks, or for decisions you make. Nothing in these terms excludes liability that cannot lawfully be excluded.",
    ],
  },
  {
    h: "6. Account deletion and suspension",
    body: [
      "You may delete your account at any time, provided you do not owe us money and have no verification currently in progress that you have paid for. On deletion we anonymise your personal data as described in the Privacy Policy; sealed anonymous verification records remain and stay independently verifiable. We may suspend accounts that misuse the service or breach these terms.",
    ],
  },
  {
    h: "7. Governing law and disputes",
    body: [
      "These terms are governed by the laws of the Federal Republic of Nigeria.",
    ],
  },
  {
    h: "8. Changes to these terms",
    body: [
      "We may update these terms; continued use after changes means you accept them. Last updated 30 June 2026.",
    ],
  },
];

export default function Terms() {
  return (
    <main className="wrap legal">
      <section className="hero">
        <div className="eyebrow">Terms of Service</div>
        <h1>The terms of using Ilevest.</h1>
        <p className="lede">
          These terms govern your use of Ilevest&rsquo;s services. By using ilevest.com, you agree
          to them. Please read the sections on the nature of our service and on liability carefully.
        </p>
        <p className="muted" style={{ fontSize: 13, marginTop: 8 }}>Last updated 30 June 2026.</p>
      </section>

      <section className="section legal-body">
        {sections.map((s) => (
          <div key={s.h} className="legal-section">
            <h2>{s.h}</h2>
            {s.body && s.body.map((p, i) => <p key={i}>{p}</p>)}
            {s.list && (
              <ul>
                {s.list.map((li, i) => <li key={i}>{li}</li>)}
              </ul>
            )}
          </div>
        ))}
        <p className="muted" style={{ fontSize: 13.5, marginTop: 24 }}>
          Questions? Contact us at <a href="mailto:support@ilevest.com">support@ilevest.com</a>. See
          also our <a href="/privacy">Privacy Policy</a>.
        </p>
      </section>
    </main>
  );
}
