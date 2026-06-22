// Paystack webhook signature verification.
// Paystack signs the RAW request body with HMAC SHA-512 keyed by your SECRET key and sends the
// hex digest in the `x-paystack-signature` header. We recompute it and compare in constant time.
// Implemented with Web Crypto so the code is byte-for-byte identical under Deno (the Edge
// runtime) and Node (where it is unit-tested). No external dependencies.

const encoder = new TextEncoder();

function toHex(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let out = "";
  for (let i = 0; i < bytes.length; i++) out += bytes[i].toString(16).padStart(2, "0");
  return out;
}

// Length-independent constant-time compare to avoid leaking how much of the signature matched.
function timingSafeEqual(a: string, b: string): boolean {
  const len = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let i = 0; i < len; i++) diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}

export async function computeSignature(rawBody: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-512" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
  return toHex(sig);
}

export async function verifyPaystackSignature(
  rawBody: string, signature: string | null | undefined, secret: string,
): Promise<boolean> {
  if (!signature || !secret) return false;
  const expected = await computeSignature(rawBody, secret);
  return timingSafeEqual(expected.toLowerCase(), signature.trim().toLowerCase());
}
