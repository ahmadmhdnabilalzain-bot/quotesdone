// SEARCH CONSOLE: the site's Google search results, read every day (marketing, 15 Nov 2026; founder rulings 1701, 1705).
// Owner: the marketing seat. Writes public.marketing_search_day (clicks, impressions, CTR and average position per day for
// the site, each query and each page) and public.marketing_search_sitemap (URLs submitted and indexed per sitemap);
// scripts/sql/the_marketing_seat_measures_search_registrations_and_cost_per_supplier_every_day.sql turns them into the
// seat's daily KPIs and the CEO's reading.
//
// SOURCE: the Google Search Console API (searchAnalytics.query, sitemaps.list), read-only scope
// https://www.googleapis.com/auth/webmasters.readonly, as a Google Cloud SERVICE ACCOUNT that the property owner adds as a
// user of the property (Search Console > Settings > Users and permissions > Add user, Restricted). Two app_secrets:
//   google_search_console_sa    the service account's JSON key (client_email, private_key); never logged or returned
//   google_search_console_site  the property, e.g. "sc-domain:quotesdone.com" or "https://quotesdone.com/"
// Until both are set the duty is INERT: it says so and is not due. Once a day (Dubai); it re-reads the last three days that
// have data (Search Console lags about two days), so a late figure replaces the early one.
import type { Duty, DutyContext } from './types.ts';

export const SC_SCOPE = 'https://www.googleapis.com/auth/webmasters.readonly';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const API = 'https://searchconsole.googleapis.com/webmasters/v3/sites/';
const ROW_LIMIT = 1000;

export interface ServiceAccount { client_email: string; private_key: string }
type Fetch = typeof fetch;

/** The service-account key, or null when the secret is missing or is not one. */
export function readServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw) return null;
  try {
    const j = JSON.parse(raw);
    return typeof j?.client_email === 'string' && typeof j?.private_key === 'string' && j.private_key.includes('PRIVATE KEY') ? j : null;
  } catch { return null; }
}

/** The Dubai calendar day of an instant, YYYY-MM-DD. */
export function dubaiDay(at: Date): string { return new Date(at.getTime() + 4 * 3600_000).toISOString().slice(0, 10); }
function addDays(day: string, n: number): string { return new Date(Date.parse(day + 'T00:00:00Z') + n * 86400_000).toISOString().slice(0, 10); }

/** The window to read: the three days ending two days before today (Search Console's lag). */
export function readWindow(now: Date): { startDate: string; endDate: string } {
  const end = addDays(dubaiDay(now), -2);
  return { startDate: addDays(end, -2), endDate: end };
}

const b64url = (b: Uint8Array | string) => {
  const bytes = typeof b === 'string' ? new TextEncoder().encode(b) : b;
  let s = ''; for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

/** The signed RS256 assertion Google's token endpoint exchanges for an access token (RFC 7523). */
export async function signedAssertion(sa: ServiceAccount, now: Date): Promise<string> {
  const iat = Math.floor(now.getTime() / 1000);
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({ iss: sa.client_email, scope: SC_SCOPE, aud: TOKEN_URL, iat, exp: iat + 3600 }));
  const pem = sa.private_key.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(head + '.' + claims)));
  return head + '.' + claims + '.' + b64url(sig);
}

export interface SearchRow { day: string; dim: 'total' | 'query' | 'page'; key: string; clicks: number; impressions: number; ctr: number | null; position: number | null }

/** Search Console rows ({keys: [date, query|page], clicks, impressions, ctr, position}) as marketing_search_day rows. */
export function toSearchRows(dim: SearchRow['dim'], rows: unknown): SearchRow[] {
  if (!Array.isArray(rows)) return [];
  const out: SearchRow[] = [];
  for (const r of rows as Array<{ keys?: unknown[]; clicks?: number; impressions?: number; ctr?: number; position?: number }>) {
    const keys = Array.isArray(r?.keys) ? r.keys.map(String) : [];
    const day = keys[0];
    if (!day || !/^\d{4}-\d{2}-\d{2}$/.test(day)) continue;
    const key = dim === 'total' ? '' : String(keys[1] ?? '').slice(0, 500);
    if (dim !== 'total' && !key) continue;
    out.push({ day, dim, key, clicks: Math.max(0, Math.round(Number(r.clicks) || 0)), impressions: Math.max(0, Math.round(Number(r.impressions) || 0)),
               ctr: Number.isFinite(Number(r.ctr)) ? Number(r.ctr) : null, position: Number.isFinite(Number(r.position)) ? Number(r.position) : null });
  }
  return out;
}

