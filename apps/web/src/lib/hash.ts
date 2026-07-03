// Browser-side SHA-256 (WebCrypto), lowercase hex — the client half of the
// evidence discipline: the browser fingerprints what it captures, the database
// re-derives and enforces (findings), and the sealed canon covers the result.
// No dependencies; WebCrypto is available in every modern browser over HTTPS.

export async function sha256HexOfFile(file: Blob): Promise<string> {
  const buf = await file.arrayBuffer();
  return sha256HexOfBuffer(buf);
}

export async function sha256HexOfText(text: string): Promise<string> {
  const buf = new TextEncoder().encode(text);
  return sha256HexOfBuffer(buf);
}

async function sha256HexOfBuffer(buf: ArrayBuffer | Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", buf as ArrayBuffer);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export const shortHash = (h: string | null | undefined) =>
  h ? `${h.slice(0, 12)}…` : "";
