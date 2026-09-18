// THE SALES ENGINEER'S REWRITE — a supplier's own words about its services, turned into the platform's
// standard service list. Seat: sales_engineer. 15 Sep 2026.
//
// Founder, 15 Sep 2026: "for adding services its not a checkbox or drop down menu. i told you its a voice
// to text or text box. once filled the sales engineer will rewrite that professionally since he will cross
// match based on that." So the supplier types (or, once the voice switch is on, speaks) one free text, and
// this module rewrites it. The supplier sees the result, confirms or edits it, and the CONFIRMED service
// keys are what matching reads (fn_match_capability p_services).
//
// NO MODEL. The LLM route is on hold, and a rewrite that decides who receives an inquiry must be
// reproducible. The rules:
//   1. The text is split into phrases at line breaks, bullets, numbered items, commas (, ،), semicolons
//      (; ؛), '|' and full stops.
//   2. Inside a phrase every service alias (service_aliases.json, stored in taxonomy_trade_service.aliases)
//      is matched with the trade matcher's own rule (trade_words.ts termPattern): Arabic folded the way
//      fn_ar_norm folds it, word-START anchored, Arabic proclitics and ال allowed. Where two hits overlap
//      the LONGER alias wins ("solar panel cleaning" is maintenance, not installation); two hits on the
//      very same words are both kept (Wooden doors is a joinery and a doors service).
//   3. What is left of a phrase once its hits are removed is split at 'and' / '&' / '+' / 'و' and read
//      again. Words that only describe a service in general (supply, installation, works, توريد, تركيب,
//      أعمال, ...) are not a service of their own and are dropped; anything else is kept.
//   4. A phrase, or a leftover, that names no service but names a TRADE (fn_norm_trades' aliases through
//      trade_words.ts) is kept in the supplier's words with that trade. One that names neither is kept in
//      the supplier's words, tidied, and FLAGGED for the sales engineer — never dropped, never guessed.
// EXACT OR NONE (founder, 14 Sep 2026: "either exact match or no match"): no similarity, no stemmer, no
// nearest service. A phrase the aliases do not name stays the supplier's own words until the sales
// engineer maps it.
import { arNorm, foldForMatch, termPattern, tradesFromText, type TradeTerm } from './trade_words.ts';

export type ServiceTerm = { trade_code: string; code: string; label_en: string; label_ar: string; aliases?: string[] | null };
export type RewriteItem =
  | { kind: 'service'; key: string; trade: string; label_en: string; label_ar: string; from: string }
  | { kind: 'trade'; trades: string[]; text: string; from: string }
  | { kind: 'unmatched'; text: string; from: string };
export type Rewrite = { items: RewriteItem[]; service_keys: string[]; own_words: string[]; summary_en: string; summary_ar: string };

export const MAX_TEXT = 2000;
export const MAX_PHRASES = 40;
export const PHRASE_LEN = 120;
// THE SCAN IS BOUNDED, not merely finite (TypeScript review, 18 Sep 2026). ~1,500 alias patterns are
// re-scanned against every phrase, so the worst case is the whole 2,000 characters arriving as one
// phrase that matches nothing. Capping a phrase at MATCH_LEN bounds the work at
// MAX_PHRASES x MATCH_LEN x |aliases| regardless of what the supplier sends — an edge function has a
// CPU cap that no deadline bounds, and this estate has already lost a job to one.
export const MATCH_LEN = 300;

type Compiled = { key: string; term: ServiceTerm; re: RegExp };
type Hit = { c: Compiled; start: number; end: number; len: number };

