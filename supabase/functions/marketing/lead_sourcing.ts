// CONTINUOUS SUPPLIER LEAD SOURCING (marketing, 12 Oct 2026; founder rulings 1184 and 1186).
//
// "The marketing seat must continuously find NEW UAE supplier leads beyond the existing ~19,900 in public.leads,
// complete (company, trade, contact name, position, business email, mobile/phone, website, emirate), so a next
// list is ready when the current one is exhausted." 1186 supersedes the 10 Aug "no new leads" pause; Apify stays
// cancelled (no purchase without a cost quote).
//
// THE PIPELINE. Code first; the model only where code cannot read (founder 1175, 7 Oct: OpenRouter is always on):
// the contact name and title on a site's own pages, and whether that contact is real (see THE NAME below).
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
  model_answer?: string | null;            // the model's answer about the contact, verbatim (lead_prospect.model_answer)
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

// ── THE NAME: the model reads the pages, LinkedIn titles from public Google results fill the rest ──────
// Pilot 12 Oct 2026: only 4 of 59 sites gave a person by pattern. A person on an about/team page, or the manager
// named in trade-licence details a site publishes, is written in too many shapes for a pattern, so the model reads
// them (founder 1175: OpenRouter always on; the routine class, gpt-6-luna, cost logged by ai_gateway in ai_cost_log under fn
// 'marketing', class routine_employee_reasoning). What it may return is held to the page: the name must appear in the text it was given.
export type AskModel = (prompt: string) => Promise<{ content: string | null; cost_usd: number }>;
export const MODEL_TEXT_CHARS = 10000;

