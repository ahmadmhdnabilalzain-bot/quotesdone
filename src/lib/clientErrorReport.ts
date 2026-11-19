// What a browser tells the estate when a page crashes (launch checklist item, 19 Nov 2026, it_engineer).
//
// src/instrumentation.ts reports SERVER errors. A crash that happens in the visitor's browser (a render
// error caught by error.tsx or global-error.tsx) never reached the server, so it was invisible: the
// visitor saw the error page and the estate saw nothing. The two boundaries call reportClientError();
// it posts to /api/client-error, which rate-limits per IP and forwards to the site_error_ingest edge
// function (the same table, error_events, the same reading the IT engineer's tick already takes).
//
// WHAT IS SENT, AND WHAT IS NEVER SENT. Only: the error message, its digest, the page path and the
// user-agent string. The path is cut at "?" and "#" because a query string or fragment can carry a
// magic-link token or an email; the message has email addresses, long digit runs (phone numbers, ids)
// and token-shaped strings blanked out, because an error text can echo user input. No cookie, no
// header, no request or response body, no user id is read here or on the server.
//
// Pure functions are exported so scripts can test them without a browser (clientErrorReport.test.mjs).

export type ClientErrorReport = { message: string; digest: string | null; path: string; user_agent: string };

const EMAIL = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const DIGITS = /\d{7,}/g;
const TOKENISH = /\b[A-Za-z0-9_-]{32,}\b/g;

export function scrubText(v: unknown, max: number): string {
  return String(v ?? '').replace(EMAIL, '[email]').replace(TOKENISH, '[token]').replace(DIGITS, '[number]').slice(0, max);
}

/** The path only: no query string, no fragment, no host. */
export function cleanPath(v: unknown): string {
  const raw = String(v ?? '');
  let p = raw;
  try { if (/^https?:\/\//i.test(raw)) p = new URL(raw).pathname; } catch { p = raw; }
  p = p.split('#')[0].split('?')[0];
  return scrubText(p, 200) || '/';
}

/** The one shape both the browser and the route build, so the route never trusts the browser's cleaning. */
export function cleanReport(b: unknown): ClientErrorReport | null {
  const o = (b && typeof b === 'object' ? b : null) as Record<string, unknown> | null;
  if (!o) return null;
  const message = scrubText(o.message, 300);
  if (!message) return null;
  const digest = o.digest == null || o.digest === '' ? null : String(o.digest).replace(/[^A-Za-z0-9_-]/g, '').slice(0, 40) || null;
  return { message, digest, path: cleanPath(o.path), user_agent: String(o.user_agent ?? '').replace(/[\r\n]/g, ' ').slice(0, 200) };
}

/** Browser side: fire-and-forget, never throws, never blocks the error page. */
export function reportClientError(error: { message?: string; digest?: string } | undefined): void {
  try {
    if (typeof window === 'undefined') return;
    const body = JSON.stringify({
      message: String(error?.message || 'unknown error'),
      digest: error?.digest || null,
      path: window.location.pathname,
      user_agent: navigator.userAgent,
    });
    const blob = new Blob([body], { type: 'application/json' });
    if (navigator.sendBeacon && navigator.sendBeacon('/api/client-error', blob)) return;
    void fetch('/api/client-error', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body, keepalive: true, credentials: 'omit' }).catch(() => {});
  } catch { /* reporting never throws */ }
}
