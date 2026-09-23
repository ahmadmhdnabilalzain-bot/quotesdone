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

export async function call(path: string, body: Record<string, unknown>, token?: string | null): Promise<any> {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), TIMEOUT_MS);
  let r: Response;
  try {
    r = await fetch(fnUrl(path), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
      body: JSON.stringify(body),
      signal: ac.signal,
    });
  } catch (_e) {
    return { ok: false, code: ac.signal.aborted ? 'timeout' : 'network' };
  } finally {
    clearTimeout(timer);
  }
  const text = await r.text().catch(() => '');
  let j: any = null;
  try { j = JSON.parse(text); } catch (_e) { j = null; }
  if (!j || typeof j !== 'object') return { ok: false, code: 'bad_response', _http: r.status };
  if (!r.ok) {
    j._http = r.status;
    if (r.status === 401) j._expired = true;
    if (!j.code) j.code = 'load_failed';
  }
  return j;
}