const WORD = /[\p{L}\p{N}]/u;
const HAS_AR = /[؀-ۿ]/;
// Words that describe how a service is delivered, or glue a sentence together, rather than naming a
// service. Compared after arNorm, with a leading و / ال / وال removed from Arabic words.
//
// A LEFTOVER MADE ONLY OF THESE IS NOT A PENDING TAXONOMY ITEM. Measured 18 Sep 2026 against a
// realistic supplier paragraph ("We are an interior decoration and fit-out company in Dubai. We do
// gypsum partitions... plus chiller maintenance..."): the rewriter handed the sales engineer "We are
// an", "Plus", "ننفذ" and "تجهيز في دبي" as services to decide on. Nothing the supplier named was
// lost — that queue was filling with grammar. The words below are the ones that did it: sentence
// verbs and pronouns, the connectives a list uses, and the emirates a company says it works in.
const STOP = new Set([
  'and', 'or', 'of', 'for', 'the', 'a', 'an', 'in', 'on', 'with', 'to', 'all', 'any', 'other', 'type', 'types',
  'kind', 'kinds', 'various', 'general', 'including', 'etc', 'supply', 'supplying', 'supplier', 'suppliers',
  'installation', 'installations', 'install', 'installing', 'fixing', 'works', 'work', 'service', 'services',
  'solution', 'solutions', 'maintenance', 'repair', 'repairs', 'company', 'contracting', 'contractor',
  'contractors', 'llc', 'we', 'our', 'do', 'provide', 'providing', 'also', 'system', 'systems',
  // sentence glue: a leftover made only of these says nothing about what the company does
  'are', 'is', 'was', 'be', 'been', 'am', 'us', 'you', 'they', 'it', 'its', 'their', 'his', 'her',
  'have', 'has', 'had', 'can', 'will', 'would', 'shall', 'may', 'plus', 'both', 'from', 'by', 'at', 'as',
  'that', 'this', 'these', 'those', 'who', 'which', 'what', 'where', 'when', 'than', 'then', 'such',
  'many', 'most', 'some', 'more', 'every', 'each', 'well', 'full', 'complete', 'new', 'best', 'top',
  'quality', 'high', 'professional', 'reliable', 'specialist', 'specialised', 'specialized', 'expert',
  'experts', 'experienced', 'leading', 'years', 'year', 'since', 'based', 'located', 'offer', 'offering',
  'carry', 'carrying', 'out', 'undertake', 'undertaking', 'execute', 'execution', 'deal', 'dealing',
  // the UAE, as a company writes where it works
  'uae', 'emirates', 'emirate', 'dubai', 'abu', 'dhabi', 'sharjah', 'ajman', 'fujairah', 'ras', 'khaimah',
  'quwain', 'umm', 'alquwain', 'rak', 'auh', 'dxb', 'wide', 'countrywide', 'nationwide', 'across',
  'في', 'من', 'مع', 'علي', 'الي', 'جميع', 'كافه', 'كل', 'انواع', 'نوع', 'توريد', 'تركيب', 'اعمال', 'عمل',
  'خدمات', 'خدمه', 'صيانه', 'تصليح', 'تنفيذ', 'نقوم', 'نقدم', 'لدينا', 'شركه', 'مقاولات', 'غيرها', 'ايضا',
  'انظمه', 'نظام',
  'ننفذ', 'ننفذها', 'نعمل', 'نحن', 'نستطيع', 'يمكننا', 'ونقوم', 'وننفذ', 'كذلك', 'حسب', 'الطلب', 'طلب',
  'تجهيز', 'تجهيزات',   // "fit-out" as a verb; "تجهيز مطابخ" still keeps مطابخ, "تجهيز في دبي" keeps nothing
  'خبره', 'سنوات', 'سنه', 'متخصصون', 'متخصصه', 'متخصص', 'مختصون', 'افضل', 'اعلي', 'جوده', 'احترافيه',
  'مؤسسه', 'مجموعه', 'فرع', 'فروع', 'مقرها', 'مقرنا', 'كامله', 'كامل', 'شامله', 'شامل',
  'دبي', 'ابوظبي', 'الشارقه', 'عجمان', 'الفجيره', 'الخيمه', 'القيوين', 'راس', 'ام', 'الامارات', 'امارات',
].map(arNorm));

const isStop = (w: string): boolean => {
  const n = arNorm(w).toLowerCase();
  if (n.length < 3) return true;
  const forms = [n, n.replace(/^و/, ''), n.replace(/^ال/, ''), n.replace(/^وال/, '')];
  return forms.some((f) => STOP.has(f) || f.length < 2);
};

