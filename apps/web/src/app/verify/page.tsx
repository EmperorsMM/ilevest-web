"use client";

// /verify — the public entry point for confirming a certificate. Someone who has
// been given a certificate reference (or link) arrives here to look it up. The
// per-certificate page lives at /verify/[check]; this is the landing that routes
// to it. Sober and official in tone, matching the certificate itself — this is a
// trust surface, not a marketing page.

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function VerifyLanding() {
  const router = useRouter();
  const [ref, setRef] = useState("");

  function lookup(e: React.FormEvent) {
    e.preventDefault();
    const id = ref.trim();
    if (!id) return;
    // A pasted full URL or a bare reference both work: take the last path segment.
    const afterPath = id.includes("/verify/") ? id.split("/verify/")[1] : id;
    const clean = (afterPath ?? id).split(/[?#]/)[0] ?? id;
    if (!clean.trim()) return;
    router.push(`/verify/${encodeURIComponent(clean.trim())}`);
  }

  return (
    <main className="wrap">
      <section className="hero">
        <div className="eyebrow">Verify a certificate</div>
        <h1>Confirm a sealed Ilevest result is genuine.</h1>
        <p className="lede">
          Every Ilevest verification is sealed with tamper-evident proof and given a certificate
          anyone can independently confirm — with no personal information exposed. If you&rsquo;ve
          been given a certificate reference or link, look it up here.
        </p>
      </section>

      <section className="section">
        <div className="card" style={{ cursor: "default", maxWidth: 560 }}>
          <form onSubmit={lookup}>
            <div className="field">
              <label htmlFor="ref">Certificate reference or link</label>
              <input
                id="ref"
                type="text"
                value={ref}
                onChange={(e) => setRef(e.target.value)}
                placeholder="Paste the certificate link or reference"
                autoComplete="off"
              />
            </div>
            <button className="btn primary" type="submit" disabled={!ref.trim()} style={{ width: "auto" }}>
              Verify certificate
            </button>
          </form>
        </div>
      </section>

      <section className="section">
        <h2>What verifying tells you</h2>
        <div className="grid">
          <div className="card" style={{ cursor: "default" }}>
            <div className="name">It&rsquo;s genuine</div>
            <div className="who">The certificate was issued by Ilevest and its seal is intact.</div>
          </div>
          <div className="card" style={{ cursor: "default" }}>
            <div className="name">It hasn&rsquo;t been altered</div>
            <div className="who">The sealed result is exactly as issued — anchored to public infrastructure and unchangeable after the fact.</div>
          </div>
          <div className="card" style={{ cursor: "default" }}>
            <div className="name">No private details</div>
            <div className="who">A certificate confirms an outcome and its proof, and reveals nothing about who requested the check.</div>
          </div>
        </div>
      </section>

      <section className="section" style={{ paddingBottom: 80 }}>
        <div className="rail" style={{ display: "flex", alignItems: "center",
              justifyContent: "space-between", flexWrap: "wrap", gap: 16 }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 19, letterSpacing: "-0.01em" }}>
              Don&rsquo;t have a certificate yet?
            </div>
            <div className="muted" style={{ fontSize: 14, marginTop: 4 }}>
              Verify a property before you buy, and you&rsquo;ll get one you can share.
            </div>
          </div>
          <a className="btn" href="/start" style={{ width: "auto", border: "1px solid var(--line)", color: "var(--ink)" }}>
            Start a verification
          </a>
        </div>
      </section>
    </main>
  );
}
