"use client";

// Decides, by pathname, whether the current page shows the public footer.
// The HEADER is global for everyone (DeskShell adapts by role). The FOOTER is
// for public + buyer pages, never staff desks (blueprint §4 / CISO), and not on
// the bare auth callback. Renders the footer as a client decision so the server
// layout can stay simple.
import { usePathname } from "next/navigation";
import SiteFooter from "./site-footer";

const NO_FOOTER_PREFIXES = ["/work", "/review", "/ops", "/admin", "/auth"];

export default function SiteChrome() {
  const pathname = usePathname() || "/";
  const hideFooter = NO_FOOTER_PREFIXES.some((p) => pathname.startsWith(p));
  if (hideFooter) return null;
  return <SiteFooter />;
}
