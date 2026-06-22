// Payment-provider abstraction. Ruling 2: Paystack now, swappable without touching the
// workflow. To swap to Flutterwave later, implement its branch here + its signature function;
// nothing downstream changes.
import { verifyPaystackSignature } from "./paystack.ts";

export type Provider = "paystack" | "flutterwave";

export const ACTIVE_PROVIDER: Provider =
  (Deno.env.get("PAYMENT_PROVIDER") as Provider) ?? "paystack";

export async function verifyWebhook(provider: Provider, rawBody: string, headers: Headers): Promise<boolean> {
  switch (provider) {
    case "paystack": {
      const secret = Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";
      return await verifyPaystackSignature(rawBody, headers.get("x-paystack-signature"), secret);
    }
    case "flutterwave":
      // Future swap: Flutterwave sends a `verif-hash` header compared to a configured secret.
      throw new Error("Flutterwave webhook verification not yet implemented");
    default:
      throw new Error(`Unknown payment provider: ${provider}`);
  }
}

// Pull the order id + reference out of a provider's event, and whether it is a successful charge.
export function extractCharge(provider: Provider, event: any): { orderId?: string; reference?: string; success: boolean } {
  if (provider === "paystack") {
    return {
      success: event?.event === "charge.success",
      reference: event?.data?.reference,
      orderId: event?.data?.metadata?.order_id,
    };
  }
  return { success: false };
}
