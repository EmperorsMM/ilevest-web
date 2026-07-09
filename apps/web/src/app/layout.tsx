import type { ReactNode } from "react";
// Self-hosted fonts (offline-safe for CI). Fraunces = display voice (headlines
// only); Inter = body + UI.
import "@fontsource-variable/fraunces";
import "@fontsource-variable/inter";
import "./globals.css";
import DeskShell from "../components/desk-shell";
import SiteChrome from "../components/site-chrome";

export const metadata = {
  title: "Ilevest — verify before you buy",
  description: "Independent verification for Nigerian property. Know what you're buying before you pay.",
  metadataBase: new URL("https://ilevest.com"),
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/icon-192.png", type: "image/png", sizes: "192x192" },
      { url: "/icon-512.png", type: "image/png", sizes: "512x512" },
    ],
    apple: [{ url: "/apple-icon.png", sizes: "180x180" }],
  },
  openGraph: {
    title: "Ilevest — verify before you buy",
    description: "Independent, evidence-backed property verification for Nigeria.",
    images: [{ url: "/og.png" }],
    type: "website",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        {/* Global header — one for the whole app; DeskShell adapts by role
            (Sign in for anonymous, role-aware nav for signed-in users). */}
        <DeskShell />
        {children}
        {/* Global footer — shown on public + buyer pages, hidden on staff
            surfaces and the auth callback (decided in SiteChrome). */}
        <SiteChrome />
      </body>
    </html>
  );
}
