// Server Supabase client (RSC / route handlers). Still uses the anon key so that
// Row-Level Security applies to the signed-in user. The SERVICE ROLE key is reserved
// for narrow, audited server tasks only and must never be the default path.
// Starting stub — verify the API against the installed @supabase/ssr version.
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export function createSupabaseServerClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (toSet) => {
          try {
            toSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Called from a Server Component without a writable cookie store — safe to ignore.
          }
        },
      },
    },
  );
}