/** Readable text of a page (scripts, styles and tags out), for the model. */
export function visibleText(html: string): string {
  return html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<noscript[\s\S]*?<\/noscript>/gi, ' ')
    .replace(/<[^>]+>/g, '\n').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/[ \t]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
}
export function contactPrompt(company: string, pages: { url: string; text: string }[], candidate: { name: string; title: string } | null): string {
  const body = pages.map((p) => `### ${p.url}\n${p.text}`).join('\n\n').slice(0, MODEL_TEXT_CHARS);
  return `Company: ${company}\nBelow is text from the company's own website pages.\n` +
    `Find ONE real person who runs or sells for this company (owner, managing director, general manager, director, sales or ` +
    `procurement manager), including a manager or owner named in trade licence details on the page. ` +
    (candidate ? `A pattern found "${candidate.name}" as "${candidate.title}": confirm it only if that is a real named person at this company. ` : '') +
    `Placeholders (John Doe), testimonials from customers, page headings and staff of other companies are NOT real contacts.\n` +
    `Answer with ONE JSON object only: {"name": string|null, "title": string|null, "real": boolean, "url": string|null} ` +
    `where name is copied exactly as written on the page and url is the page it is on.\n\n${body}`;
}
/** Parse and hold the model to the page: a name that is not in the text it was shown is refused. */
export function acceptContact(answer: string | null, pages: { url: string; text: string }[]): { name: string; title: string; url: string } | null {
  if (!answer) return null;
  let j: { name?: string | null; title?: string | null; real?: boolean; url?: string | null };
  try { j = JSON.parse(answer.slice(answer.indexOf('{'), answer.lastIndexOf('}') + 1)); } catch { return null; }
  const name = String(j.name || '').trim(); const title = String(j.title || '').trim();
  if (!j.real || name.split(/\s+/).length < 2 || !title || name.length > 60 || title.length > 80) return null;
  const has = (p: { text: string }) => p.text.toLowerCase().includes(name.toLowerCase());
  const page = pages.find((p) => p.url === j.url && has(p)) ?? pages.find(has);
  return page ? { name, title, url: page.url } : null;
}
/** "First Last - Sales Manager - Acme Trading LLC | LinkedIn" -> the person, only when the company and a title word match. */
export function linkedinPerson(resultTitle: string, company: string): { name: string; title: string } | null {
  // Pilot 12 Oct 2026: Google's titles carry RTL marks (U+200E/U+200F) and write "Title @ Company" as often as
  // "Title at Company"; a long one ends in "...".
  const clean = String(resultTitle || '').replace(/[‎‏]/g, '').replace(/\s*(\.\.\.|…)\s*$/, '').replace(/\s*\|\s*LinkedIn.*$/i, '');
  const parts = clean.split(/\s+[-–]\s+/);
  if (parts.length === 2 && /\s(at|@)\s?/i.test(parts[1])) parts.splice(1, 1, ...parts[1].split(/\s(?:at|@)\s?/i).slice(0, 2));
  if (parts.length < 3) return null;
  const [name, title, org] = parts;
  const key = words(company).trim().split(' ').find((w) => w.length >= 4 && !/^(llc|trading|general|company|group|dubai|services?)$/.test(w));
  if (!key || !words(org).includes(' ' + key + ' ')) return null;
  if (!new RegExp(`\\b(${TITLES}|Head|Chief|President)\\b`, 'i').test(title)) return null;
  if (name.split(/\s+/).length < 2 || /[|@]/.test(name)) return null;
  const latin = name.replace(/[^\p{Script=Latin}\s.'-]/gu, '').replace(/\s+/g, ' ').trim();   // 'HANKUK LEE 님' in the pilot
  return latin.split(' ').length >= 2 ? { name: latin, title: title.trim() } : null;
}

type SerperPath = 'places' | 'search';
type SerperReply = { places?: Place[]; organic?: { title?: string; link?: string }[]; credits?: number };
export interface SourceOptions {
  serperKey: string; trades: Trade[]; emirate: string; pagesPerQuery: number; maxSites: number; deadlineMs: number;
  fetchSerper?: (path: SerperPath, body: unknown) => Promise<SerperReply>;
  askModel?: AskModel;
  // SPEND CAPS for this batch (release review of #1304): it stops searching at maxSerperCredits and stops asking the
  // model at maxLlmUsd. Both come from the day's remaining budget (fn_lead_sourcing_today).
  maxSerperCredits?: number; maxLlmUsd?: number;
}
export interface SourceResult { prospects: Prospect[]; queries: number; serper_credits: number; places: number; sites_crawled: number;
  pages_fetched: number; robots_refused: number; model_calls: number; llm_cost_usd: number; linkedin_queries: number; linkedin_titles: string[]; errors: string[] }

export async function sourceLeads(o: SourceOptions): Promise<SourceResult> {
  const stopAt = Date.now() + o.deadlineMs;
  const out: SourceResult = { prospects: [], queries: 0, serper_credits: 0, places: 0, sites_crawled: 0, pages_fetched: 0, robots_refused: 0,
    model_calls: 0, llm_cost_usd: 0, linkedin_queries: 0, linkedin_titles: [], errors: [] };
  const serper = o.fetchSerper ?? (async (path: SerperPath, body: unknown): Promise<SerperReply> => {
    const r = await timedFetch('https://google.serper.dev/' + path, { method: 'POST',
      headers: { 'X-API-KEY': o.serperKey, 'Content-Type': 'application/json' }, body: JSON.stringify(body) }, 20000);
    if (!r.ok) throw new Error('serper ' + r.status + ' ' + (await r.text()).slice(0, 120));
    return await r.json();
  });
  const serperLeft = () => out.serper_credits < (o.maxSerperCredits ?? Infinity);
  const modelLeft = () => out.llm_cost_usd < (o.maxLlmUsd ?? Infinity);
  const seen = new Set<string>();
  for (const t of o.trades) {
    for (let page = 1; page <= o.pagesPerQuery; page++) {
      if (Date.now() > stopAt || !serperLeft()) return out;
      const query = `${t.label} supplier in ${o.emirate}, UAE`;
      let res: SerperReply;
      try { res = await serper('places', { q: query, gl: 'ae', hl: 'en', page }); } catch (e) { out.errors.push(String(e).slice(0, 160)); break; }
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

  async function crawlSite(p: Prospect) {
    const origin = new URL(p.website!).origin;
    const robotsUrl = origin + '/robots.txt';
    const rb = await safeFetch(robotsUrl, { timeoutMs: 8000, maxBytes: 200_000, headers: { 'User-Agent': USER_AGENT } });
    // No robots.txt (404) allows; a robots.txt we could not read (refused, timeout, 5xx) is treated as a refusal.
    let robots = robotsParser(robotsUrl, '');
    if (rb.ok) robots = robotsParser(robotsUrl, dec.decode(rb.bytes));
    else if (rb.error !== 'http_404' && rb.error !== 'http_410') { out.robots_refused++; return; }
    out.sites_crawled++;
    const texts: { url: string; text: string }[] = [];
    let candidate: { name: string; title: string; url: string } | null = null;
    for (const u of [origin + '/', ...CONTACT_PATHS.map((x) => origin + x)]) {
      if (texts.length >= MAX_PAGES || Date.now() > stopAt) break;   // the deadline bounds each page, not only each site
      if (robots.isAllowed(u, USER_AGENT) === false) { out.robots_refused++; continue; }
      await sleep(PER_SITE_GAP_MS);
      const r = await safeFetch(u, { timeoutMs: 10000, maxBytes: PAGE_BYTES, headers: { 'User-Agent': USER_AGENT } });
      if (!r.ok || !/html/i.test(r.contentType)) continue;
      out.pages_fetched++;
      const html = dec.decode(r.bytes);
      texts.push({ url: u, text: visibleText(html).slice(0, 4000) });
      const c = extractContacts(html, p.domain);
      if (!p.email && c.emails.length) { p.email = c.emails.find((e) => /^(sales|info|enquir|inquir|contact)/.test(e)) || c.emails[0]; p.field_sources.email = u; }
      const mobile = c.phones.find((x) => x.kind === 'mobile');
      if (mobile && p.phone_kind !== 'mobile') { p.phone_e164 = mobile.e164; p.phone_kind = 'mobile'; p.field_sources.phone_e164 = u; }
      else if (!p.phone_e164 && c.phones[0]) { p.phone_e164 = c.phones[0].e164; p.phone_kind = c.phones[0].kind; p.field_sources.phone_e164 = u; }
      if (!candidate && c.person) candidate = { ...c.person, url: u };
    }
    if (p.email) {
      const kind = await mxKind(p.email.split('@')[1]);
      p.email_status = kind === 'mx' || kind === 'a_implicit' ? 'mx_ok' : 'mx_' + kind;
      p.field_sources.email_status = 'dns:cloudflare-dns.com ' + kind;
    }
    // Spend on a name only where the name is the last missing field: a model call or a search on a lead that can
    // never be complete is money for nothing.
    if (p.email_status !== 'mx_ok' || !p.phone_e164 || !p.emirate) return;
    let person: { name: string; title: string; src: string } | null = null;
    let answer: string | null = null;
    if (o.askModel && texts.length && Date.now() < stopAt && modelLeft()) {
      out.model_calls++;   // the model also judges the pattern's candidate: a candidate it does not confirm is dropped
      const reply = await o.askModel(contactPrompt(p.company_name, texts, candidate)).catch(() => ({ content: null, cost_usd: 0 }));
      out.llm_cost_usd += reply.cost_usd; answer = reply.content; p.model_answer = answer;
      const got = acceptContact(answer, texts);
      if (got) person = { name: got.name, title: got.title, src: got.url + ' (read by model)' };
    }
    // No model answer at all (not a "not real" verdict): the pattern's candidate stands, as it did before the model.
    if (!person && answer === null && candidate) person = { name: candidate.name, title: candidate.title, src: candidate.url };
    if (!person && Date.now() < stopAt && serperLeft()) {
      // Public Google results only (Serper search). The LinkedIn page is never opened; the result TITLE is the source.
      out.linkedin_queries++;
      try {
        const core = p.company_name.split(/[|,(]| - /)[0].replace(/\b(l\.?l\.?c|fze|fzco|fz-llc|est|co)\b\.?/gi, '').trim();
        const res = await serper("search", { q: `site:linkedin.com/in "${core}"`, gl: "ae", num: 10 });
        for (const r of (res.organic || []).slice(0, 2)) if (out.linkedin_titles.length < 40) out.linkedin_titles.push(String(r.title || ""));
        out.serper_credits += Number(res.credits ?? 1);
        for (const r of res.organic || []) {
          const lp = linkedinPerson(String(r.title || ''), p.company_name);
          if (lp) { person = { ...lp, src: 'serper:search google result title ' + (r.link || '') }; break; }
        }
      } catch (e) { out.errors.push('linkedin search: ' + String(e).slice(0, 100)); }
    }
    if (person) { p.contact_name = person.name; p.contact_title = person.title; p.field_sources.contact_name = person.src; p.field_sources.contact_title = person.src; }
  }

  // Crawl only places that already carry a trade and a site: the rest can never become complete.
  const toCrawl = out.prospects.filter((p) => p.trade_code && p.domain).slice(0, o.maxSites);
  await Promise.all(Array.from({ length: 6 }, async (_, w) => {
    for (let i = w; i < toCrawl.length; i += 6) {
      if (Date.now() > stopAt) return;
      await crawlSite(toCrawl[i]).catch((e) => out.errors.push(`${toCrawl[i].domain}: ${String(e).slice(0, 100)}`));
    }
  }));
  return out;
}

// ── ONE BATCH (the marketing function's 'lead_sourcing' action; pg_cron lead_sourcing_batch, every 10 minutes) ──
// One (trade, emirate) cell per batch, fewest suppliers first. Before it spends anything the batch RESERVES its budget
// (fn_lead_sourcing_begin: under an advisory lock, one reservation at a time, never more than the day has left of the
// lead quota, the Serper USD cap and the model USD cap). The reservation counts as spent until the batch records its
// real spend, so a batch killed at the 150 s cap, or a failed record call, can never let the day overspend.
// 110 s of work, inside the edge's 150 s cap with room to record. The day before is reported to the CEO.
export const BATCH_DEADLINE_MS = 110_000;
export const BATCH_SERPER_CREDITS = 80;   // the pilot's busiest batch spent 22
export const BATCH_LLM_USD = 0.1;         // the pilot spent ~USD 0.001 a model call, ~21 calls in its busiest batch
// deno-lint-ignore no-explicit-any
export async function runLeadBatch(admin: any, askModel: AskModel): Promise<Record<string, unknown>> {
  const key = Deno.env.get('SERPER_API_KEY');
  if (!key) return { ok: false, error: 'no SERPER_API_KEY edge secret' };
  const report = await admin.rpc('fn_lead_sourcing_daily_report');
  const cells = await admin.rpc('fn_lead_sourcing_next_cells', { p_limit: 1 });
  if (cells.error || !cells.data?.length) return { ok: false, error: 'fn_lead_sourcing_next_cells: ' + (cells.error?.message ?? 'no cell') };
  const cell = cells.data[0] as Trade & { emirate: string };
  const begun = await admin.rpc('fn_lead_sourcing_begin', { p_emirate: cell.emirate, p_trades: [cell.code],
    p_serper_credits: BATCH_SERPER_CREDITS, p_llm_usd: BATCH_LLM_USD });
  if (begun.error) return { ok: false, error: 'fn_lead_sourcing_begin: ' + begun.error.message };
  const b = begun.data as { run_id?: number; serper_credits: number; llm_usd: number; usd_per_credit: number; stop?: string };
  if (!b.run_id) return { ok: true, due: false, ...b };
  const startedAt = new Date().toISOString();
  const r = await sourceLeads({ serperKey: key, trades: [cell], emirate: cell.emirate, pagesPerQuery: 3, maxSites: 40,
    deadlineMs: BATCH_DEADLINE_MS, askModel, maxSerperCredits: b.serper_credits, maxLlmUsd: b.llm_usd });
  const rec = await admin.rpc('fn_lead_sourcing_record', {
    p_run: { run_id: b.run_id, kind: 'batch', emirate: cell.emirate, trades: [cell.code], started_at: startedAt, queries: r.queries,
      serper_credits: r.serper_credits, usd_per_credit: b.usd_per_credit, places: r.places, sites_crawled: r.sites_crawled,
      pages_fetched: r.pages_fetched, robots_refused: r.robots_refused, model_calls: r.model_calls, llm_cost_usd: r.llm_cost_usd,
      linkedin_queries: r.linkedin_queries, errors: r.errors.slice(0, 20) },
    p_prospects: r.prospects });
  if (rec.error) return { ok: false, error: 'fn_lead_sourcing_record: ' + rec.error.message + ' (the reservation stays counted)' };
  return { ok: true, due: true, cell: `${cell.code}@${cell.emirate}`, ...(rec.data as Record<string, unknown>),
    report: report.error ? report.error.message : report.data };
}
