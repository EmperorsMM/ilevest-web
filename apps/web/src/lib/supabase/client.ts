// Browser Supabase client. Uses the CLIENT-SAFE anon key only.
//
// PKCE note: @supabase/ssr's createBrowserClient, when called WITHOUT a custom
// cookies option, automatically stores auth state (including the PKCE
// code-verifier) using the document.cookie API. Storing the verifier as a
// cookie is exactly what lets it survive the sign-in -> Google -> /auth/callback
// round-trip. So we deliberately pass NO cookies option and let the library
// handle it — this is the library's own recommended browser configuration.
import { createBrowserClient } from "@supabase/ssr";

export function createSupabaseBrowserClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