/** Is this leftover worth putting in front of the sales engineer at all?
 *
 *  A service name is a short noun phrase — "Helicopter window polishing", "تلميع نوافذ المروحيات",
 *  "supply and installation of aluminium composite panel cladding". A sentence about the company is
 *  long and says almost nothing — "We are a leading company with many years of experience" is ten
 *  words carrying one content word. So: three or more content words is a service however long it is,
 *  and below that it has to be short. Chasing every adjective into STOP would never end; this is the
 *  shape difference, and it does not need a word list to keep working.
 *
 *  This can only drop PROSE. Anything an alias names was already matched before a leftover exists,
 *  and anything short stays whatever it is — the founder's "never dropped" is about a service the
 *  supplier named, not about the sentence it was wrapped in. */
const looksLikeAService = (text: string): boolean => {
  const words = text.split(/\s+/).filter(Boolean);
  const content = words.filter((w) => !isStop(w)).length;
  return content >= 3 || (content >= 1 && words.length <= 6);
};


/** Rule 1: the phrases of a free text, at most MAX_PHRASES, each trimmed and on one line.
 *  The list marker is stripped AFTER the split, not inside it: the line-break branch consumes the
 *  newline first, so a `(?:^|\s)•` branch could never match a bullet at the start of a line
 *  (measured by service_rewrite.test.ts, which read back "• d4" and "2) e5" as phrases). */
export function splitPhrases(text: string): string[] {
  return String(text ?? '').slice(0, MAX_TEXT)
    .split(/\r?\n|[,،;؛|]+|\.\s+/)
    .map((s) => s.replace(/^\s*(?:[•·▪●◦*–—-]|\d{1,2}[.)])\s+/, '').replace(/\s+/g, ' ').trim().slice(0, MATCH_LEN))
    .filter((s) => s.length >= 2)
    .slice(0, MAX_PHRASES);
}

/** The supplier's words, tidied: one space, no stray connector at either end, sentence case in English
 *  (short all-capital words such as VRF or HDPE are kept as written), clipped. Arabic is left as typed. */
export function tidy(text: string): string {
  let s = String(text ?? '').replace(/\s+/g, ' ')
    .replace(/^[\s,،;؛.:\-–—•·*&+/]+|[\s,،;؛.:\-–—•·*&+/]+$/g, '')
    .replace(/^(?:and|or|&)\s+/i, '').replace(/^و\s+/, '').trim();
  // The Arabic conjunction attaches to its word, so a list item reads "وتلميع نوافذ" and the supplier
  // sees its own service with an "and" stuck to the front. Stripped only on a MULTI-WORD phrase: a
  // single word could legitimately begin with و (وقود, وكالة) and must not lose its first letter.
  if (/^و[ء-ي]/.test(s) && s.includes(' ')) s = s.slice(1);
  if (!HAS_AR.test(s) && /[a-z]/i.test(s)) {
    s = s.split(' ').map((w) => (/^[A-Z0-9&]{2,4}$/.test(w) ? w : w.toLowerCase())).join(' ');
    s = s.charAt(0).toUpperCase() + s.slice(1);
  }
  return s.slice(0, PHRASE_LEN).trim();
}

/** The alias index, compiled once per request. A term is an alias; labels are not terms (a label such
 *  as "Maintenance contracts" is too general to be exact). */
export function compileServices(vocab: ServiceTerm[]): Compiled[] {
  const out: Compiled[] = [];
  for (const term of vocab) {
    for (const a of term.aliases || []) {
      const re = termPattern(a);
      if (re) out.push({ key: `${term.trade_code}.${term.code}`, term, re: new RegExp(re.source, 'giu') });
    }
  }
  return out;
}

