'use client';
// 'use client' IS LOAD-BEARING SINCE callShared BELOW HOLDS MODULE-LEVEL STATE. Every importer of
// this file is already a client component, so its in-flight Map is one per browser tab. Without this
// directive nothing STOPS a future Server Component or Route Handler from importing `call` from
// here "conveniently", and that Map would then become a singleton in the Node process, shared and
// unbounded across concurrent requests from different suppliers. The directive makes such an import
// fail at the boundary instead of silently leaking.
//
// The one fetch helper for the supplier portal's edge-function calls. It lived inline in
// SupplierPortal.tsx; the RFQ, journey and insights components split out on 14 Sep 2026 need the same
// call, and a second copy is how two error-handling behaviours start.
//
// `_http` carries the status of a non-2xx answer (14 Sep 2026). The body alone cannot tell an expired
// session from a refusal — the gateway's "Invalid JWT" and a function's own 401 look different — so
// the portal could only show "Something went wrong" and a retry that could never succeed.
import { SUPA_ANON as ANON, fnUrl } from '@/lib/supaEnv';
import { retryRead, isReadAction } from '@/lib/fetchRetry';

/**
 * ONE IN-FLIGHT READ, SHARED BY EVERY CALLER THAT ASKS FOR IT AT THE SAME TIME.
 *
 * MEASURED 18 Sep 2026 on production, opening the supplier's Insights tab: `supplier_portal`'s
 * `opportunities` action was fetched TWICE, concurrently, every single time — SupplierOpportunities
 * and SupplierQuoteBuilder are both `parts` of the one `recommended` panel (Insights.tsx) and each
 * fetched the identical payload for itself. The two contended: 683 ms and 1375 ms on the same open,
 * and that 1375 ms was the tail the whole tab's busy state waited on.
 *
 * WHY NOT INSIDE `call()`. `call()` carries writes as well as reads — `save_settings`, `approve`,
 * `submit`. De-duplicating a POST that CHANGES something would silently drop the second one, so
 * this is a separate door and the actions allowed through it are named here, one by one, and must
 * be idempotent reads.
 *
 * The window is deliberately short: entries are dropped as soon as the fetch settles, so this
 * shares a flight in progress and caches NOTHING. A later open re-reads, and a refresh after a
 * write still sees the new value — the failure mode of a real cache (a stale panel after saving)
 * cannot happen here.
 */
const SHAREABLE_READS = new Set(['opportunities']);
const inFlight = new Map<string, Promise<any>>();

export function callShared(path: string, body: Record<string, unknown>, token?: string | null): Promise<any> {
  const action = String(body.action ?? '');
  if (!SHAREABLE_READS.has(action) || Object.keys(body).length !== 1) return call(path, body, token);
  const key = `${path}:${action}:${token || 'anon'}`;
  const live = inFlight.get(key);
  if (live) return live;
  const p = call(path, body, token).finally(() => { inFlight.delete(key); });
  inFlight.set(key, p);
  return p;
}

/**
 * EVERY FAILURE MODE ARRIVES AS AN OBJECT, NEVER AS A THROW (22 Sep 2026, audit SP-C-05/SP-I-01).
 *
 * Twelve panels had each written their own `call` whose whole body was `return r.json()`. Seven of
 * them (MarketIntelligence, ProductIntelligence, SupplierAdvisor, SupplierDocumentImpact,
 * SupplierInventory, SupplierKnowledgeGraph, SupplierTwin) then did `.then(j => …)` with no
 * `.catch`: a gateway 502 whose body is HTML, or a dropped connection, rejected the promise, the
 * component's state was never written, and the panel sat on "Loading…" for as long as the supplier
 * left it open. This helper resolves — never rejects — so `if (j.ok)` / `else` is the whole
 * contract, and the `else` branch always has something to say.
 *
 * `code` is what the UI renders (translated by supplier/PanelState); `error` is the server's own
 * English, kept as a fallback for a code no client knows yet. A 500's `error` is NOT shown: since
 * 22 Sep supplier_portal returns `code: 'load_failed'` and keeps the Postgres message on the server.
 *
 * `_expired` is set on ANY 401 — the gateway's `UNAUTHORIZED_INVALID_JWT_FORMAT` and a function's
 * own refusal look nothing alike in the body, and only the status tells them apart. Before this,
 * only the dashboard read `_http === 401`; Projects, Receipts and RfqParts rendered an empty tab.
 *
 * TIMEOUT: a Supabase edge function is killed at its own wall clock, but a request that never gets
 * a response back (captive portal, dead mobile leg) hangs the panel forever. 20s, then `timeout`.
 */
