export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-paystack-signature",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function preflight(req: Request): Response | null {
  return req.method === "OPTIONS" ? new Response("ok", { headers: corsHeaders }) : null;
}
