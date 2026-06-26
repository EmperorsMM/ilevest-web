"use client";

// Small client control for the dashboard header: ends the Supabase session and
// returns the visitor to the public entry page.
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "../../lib/supabase/client";

export default function SignOutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function signOut() {
    setBusy(true);
    try {
      const supabase = createSupabaseBrowserClient();
      await supabase.auth.signOut();
      router.push("/start");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <button type="button" className="signin" onClick={signOut} disabled={busy}>
      {busy ? "Signing out\u2026" : "Sign out"}
    </button>
  );
}
