// Defence-in-depth routing gate. The AUTHORITATIVE permission engine is
// Row-Level Security in PostgreSQL (invariant #2); each protected page also
// redirects unauthenticated users itself. This middleware adds a third layer:
// it refreshes the Supabase session on every protected request and bounces a
// visitor with no session to sign-in before the page even runs. It never
// grants access — it only ever denies earlier. RLS remains the real boundary.
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function middleware(req: NextRequest) {
  const res = NextResponse.next({ request: { headers: req.headers } });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return req.cookies.getAll();
        },
        setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
          cookiesToSet.forEach(({ name, value, options }) => res.cookies.set(name, value, options));
        },
      },
    },
  );

  // Refresh the session (keeps cookies fresh) and read the user.
  const { data: { user } } = await supabase.auth.getUser();

  // No session on a protected path -> straight to sign-in, preserving intent.
  if (!user) {
    const url = req.nextUrl.clone();
    const next = url.pathname + url.search;
    url.pathname = "/signup";
    url.search = `?mode=signin&next=${encodeURIComponent(next)}`;
    return NextResponse.redirect(url);
  }

  // Signed in: allow through. Role-to-surface authorisation is enforced by the
  // page (its RPCs) and by RLS at the database — not guessed here.
  return res;
}

export const config = {
  // Only the protected surfaces. Public routes (/, /start, /signup, /new,
  // /verify) and assets are deliberately excluded.
  matcher: ["/client/:path*", "/work/:path*", "/review/:path*", "/ops/:path*", "/admin/:path*"],
};