const TIMEOUT_MS = 20000;

/**
 * AN ACTION THAT READS BY REASONING WAITS FOR ITS ANSWER (27 Oct 2026, it_engineer; supplier registration walk on
 * production). services_save_rewrite resolves each of the supplier's own words by reasoning (supplier_services.ts
 * resolveText -> tradeOfWords: a plan call and an answer call per word, the words in parallel). Measured on a ZZ DEMO
 * supplier with three own words: 36,959 ms, HTTP 200, capability confirmed. The portal had aborted at 20 s and told
 * him "Could not save your services." — a save that succeeded, reported as failed. The rewrite preview can reason the
 * same way. These two wait REASONING_TIMEOUT_MS; every other call keeps 20 s.
 * Guard: scripts/checks/a_services_save_that_reasons_is_not_cut_off_by_the_portal.test.mjs
 */
export const REASONING_TIMEOUT_MS = 90000;

/**
 * THE NEXT CALL'S PREFLIGHT IS PAID WHILE THE SUPPLIER IS ALREADY WAITING (15 Nov 2026, customer_support; the code e-mail to the
 * registration form measured 3,026 and 3,078 ms against 3,000, from the US container).
 *
 * Every call() is a cross-origin POST with Authorization and Content-Type: application/json, so the browser first sends an
 * OPTIONS preflight to that function and waits for it, a full round trip to ap-southeast-1, before the POST leaves. Without
 * Access-Control-Max-Age a preflight is remembered for 5 seconds (the Fetch standard's default), so the first supplier_api call
 * after sign-in, create_company, always paid one on the step's critical path. This sends the same request shape (the same URL,
 * method and header names, so its preflight is the one create_company needs) with the anonymous key and
 * {"action":"warm"}, which supplier_api answers 204 before the sign-in check or any database read (lib/door.ts warmOnly). Fired
 * beside the code check, the preflight lands while login_otp is still answering. Best effort: nothing waits on it, and a failure
 * changes nothing. An older supplier_api answers it 401 at the sign-in check; the preflight is paid all the same.
 * Prevented by: scripts/checks/the_registration_does_not_wait_on_a_preflight.test.mjs
 */
export function preflightNow(path: string): void {
  try {
    void fetch(fnUrl(path), { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + ANON }, body: '{"action":"warm"}' })
      .then((r) => r.body?.cancel(), () => undefined).catch(() => undefined);
  } catch (_e) { /* best effort: the call itself pays the preflight as before */ }
}

export async function call(path: string, body: Record<string, unknown>, token?: string | null, opts: { timeoutMs?: number } = {}): Promise<any> {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), opts.timeoutMs && opts.timeoutMs > 0 ? opts.timeoutMs : TIMEOUT_MS);
  let r: Response;
  try {
    r = await retryRead(async () => await fetch(fnUrl(path), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
      body: JSON.stringify(body),
      signal: ac.signal,
    }), isReadAction(body), 2, () => ac.signal.aborted, body); // reads only: a write is never resent; a cheap read is hedged (fetchRetry HEDGE_MS)
  } catch (_e) {
    return { ok: false, code: ac.signal.aborted ? 'timeout' : 'network' };
  } finally {
    clearTimeout(timer);
  }
  const text = await r.text().catch(() => '');
  let j: any = null;
  try { j = JSON.parse(text); } catch (_e) { j = null; }
  if (!j || typeof j !== 'object') return { ok: false, code: platformCode(r.status) || 'bad_response', _http: r.status };
  if (!r.ok) {
    // The platform's own failure, never its text (see platformCode).
    if (!ownCode(j.code) && platformCode(r.status)) return { ok: false, code: platformCode(r.status), _http: r.status };
    j._http = r.status;
    // A DEAD SESSION IS NEVER "Invalid JWT" (12 Nov 2026, customer_support; browser walk M7). The gateway answers an expired token
    // 401 {"code":"UNAUTHORIZED_LEGACY_JWT","message":"Invalid JWT"} (probed on production), and srvMsg showed its message. A 401
    // without one of OUR codes is session_expired, which has our own sentence; callFresh below refreshes and asks once more.
    if (r.status === 401) { j._expired = true; if (!ownCode(j.code)) j.code = 'session_expired'; }
    // A REFUSAL THAT SAYS WHY KEEPS ITS WORDS (12 Nov 2026, customer_support; browser walk M1). A .docx licence was refused by
    // supplier_api with error 'file_type_not_allowed' and the sentence "That licence file cannot be accepted. Please upload a PDF
    // or a clear photo (JPEG or PNG)…" and no `code`; this gave it load_failed, which srvMsg prefers, so he read "Could not load
    // this section. Please try again." Only an answer with neither a code nor a sentence is load_failed now.
    if (!j.code && !j.message) j.code = 'load_failed';
  }
  return j;
}

