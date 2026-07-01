"use client";

// Buyer "Pay now" — Paystack inline. We pass the order id in metadata so the
// (already proven) webhook can confirm the payment server-side and fan the order
// out into live checks. The client callback is a UX signal only; confirmation is
// the webhook's job, so after it we refresh to pick up the verified state.
import { useState } from "react";
import { useRouter } from "next/navigation";

declare global {
  interface Window { PaystackPop?: any }
}

export default function PayButton({
  orderId, email, amountKobo,
}: { orderId: string; email: string; amountKobo: number }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const pk = process.env.NEXT_PUBLIC_PAYSTACK_PUBLIC_KEY;

  function pay() {
    if (!pk) { alert("Payments aren't configured yet."); return; }
    setBusy(true);

    const open = () => {
      try {
        const handler = window.PaystackPop.setup({
          key: pk,
          email,
          amount: amountKobo,
          currency: "NGN",
          ref: `ilv_${orderId.replace(/-/g, "").slice(0, 12)}_${Date.now()}`,
          metadata: { order_id: orderId },
          onClose: () => setBusy(false),
          callback: () => {
            setConfirming(true);
            setTimeout(() => router.refresh(), 3500);
          },
        });
        handler.openIframe();
      } catch {
        setBusy(false);
        alert("Could not open payment. Please try again.");
      }
    };

    if (window.PaystackPop) { open(); return; }
    const s = document.createElement("script");
    s.src = "https://js.paystack.co/v1/inline.js";
    s.onload = open;
    s.onerror = () => { setBusy(false); alert("Could not load payment. Check your connection and try again."); };
    document.body.appendChild(s);
  }

  if (confirming) {
    return <p className="status-sub">Payment received — setting up your checks. This page will update in a moment&hellip;</p>;
  }
  return (
    <button className="btn primary lg" onClick={pay} disabled={busy} style={{ marginTop: 4 }}>
      {busy ? "Opening\u2026" : `Pay \u20a6${(amountKobo / 100).toLocaleString("en-NG")}`}
    </button>
  );
}
