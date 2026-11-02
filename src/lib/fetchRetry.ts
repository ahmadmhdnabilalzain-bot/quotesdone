// One retry policy for every portal call to an edge function.
// Measured 2 Nov 2026 (function_edge_logs, 24 h): 174 of 56,155 calls ended 5xx (0.31%), all clustered under
// our own load (18:00Z on; 0 in ~1,600 quiet-hour calls). A 546/502/503 carries no Access-Control-Allow-Origin,
// so the browser logs a CORS preflight failure (net::ERR_FAILED) and fetch() throws.
// Retry only READS: a thrown fetch cannot say whether the server already acted, so a write is never resent.
// The caller keeps its own region-pinned `await fetch(fnUrl(...), {...})` and hands it in as `send`.
const RETRY_STATUS = new Set([500, 502, 503, 504, 546]);
// Exact names only (each is a read: no prefix rule, so a future write named get_/list_ is never resent).
const READ_ACTIONS = new Set(['state', 'overview', 'dashboard', 'threads', 'thread', 'decision_support', 'my_inquiries', 'opportunities', 'insights']);
export const isReadAction = (body: unknown): boolean =>
  READ_ACTIONS.has(body && typeof body === 'object' ? String((body as any).action || '') : '');
const sleep = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
/** Run `send`; for a read, up to `retries` more tries (400 ms, then 1.2 s) on a throw or RETRY_STATUS. */
export async function retryRead(send: () => Promise<Response>, read: boolean, retries = 2, aborted: () => boolean = () => false): Promise<Response> {
  for (let i = 0; ; i++) {
    try {
      const r = await send();
      if (!read || i >= retries || !RETRY_STATUS.has(r.status)) return r;
    } catch (e) {
      if (!read || i >= retries || aborted()) throw e;
    }
    await sleep(400 * 3 ** i);
  }
}
