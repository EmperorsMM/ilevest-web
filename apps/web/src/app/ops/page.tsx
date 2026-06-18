// Placeholder for the Ops / Reviewer Console surface. Role-gated by middleware.ts (UX),
// and authoritatively by Row-Level Security at the database (security).
export default function OpsSurface() {
  return (
    <main style={{ padding: 24, fontFamily: "system-ui" }}>
      <h1>Ops / Reviewer surface</h1>
      <p style={{ color: "#666" }}>Scaffolding placeholder — no features yet.</p>
    </main>
  );
}
