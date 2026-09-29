// marketing_trends — the marketing seat's trend watch and GEO audit, the parts that are pure code.
// Seat: marketing. 24 Sep 2026, ledger 983 (GAPS.md "## Marketing" gaps 3 and 5).
//
// Parsing an RSS feed and asking "is our own domain in this result list / our own name in this answer" are
// FORMAT and FACT checks, which the founder's no-word-matching ruling permits. Whether a trend MATTERS to the
// business is a meaning, so it is decided by think() in marketing/duties.ts, never here.
// Tables and routines: scripts/sql/marketing_watches_trends_audits_answer_engines_and_reviews_the_brand_each_quarter.sql.

export interface TrendItem { url: string; title: string; published_at: string | null }

const decode = (s: string) => s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, '&').trim();
const tag = (block: string, name: string) => { const m = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, 'i')); return m ? decode(m[1]) : ''; };

/** The <item>s of an RSS 2.0 feed (Google News), newest first as given, at most `max`. */
export function parseRss(xml: string, max = 15): TrendItem[] {
  const out: TrendItem[] = [];
  for (const m of xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)) {
    const url = tag(m[1], 'link'), title = tag(m[1], 'title');
    if (!/^https?:\/\//.test(url) || !title) continue;
    const d = Date.parse(tag(m[1], 'pubDate'));
    out.push({ url, title: title.slice(0, 500), published_at: Number.isFinite(d) ? new Date(d).toISOString() : null });
    if (out.length >= max) break;
  }
  return out;
}

export const OUR_HOSTS = ['quotesdone.ae', 'quotesdone.com'];
const ourHost = (url: string) => { try { const h = new URL(url).hostname.toLowerCase(); return OUR_HOSTS.some((o) => h === o || h.endsWith('.' + o)); } catch { return false; } };

/** Web engine: the 1-based rank of the first result on our domain, or null. */
export function webCitation(results: { url: string }[]): { cited: boolean; rank: number | null; evidence: string | null } {
  const i = results.findIndex((r) => ourHost(r.url));
  return i < 0 ? { cited: false, rank: null, evidence: results.slice(0, 3).map((r) => r.url).join(' | ') || null } : { cited: true, rank: i + 1, evidence: results[i].url };
}

/** Model engine: does the answer name QuotesDone or link our domain (our own brand, a fact, not a meaning). */
export function modelCitation(answer: string): { cited: boolean; evidence: string } {
  // "quotes done" is ordinary English ("get your quotes done"): the spaced form counts only as the capitalised name.
  const cited = /quotesdone/i.test(answer) || /\bQuotes ?Done\b/.test(answer) || OUR_HOSTS.some((h) => answer.toLowerCase().includes(h));
  return { cited, evidence: answer.slice(0, 1000) };
}

/**
 * Which competitors an answer engine named: each name as a whole phrase, case-insensitive, in the order given.
 * A brand name in the text is a fact, not a meaning, so this is code (founder: no model for routine work).
 * A name shorter than 4 characters is skipped: it would match ordinary words.
 */
export function competitorsNamed(answer: string, names: string[]): string[] {
  // a dot stays only inside a name (biznex.ae); a sentence-ending dot is a space
  const text = ' ' + String(answer || '').toLowerCase().replace(/\.(?![\p{L}\p{N}])/gu, ' ').replace(/[^\p{L}\p{N}.]+/gu, ' ') + ' ';
  const out: string[] = [];
  for (const n of names) {
    // "Tradeling (Tradeling Group)" is named in an answer as "Tradeling": the part before a bracket is the brand
    const key = String(n || '').replace(/\s*\(.*$/, '').toLowerCase().replace(/[^\p{L}\p{N}.]+/gu, ' ').trim();
    if (key.length >= 4 && text.includes(' ' + key + ' ') && !out.includes(n)) out.push(n);
  }
  return out;
}

/**
 * One web search for the GEO audit. DuckDuckGo answers a bot-checked GET from a datacenter address with a 2xx page
 * that carries no results (HTTP 202 anomaly page), so r.ok alone never proves a result list came back. On an empty
 * GET the same query is re-sent as the POST its own search form makes; if that is empty too, the error names both
 * statuses and whether the bot check was seen, so the finding says WHY rather than only "no results".
 */
export async function duckSearch(q: string, fetchFn: (url: string, init: RequestInit) => Promise<Response>): Promise<{ url: string; title: string }[]> {
  const URL_ = 'https://html.duckduckgo.com/html/';
  const headers = { 'User-Agent': 'QuotesDone-marketing-geo/1.0 (+https://www.quotesdone.ae)' };
  const seen: string[] = [];
  for (const init of [
    { url: URL_ + '?q=' + encodeURIComponent(q), init: { headers } as RequestInit },
    { url: URL_, init: { method: 'POST', headers: { ...headers, 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'q=' + encodeURIComponent(q) } as RequestInit },
  ]) {
    const r = await fetchFn(init.url, init.init);
    const html = r.ok ? await r.text() : '';
    const results = parseDuckResults(html);
    if (results.length) return results;
    seen.push((init.init.method || 'GET') + ' HTTP ' + r.status + (/anomaly|captcha|challenge/i.test(html) ? ' bot-check' : ''));
  }
  throw new Error('web search returned no results (' + seen.join(', ') + ')');
}

/** DuckDuckGo's HTML results (the same public endpoint think.ts's research uses), unwrapped to target URLs. */
export function parseDuckResults(html: string): { url: string; title: string }[] {
  const out: { url: string; title: string }[] = [];
  for (const m of html.matchAll(/<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g)) {
    let url = decode(m[1]);
    const uddg = url.match(/[?&]uddg=([^&]+)/);
    if (uddg) url = decodeURIComponent(uddg[1]);
    if (url.startsWith('//')) url = 'https:' + url;
    out.push({ url, title: decode(m[2].replace(/<[^>]+>/g, '')) });
  }
  return out;
}
