"use client";

// The nav tabs — a client component so it can read the current pathname and
// highlight the active desk itself. DeskShell (server) computes which tabs to
// show from the user's roles and hands them here; this component decides which
// one is "on" by matching the URL. This is why the active tab highlights again
// after the header became global: the highlight is derived from the route, not
// passed down per-page.
import { usePathname } from "next/navigation";

type Tab = { href: string; label: string };

export default function DeskNav({ tabs }: { tabs: Tab[] }) {
  const pathname = usePathname() || "";
  if (tabs.length === 0) return null;

  return (
    <nav style={{ display: "flex", gap: 4, marginRight: "auto", marginLeft: 24 }}>
      {tabs.map((t) => {
        // A tab is active if the path is that tab exactly OR a sub-route of it
        // (e.g. /client/orders/123 highlights "My verifications").
        const on = pathname === t.href || pathname.startsWith(t.href + "/");
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
  );
}
