// Browser Supabase client. Uses the CLIENT-SAFE anon key only.
//
// IMPORTANT (PKCE): @supabase/ssr's createBrowserClient stores the PKCE
// code-verifier via the cookie methods we provide here. Storing it as a COOKIE
// (not localStorage) is what lets the verifier written when sign-in STARTS be
// read again on /auth/callback after the round-trip to Google — the exact thing
// the "PKCE code verifier not found in storage" error was complaining about.
import { createBrowserClient, type CookieOptions } from "@supabase/ssr";

export function createSupabaseBrowserClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          if (typeof document === "undefined") return [];
          return document.cookie
            .split("; ")
            .filter(Boolean)
            .map((c) => {
              const eq = c.indexOf("=");
              const name = decodeURIComponent(c.slice(0, eq));
              const value = decodeURIComponent(c.slice(eq + 1));
              return { name, value };
            });
        },
        setAll(cookiesToSet: { name: string; value: string; options?: CookieOptions }[]) {
          if (typeof document === "undefined") return;
          cookiesToSet.forEach(({ name, value, options }) => {
            let cookie = `${encodeURIComponent(name)}=${encodeURIComponent(value)}`;
            const path = options?.path ?? "/";
            cookie += `; Path=${path}`;
            if (options?.maxAge) cookie += `; Max-Age=${options.maxAge}`;
            if (options?.domain) cookie += `; Domain=${options.domain}`;
            if (options?.sameSite) cookie += `; SameSite=${options.sameSite}`;
            // Secure on https (production). Harmless to omit on localhost.
            if (typeof location !== "undefined" && location.protocol === "https:") {
              cookie += "; Secure";
            }
            document.cookie = cookie;
          });
        },
      },
    },
  );
}
