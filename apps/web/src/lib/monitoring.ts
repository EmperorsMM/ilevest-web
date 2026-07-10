// Vendor-agnostic error + event reporting.
//
// Today this logs structured JSON to the console (captured by Vercel's log
// drains and the platform log view). When a monitoring DSN is configured
// (NEXT_PUBLIC_SENTRY_DSN or SENTRY_DSN), a thin adapter can forward these same
// calls to the vendor without changing any call sites. The point: error capture
// works NOW, and turning on a vendor later is a one-place change, not a rewrite.

type Level = "error" | "warn" | "info";

interface ReportContext {
  [key: string]: unknown;
}

function emit(level: Level, message: string, context?: ReportContext) {
  const record = {
    level,
    message,
    at: new Date().toISOString(),
    ...(context ? { context } : {}),
  };
  // Structured single-line JSON — greppable in Vercel logs / any drain.
  const line = JSON.stringify(record);
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);

  // Vendor hook (no-op until configured). Kept intentionally minimal so adding
  // Sentry later means implementing this one function.
  forwardToVendor(level, message, context);
}

function forwardToVendor(_level: Level, _message: string, _context?: ReportContext) {
  // Intentionally empty. When a DSN is configured, forward here, e.g.:
  //   Sentry.captureMessage(_message, { level: _level, extra: _context });
  // Left as a seam so call sites never change.
}

export function reportError(error: unknown, context?: ReportContext) {
  const message = error instanceof Error ? error.message : String(error);
  const stack = error instanceof Error ? error.stack : undefined;
  emit("error", message, { ...context, ...(stack ? { stack } : {}) });
}

export function reportWarning(message: string, context?: ReportContext) {
  emit("warn", message, context);
}

export function reportEvent(message: string, context?: ReportContext) {
  emit("info", message, context);
}
