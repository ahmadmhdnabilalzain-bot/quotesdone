// One retry policy for every portal call to an edge function.
// Measured 2 Nov 2026 (function_edge_logs, 24 h): 174 of 56,155 calls ended 5xx (0.31%), all clustered under
// our own load (18:00Z on; 0 in ~1,600 quiet-hour calls). A 546/502/503 carries no Access-Control-Allow-Origin,
// so the browser logs a CORS preflight failure (net::ERR_FAILED) and fetch() throws.
// Retry only READS: a thrown fetch cannot say whether the server already acted, so a write is never resent.
const RETRY_STATUS = new Set([500, 502, 503, 504, 546]);
const READ_EXACT = new Set(['state', 'overview', 'dashboard', 'threads', 'thread', 'decision_support', 'summary', 'status']);
export const isReadAction = (body: unknown): boolean => {
  const a = body && typeof body === 'object' ? String((body as any).action || '') : '';
  return READ_EXACT.has(a) || /^(get_|list_|my_)/.test(a);
};
const sleep = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
/** fetch(), and for a read: up to `retries` more tries (400 ms, then 1.2 s) on a throw or RETRY_STATUS. */
export async function fetchRetry(url: string, init: RequestInit, read: boolean, retries = 2): Promise<Response> {
  for (let i = 0; ; i++) {
    try {
      const r = await fetch(url, init);
      if (!read || i >= retries || !RETRY_STATUS.has(r.status)) return r;
    } catch (e) {
      if (!read || i >= retries || (init.signal && init.signal.aborted)) throw e;
    }
    await sleep(400 * 3 ** i);
  }
}