/** sitemaps.list as marketing_search_sitemap rows: submitted and indexed summed over each sitemap's contents. */
export function toSitemapRows(body: unknown): Array<Record<string, unknown>> {
  const list = (body as { sitemap?: unknown[] })?.sitemap;
  if (!Array.isArray(list)) return [];
  return list.map((s) => {
    const x = s as { path?: string; lastDownloaded?: string; errors?: string | number; warnings?: string | number; contents?: Array<{ submitted?: string | number; indexed?: string | number }> };
    const sum = (k: 'submitted' | 'indexed') => (x.contents || []).reduce((a, c) => a + (Number(c?.[k]) || 0), 0);
    return { path: String(x.path || ''), submitted: sum('submitted'), indexed: sum('indexed'), last_downloaded: x.lastDownloaded ?? null,
             errors: Number(x.errors) || 0, warnings: Number(x.warnings) || 0 };
  }).filter((r) => r.path);
}

export async function pullSearchConsole(ctx: DutyContext, f: Fetch = fetch): Promise<Record<string, unknown>> {
  const sa = readServiceAccount(await ctx.sec('google_search_console_sa'));
  const site = (await ctx.sec('google_search_console_site'))?.trim();
  if (!sa || !site) return { due: false, inert: true, reason: 'app_secrets google_search_console_sa (a service-account key added as a user of the property) and google_search_console_site are not both set' };
  const today = dubaiDay(ctx.now);
  const { data: last } = await ctx.admin.from('marketing_search_day').select('fetched_at').order('fetched_at', { ascending: false }).limit(1).maybeSingle();
  if (last?.fetched_at && dubaiDay(new Date(last.fetched_at)) === today) return { due: false, reason: 'read today' };

  const tok = await f(TOKEN_URL, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: await signedAssertion(sa, ctx.now) }),
    signal: AbortSignal.timeout(15000) });
  // deno-lint-ignore no-explicit-any
  const tj = await tok.json().catch(() => null) as any;
  if (!tok.ok || !tj?.access_token) throw new Error('Search Console token refused (' + tok.status + '): ' + String(tj?.error_description || tj?.error || '').slice(0, 120));
  const auth = { authorization: 'Bearer ' + tj.access_token, 'content-type': 'application/json' };
  const base = API + encodeURIComponent(site);
  const win = readWindow(ctx.now);
  const query = async (dims: string[]) => {
    const r = await f(base + '/searchAnalytics/query', { method: 'POST', headers: auth, signal: AbortSignal.timeout(20000),
      body: JSON.stringify({ ...win, dimensions: dims, rowLimit: ROW_LIMIT, dataState: 'all' }) });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    if (!r.ok) throw new Error('searchAnalytics ' + dims.join('+') + ' (' + r.status + '): ' + String(j?.error?.message || '').slice(0, 160));
    return j?.rows ?? [];
  };
  const rows = [...toSearchRows('total', await query(['date'])), ...toSearchRows('query', await query(['date', 'query'])),
                ...toSearchRows('page', await query(['date', 'page']))];
  const fetched_at = ctx.now.toISOString();
  if (rows.length) {
    const { error } = await ctx.admin.from('marketing_search_day').upsert(rows.map((r) => ({ ...r, fetched_at })), { onConflict: 'day,dim,key' });
    if (error) throw new Error('marketing_search_day: ' + error.message);
  } else {
    // nothing in the window yet (a new property): one zero total row records the read, so the duty is not re-run today
    const { error } = await ctx.admin.from('marketing_search_day').upsert([{ day: win.endDate, dim: 'total', key: '', clicks: 0, impressions: 0, ctr: null, position: null, fetched_at }], { onConflict: 'day,dim,key' });
    if (error) throw new Error('marketing_search_day: ' + error.message);
  }
  const sm = await f(base + '/sitemaps', { headers: auth, signal: AbortSignal.timeout(15000) });
  const smRows = sm.ok ? toSitemapRows(await sm.json().catch(() => null)) : [];
  if (smRows.length) {
    const { error } = await ctx.admin.from('marketing_search_sitemap').upsert(smRows.map((r) => ({ ...r, fetched_at })), { onConflict: 'path' });
    if (error) throw new Error('marketing_search_sitemap: ' + error.message);
  }
  return { due: true, ok: true, window: win, rows: rows.length, sitemaps: smRows.length, sitemaps_status: sm.status };
}

export const searchConsole: Duty = { name: 'search_console', owner_seat: 'marketing', run: (ctx) => pullSearchConsole(ctx) };
