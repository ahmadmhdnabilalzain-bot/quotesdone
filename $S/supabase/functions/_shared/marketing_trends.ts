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
    const title = tag(m[1], 'title');
    let url = tag(m[1], 'link');
    if (!/^https?:\/\//.test(url) || !title) continue;
    // Google Trends' daily searches all link the feed itself; each search is cited by its own explore page instead
    // (marketing_trend.url is unique, so otherwise only the first search of a feed would ever be stored).
    try {
      const u = new URL(url);
      if (u.hostname === 'trends.google.com' && u.pathname.startsWith('/trending/rss')) {
        url = 'https://trends.google.com/trends/explore?geo=' + encodeURIComponent(u.searchParams.get('geo') || 'AE') + '&q=' + encodeURIComponent(title);
      }
    } catch { continue; }
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

