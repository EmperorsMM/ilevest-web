import type { ReactNode } from "react";
import "./globals.css";

export const metadata = {
  title: "Ilevest — verify before you buy",
  description: "Independent verification for Nigerian property. Know what you're buying before you pay.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