/** Rule 2: the hits in one phrase, overlaps resolved longest-first. */
function hitsIn(norm: string, index: Compiled[]): Hit[] {
  const all: Hit[] = [];
  for (const c of index) {
    c.re.lastIndex = 0;
    for (let m = c.re.exec(norm); m; m = c.re.exec(norm)) {
      let end = m.index + m[0].length;
      while (end < norm.length && WORD.test(norm[end])) end++;   // the rest of the last word ("units")
      all.push({ c, start: m.index, end, len: m[0].length });
      if (m[0].length === 0) c.re.lastIndex++;
    }
  }
  all.sort((a, b) => b.len - a.len || a.start - b.start);
  const kept: Hit[] = [];
  for (const h of all) {
    const clash = kept.some((k) => h.start < k.end && k.start < h.end && !(k.start === h.start && k.end === h.end));
    if (!clash) kept.push(h);
  }
  return kept.sort((a, b) => a.start - b.start);
}

/** Rule 3: the leftovers of a phrase once its hits are cut out, as the supplier wrote them. */
function leftovers(phrase: string, norm: string, at: number[], hits: Hit[]): string[] {
  const orig = (a: number, b: number) => phrase.slice(at[a] ?? phrase.length, b < at.length ? at[b] : phrase.length);
  const gaps: { text: string; afterHit: boolean }[] = [];
  let pos = 0;
  for (const h of hits) {
    if (h.start > pos) gaps.push({ text: orig(pos, h.start), afterHit: pos > 0 });
    pos = Math.max(pos, h.end);
  }
  if (pos < norm.length) gaps.push({ text: orig(pos, norm.length), afterHit: pos > 0 });
  const pieces: string[] = [];
  for (const g of gaps) {
    // A leftover that follows a hit and starts with an attached و is the conjunction ("... وتنجيد سيارات").
    const t = g.afterHit ? g.text.replace(/^\s*و(?=[ء-ي])/, '') : g.text;
    for (const p of t.split(/\s+(?:and|or|with)\s+|\s*[&+]\s*|\s+و\s+/i)) {
      if (looksLikeAService(p.trim())) pieces.push(p);
    }
  }
  return pieces;
}

/** Rule 4: a phrase with no service in it — a trade, or the supplier's own words for review. */
function wordsItem(text: string, from: string, trades: TradeTerm[]): RewriteItem | null {
  const t = tidy(text);
  if (t.length < 2) return null;
  // THE TRADE IS LOOKED FOR FIRST. A phrase that names a trade is never prose, however it is wrapped
  // ("We are an interior fit out company" is seven words carrying one content word, and it is still
  // the clearest thing the supplier said). Only when no trade is named does the prose test apply.
  const codes = tradesFromText(text, trades).map((h) => h.code);
  if (codes.length) return { kind: 'trade', trades: codes, text: t, from };
  return looksLikeAService(t) ? { kind: 'unmatched', text: t, from } : null;
}

/** The whole rewrite. `services` are the active taxonomy_trade_service rows with their aliases;
 *  `trades` the active taxonomy_trade codes with theirs. */
export function rewriteServices(text: string, services: ServiceTerm[], trades: TradeTerm[]): Rewrite {
  const index = compileServices(services);
  const items: RewriteItem[] = [];
  const seenKey = new Set<string>(); const seenWords = new Set<string>(); const seenTrades = new Set<string>();
  const push = (it: RewriteItem | null) => {
    if (!it) return;
    if (it.kind === 'service') { if (seenKey.has(it.key)) return; seenKey.add(it.key); items.push(it); return; }
    const k = arNorm(it.text).toLowerCase();
    if (seenWords.has(k)) return;
    if (it.kind === 'trade') { const tk = [...it.trades].sort().join('+'); if (seenTrades.has(tk)) return; seenTrades.add(tk); }
    seenWords.add(k); items.push(it);
  };
  for (const phrase of splitPhrases(text)) {
    const { norm, at } = foldForMatch(phrase);
    const hits = hitsIn(norm, index);
    if (!hits.length) { push(wordsItem(phrase, phrase, trades)); continue; }
    for (const h of hits) {
      push({ kind: 'service', key: h.c.key, trade: h.c.term.trade_code, label_en: h.c.term.label_en, label_ar: h.c.term.label_ar, from: phrase });
    }
    for (const rest of leftovers(phrase, norm, at, hits)) push(wordsItem(rest, phrase, trades));
  }
  // A trade the supplier named in general is already carried by a service of that trade.
  const serviceTrades = new Set(items.flatMap((i) => (i.kind === 'service' ? [i.trade] : [])));
  const final = items.filter((i) => !(i.kind === 'trade' && i.trades.every((c) => serviceTrades.has(c))));
  const label = (i: RewriteItem, ar: boolean) => (i.kind === 'service' ? (ar ? i.label_ar : i.label_en) : i.text);
  return {
    items: final,
    service_keys: final.flatMap((i) => (i.kind === 'service' ? [i.key] : [])),
    own_words: final.flatMap((i) => (i.kind === 'service' ? [] : [i.text])),
    summary_en: final.map((i) => label(i, false)).join(' · '),
    summary_ar: final.map((i) => label(i, true)).join(' · '),
  };
}

