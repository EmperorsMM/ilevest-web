// The front door — ilevest.com/. Signed-in visitors route to their surface;
// the public sees the landing. Built on the shared design system in globals.css
// (the "evidence-room" identity: ink authority, one cleared-green, warm paper,
// the verdict scale as the signature) rather than ad-hoc inline styles, so the
// root matches /start and /client exactly.
import { redirect } from "next/navigation";
import Image from "next/image";
import { createSupabaseServerClient } from "../lib/supabase/server";
import DeskShell from "../components/desk-shell";

export const dynamic = "force-dynamic";

export default async function Home() {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (user) {
    const { data } = await supabase.from("user_role").select("role");
    const roles = (data ?? []).map((r: { role: string }) => r.role);
    if (roles.includes("ops") || roles.includes("reviewer") || roles.includes("admin")) {
      redirect("/review");
    }
    redirect("/client");
  }

  return (
    <>
      <DeskShell />
      <main className="wrap">
        <section className="hero">
          <div className="hero-head">
            <div>
              <p className="eyebrow">Independent property verification · Lagos · Ogun · FCT</p>
              <h1>Know exactly what you&rsquo;re buying before you pay for it.</h1>
            </div>
            <div className="hero-seal">
              <Image src="/seal.png" alt="Ilevest verification seal" width={128} height={128} priority />
            </div>
          </div>
          <p className="lede">
            Land fraud, fake titles and disputed ownership cost Nigerian buyers everything.
            We check the property against the registries, the survey records and the courts,
            then give you a clear, evidence-backed verdict you can verify yourself.
          </p>

          <div className="verdicts">
            <span className="verdict g"><span className="dot g" /><b>Green</b> clear to proceed</span>
            <span className="verdict"><span className="dot a" /><b>Amber</b> proceed with care</span>
            <span className="verdict"><span className="dot r" /><b>Red</b> a serious problem</span>
          </div>

          <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginTop: 30, maxWidth: 440 }}>
            <a className="btn primary" href="/start" style={{ width: "auto", flex: "1 1 auto" }}>
              Start a verification
            </a>
            <a className="btn" href="/signup?mode=signin"
               style={{ width: "auto", flex: "0 0 auto", border: "1px solid var(--line)", color: "var(--ink)" }}>
              Sign in
            </a>
          </div>
        </section>

        <section className="section">
          <h2>How the trust is built</h2>
          <div className="grid">
            <div className="card" style={{ cursor: "default" }}>
              <div className="name">Evidence-backed</div>
              <div className="who">
                Every finding is captured, fingerprinted and kept &mdash; no trust-me verdicts.
                You see what we saw.
              </div>
            </div>
            <div className="card" style={{ cursor: "default" }}>
              <div className="name">Publicly verifiable</div>
              <div className="who">
                Each sealed result gets a public certificate anyone can check &mdash; and it
                carries no personal information about you.
              </div>
            </div>
            <div className="card" style={{ cursor: "default" }}>
              <div className="name">Tamper-evident</div>
              <div className="who">
                Results are sealed and anchored daily to public infrastructure, so a verdict
                cannot be quietly changed after the fact.
              </div>
            </div>
            <div className="card" style={{ cursor: "default" }}>
              <div className="name">On the ground</div>
              <div className="who">
                For diaspora buyers, we become your eyes at the registry and the site &mdash;
                the checks you cannot make from abroad.
              </div>
            </div>
          </div>
        </section>

        <section className="section" style={{ paddingBottom: 80 }}>
          <div className="rail" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 16 }}>
            <div>
              <div style={{ fontWeight: 800, fontSize: 19, letterSpacing: "-0.01em" }}>Ready to check a property?</div>
              <div className="muted" style={{ fontSize: 14, marginTop: 4 }}>
                Choose a verification pack or build your own. We prepare an itemised quote for your specific property.
              </div>
            </div>
            <a className="btn primary" href="/start" style={{ width: "auto" }}>Start a verification</a>
          </div>
        </section>
      </main>
    </>
  );
}
