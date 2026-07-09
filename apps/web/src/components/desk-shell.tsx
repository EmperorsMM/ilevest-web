// The shared shell — one header for every signed-in surface. It reads the
// visitor once, discovers their roles, and shows only the desks they can reach:
// a buyer sees My verifications; a worker sees Work; Ops and Reviewers see the
// Desk and Ops. This is the navigation the operator was missing — no more
// typing URLs to move between the places the loop already connects by data.
//
// Server component: roles come from user_role under RLS (a user always sees
// their own roles), so the nav is correct without trusting the client.

import { createSupabaseServerClient } from "../lib/supabase/server";
import Image from "next/image";
import SignOutButton from "../app/client/sign-out-button";

type Tab = { href: string; label: string; show: boolean };

export default async function DeskShell({ active }: { active?: string }) {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  let roles: string[] = [];
  if (user) {
    const { data } = await supabase.from("user_role").select("role");
    roles = (data ?? []).map((r: { role: string }) => r.role);
  }
  const has = (r: string) => roles.includes(r);
  const isStaff = has("ops") || has("reviewer") || has("admin");

  const tabs: Tab[] = [
    { href: "/client", label: "My verifications", show: !!user },
    { href: "/work", label: "Work", show: has("field_agent") || has("partner") },
    { href: "/review", label: "Desk", show: isStaff },
    { href: "/ops", label: "Ops", show: has("ops") || has("admin") },
  ].filter((t) => t.show);

  return (
    <header className="topbar">
      <div className="wrap">
        <a className="brand" href={user ? "/client" : "/start"} aria-label="Ilevest — verify before you buy">
          <Image className="brand-logo" src="/logo.png" alt="Ilevest — verify before you buy" width={1046} height={346} priority />
          <Image className="brand-seal" src="/seal.png" alt="Ilevest" width={40} height={40} priority />
        </a>

        {tabs.length > 0 && (
          <nav style={{ display: "flex", gap: 4, marginRight: "auto", marginLeft: 24 }}>
            {tabs.map((t) => {
              const on = active === t.href;
              return (
                <a
                  key={t.href}
                  href={t.href}
                  style={{
                    textDecoration: "none",
                    fontSize: 14,
                    padding: "6px 12px",
                    borderRadius: 8,
                    fontWeight: on ? 700 : 500,
                    color: on ? "var(--ink)" : "var(--muted)",
                    background: on ? "var(--line)" : "transparent",
                  }}
                >
                  {t.label}
                </a>
              );
            })}
          </nav>
        )}

        {user ? <SignOutButton /> : <a className="signin" href="/signup?mode=signin">Sign in</a>}
      </div>
    </header>
  );
}
