// CONTINUOUS SUPPLIER LEAD SOURCING (marketing, 12 Oct 2026; founder rulings 1184 and 1186).
//
// "The marketing seat must continuously find NEW UAE supplier leads beyond the existing ~19,900 in public.leads,
// complete (company, trade, contact name, position, business email, mobile/phone, website, emirate), so a next
// list is ready when the current one is exhausted." 1186 supersedes the 10 Aug "no new leads" pause; Apify stays
// cancelled (no purchase without a cost quote).
//
// THE PIPELINE, deterministic end to end (no model call: OpenRouter is the founder's one standing hold, and an
// exact-trade rule needs no judgement):
//   1. SOURCE  Serper /places (SERPER_API_KEY, an edge secret) per trade x emirate, trades with the FEWEST
//              suppliers first (fn_lead_sourcing_priority). An API, not a scrape of Google Maps.
//   2. CRAWL   the company's OWN website only: robots.txt is read first and obeyed (a missing robots.txt allows,
//              an unreadable one refuses), at most MAX_PAGES pages per site, one request per site at a time with
//              PER_SITE_GAP_MS between them, a byte cap and a timeout (safeFetch: a URL we did not choose).
//              LinkedIn and every other social or directory host is NEVER fetched (SKIP_HOSTS), logged in or not.
//   3. EXTRACT emails (mailto + text), phones (tel: + text), and a named person with a title (schema.org Person
//              jobTitle, or "Name - Title" / "Title: Name" next to a known title word).
//   4. VERIFY  email syntax, business domain (no free-mail), MX via DNS-over-HTTPS (implicit A per RFC 5321 5.1).
//              Catch-all is NOT measured here: it needs an SMTP RCPT probe on port 25, which an edge isolate
//              cannot open, and the ruling says no sending. Recorded as email_status 'mx_ok' (never 'verified').
//   5. MAP     the trade is the QUERIED trade only when the place's category or name contains one of that trade's
//              own names (label parts and aliases, whole words). Otherwise trade_code is null: exact trade or none.
//   6. RECORD  every field carries its source URL and collected_at (UAE PDPL); fn_lead_sourcing_record dedupes
//              against leads (domain, phone, name), refuses a suppressed/bounced/erased contact, and promotes only
//              the complete ones.
import { parsePhoneNumberFromString } from 'npm:libphonenumber-js@1.13.14/max';
import robotsParserCjs from 'npm:robots-parser@3.0.1';
import { safeFetch } from '../_shared/safe_url.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';

// robots-parser is CommonJS (module.exports = function); its .d.ts types a namespace, so name the call shape.
const robotsParser = robotsParserCjs as unknown as (url: string, body: string) => { isAllowed(url: string, ua?: string): boolean | undefined };

export const USER_AGENT = 'QuotesDoneLeadBot/1.0 (+https://www.quotesdone.ae)';
export const MAX_PAGES = 4;                 // home + up to 3 contact/about/team pages
export const PER_SITE_GAP_MS = 1200;        // polite: one request per site at a time, >1s apart
const PAGE_BYTES = 600_000;
const CONTACT_PATHS = ['/contact', '/contact-us', '/about', '/about-us', '/team', '/our-team'];
// Hosts never crawled. LinkedIn above all (its terms forbid it, and a logged-in session is never used).
export const SKIP_HOSTS = /(^|\.)(linkedin\.com|facebook\.com|instagram\.com|x\.com|twitter\.com|tiktok\.com|youtube\.com|wa\.me|whatsapp\.com|google\.[a-z.]+|goo\.gl|yellowpages[a-z.-]*|dubizzle\.com|bayut\.com|propertyfinder\.ae|connect\.ae|2gis\.ae)$/i;
const FREE_MAIL = /^(gmail|googlemail|yahoo|ymail|hotmail|outlook|live|msn|icloud|me|aol|proton|protonmail|gmx|mail|yandex|zoho)\.[a-z.]+$/i;
export const EMIRATES = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
const TITLES = 'Managing Director|General Manager|Chief Executive Officer|CEO|Founder|Co-Founder|Owner|Partner|Director|Sales Director|Sales Manager|Business Development Manager|Procurement Manager|Purchasing Manager|Operations Manager|Technical Manager|Project Manager|Branch Manager|Manager';

