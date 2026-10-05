// The seats' web search: Serper (Google results), it_engineer, 5 Oct 2026 (founder ledger 1118).
//
// The keyless scrape this replaces was refused by a bot-check on every datacenter call and is removed totally.
// Serper is a keyed account the founder holds; the key is the edge secret SERPER_API_KEY, read by name and never
// logged or echoed (nothing here puts it in a message, a finding or a return value).
//
// Every search, in order:
//   1. no key                -> no search, one it_engineer finding (notify=false)
//   2. fn_web_search_claim   -> refuses a query naming a supplier, customer or lead (exact names and emails held in
//                               the database, never word matching), and counts the day against a hard cap of 50;
//                               over the cap the routine itself raises the it_engineer finding (notify=false)
//   3. POST google.serper.dev with gl=ae and hl=en, or hl=ar when the query is Arabic, restricted to site:gov.ae
//   4. 401/402/403 (key or billing: only the account holder can fix it) -> finding notify=true;
//      any other failure (an outage) -> finding notify=false. Either way the seat reasons without the web.
//   5. only official UAE sources survive: https on *.gov.ae (uaelegislation, moec, tax, tdra, dm and the federal
//      Official Gazette all sit under it). Everything else is dropped.
export type Hit = { url: string; title: string };
export interface SearchDeps {
  key: string | undefined;
  fetch: (url: string, init: RequestInit) => Promise<Response>;
  rpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
}

export const SERPER_URL = 'https://google.serper.dev/search';

export function officialUaeSource(url: string): boolean {
  try {
    const u = new URL(url);
    const h = u.hostname.toLowerCase();
    return u.protocol === 'https:' && (h === 'gov.ae' || h.endsWith('.gov.ae'));
  } catch { return false; }
}

export const isArabic = (q: string) => /[؀-ۿ]/.test(q);

export function serperBody(query: string) {
  return { q: `${query} site:gov.ae`, gl: 'ae', hl: isArabic(query) ? 'ar' : 'en', num: 10 };
}

export function parseSerper(json: unknown): Hit[] {
  const organic = (json as { organic?: { link?: unknown; title?: unknown }[] } | null)?.organic;
  if (!Array.isArray(organic)) return [];
  return organic
    .map((o) => ({ url: String(o?.link ?? ''), title: String(o?.title ?? '') }))
    .filter((h) => officialUaeSource(h.url));
}

async function degrade(deps: SearchDeps, reason: string, notify: boolean, detail: string): Promise<Hit[]> {
  await deps.rpc('fn_web_search_degraded', { p_reason: reason, p_notify: notify, p_detail: detail }).catch(() => null);
  return [];
}

export async function serperSearch(query: string, deps: SearchDeps): Promise<Hit[]> {
  if (!deps.key) return degrade(deps, 'no_key', false, 'the edge secret SERPER_API_KEY is not set');
  const { data, error } = await deps.rpc('fn_web_search_claim', { p_query: query });
  if (error) return degrade(deps, 'claim_failed', false, 'fn_web_search_claim: ' + error.message);
  const claim = (data ?? {}) as { allowed?: boolean; reason?: string };
  if (claim.allowed !== true) return [];          // a private name (refused) or the cap (the routine raised it)
  let r: Response;
  try {
    r = await deps.fetch(SERPER_URL, {
      method: 'POST',
      headers: { 'X-API-KEY': deps.key, 'Content-Type': 'application/json' },
      body: JSON.stringify(serperBody(query)),
    });
  } catch (e) {
    return degrade(deps, 'outage', false, 'Serper unreachable: ' + String((e as Error)?.message ?? e).slice(0, 200));
  }
  if (r.status === 401 || r.status === 402 || r.status === 403) {
    return degrade(deps, 'key_or_billing', true, `Serper refused the key or the account (HTTP ${r.status})`);
  }
  if (!r.ok) return degrade(deps, 'outage', false, `Serper answered HTTP ${r.status}`);
  return parseSerper(await r.json().catch(() => null));
}
