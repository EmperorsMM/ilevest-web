"use client";

// Public verification page. Anyone with the link can confirm a sealed check
// independently — even without an Ilevest account. It calls the anon
// verify_certificate RPC and shows the verdict, what was checked, the property
// (location only), and the integrity record with its honest protection state.
// No personal information is shown: no buyer, no seller.
import { useEffect, useMemo, useState } from "react";
import Seal from "../../../components/seal";
import { useParams } from "next/navigation";
import { createSupabaseBrowserClient } from "../../../lib/supabase/client";

type Cert = {
  valid: boolean;
  verdict?: "green" | "amber" | "red" | "unresolved" | null;
  check_state?: string;
  service_code?: string;
  property?: { lga: string | null; state: string | null; locality: string | null };
  sealed_at?: string | null;
  content_hash?: string | null;
  prev_hash?: string | null;
  anchored?: boolean;
  externally_witnessed?: boolean;
  anchored_at?: string | null;
  merkle_root?: string | null;
  anchor_ref?: string | null;
  protection?: string | null;
};

const VERDICT: Record<string, { c: string; t: string }> = {
  green: { c: "g", t: "Cleared" },
  amber: { c: "a", t: "Proceed with care" },
  red: { c: "r", t: "Serious problem found" },
  unresolved: { c: "u", t: "Unresolved" },
};

export default function VerifyPage() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const params = useParams();
  const check = (Array.isArray(params.check) ? params.check[0] : params.check) || "";

  const [loading, setLoading] = useState(true);
  const [cert, setCert] = useState<Cert | null>(null);
  const [title, setTitle] = useState<string>("");

  useEffect(() => {
    let active = true;
    (async () => {
      const { data } = await supabase.rpc("verify_certificate", { p_check: check });
      if (!active) return;
      const c = (data ?? { valid: false }) as Cert;
      setCert(c);
      if (c.valid && c.service_code) {
        const { data: sc } = await supabase.from("service_catalogue").select("title").eq("code", c.service_code).maybeSingle();
        if (active && sc) setTitle((sc as { title: string }).title);
      }
      setLoading(false);
    })();
    return () => { active = false; };
  }, [supabase, check]);

  return (
    <>

      <main className="wrap verify-wrap">
        {loading ? (
          <p className="dash-reassure" style={{ textAlign: "center", marginTop: 48 }}>Checking the record&hellip;</p>
        ) : !cert || !cert.valid ? (
          <div className="verify-card">
            <h1 className="verify-h1">No record found</h1>
            <p className="verify-lead">
              We couldn&rsquo;t find a sealed verification for this reference. Check the link is complete and correct.
            </p>
            <p className="verify-ref">Reference: {check}</p>
          </div>
        ) : (
          <Result cert={cert} title={title} check={check} />
        )}
      </main>
    </>
  );
}

function Result({ cert, title, check }: { cert: Cert; title: string; check: string }) {
  const v = cert.verdict ? VERDICT[cert.verdict] : null;
  const loc = cert.property
    ? [cert.property.locality, cert.property.lga, cert.property.state].filter(Boolean).join(", ")
    : "";
  const fmt = (d?: string | null) => (d ? new Date(d).toLocaleString("en-NG", { dateStyle: "medium", timeStyle: "short" }) : "—");

  return (
    <div className="verify-card verify-card-sealed">
      <div className="verify-seal">
        <Seal size={84} tone="official" label="Ilevest verification seal" />
      </div>
      <p className="verify-eyebrow">Verified Ilevest record</p>
      <h1 className="verify-h1">{title || cert.service_code}</h1>
      {loc && <p className="verify-lead">For a property in {loc}.</p>}

      {v && (
        <div className={`verdict-banner ${v.c}`} style={{ marginTop: 18 }}>
          <div className="verdict-banner-head">
            <span className={`dot ${v.c}`} />
            <span className="verdict-banner-title">{v.t}</span>
          </div>
          {cert.sealed_at && <p className="verdict-banner-line">Sealed {fmt(cert.sealed_at)}.</p>}
        </div>
      )}

      {cert.protection && (
        <>
          <h2 className="verify-section">What protects this record</h2>
          <p className="verify-protect">{cert.protection}</p>
        </>
      )}

      <h2 className="verify-section">The integrity record</h2>
      <dl className="proof-grid">
        <dt>Status</dt>
        <dd>{cert.externally_witnessed ? "Publicly anchored & externally witnessed" : cert.anchored ? "Committed to a daily Merkle root (anchoring in progress)" : "Sealed (awaiting next daily anchor)"}</dd>
        <dt>Fingerprint</dt>
        <dd className="mono">{cert.content_hash || "—"}</dd>
        {cert.merkle_root && (<><dt>Merkle root</dt><dd className="mono">{cert.merkle_root}</dd></>)}
        {cert.anchor_ref && (<><dt>Public witness</dt><dd className="mono">{cert.anchor_ref}</dd></>)}
        {cert.anchored_at && (<><dt>Anchored</dt><dd>{fmt(cert.anchored_at)}</dd></>)}
        <dt>Reference</dt>
        <dd className="mono">{check}</dd>
      </dl>

      <p className="verify-foot">
        This record contains no personal information by design. It confirms the outcome and its cryptographic
        integrity, nothing about who requested it.
      </p>
    </div>
  );
}
