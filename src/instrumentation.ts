// The website tells the estate when it throws (22 Sep 2026, it_engineer, SEATS-06).
//
// The IT engineer's tick reported the website's runtime errors as "NOT checked" because no Vercel
// REST endpoint serves them to the stored token — measured this morning, eight candidate paths, all
// 404 (see supabase/functions/site_error_ingest/index.ts for the list). `onRequestError` is
// Next.js's own hook for every uncaught server error, so the site reports itself instead of being
// polled, and the reading stops being a permanent blank.
//
// NEVER LET REPORTING BREAK THE THING IT WATCHES: every post is fire-and-forget with a 3 s timeout
// and its own failure swallowed. A page that already failed must not fail twice.
//
// register() posts one 'site_report_ready' per cold start. That heartbeat is what lets the tick
// tell "the site is healthy" from "nobody is reporting": with no heartbeat in 24 h the reading is
// reported as unavailable rather than as zero errors.

const INGEST = (process.env.NEXT_PUBLIC_SUPABASE_URL || '') + '/functions/v1/site_error_ingest';

function post(body: Record<string, unknown>): void {
  const secret = process.env.SITE_ERROR_INGEST_SECRET;
  if (!secret || !process.env.NEXT_PUBLIC_SUPABASE_URL) return;
  try {
    void fetch(INGEST, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-qd-site-secret': secret },
      body: JSON.stringify({
        ...body,
        env: process.env.VERCEL_ENV || 'unknown',
        deployment: process.env.VERCEL_DEPLOYMENT_ID || null,
      }),
      signal: AbortSignal.timeout(3000),
    }).catch(() => {});
  } catch { /* reporting never throws */ }
}

export function register(): void {
  post({ kind: 'site_report_ready' });
}

export function onRequestError(
  err: unknown,
  request: { path?: string; method?: string },
  context: { routePath?: string; renderSource?: string },
): void {
  const e = err as { message?: string; digest?: string } | undefined;
  post({
    kind: 'runtime_error',
    message: String(e?.message || err || 'unknown error'),
    route: context?.routePath || null,
    path: request?.path || null,
    digest: e?.digest || null,
    render_source: context?.renderSource || null,
  });
}
