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

export async function call(path: string, body: Record<string, unknown>, token?: string | null): Promise<any> {
  const r = await fetch(fnUrl(path), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => ({ ok: false, error: 'bad_response' }));
  if (!r.ok && j && typeof j === 'object') j._http = r.status;
  return j;
}
