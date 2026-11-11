// One retry policy for every portal call to an edge function.
// Measured 2 Nov 2026 (function_edge_logs, 24 h): 174 of 56,155 calls ended 5xx (0.31%), all clustered under
// our own load (18:00Z on; 0 in ~1,600 quiet-hour calls). A 546/502/503 carries no Access-Control-Allow-Origin,
// so the browser logs a CORS preflight failure (net::ERR_FAILED) and fetch() throws.
// Retry only READS: a thrown fetch cannot say whether the server already acted, so a write is never resent.
// The caller keeps its own region-pinned `await fetch(fnUrl(...), {...})` and hands it in as `send`.
const RETRY_STATUS = new Set([500, 502, 503, 504, 546]);
// Exact names only (each is a read: no prefix rule, so a future write named get_/list_ is never resent).
// 3 Nov 2026 (stage 2 run 4506ead8): one relay 502 on supplier_api's inquiries_list (10:36:25Z, Cloudflare's page, no worker ran)
// left the supplier's Inquiries tab on "Something went wrong" - the list was not a named read. inquiries_list / inquiry_detail /
// inquiry_documents (supplier_api quote_review_actions.ts) and me (supplier_api, customer_api) only select.
const READ_ACTIONS = new Set(['state', 'overview', 'dashboard', 'threads', 'thread', 'decision_support', 'my_inquiries', 'opportunities', 'insights',
  'inquiries_list', 'inquiry_detail', 'inquiry_documents', 'me']);
const actionOf = (body: unknown): string => (body && typeof body === 'object' ? String((body as any).action || '') : '');
export const isReadAction = (body: unknown): boolean => READ_ACTIONS.has(actionOf(body));

// A STALLED READ IS ASKED A SECOND TIME, NOT WAITED OUT (11 Nov 2026, it_engineer; founder ruling 1620: registration must
// not be laggy). Measured on production, kyc, 24 h to 16:30Z on 11 Nov: seven calls took 10.3-54.6 s at the edge
// (function_edge_logs.execution_time_ms), and in every one kyc's own handler ran 70-680 ms (agent_runs fn:kyc counts.ms) and
// made its first database call only in the last 0.4 s. The request had been received (its request_id is a UUIDv7 stamped at
// receipt) and sat on a warm isolate for the rest. In two of those windows the other kyc calls that arrived meanwhile were
// served by a freshly booted isolate in 0.6-0.75 s (10 Nov 19:58:23Z, 11 Nov 04:43:19Z and 04:43:28Z). Nothing in our code
// waits, so the client hedges: when a cheap read has no answer after HEDGE_MS, the same read goes out once more and the first
// answer is taken. Only the reads named here, which select a handful of rows and answer in well under a second on the server
// (kyc state p95 254 ms, max 754 ms, n 730; supplier_api me and supplier_portal dashboard p95 1.3-1.5 s at the edge, max
// 4.7-5.3 s); never a write, never a read that reasons (decision_support, insights, opportunities), so a duplicate costs a
// few selects and nothing else. The losing request is left to finish: it changes nothing.
// Prevented by: src/lib/fetchRetry.test.mjs (a stalled read is answered by its hedge).
export const HEDGE_MS = 4000;
const HEDGED_READS = new Set(['state', 'me', 'dashboard']);
export const isHedgedRead = (body: unknown): boolean => HEDGED_READS.has(actionOf(body));

/**
 * The answer of `send()`, or, when none has come after `hedgeMs`, the first good answer of it and one more `send()`.
 * A good answer is any status outside RETRY_STATUS. A failure while the other call is still out waits for that call; a
 * failure with nothing else out settles at once, so retryRead's own retries run exactly as without a hedge.
 */
export function hedge(send: () => Promise<Response>, hedgeMs: number): Promise<Response> {
  return new Promise((resolve, reject) => {
    let done = false; let out = 0;
    let held: { r: Response } | { e: unknown } | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const finish = (f: () => void) => { if (done) return; done = true; if (timer) clearTimeout(timer); f(); };
    const settleHeld = () => { const h = held; finish(() => (h && 'r' in h ? resolve(h.r) : reject(h ? h.e : new Error('no answer')))); };
    const go = () => {
      out++;
      let p: Promise<Response>;
      try { p = send(); } catch (e) { p = Promise.reject(e); }
      p.then((r) => {
        out--;
        if (!RETRY_STATUS.has(r.status)) return finish(() => resolve(r));
        held = { r };
        if (!out) settleHeld();
      }, (e) => {
        out--;
        if (!held || !('r' in held)) held = { e };
        if (!out) settleHeld();
      });
    };
    go();
    timer = setTimeout(() => { timer = null; if (!done) go(); }, hedgeMs);
  });
}

const sleep = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
/**
 * Run `send`; for a read, up to `retries` more tries (400 ms, then 1.2 s) on a throw or RETRY_STATUS. When `body` names a
 * hedged read (isHedgedRead), each try is hedged after HEDGE_MS (`hedgeMs` overrides it, for tests).
 */
export async function retryRead(send: () => Promise<Response>, read: boolean, retries = 2, aborted: () => boolean = () => false,
    body?: unknown, hedgeMs = HEDGE_MS): Promise<Response> {
  const once = read && hedgeMs > 0 && isHedgedRead(body) ? () => hedge(send, hedgeMs) : send;
  for (let i = 0; ; i++) {
    try {
      const r = await once();
      if (!read || i >= retries || !RETRY_STATUS.has(r.status)) return r;
    } catch (e) {
      if (!read || i >= retries || aborted()) throw e;
    }
    await sleep(400 * 3 ** i);
  }
}
