// Auth callback: completes the OAuth (and email-confirmation) round-trip by exchanging
// the returned code for a session cookie, then sends the user on to `next`.
import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "../../../lib/supabase/server";

export async function GET(req: NextRequest) {
  const { searchParams, origin } = new URL(req.url);
  const code = searchParams.get("code");
  const next = searchParams.get("next") ?? "/client";

  if (code) {
    const supabase = createSupabaseServerClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) {
      return NextResponse.redirect(`${origin}/signup?error=${encodeURIComponent("Sign-in could not be completed.")}`);
    }
  }
  return NextResponse.redirect(`${origin}${next}`);
}
