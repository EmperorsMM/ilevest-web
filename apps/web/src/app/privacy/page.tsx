// /privacy — the Privacy Policy. Content is the lawyer-approved interim text,
// transcribed verbatim (legal substance unchanged); only laid out on the design
// system. No internal scaffolding ("Working Draft", "LAWYER REVIEW", the Part C
// rollout notes) appears here. Global header + footer from the layout.

export const metadata = {
  title: "Privacy Policy — Ilevest",
  description:
    "How Ilevest Nigeria Ltd collects, uses, protects, and retains your personal data under the Nigeria Data Protection Act (NDPA) 2023, and the rights you have over it.",
};

const sections = [
  {
    h: "1. Who we are (the data controller)",
    body: [
      "Ilevest Nigeria Ltd, RC 9622137, incorporated in Nigeria, is the data controller responsible for your personal data. You can contact us about your data at support@ilevest.com.",
    ],
  },
  {
    h: "2. What personal data we collect",
    body: [
      "We deliberately collect the minimum necessary to provide verification (data minimisation). Specifically:",
    ],
    list: [
      "Account data: your name and a contact (email and/or phone), and your login identity (including via Google sign-in, which gives us your basic Google profile for access only).",
      "Order data: the property you ask us to verify (state, LGA/area, address if you give it), the checks you select, and — if you choose to provide it — the seller\u2019s name.",
      "Documents you upload: any documents you choose to share to support a verification (you may proceed with none). These are yours; we store them privately and use them only for your verification.",
      "Payment data: we use Paystack to process payments. We do not store your full card details; Paystack handles card data under its own security standards. We keep a record that a payment was made, its amount, and its reference.",
      "Verification records: the evidence our professionals gather and the sealed outcome of your checks. Sealed records are permanent and cannot be altered (this is the tamper-evidence that makes our verification trustworthy).",
    ],
  },
  {
    h: "3. Why we process your data, and our lawful basis",
    body: ["We process your data on these lawful bases under the NDPA:"],
    list: [
      "Contractual necessity: to provide the verification you ordered and paid for — the core of our service.",
      "Consent: for anything beyond providing the service (e.g. optional communications), which you may withdraw at any time.",
      "Legitimate interest / legal obligation: to keep secure, tamper-evident records of verifications performed, to prevent fraud, and to meet our own legal and tax obligations.",
    ],
  },
  {
    h: "4. How we protect your data",
    body: [
      "We apply technical and organisational security measures, including: encrypted connections (TLS) for all data in transit; access controls enforced at the database level so users can only access their own data; private storage for uploaded documents with time-limited access links; strong authentication for staff accounts; and complete, tamper-evident audit logs of actions taken. Our public verification certificates are designed to contain no personal information whatsoever — they confirm an outcome and its cryptographic proof, and reveal nothing about who requested a check.",
    ],
  },
  {
    h: "5. How long we keep your data",
    body: [
      "We keep personal account and contact data for as long as you have an account and as required afterward by law. Sealed verification records and their cryptographic proofs are kept permanently and cannot be deleted — this permanence is what allows anyone to independently verify a result years later, which is the core of our service. However, these sealed records and their public proofs contain no personal information about who requested them. If you delete your account, we remove or anonymise your personal login and contact data while the anonymous, personally-unidentifiable sealed records remain.",
    ],
  },
  {
    h: "6. Who we share your data with",
    body: [
      "We share your data only as needed to provide the service: with the vetted professionals who perform your verification (limited to what their task requires); with Paystack to process your payment; and with the infrastructure providers who host our system securely. We do not sell your personal data to anyone, ever. We may disclose data if legally required to do so.",
    ],
    sub: {
      h: "Cross-border processing",
      body: "Our systems are hosted on infrastructure that may store data outside Nigeria. Where your data is transferred outside Nigeria, we take steps to ensure it receives adequate protection.",
    },
  },
  {
    h: "7. Your rights over your data",
    body: [
      "Under the NDPA you have the right to: access the personal data we hold about you; correct inaccurate data; request deletion of your personal data (subject to the retention of anonymous sealed records and any legal obligations); object to or restrict certain processing; withdraw consent; and lodge a complaint with the Nigeria Data Protection Commission (NDPC). To exercise any of these, contact us at support@ilevest.com.",
    ],
  },
  {
    h: "8. Changes to this policy",
    body: [
      "We may update this policy; we will post changes here and, where significant, notify you. This policy was last updated 30 June 2026.",
    ],
  },
];

export default function Privacy() {
  return (
    <main className="wrap legal">
      <section className="hero">
        <div className="eyebrow">Privacy Policy</div>
        <h1>Your data, and how we protect it.</h1>
        <p className="lede">
          Ilevest Nigeria Ltd (&ldquo;Ilevest&rdquo;, &ldquo;we&rdquo;, &ldquo;us&rdquo;) provides
          independent land and property verification services. This policy explains what personal
          data we collect, why, how we protect it, how long we keep it, and the rights you have over
          it under the Nigeria Data Protection Act (NDPA) 2023. It applies to everyone who uses
          ilevest.com.
        </p>
        <p className="muted" style={{ fontSize: 13, marginTop: 8 }}>Last updated 30 June 2026.</p>
      </section>

      <section className="section legal-body">
        {sections.map((s) => (
          <div key={s.h} className="legal-section">
            <h2>{s.h}</h2>
            {s.body.map((p, i) => <p key={i}>{p}</p>)}
            {s.list && (
              <ul>
                {s.list.map((li, i) => <li key={i}>{li}</li>)}
              </ul>
            )}
            {s.sub && (
              <>
                <h3>{s.sub.h}</h3>
                <p>{s.sub.body}</p>
              </>
            )}
          </div>
        ))}
        <p className="muted" style={{ fontSize: 13.5, marginTop: 24 }}>
          Questions about your data? Contact us at{" "}
          <a href="mailto:support@ilevest.com">support@ilevest.com</a>. See also our{" "}
          <a href="/terms">Terms of Service</a>.
        </p>
      </section>
    </main>
  );
}
