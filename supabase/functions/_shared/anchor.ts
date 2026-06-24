// Anchor orchestration — PURE and dependency-injected, so the control flow is unit-testable
// offline (no Deno, no network, no Supabase import here). The Edge handler wires the real
// database calls and the external providers into these injection points.
//
// Flow: ask the database to anchor the day's pending fingerprints (one atomic batch + root);
// if something was anchored, submit that root to the two independent external witnesses
// (OpenTimestamps + the public mirror) and write the proof reference back to the batch (once).

export interface AnchorPendingResult {
  anchored: boolean;
  reason?: string;
  batch_id?: string;
  batch_date?: string;
  merkle_root?: string;
  checks_anchored?: number;
}

export interface AnchorDeps {
  anchorPending: () => Promise<AnchorPendingResult>;
  stampRoot: (rootHex: string) => Promise<unknown>;            // OpenTimestamps (Bitcoin calendars)
  mirrorRoot: (batchDate: string, rootHex: string) => Promise<unknown>;  // public append-only mirror
  recordProof: (batchId: string, ref: unknown) => Promise<{ ok: boolean }>;
}

export interface AnchorSummary {
  anchored: boolean;
  reason?: string;
  batch_id?: string;
  batch_date?: string;
  merkle_root?: string;
  checks_anchored?: number;
  proof_recorded?: boolean;
}

export async function anchorOnce(deps: AnchorDeps): Promise<AnchorSummary> {
  const pending = await deps.anchorPending();
  if (!pending.anchored) {
    return { anchored: false, reason: pending.reason ?? "nothing to anchor" };
  }

  const root = pending.merkle_root as string;
  // Two independent witnesses, submitted together; neither is controlled by Ilevest.
  const [ots, mirror] = await Promise.all([
    deps.stampRoot(root),
    deps.mirrorRoot(pending.batch_date as string, root),
  ]);

  const rec = await deps.recordProof(pending.batch_id as string, { ots, mirror });

  return {
    anchored: true,
    batch_id: pending.batch_id,
    batch_date: pending.batch_date,
    merkle_root: root,
    checks_anchored: pending.checks_anchored ?? 0,
    proof_recorded: rec.ok,
  };
}