export interface Trade { code: string; label: string; aliases: string[] | null }
export interface Place { title?: string; address?: string; category?: string; phoneNumber?: string; website?: string; cid?: string }
export interface Sourced { value: string; source: string }
export interface Prospect {
  company_name: string; trade_code: string | null; emirate: string | null; website: string | null; domain: string | null;
  phone_e164: string | null; phone_kind: string | null; email: string | null; email_status: string | null;
  contact_name: string | null; contact_title: string | null; place_id: string | null; query: string;
  field_sources: Record<string, string>;   // field -> source URL (PDPL)
}

// ── PURE HELPERS (tested in lead_sourcing.test.ts) ────────────────────────────────────────────────────
const words = (s: string) => ' ' + s.toLowerCase().normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu, ' ').trim() + ' ';

/** The trade's own names: each alias, and the label split on '&', ',' and '/'. Nothing from a neighbour trade. */
export function tradeNames(t: Trade): string[] {
  const parts = [t.label, ...String(t.label).split(/[&,/()]| and /i), ...(t.aliases || [])];
  return [...new Set(parts.map((p) => words(p).trim()).filter((p) => p.length >= 4))];
}
/** Exact trade or none: the queried trade only when the place's category or name contains one of its names. */
export function matchTrade(t: Trade, p: Place): string | null {
  const hay = words(`${p.category || ''} ${p.title || ''}`);
  return tradeNames(t).some((n) => hay.includes(' ' + n + ' ') || hay.includes(' ' + n.replace(/s$/, '') + ' ')) ? t.code : null;
}
/** The emirate only when the address names it. */
export function emirateOf(address: string | undefined): string | null {
  const a = String(address || '').toLowerCase();
  return EMIRATES.find((e) => a.includes(e.toLowerCase())) ?? null;
}
/** E.164 and mobile/landline for a UAE number; null when it is not a valid UAE number. */
export function normalisePhone(raw: string | undefined): { e164: string; kind: 'mobile' | 'landline' | 'other' } | null {
  const p = parsePhoneNumberFromString(String(raw || ''), 'AE');
  if (!p || !p.isValid() || p.country !== 'AE') return null;
  const t = p.getType();
  return { e164: p.number, kind: t === 'MOBILE' ? 'mobile' : t === 'FIXED_LINE' ? 'landline' : 'other' };
}
export function hostOf(url: string | null | undefined): string | null {
  try { return new URL(String(url)).hostname.toLowerCase().replace(/^www\./, ''); } catch { return null; }
}
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
/** A business address: valid syntax, not free-mail, not an image filename, and on the company's domain when it has one. */
export function businessEmail(e: string, domain: string | null): boolean {
  const m = e.toLowerCase().match(/^[a-z0-9._%+-]+@([a-z0-9.-]+\.[a-z]{2,})$/);
  if (!m || /\.(png|jpe?g|gif|webp|svg)$/.test(m[1]) || FREE_MAIL.test(m[1]) || /example\.|sentry|wixpress/.test(m[1])) return false;
  return !domain || m[1] === domain || m[1].endsWith('.' + domain);
}
/** Emails, phones and a named person with a title from one page's HTML. */
export function extractContacts(html: string, domain: string | null) {
  const decoded = html.replace(/&#64;|&commat;|\[at\]|\(at\)/gi, '@');
  const emails = [...new Set([...decoded.matchAll(EMAIL_RE)].map((m) => m[0].toLowerCase()))].filter((e) => businessEmail(e, domain));
  const tels = [...html.matchAll(/(?:tel:|\+971|\b0[2-9]\d?)[\s\d()+-]{7,18}/gi)].map((m) => m[0].replace(/^tel:/i, ''));
  const phones = [...new Map(tels.map(normalisePhone).filter((x) => x).map((x) => [x!.e164, x!])).values()];
  const text = html.replace(/<script(?![^>]*ld\+json)[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, '\n')
    .replace(/&nbsp;|&amp;/g, ' ').replace(/[ \t]+/g, ' ');
  let person: { name: string; title: string } | null = null;
  for (const m of html.matchAll(/"@type"\s*:\s*"Person"[^}]*?"name"\s*:\s*"([^"]{3,60})"[^}]*?"jobTitle"\s*:\s*"([^"]{2,80})"/g)) { person = { name: m[1], title: m[2] }; break; }
  const NAME = "([A-Z][a-z]+(?:[ '-][A-Z][a-z]+){1,3})";
  const T = `(${TITLES})`;
  if (!person) {
    const a = text.match(new RegExp(`${NAME}\\s*(?:[-–|,:]|\\n)\\s*${T}\\b`));
    const b = text.match(new RegExp(`${T}\\s*(?:[-–|,:]|\\n)\\s*${NAME}\\b`));
    if (a) person = { name: a[1], title: a[2] }; else if (b) person = { name: b[2], title: b[1] };
  }
  // Pilot 12 Oct 2026 caught 'John Doe' (a template placeholder) and 'On Special' (page copy) as people: a name is
  // refused when it is a known placeholder or any of its words is ordinary page vocabulary.
  if (person && (/\b(john|jane) doe\b|lorem|ipsum/i.test(person.name)
    || /\b(Our|The|On|At|In|For|Of|And|Contact|About|Meet|Sales|General|Managing|Project|Special|Offer|Offers|Team|Home|Services?|Products?|Company|Group|Trading|Call|Email|Read|More|New|View)\b/.test(person.name))) person = null;
  return { emails, phones, person };
}
/** All eight fields present: the definition of a complete lead (founder 1184). */
export function isComplete(p: Prospect): boolean {
  return !!(p.company_name && p.trade_code && p.contact_name && p.contact_title && p.email && p.email_status === 'mx_ok'
    && p.phone_e164 && p.website && p.emirate);
}

// ── NETWORK ─────────────────────────────────────────────────────────────────────────────────────────
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const dec = new TextDecoder();

/** MX (or implicit A) for a domain over DNS-over-HTTPS; same kinds as public.email_domain_mx. */
export async function mxKind(domain: string): Promise<string> {
  const q = async (type: string) => {
    const r = await timedFetch(`https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(domain)}&type=${type}`,
      { headers: { accept: 'application/dns-json' } }, 8000);
    return r.ok ? await r.json() as { Status: number; Answer?: unknown[] } : null;
  };
  try {
    const mx = await q('MX');
    if (!mx) return 'error';
    if (mx.Status === 3) return 'nxdomain';
    if (mx.Answer?.length) return 'mx';
    const a = await q('A');
    return a?.Answer?.length ? 'a_implicit' : 'no_records';
  } catch { return 'error'; }
}

export interface SourceOptions {
  serperKey: string; trades: Trade[]; emirate: string; pagesPerQuery: number; maxSites: number; deadlineMs: number;
  fetchSerper?: (body: unknown) => Promise<{ places?: Place[]; credits?: number }>;
}
export interface SourceResult { prospects: Prospect[]; queries: number; serper_credits: number; places: number; sites_crawled: number;
  pages_fetched: number; robots_refused: number; errors: string[] }

export async function sourceLeads(o: SourceOptions): Promise<SourceResult> {
  const started = Date.now();
  const out: SourceResult = { prospects: [], queries: 0, serper_credits: 0, places: 0, sites_crawled: 0, pages_fetched: 0, robots_refused: 0, errors: [] };
  const serper = o.fetchSerper ?? (async (body: unknown) => {
    const r = await timedFetch('https://google.serper.dev/places', { method: 'POST',
      headers: { 'X-API-KEY': o.serperKey, 'Content-Type': 'application/json' }, body: JSON.stringify(body) }, 20000);
    if (!r.ok) throw new Error('serper ' + r.status + ' ' + (await r.text()).slice(0, 120));
    return await r.json();
  });
  const seen = new Set<string>();
  for (const t of o.trades) {
    for (let page = 1; page <= o.pagesPerQuery; page++) {
      if (Date.now() - started > o.deadlineMs) return out;
      const query = `${t.label} supplier in ${o.emirate}, UAE`;
      let res: { places?: Place[]; credits?: number };
      try { res = await serper({ q: query, gl: 'ae', hl: 'en', page }); } catch (e) { out.errors.push(String(e).slice(0, 160)); break; }
      out.queries++; out.serper_credits += Number(res.credits ?? 1);
      const places = res.places || [];
      out.places += places.length;
      for (const p of places) {
        const key = p.cid || `${p.title}|${p.address}`;
        if (seen.has(key)) continue; seen.add(key);
        const src = `serper:places q="${query}" page=${page} cid=${p.cid ?? ''}`;
        const domain = hostOf(p.website);
        const phone = normalisePhone(p.phoneNumber);
        const pr: Prospect = { company_name: String(p.title || '').trim(), trade_code: matchTrade(t, p), emirate: emirateOf(p.address),
          website: domain && !SKIP_HOSTS.test(domain) ? p.website! : null, domain: domain && !SKIP_HOSTS.test(domain) ? domain : null,
          phone_e164: phone?.e164 ?? null, phone_kind: phone?.kind ?? null, email: null, email_status: null,
          contact_name: null, contact_title: null, place_id: p.cid ?? null, query, field_sources: {} };
        for (const f of ['company_name', 'trade_code', 'emirate', 'website', 'phone_e164'] as const) if (pr[f]) pr.field_sources[f] = src;
        out.prospects.push(pr);
      }
      if (places.length < 10) break;   // no further page
    }
  }
  // Crawl only places that already carry a trade and a site: the rest can never become complete.
  const toCrawl = out.prospects.filter((p) => p.trade_code && p.domain).slice(0, o.maxSites);
  const workers = Array.from({ length: 4 }, async (_, w) => {
    for (let i = w; i < toCrawl.length; i += 4) {
      if (Date.now() - started > o.deadlineMs) return;
      await crawlSite(toCrawl[i], out, started + o.deadlineMs).catch((e) => out.errors.push(`${toCrawl[i].domain}: ${String(e).slice(0, 100)}`));
    }
  });
  await Promise.all(workers);
  return out;
}

async function crawlSite(p: Prospect, out: SourceResult, stopAt: number) {
  const origin = new URL(p.website!).origin;
  const robotsUrl = origin + '/robots.txt';
  const rb = await safeFetch(robotsUrl, { timeoutMs: 8000, maxBytes: 200_000, headers: { 'User-Agent': USER_AGENT } });
  // No robots.txt (404) allows; a robots.txt we could not read (refused, timeout, 5xx) is treated as a refusal.
  let robots = robotsParser(robotsUrl, '');
  if (rb.ok) robots = robotsParser(robotsUrl, dec.decode(rb.bytes));
  else if (rb.error !== 'http_404' && rb.error !== 'http_410') { out.robots_refused++; return; }
  out.sites_crawled++;
  const urls = [origin + '/', ...CONTACT_PATHS.map((x) => origin + x)];
  let pages = 0;
  for (const u of urls) {
    if (pages >= MAX_PAGES || Date.now() > stopAt) break;   // the deadline bounds each page, not only each site
    if (robots.isAllowed(u, USER_AGENT) === false) { out.robots_refused++; continue; }
    await sleep(PER_SITE_GAP_MS);
    const r = await safeFetch(u, { timeoutMs: 10000, maxBytes: PAGE_BYTES, headers: { 'User-Agent': USER_AGENT } });
    if (!r.ok || !/html/i.test(r.contentType)) continue;
    pages++; out.pages_fetched++;
    const c = extractContacts(dec.decode(r.bytes), p.domain);
    if (!p.email && c.emails.length) { p.email = c.emails.find((e) => /^(sales|info|enquir|inquir|contact)/.test(e)) || c.emails[0]; p.field_sources.email = u; }
    const mobile = c.phones.find((x) => x.kind === 'mobile');
    if (mobile && p.phone_kind !== 'mobile') { p.phone_e164 = mobile.e164; p.phone_kind = 'mobile'; p.field_sources.phone_e164 = u; }
    else if (!p.phone_e164 && c.phones[0]) { p.phone_e164 = c.phones[0].e164; p.phone_kind = c.phones[0].kind; p.field_sources.phone_e164 = u; }
    if (!p.contact_name && c.person) { p.contact_name = c.person.name; p.contact_title = c.person.title;
      p.field_sources.contact_name = u; p.field_sources.contact_title = u; }
    if (p.email && p.contact_name && p.phone_kind === 'mobile') break;
  }
  if (p.email) {
    const kind = await mxKind(p.email.split('@')[1]);
    p.email_status = kind === 'mx' || kind === 'a_implicit' ? 'mx_ok' : 'mx_' + kind;
    p.field_sources.email_status = 'dns:cloudflare-dns.com ' + kind;
  }
}