/**
 * ONE MORE TRY WITH A FRESH SIGN-IN (12 Nov 2026, customer_support; browser walk M7: a dead session at Submit showed "Invalid
 * JWT"). A 401 is the gateway refusing the token before the function runs, so nothing was done and asking again cannot do a
 * thing twice. The stored refresh token is exchanged once (supabase-js's own session first, the portal's copy of the refresh
 * token second); the portal's onAuthStateChange then carries the new token to every panel. `token` is the one now in use.
 */
export async function freshToken(): Promise<string | null> {
  try {
    const { supaClient } = await import('@/lib/supaClient');
    const auth = supaClient('qd-portal-auth').auth;
    let { data } = await auth.refreshSession();
    if (!data?.session?.access_token) {
      let rt = ''; try { rt = localStorage.getItem('qd-sup-refresh') || ''; } catch (_e) { rt = ''; }
      if (rt) ({ data } = await auth.refreshSession({ refresh_token: rt }));
    }
    const s = data?.session;
    if (!s?.access_token) return null;
    try { localStorage.setItem('qd-sup-token', s.access_token); if (s.refresh_token) localStorage.setItem('qd-sup-refresh', s.refresh_token); } catch (_e) { /* kept in memory only */ }
    return s.access_token;
  } catch (_e) { return null; }
}
export async function callFresh(path: string, body: Record<string, unknown>, token: string, opts: { timeoutMs?: number } = {},
  refresh: () => Promise<string | null> = freshToken): Promise<{ j: any; token: string }> {
  const j = await call(path, body, token, opts);
  if (!(j && j._expired)) return { j, token };
  const t = await refresh();
  if (!t) return { j, token };
  return { j: await call(path, body, t, opts), token: t };
}

/**
 * A PLATFORM FAILURE IS NEVER A SENTENCE FOR A SUPPLIER (28 Oct 2026, sales_engineer; production document walk 4e9d675a).
 *
 * A 24 MB trade licence on the Documents tab ended supplier_portal at the edge's CPU cap, and the platform's own answer,
 * HTTP 546 with code WORKER_RESOURCE_LIMIT, reached the screen word for word ("Function failed due to not having enough
 * compute resources (please check logs)"): srvMsg shows an unknown code's `message` to an English reader. Our functions'
 * codes are lower-case snake_case (load_failed, upload_failed, quote_read_failed); the platform's are UPPER_CASE
 * (WORKER_RESOURCE_LIMIT, BOOT_ERROR) or absent, and a gateway 502/504 is not JSON at all. A 5xx (or a 413) that does
 * not carry one of OUR codes is replaced by our own code, so its text is never passed on; our own 5xx keep theirs.
 * Guard: scripts/checks/a_supplier_never_reads_platform_text.test.mjs
 */
const ownCode = (c: unknown) => typeof c === 'string' && /^[a-z][a-z0-9_]*$/.test(c);
function platformCode(status: number): string | null {
  if (status === 546) return 'worker_limit';     // the function ran out of CPU or memory on what it was given
  if (status === 413) return 'file_too_large';   // the request itself was refused as too large
  if (status >= 500) return 'server_error';
  return null;
}

/**
 * THE LARGEST FILE A SYNCHRONOUS READ TAKES (28 Oct 2026, sales_engineer). Measured on production with scanner-style
 * licences (one JPEG per page, a text layer on page 1): 9.66 MB was stored and read on supplier_portal save_documents and
 * supplier_api process_docs; 14.50 MB and 19.33 MB ended both at the CPU cap (HTTP 546). The trade licence, the
 * certificates and the quotation travel in the request body and are read before the answer, so the portal refuses a
 * larger file before it uploads anything, in plain words. A company profile or catalogue goes straight to storage and is
 * read after the answer; it keeps its own limit.
 */
export const MAX_READ_BYTES = 10 * 1024 * 1024;
export const tooBigToRead = (file: { size?: number } | null | undefined) => !!file && Number(file.size || 0) > MAX_READ_BYTES;
// IN THE MEGABYTES HIS PHONE SHOWS (12 Nov 2026, customer_support; browser walk L4: a 15.33 MB file was called "14.6 MB"). A phone's
// Files app and Finder count a megabyte as 1,000,000 bytes; the ceiling above stays in binary units, as the server measures it.
export const sizeMb = (file: { size?: number } | null | undefined) => Math.round((Number(file?.size || 0) / 1e6) * 10) / 10;
