// think/research.ts — the authoritative web: which hosts may be read, the search and the page reader (moved whole from _shared/think.ts).
import type { Admin } from './types.ts';

// ── the authoritative web (research) ─────────────────────────────────────────────────────────────
// Only these hosts are read. UAE federal and emirate government, the free-zone and utility authorities,
// the standards bodies the knowledge packs cite. A hostname ends with one of them or it is not fetched —
// which is also the SSRF guard: the search engine never chooses an address we connect to.
export const AUTHORITY_HOSTS = [
  '.gov.ae', 'u.ae', 'dm.gov.ae', 'dubaimunicipality.gov.ae', 'dcd.gov.ae', 'dewa.gov.ae', 'rta.ae', 'dubailand.gov.ae',
  'trakhees.ae', 'dso.ae', 'dda.gov.ae', 'jafza.ae', 'dmcc.ae', 'adm.gov.ae', 'dmt.gov.ae', 'adcd.gov.ae', 'addc.ae',
  'sewa.gov.ae', 'shjmun.gov.ae', 'etihadwe.ae', 'moei.gov.ae', 'moccae.gov.ae', 'mohre.gov.ae', 'tax.gov.ae',
  'uaelegislation.gov.ae', 'moiat.gov.ae', 'esma.gov.ae', 'tdra.gov.ae', 'nfpa.org', 'iso.org', 'bsigroup.com',
] as const;
export function authoritative(url: string): boolean {
  try {
    const u = new URL(url);
    if (u.protocol !== 'https:') return false;
    const h = u.hostname.toLowerCase();
    return AUTHORITY_HOSTS.some((a) => a.startsWith('.') ? h.endsWith(a) : (h === a || h.endsWith('.' + a)));
  } catch (_e) { return false; }
}

// The search engine: Serper, through web_search.ts (cap, private-name guard, official UAE sources only).
// Without a key, over the cap or on a failure it returns no hits and think() reasons from the knowledge base.
export async function webSearch(admin: Admin, query: string): Promise<{ url: string; title: string }[]> {
  const { serperSearch } = await import('../web_search.ts');
  const { timedFetch } = await import('../timed_fetch.ts');
  return await serperSearch(query, {
    key: Deno.env.get('SERPER_API_KEY'),
    fetch: (u, i) => timedFetch(u, i, 10_000),
    rpc: async (f, args) => { const r = await admin.rpc(f, args); return { data: r.data, error: r.error }; },
  });
}
export async function readPage(url: string): Promise<string | null> {
  if (!authoritative(url)) return null;
  const { timedFetch } = await import('../timed_fetch.ts');
  const r = await timedFetch(url, { headers: { 'User-Agent': 'QuotesDone-research/1.0 (+https://www.quotesdone.ae)' }, redirect: 'manual' }, 10_000);
  if (!r.ok) return null;
  const type = r.headers.get('content-type') ?? '';
  if (!/text\/html|text\/plain/.test(type)) return null;
  return htmlText((await r.text()).slice(0, 400_000));
}
export function htmlText(html: string): string {
  return html.replace(/<(script|style|noscript)[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/\s+/g, ' ').trim();
}
