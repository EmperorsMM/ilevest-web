// The shared shell — one header for every signed-in surface. It reads the
// visitor once, discovers their roles, and shows only the desks they can reach:
// a buyer sees My verifications; a worker sees Work; Ops and Reviewers see the
// Desk and Ops.
//
// Server component: roles come from user_role under RLS (a user always sees
// their own roles), so the nav is correct without trusting the client. The tabs
// are handed to <DeskNav/> (a client component) which highlights the active one
// by reading the current pathname — so highlighting works with the global header.

import { createSupabaseServerClient } from "../lib/supabase/server";
import Image from "next/image";
import SignOutButton from "../app/client/sign-out-button";
import DeskNav from "./desk-nav";

export default async function DeskShell() {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  let roles: string[] = [];
  if (user) {
    const { data } = await supabase.from("user_role").select("role");
    roles = (data ?? []).map((r: { role: string }) => r.role);
  }
  const has = (r: string) => roles.includes(r);
  const isStaff = has("ops") || has("reviewer") || has("admin");

  const tabs = [
    { href: "/client", label: "My verifications", show: !!user },
    { href: "/work", label: "Work", show: has("field_agent") || has("partner") },
    { href: "/review", label: "Desk", show: isStaff },
    { href: "/ops", label: "Ops", show: has("ops") || has("admin") },
  ]
    .filter((t) => t.show)
    .map(({ href, label }) => ({ href, label }));

  return (
    <header className="topbar">
      <div className="wrap">
        <a className="brand" href={user ? "/client" : "/start"} aria-label="Ilevest — verify before you buy">
          <Image className="brand-logo" src="/logo.png" alt="Ilevest — verify before you buy" width={1046} height={346} priority />
          <Image className="brand-compact" src="/logo-compact.png" alt="Ilevest" width={823} height={281} priority />
        </a>

        <DeskNav tabs={tabs} />

        {user ? <SignOutButton /> : <a className="signin" href="/signup?mode=signin">Sign in</a>}
      </div>
    </header>
  );
}
