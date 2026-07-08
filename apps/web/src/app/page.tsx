// The front door — ilevest.com/. A signed-in visitor is sent straight to their
// own surface; the public sees a real landing (no scaffolding), with the shared
// shell on top and a clear path into the journey. Server component so the
// redirect happens before any render.
//
// This replaces the Stage 0 placeholder. Protected surfaces (/client, /work,
// /review, /ops) each still enforce their own sign-in redirect and RLS; this
// page only decides where a visitor to the bare domain lands.

import { redirect } from "next/navigation";
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
      <main className="wrap" style={{ padding: "72px 24px 96px", maxWidth: 720, textAlign: "center" }}>
        <h1 style={{ fontSize: 40, lineHeight: 1.1, letterSpacing: "-0.02em", margin: "0 0 16px" }}>
          Verify before you buy.
        </h1>
        <p style={{ fontSize: 19, color: "var(--muted)", lineHeight: 1.5, margin: "0 auto 32px", maxWidth: 560 }}>
          Independent land and property verification for Nigeria. We check the title,
          the survey, the courts and the seller — then seal the result as a tamper-evident
          record you can trust and anyone can verify.
        </p>
        <div style={{ display: "flex", gap: 12, justifyContent: "center", flexWrap: "wrap" }}>
          <a className="btn" href="/start" style={{ fontSize: 16, padding: "12px 22px" }}>
            Start a verification
          </a>
          <a href="/signup?mode=signin"
             style={{ fontSize: 16, padding: "12px 22px", textDecoration: "none",
                      color: "var(--ink)", border: "1px solid var(--line)", borderRadius: 10 }}>
            Sign in
          </a>
        </div>

        <div style={{ marginTop: 56, display: "grid", gap: 20, gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
                      textAlign: "left" }}>
          <div>
            <strong>Evidence-backed</strong>
            <p style={{ color: "var(--muted)", margin: "6px 0 0", fontSize: 15 }}>
              Every finding is captured, fingerprinted, and kept — no trust-me verdicts.
            </p>
          </div>
          <div>
            <strong>Publicly verifiable</strong>
            <p style={{ color: "var(--muted)", margin: "6px 0 0", fontSize: 15 }}>
              Each sealed result gets a public certificate — with no personal information.
            </p>
          </div>
          <div>
            <strong>Tamper-evident</strong>
            <p style={{ color: "var(--muted)", margin: "6px 0 0", fontSize: 15 }}>
              Results are anchored daily to public infrastructure and cannot be altered after.
            </p>
          </div>
        </div>
      </main>
    </>
  );
}
