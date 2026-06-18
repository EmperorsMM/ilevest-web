// Role-based ROUTING for the three surfaces. This is UX + defense-in-depth ONLY.
// The authoritative permission engine is Row-Level Security in PostgreSQL (invariant #2).
//
// STUB: refreshes the Supabase session and marks where the role gate goes. The actual
// role lookup + redirects are wired in a later stage, against the schema from Stage 1.
import { NextResponse, type NextRequest } from "next/server";

export async function middleware(_req: NextRequest) {
  // TODO (later stage):
  //  1. Load the Supabase session from cookies (@supabase/ssr).
  //  2. If no session -> redirect to sign-in.
  //  3. Read the caller's role; if it does not match the requested surface
  //     (/client, /ops, /admin) -> redirect to their own surface or 403.
  //  Reminder: even with this gate, the database must independently deny access via RLS.
  return NextResponse.next();
}

export const config = {
  matcher: ["/client/:path*", "/ops/:path*", "/admin/:path*"],
};
