// Placeholder for the Admin Console surface. Role-gated by middleware.ts (UX),
// and authoritatively by Row-Level Security at the database (security).
export default function AdminSurface() {
  return (
    <main className="wrap-work" style={{ padding: "40px 24px" }}>
      <h1>Admin surface</h1>
      <p className="muted">Scaffolding placeholder — no features yet.</p>
    </main>
  );
}
