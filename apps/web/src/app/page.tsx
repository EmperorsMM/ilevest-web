// Entry point. In a later stage this reads the signed-in user's role and redirects
// to /client, /ops, or /admin. Scaffolding placeholder for now.
export default function Home() {
  return (
    <main style={{ padding: 24, fontFamily: "system-ui" }}>
      <h1>Ilevest</h1>
      <p>Verify before you buy.</p>
      <p style={{ color: "#666" }}>
        Scaffolding only (Build Stage 0). Surfaces: <code>/client</code>, <code>/ops</code>,{" "}
        <code>/admin</code>.
      </p>
    </main>
  );
}
