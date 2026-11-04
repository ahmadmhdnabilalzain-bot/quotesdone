// AN ANSWER THE PLATFORM GAVE BEFORE ANY OF OUR CODE RAN (it_engineer, 2 Nov 2026).
//
// Measured on production, function_edge_logs, 1-2 Nov 2026 (24 h): 127 HTTP 502s were Cloudflare's own text/html error
// page with no `x-served-by` header, no execution_id and no deployment_id - the request never reached a worker. 92 of the
// 166 platform 502/503s fell in the first 10 s of a five-minute mark (3,023 requests, a 3.0% failure rate) against 74 in
// the other 78,308 requests (0.09%): the cron fan-out burst, not one of our deploys (no deploy between 05:15 and the
// 07:00-07:30 bursts). A worker that ran always answers with `x-served-by: supabase-edge-runtime`, a 546 included.
//
// So a 502/503/521/522/523 WITHOUT that header did nothing: nothing was routed, written or sent, and asking once more is
// safe for any call. 504, 520 and 524 are left out on purpose: they are timeouts or a broken answer after the origin may
// already have acted (07:02Z: ai_gateway 520 after 39.8 s of work). prevented by: _shared/not_reached.test.ts
export const RUNTIME = 'supabase-edge-runtime';
const RELAY_REFUSED = new Set([502, 503, 521, 522, 523]);

/** True when the edge runtime never served this request, so retrying it cannot repeat any work. */
export function platformRefused(status: number, servedBy: string | null | undefined): boolean {
  return RELAY_REFUSED.has(status) && String(servedBy || '').toLowerCase() !== RUNTIME;
}

/** The same test on a Response. */
export const notReached = (r: Response): boolean => platformRefused(r.status, r.headers.get('x-served-by'));
