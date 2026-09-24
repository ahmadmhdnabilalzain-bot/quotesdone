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
