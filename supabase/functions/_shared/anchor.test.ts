// Offline test of the anchor orchestration control flow (no network, no Deno).
// Run with: node --experimental-strip-types supabase/functions/_shared/anchor.test.ts
import { anchorOnce, type AnchorDeps } from "./anchor.ts";

let passed = 0;
function ok(cond: boolean, msg: string) {
  if (!cond) throw new Error("FAIL: " + msg);
  console.log("PASS: " + msg);
  passed++;
}

function makeDeps(pending: any) {
  const calls = { stamp: 0, mirror: 0, record: 0 };
  let recordedRef: unknown = null;
  const deps: AnchorDeps = {
    anchorPending: async () => pending,
    stampRoot: async (r) => { calls.stamp++; return { provider: "test-ots", root: r }; },
    mirrorRoot: async (d, r) => { calls.mirror++; return { provider: "test-mirror", date: d, root: r }; },
    recordProof: async (_b, ref) => { calls.record++; recordedRef = ref; return { ok: true }; },
  };
  return { deps, calls, getRef: () => recordedRef };
}

// 1) a real batch -> both witnesses submitted, proof recorded
{
  const { deps, calls, getRef } = makeDeps({
    anchored: true, batch_id: "b1", batch_date: "2026-06-23",
    merkle_root: "ab".repeat(32), checks_anchored: 3,
  });
  const s = await anchorOnce(deps);
  ok(s.anchored === true, "an anchored batch is processed");
  ok(calls.stamp === 1 && calls.mirror === 1, "both independent witnesses (OpenTimestamps + mirror) are submitted");
  ok(calls.record === 1 && s.proof_recorded === true, "the combined proof is written back to the batch once");
  ok(s.checks_anchored === 3 && s.merkle_root === "ab".repeat(32), "the summary carries the root and the count");
  const ref: any = getRef();
  ok(ref && ref.ots && ref.mirror, "the recorded reference holds BOTH the OTS and the mirror proof");
}

// 2) nothing pending -> no external submission at all
{
  const { deps, calls } = makeDeps({ anchored: false, reason: "nothing pending" });
  const s = await anchorOnce(deps);
  ok(s.anchored === false, "no batch -> not anchored");
  ok(calls.stamp === 0 && calls.mirror === 0 && calls.record === 0, "nothing is submitted or recorded when there is nothing pending");
}

// 3) a failed proof write is reported honestly (not swallowed)
{
  const { deps } = makeDeps({
    anchored: true, batch_id: "b2", batch_date: "2026-06-23",
    merkle_root: "cd".repeat(32), checks_anchored: 1,
  });
  deps.recordProof = async () => ({ ok: false });
  const s = await anchorOnce(deps);
  ok(s.anchored === true && s.proof_recorded === false, "a failed proof-record surfaces as proof_recorded=false");
}

console.log(`\n${passed} passed, 0 failed`);
console.log("ALL ANCHOR ORCHESTRATION ASSERTIONS PASSED");
