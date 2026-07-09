// Site-wide footer (blueprint §4). Appears on all public and buyer pages; staff
// surfaces use a minimal or no footer. Four columns + a base bar. It reinforces
// trust for a nervous buyer (a real registered company stands behind this) and
// carries the legally required links — /privacy and /terms — on every page.
//
// The legal PAGES themselves are built with lawyer-supplied wording; this footer
// only links to them, which is safe to ship now.

export default function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="wrap site-footer-grid">
        {/* Column 1 — brand & mission */}
        <div>
          <div className="site-footer-brand">
            ile<span>vest</span>
          </div>
          <p className="site-footer-mission">
            Independent property verification for Nigeria. Verify before you buy.
          </p>
          <p className="site-footer-coverage">Lagos · Ogun · FCT Abuja</p>
        </div>

        {/* Column 2 — product / services */}
        <div>
          <div className="site-footer-h">Product</div>
          <a href="/how-it-works">How It Works</a>
          <a href="/services">Services</a>
          <a href="/trust">Trust &amp; Verification</a>
          <a href="/start">Start a Verification</a>
        </div>

        {/* Column 3 — company */}
        <div>
          <div className="site-footer-h">Company</div>
          <a href="/about">About</a>
          <a href="/contact">Contact</a>
          <a href="/faq">FAQ</a>
          <p className="site-footer-rc">Ilevest Nigeria Ltd · RC 9622137</p>
        </div>

        {/* Column 4 — legal & trust (required) */}
        <div>
          <div className="site-footer-h">Legal &amp; Trust</div>
          <a href="/privacy">Privacy Policy</a>
          <a href="/terms">Terms of Service</a>
          <a href="/verify">Verify a Certificate</a>
        </div>
      </div>

      <div className="site-footer-base">
        <div className="wrap site-footer-base-row">
          <span>© 2026 Ilevest Nigeria Ltd. All rights reserved.</span>
          <span className="site-footer-disclaimer">
            Verification is professional due diligence, not a guarantee — see our Terms.
          </span>
        </div>
      </div>
    </footer>
  );
}
