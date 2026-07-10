"use client";

// Route error boundary — catches unexpected errors in any page, shows the buyer
// a calm, on-brand message instead of a crash, and reports the error for
// diagnosis. (Auth/data errors still surface their own messages; this is the
// last-resort net.)
import { useEffect } from "react";
import { reportError } from "../lib/monitoring";

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    reportError(error, { boundary: "route", digest: error.digest });
  }, [error]);

  return (
    <main className="wrap" style={{ padding: "80px 24px", textAlign: "center", maxWidth: 560 }}>
      <h1 style={{ fontFamily: "var(--serif)", fontSize: 30, marginBottom: 10 }}>Something went wrong</h1>
      <p style={{ color: "var(--ink-soft)", lineHeight: 1.6 }}>
        We hit an unexpected problem loading this page. Your data is safe. Please try again — if it
        keeps happening, contact us and we&rsquo;ll sort it out.
      </p>
      <div style={{ display: "flex", gap: 12, justifyContent: "center", marginTop: 24, flexWrap: "wrap" }}>
        <button className="btn primary" onClick={reset} style={{ width: "auto", cursor: "pointer" }}>
          Try again
        </button>
        <a className="btn" href="/client" style={{ width: "auto", border: "1px solid var(--line)", color: "var(--ink)" }}>
          Go to my verifications
        </a>
      </div>
    </main>
  );
}
