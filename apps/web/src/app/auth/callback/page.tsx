"use client";

// OAuth / email-confirmation callback — CLIENT side (PKCE verifier lives in the
// browser, so only the browser client can exchange the ?code=). useSearchParams
// requires a Suspense boundary in Next 14, so the logic lives in a child.

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createSupabaseBrowserClient } from "../../../lib/supabase/client";

function CallbackInner() {
  const router = useRouter();
  const params = useSearchParams();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createSupabaseBrowserClient();
    const next = params.get("next") || "/client";
    const code = params.get("code");
    const errDesc = params.get("error_description") || params.get("error");

    async function complete() {
      if (errDesc) {
        setError(errDesc);
        return;
      }
      try {
        if (code) {
          const { error } = await supabase.auth.exchangeCodeForSession(code);
          if (error) {
            const { data } = await supabase.auth.getSession();
            if (!data.session) {
              setError(error.message);
              return;
            }
          }
        }
        const { data } = await supabase.auth.getSession();
        if (data.session) {
          router.replace(next);
        } else {
          setError("Sign-in did not complete. Please try again.");
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : "Sign-in could not be completed.");
      }
    }
    void complete();
  }, [params, router]);

  return (
    <main className="wrap" style={{ padding: "80px 24px", textAlign: "center" }}>
      {error ? (
        <>
          <h1 style={{ fontFamily: "var(--serif)", fontSize: 28 }}>Sign-in problem</h1>
          <p style={{ color: "var(--ink-soft)", marginTop: 8 }}>{error}</p>
          <p style={{ marginTop: 20 }}>
            <a className="btn primary" href="/signup?mode=signin" style={{ width: "auto" }}>
              Back to sign in
            </a>
          </p>
        </>
      ) : (
        <>
          <h1 style={{ fontFamily: "var(--serif)", fontSize: 28 }}>Signing you in…</h1>
          <p style={{ color: "var(--muted)", marginTop: 8 }}>One moment while we complete your sign-in.</p>
        </>
      )}
    </main>
  );
}

export default function AuthCallback() {
  return (
    <Suspense
      fallback={
        <main className="wrap" style={{ padding: "80px 24px", textAlign: "center" }}>
          <h1 style={{ fontFamily: "var(--serif)", fontSize: 28 }}>Signing you in…</h1>
        </main>
      }
    >
      <CallbackInner />
    </Suspense>
  );
}
