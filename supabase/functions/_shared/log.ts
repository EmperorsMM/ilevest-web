// Structured logging for edge functions. One-line JSON, captured by Supabase's
// function logs. Gives every critical path a greppable success/failure signal
// with context — so a silent webhook or a failed nightly anchor is VISIBLE
// instead of vanishing. Mirrors the app-side monitoring shape.

type Level = "error" | "warn" | "info";

export function log(level: Level, fn: string, event: string, context?: Record<string, unknown>) {
  const line = JSON.stringify({
    level,
    fn,             // which function
    event,          // what happened (e.g. "payment_confirmed", "anchor_failed")
    at: new Date().toISOString(),
    ...(context ? { context } : {}),
  });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

// Convenience wrappers.
export const logInfo = (fn: string, event: string, ctx?: Record<string, unknown>) => log("info", fn, event, ctx);
export const logWarn = (fn: string, event: string, ctx?: Record<string, unknown>) => log("warn", fn, event, ctx);
export const logError = (fn: string, event: string, ctx?: Record<string, unknown>) => log("error", fn, event, ctx);
