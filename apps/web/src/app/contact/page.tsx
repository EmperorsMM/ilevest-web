// /contact — the last public page. It carries ONLY channels the founder has
// confirmed are genuinely monitored, and states only response times we can
// actually meet. An unanswered enquiry from a frightened buyer damages the trust
// we sell, so nothing here is aspirational.
//
// Channels confirmed: support@ilevest.com (already published on /privacy and
// /terms), and 0817 507 0646 for both phone and WhatsApp, 9am-4pm Mon-Fri.
// Email response: within one working day.

export const metadata = {
  title: "Contact — Ilevest",
  description:
    "Talk to Ilevest. Email support@ilevest.com (we reply within one working day), or call/WhatsApp 0817 507 0646, Monday to Friday, 9am to 4pm.",
};

// International format for the tel:/WhatsApp links (0817... -> +234 817...).
const PHONE_DISPLAY = "0817 507 0646";
const PHONE_TEL = "+2348175070646";
const WHATSAPP_URL = "https://wa.me/2348175070646";

export default function Contact() {
  return (
    <main className="wrap">
      <section className="hero">
        <div className="eyebrow">Contact</div>
        <h1>Talk to a real person.</h1>
        <p className="lede">
          Buying property is stressful, and questions deserve answers. Reach us by email, phone or
          WhatsApp — we&rsquo;ll tell you honestly what we can and cannot do for your situation.
        </p>
      </section>

      <section className="section">
        <div className="grid">
          <div className="card" style={{ cursor: "default" }}>
            <div className="name" style={{ fontSize: 17 }}>Email</div>
            <div className="who" style={{ marginTop: 6 }}>
              For any question, or to exercise your data rights.
            </div>
            <p style={{ marginTop: 12 }}>
              <a href="mailto:support@ilevest.com" style={{ color: "var(--green)", fontWeight: 700, fontSize: 15.5 }}>
                support@ilevest.com
              </a>
            </p>
            <div className="muted" style={{ fontSize: 13.5 }}>We reply within one working day.</div>
          </div>

          <div className="card" style={{ cursor: "default" }}>
            <div className="name" style={{ fontSize: 17 }}>Phone</div>
            <div className="who" style={{ marginTop: 6 }}>
              If you&rsquo;d rather talk it through.
            </div>
            <p style={{ marginTop: 12 }}>
              <a href={`tel:${PHONE_TEL}`} style={{ color: "var(--green)", fontWeight: 700, fontSize: 15.5 }}>
                {PHONE_DISPLAY}
              </a>
            </p>
            <div className="muted" style={{ fontSize: 13.5 }}>Monday to Friday, 9am – 4pm (WAT).</div>
          </div>

          <div className="card" style={{ cursor: "default" }}>
            <div className="name" style={{ fontSize: 17 }}>WhatsApp</div>
            <div className="who" style={{ marginTop: 6 }}>
              Message us — often the quickest way to reach us.
            </div>
            <p style={{ marginTop: 12 }}>
              <a
                href={WHATSAPP_URL}
                target="_blank"
                rel="noopener noreferrer"
                style={{ color: "var(--green)", fontWeight: 700, fontSize: 15.5 }}
              >
                {PHONE_DISPLAY}
              </a>
            </p>
            <div className="muted" style={{ fontSize: 13.5 }}>Monday to Friday, 9am – 4pm (WAT).</div>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="card" style={{ cursor: "default", background: "var(--surface)" }}>
          <div className="name" style={{ fontSize: 17 }}>The company behind Ilevest</div>
          <div className="who" style={{ marginTop: 6, maxWidth: "62ch", lineHeight: 1.6 }}>
            Ilevest is operated by <strong>Ilevest Nigeria Ltd</strong>, a company registered in
            Nigeria (<strong>RC 9622137</strong>). We serve Lagos, Ogun and the Federal Capital
            Territory (Abuja).
          </div>
          <div className="muted" style={{ fontSize: 13.5, marginTop: 10 }}>
            For questions about your personal data, see our{" "}
            <a href="/privacy" style={{ color: "var(--green)" }}>Privacy Policy</a>.
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
              You don&rsquo;t need to call first — start a verification and we&rsquo;ll quote your
              exact property.
            </div>
          </div>
          <a className="btn primary" href="/start" style={{ width: "auto" }}>Start a verification</a>
        </div>
      </section>
    </main>
  );
}
