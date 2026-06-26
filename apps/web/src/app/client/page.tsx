// Client dashboard — the logged-in landing. Reads the caller's own orders via
// my_orders() (owner-scoped, RLS/boundary proven) and shows each order's
// buyer-facing status and verdict. A brand-new account has no orders, so the
// empty state is the front door: a moment of reassurance + a single call to
// start a verification, routing back to /start.
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../lib/supabase/server";
import SignOutButton from "./sign-out-button";

export const dynamic = "force-dynamic";

type Verdict = "green" | "amber" | "red" | "unresolved" | null;
type OrderRow = {
  order_id: string;
  bundle: string;
  created_at: string;
  paid: boolean;
  total_checks: number;
  ready_checks: number;
  ready: boolean;
  headline_verdict: Verdict;
};

const BUNDLE_LABEL: Record<string, string> = {
  essential: "Essential Check",
  complete: "Complete Due Diligence",
  inheritance: "Inheritance & Family Land",
  diaspora: "Diaspora Package",
  ala_carte: "Custom Selection",
};

export default async function ClientHome() {
  const supabase = createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/signup?mode=signin&next=/client");

  const { data } = await supabase.rpc("my_orders");
  const orders: OrderRow[] = Array.isArray(data) ? (data as OrderRow[]) : [];
  const fullName = (user.user_metadata?.full_name as string | undefined) ?? "";
  const first = fullName.trim().split(/\s+/)[0] || "";

  return (
    <>
      <header className="topbar">
        <div className="wrap">
          <a className="brand" href="/start" style={{ textDecoration: "none" }}>ile<span>vest</span></a>
          <SignOutButton />
        </div>
      </header>
      <main className="wrap dash">
        {orders.length === 0 ? <EmptyState first={first} /> : <OrderList orders={orders} first={first} />}
      </main>
    </>
  );
}

function EmptyState({ first }: { first: string }) {
  return (
    <section className="dash-empty">
      <p className="dash-kicker">{first ? `Welcome, ${first}` : "Welcome"}</p>
      <h1>Verify before you buy.</h1>
      <p className="dash-lead">
        Buying land in Nigeria shouldn&rsquo;t mean taking a stranger&rsquo;s word for it. Start by telling us
        about the property you&rsquo;re considering &mdash; we&rsquo;ll check what&rsquo;s real, flag what
        isn&rsquo;t, and hand you back proof you can keep.
      </p>
      <a className="btn primary lg" href="/start">Start your first verification</a>
      <p className="dash-reassure">No payment until you&rsquo;ve seen exactly what your verification covers, itemised.</p>
    </section>
  );
}

function OrderList({ orders, first }: { orders: OrderRow[]; first: string }) {
  return (
    <section>
      <div className="dash-head">
        <div>
          <p className="dash-kicker">{first ? `Welcome back, ${first}` : "Welcome back"}</p>
          <h1>Your verifications</h1>
        </div>
        <a className="btn primary" href="/start">Start another</a>
      </div>
      <div className="order-grid">
        {orders.map((o) => (
          <OrderCard key={o.order_id} o={o} />
        ))}
      </div>
    </section>
  );
}

function OrderCard({ o }: { o: OrderRow }) {
  const label = BUNDLE_LABEL[o.bundle] ?? "Verification";
  const placed = new Date(o.created_at).toLocaleDateString("en-NG", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
  return (
    <article className="order-card">
      <div className="order-top">
        <div>
          <h3>{label}</h3>
          <p className="order-meta">Placed {placed}</p>
        </div>
        {o.ready && <VerdictChip v={o.headline_verdict} />}
      </div>
      <div className="order-status">
        <Status o={o} />
      </div>
    </article>
  );
}

function Status({ o }: { o: OrderRow }) {
  if (o.total_checks === 0) {
    return (
      <>
        <span className="status-pill"><span className="dot u" />Awaiting your quote</span>
        <p className="status-sub">We&rsquo;re preparing your itemised invoice. You&rsquo;ll be notified the moment it&rsquo;s ready.</p>
      </>
    );
  }
  if (!o.ready) {
    const pct = Math.max(4, Math.round((o.ready_checks / o.total_checks) * 100));
    return (
      <>
        <span className="status-pill"><span className="dot a" />In progress</span>
        <div className="progress"><i style={{ width: `${pct}%` }} /></div>
        <p className="status-sub">{o.ready_checks} of {o.total_checks} checks complete</p>
      </>
    );
  }
  return <p className="status-sub">Verification complete &mdash; your full report and proof are ready.</p>;
}

function VerdictChip({ v }: { v: Verdict }) {
  const map = {
    green: { c: "g", t: "Cleared" },
    amber: { c: "a", t: "Caution" },
    red: { c: "r", t: "Issues found" },
    unresolved: { c: "u", t: "Unresolved" },
  } as const;
  const m = v ? map[v] : { c: "u", t: "Pending" };
  return (
    <span className={`verdict ${m.c}`}>
      <span className={`dot ${m.c}`} />
      <b>{m.t}</b>
    </span>
  );
}
