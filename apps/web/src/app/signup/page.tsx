"use client";

// Account page: minimal signup (name, email, password) plus Continue with Google.
// Wired to Supabase Auth; on first sign-in the database trigger creates the app_user
// (keyed to the auth uid) with the client role — the linkage proven in the backend.
// Social login is access only; verified identity stays with the C1-PE-02 KYC service.
import { Suspense, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createSupabaseBrowserClient } from "../../lib/supabase/client";

function SignupForm() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get("next") || "/client";

  const initialMode = params.get("mode") === "signin" ? "signin" : "signup";
  const [mode, setMode] = useState<"signup" | "signin">(initialMode);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [checkEmail, setCheckEmail] = useState(false);

  const callbackUrl =
    typeof window !== "undefined"
      ? `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`
      : "/auth/callback";

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (mode === "signup") {
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: { data: { full_name: name }, emailRedirectTo: callbackUrl },
        });
        if (error) throw error;
        if (!data.session) {
          setCheckEmail(true); // email confirmation is on — they must confirm first
          return;
        }
        router.push(next);
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        router.push(next);
      }
    } catch (err) {
      setError((err as Error)?.message ?? "Something went wrong. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  async function withGoogle() {
    setBusy(true);
    setError(null);
    try {
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          redirectTo: callbackUrl,
          // Ensure a full-page redirect to Google actually happens.
          skipBrowserRedirect: false,
        },
      });
      if (error) {
        setError(`Google sign-in failed: ${error.message}`);
        setBusy(false);
        return;
      }
      // If Supabase returned a URL but didn't navigate, do it explicitly.
      if (data?.url) {
        window.location.assign(data.url);
        return;
      }
      // No URL and no error => provider not configured on the Supabase side.
      setError("Google sign-in is not available right now. Please use email, or try again shortly.");
      setBusy(false);
    } catch (err) {
      setError((err as Error)?.message ?? "Google sign-in could not start.");
      setBusy(false);
    }
    // on success the browser navigates to Google, then back to /auth/callback
  }

  return (
    <>

      <div className="auth-wrap">
        <div className="auth-card">
          {checkEmail ? (
            <>
              <h1>Check your email</h1>
              <p className="sub">
                We sent a confirmation link to <strong>{email}</strong>. Open it to finish creating your
                account, then come back and sign in.
              </p>
              <button className="btn primary" onClick={() => { setCheckEmail(false); setMode("signin"); }}>
                Back to sign in
              </button>
            </>
          ) : (
            <>
              <h1>{mode === "signup" ? "Create your account" : "Welcome back"}</h1>
              <p className="sub">
                {mode === "signup"
                  ? "Just a few details to get started. We only ask for what we need."
                  : "Sign in to continue your verification."}
              </p>

              {error && <div className="auth-err">{error}</div>}

              <button className="btn google" onClick={withGoogle} disabled={busy} type="button">
                <GoogleMark /> Continue with Google
              </button>

              <div className="divider">or</div>

              <form onSubmit={submit}>
                {mode === "signup" && (
                  <div className="field">
                    <label htmlFor="name">Full name</label>
                    <input id="name" type="text" autoComplete="name" value={name}
                      onChange={(e) => setName(e.target.value)} placeholder="Your name" required />
                  </div>
                )}
                <div className="field">
                  <label htmlFor="email">Email</label>
                  <input id="email" type="email" autoComplete="email" value={email}
                    onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" required />
                </div>
                <div className="field">
                  <label htmlFor="password">Password</label>
                  <input id="password" type="password"
                    autoComplete={mode === "signup" ? "new-password" : "current-password"}
                    value={password} onChange={(e) => setPassword(e.target.value)}
                    placeholder="At least 6 characters" minLength={6} required />
                </div>
                <button className="btn primary" type="submit" disabled={busy}>
                  {busy ? "Please wait…" : mode === "signup" ? "Create account" : "Sign in"}
                </button>
              </form>

              <div className="auth-toggle">
                {mode === "signup" ? (
                  <>Already have an account?{" "}
                    <button onClick={() => { setMode("signin"); setError(null); }}>Sign in</button></>
                ) : (
                  <>New to Ilevest?{" "}
                    <button onClick={() => { setMode("signup"); setError(null); }}>Create an account</button></>
                )}
              </div>

              <p className="boundary-note">
                Signing in gives you access to your account. It is not identity verification — when identity
                matters, we verify it properly through a dedicated check.
              </p>
            </>
          )}
        </div>
      </div>
    </>
  );
}

export default function SignupPage() {
  return (
    <Suspense fallback={<div className="auth-wrap"><div className="auth-card"><p className="sub">Loading…</p></div></div>}>
      <SignupForm />
    </Suspense>
  );
}

function GoogleMark() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
      <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z" />
      <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.8.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18z" />
      <path fill="#FBBC05" d="M3.97 10.72a5.4 5.4 0 0 1 0-3.44V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.33z" />
      <path fill="#EA4335" d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58z" />
    </svg>
  );
}
