"use client";

// Global error boundary — the very last net, for errors thrown in the root
// layout. Must render its own <html>/<body>. Kept minimal and dependency-free.
import { useEffect } from "react";

export default function GlobalError({ error }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    // eslint-disable-next-line no-console
    console.error(JSON.stringify({ level: "error", message: error.message, boundary: "global", digest: error.digest, at: new Date().toISOString() }));
  }, [error]);

  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", padding: "80px 24px", textAlign: "center" }}>
        <h1 style={{ fontSize: 28 }}>Something went wrong</h1>
        <p style={{ color: "#555" }}>Please refresh the page. If the problem persists, contact Ilevest support.</p>
      </body>
    </html>
  );
}
