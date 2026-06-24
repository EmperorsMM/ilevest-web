// Scheduled anchoring job (deploy-verified — the build sandbox cannot reach the public calendars).
// Called once a day by pg_cron. Orchestration lives in ../_shared/anchor.ts (unit-tested offline);
// this file supplies the real database RPCs and the two swappable external providers.
//
// Auth: admin/scheduler-only. Gated by a shared secret header (x-anchor-secret); deploy with
// --no-verify-jwt. Never exposed to browsers.
import { serviceClient } from "../_shared/supabase.ts";
import { json, error } from "../_shared/http.ts";
import { anchorOnce, type AnchorDeps } from "../_shared/anchor.ts";

// ---- swappable external anchor providers (same discipline as the payment provider) ----
const ANCHOR_PROVIDER = Deno.env.get("ANCHOR_PROVIDER") ?? "opentimestamps";
const MIRROR_PROVIDER = Deno.env.get("MIRROR_PROVIDER") ?? (Deno.env.get("MIRROR_URL") ? "http" : "none");

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}
function bytesToB64(b: Uint8Array): string {
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s);
}

// Witness 1 — OpenTimestamps: submit the 32-byte Merkle root to public Bitcoin calendars.
// Uses the opentimestamps library (we don't hand-roll the proof format). Swap providers via env.
async function stampRoot(rootHex: string): Promise<unknown> {
  if (ANCHOR_PROVIDER === "none") return { provider: "none", note: "external timestamping disabled" };
  if (ANCHOR_PROVIDER === "opentimestamps") {
    const mod: any = await import("npm:opentimestamps");
    const OpenTimestamps = mod.default ?? mod;
    const { DetachedTimestampFile, Ops } = OpenTimestamps;
    const detached = DetachedTimestampFile.fromHash(new Ops.OpSHA256(), hexToBytes(rootHex));
    await OpenTimestamps.stamp(detached); // submits to the default public calendars
    return {
      provider: "opentimestamps",
      proof_b64: bytesToB64(detached.serializeToBytes()),
      submitted_at: new Date().toISOString(),
    };
  }
  throw new Error(`Unknown ANCHOR_PROVIDER: ${ANCHOR_PROVIDER}`);
}

// Witness 2 — public append-only mirror: POST {batch_date, merkle_root} to a public log endpoint
// (MIRROR_URL), independent of Ilevest's database. Configure to a public transparency log / repo.
async function mirrorRoot(batchDate: string, rootHex: string): Promise<unknown> {
  if (MIRROR_PROVIDER === "none") return { provider: "none", note: "mirror disabled" };
  if (MIRROR_PROVIDER === "http") {
    const url = Deno.env.get("MIRROR_URL")!;
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ batch_date: batchDate, merkle_root: rootHex }),
    });
    return { provider: "http", url, status: res.status, mirrored_at: new Date().toISOString() };
  }
  throw new Error(`Unknown MIRROR_PROVIDER: ${MIRROR_PROVIDER}`);
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("ANCHOR_TRIGGER_SECRET") ?? "";
  if (!secret || req.headers.get("x-anchor-secret") !== secret) {
    return error("unauthorized", 401);
  }
  try {
    const sb = serviceClient();
    const deps: AnchorDeps = {
      anchorPending: async () => {
        const { data, error: e } = await sb.rpc("anchor_pending");
        if (e) throw e;
        return data;
      },
      stampRoot,
      mirrorRoot,
      recordProof: async (batch, ref) => {
        const { data, error: e } = await sb.rpc("record_anchor_proof", { p_batch: batch, p_anchor_ref: ref });
        if (e) throw e;
        return data;
      },
    };
    const summary = await anchorOnce(deps);
    return json(summary);
  } catch (e) {
    return error("anchoring failed", 500, String((e as Error)?.message ?? e));
  }
});
