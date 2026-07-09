"use client";

// Safety net: if an OAuth ?code= ever lands on a page other than /auth/callback
// (e.g. the homepage, because a provider fell back to the Site URL), forward it
// to the real callback so the browser client can complete the PKCE exchange.
// Renders nothing.

import { useEffect } from "react";

export default function OAuthCodeCatcher() {
  useEffect(() => {
    if (typeof window === "undefined") return;
    const url = new URL(window.location.href);
    const code = url.searchParams.get("code");
    // Only act on the OAuth code, and only when NOT already on the callback route.
    if (code && !url.pathname.startsWith("/auth/callback")) {
      const next = url.searchParams.get("next") || "/client";
      window.location.replace(
        `/auth/callback?code=${encodeURIComponent(code)}&next=${encodeURIComponent(next)}`,
      );
    }
  }, []);
  return null;
}
