// Unit test for Paystack webhook signature verification — the one piece of pure security logic
// in the Edge layer. Runs under Node (node --experimental-strip-types) and Deno (deno run).
// It imports the REAL module and checks it against an INDEPENDENT reference signature computed
// exactly the way Paystack computes it server-side (HMAC SHA-512 of the raw body, hex).
import crypto from "node:crypto";
import { computeSignature, verifyPaystackSignature } from "./paystack.ts";

let passed = 0;
const failures: string[] = [];
function check(name: string, cond: boolean): void {
  if (cond) { passed++; console.log("PASS:", name); }
  else { failures.push(name); console.error("FAIL:", name); }
}

const secret = "sk_test_0123456789abcdef";
const body = JSON.stringify({
  event: "charge.success",
  data: { reference: "T123456", metadata: { order_id: "cc000000-0000-0000-0000-000000000001" } },
});

// Independent reference — what Paystack's servers send in x-paystack-signature.
const reference = crypto.createHmac("sha512", secret).update(body).digest("hex");

check("HMAC is SHA-512 (128 hex chars)", reference.length === 128);
check("computeSignature matches the canonical HMAC-SHA512", (await computeSignature(body, secret)) === reference);
check("valid signature is accepted", await verifyPaystackSignature(body, reference, secret));
check("uppercase signature still accepted (hex is case-insensitive)", await verifyPaystackSignature(body, reference.toUpperCase(), secret));
const tampered = reference.slice(0, -1) + (reference.endsWith("0") ? "1" : "0");
check("tampered signature is rejected", !(await verifyPaystackSignature(body, tampered, secret)));
check("tampered body is rejected", !(await verifyPaystackSignature(body + " ", reference, secret)));
check("missing signature is rejected", !(await verifyPaystackSignature(body, null, secret)));
check("empty secret is rejected", !(await verifyPaystackSignature(body, reference, "")));
check("wrong secret is rejected", !(await verifyPaystackSignature(body, reference, "sk_test_wrong")));

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length > 0) throw new Error("signature test failures: " + failures.join("; "));
console.log("ALL PAYSTACK SIGNATURE ASSERTIONS PASSED");
