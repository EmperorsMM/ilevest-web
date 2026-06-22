import { corsHeaders } from "./cors.ts";

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function error(message: string, status = 400, detail?: string): Response {
  return json(detail ? { error: message, detail } : { error: message }, status);
}

// Map a Postgres/PostgREST error code to the HTTP status the contract promises.
export function statusForDbError(code?: string): number {
  switch (code) {
    case "42501": return 403;               // RLS / insufficient privilege
    case "23514": return 403;               // check_violation (role / state-machine gate)
    case "P0001": return 403;               // raised exception (function guards)
    case "no_data_found":
    case "PGRST116": return 404;            // not found / no matching row
    default: return 400;
  }
}

// Pull a resource id from the path (the segment before `tail`, e.g. .../checks/{id}/seal) or,
// failing that, a body field. Lets a function work behind a REST gateway or when called
// directly with the id in the body.
export function resourceId(req: Request, tail: string, bodyVal?: string): string | undefined {
  const segs = new URL(req.url).pathname.split("/").filter(Boolean);
  const i = segs.lastIndexOf(tail);
  if (i > 0) return segs[i - 1];
  return bodyVal;
}