/** The service keys an inquiry asks for: the same hits, over its brief and BOQ text, nothing else. */
export function servicesFromText(text: string, services: ServiceTerm[]): string[] {
  const index = compileServices(services);
  const keys = new Set<string>();
  for (const phrase of splitPhrases(String(text ?? '').slice(0, MAX_TEXT))) {
    for (const h of hitsIn(foldForMatch(phrase).norm, index)) keys.add(h.c.key);
  }
  return [...keys].sort();
}

// ── WHAT A STATED SERVICE ALSO COVERS ──────────────────────────────────────────────────────────────
// Founder, 15 Sep 2026: "you gotta make sure the sales engineer is smart in cross matching. for example
// someone who does decoration is definitely able to do flooring even through words cross matching is not
// there." public.service_implication (service_implications.json) is the sales engineer's curated list of
// those relations, each with its reason in English and Arabic. It is applied ONE level deep: what a stated
// service implies is added, what an implied service would imply is not (decoration implies false ceilings;
// false ceilings imply acoustic ceilings; decoration does NOT imply acoustic ceilings). The SQL twin is in
// fn_services_effective, and the two are held to the same seed by scripts/checks.
export type Implication = { from: string; to: string; en: string; ar: string };
export type Implied = { key: string; because: { from: string; en: string; ar: string }[]; removed: boolean };

/** The seed file's grouped rows, one relation per row. */
export const flattenImplications = (groups: { from: string; to: string[]; en: string; ar: string }[]): Implication[] =>
  groups.flatMap((g) => g.to.map((to) => ({ from: g.from, to, en: g.en, ar: g.ar })));

/** What `sources` (stated service keys and trade codes) imply, one level, minus what is already stated.
 *  An implied key the supplier unticked is still returned, marked removed, so it can be ticked again. */
export function impliedServices(sources: string[], map: Implication[], stated: string[], removed: string[] = []): Implied[] {
  const src = new Set(sources); const have = new Set(stated); const off = new Set(removed);
  const out = new Map<string, Implied>();
  for (const r of map) {
    if (!src.has(r.from) || have.has(r.to)) continue;
    const it = out.get(r.to) || { key: r.to, because: [], removed: off.has(r.to) };
    it.because.push({ from: r.from, en: r.en, ar: r.ar });
    out.set(r.to, it);
  }
  return [...out.values()].sort((a, b) => a.key.localeCompare(b.key));
}

/** Every string inside a JSON value (a BOQ's descriptions, whatever its shape), joined one per line. */
export function jsonText(v: unknown, out: string[] = [], depth = 0): string[] {
  if (depth > 6 || out.length > 400) return out;
  if (typeof v === 'string') { if (v.trim()) out.push(v.trim()); }
  else if (Array.isArray(v)) for (const x of v) jsonText(x, out, depth + 1);
  else if (v && typeof v === 'object') for (const x of Object.values(v)) jsonText(x, out, depth + 1);
  return out;
}
