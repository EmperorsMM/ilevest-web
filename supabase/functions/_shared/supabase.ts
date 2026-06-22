import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Acts AS THE CALLER: forwards their JWT so the database sees the real user and row-level
// security + the state-machine gates apply. Use for staff/worker actions.
export function userClient(req: Request): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
      auth: { persistSession: false },
    },
  );
}

// Privileged client that bypasses row-level security. Use ONLY for verified system actions
// (the payment webhook). Its key must never reach the browser.
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

// Public client for unauthenticated reads (certificate verification).
export function anonClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { auth: { persistSession: false } },
  );
}
