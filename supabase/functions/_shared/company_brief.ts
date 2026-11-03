// THE COMPANY BRIEF (customer_support, 12 Oct 2026; founder rulings 1195 and 1196). Customer-, supplier- and
// visitor-facing chat answers the way Claude answers the founder: ONE model call that reasons with its own expertise,
// with the company knowledge GIVEN to it up front instead of searched for. This file builds that brief and holds the
// only rule code applies to the words: the figure check (moneyFiguresNotInBrief). Code never writes reply text.
//
// THE BRIEF is composed from the live sources of truth on every build, so it stays in sync with them:
//   - fn_company_context(public): identity, what we sell, the hard rules, live pricing from pricing_config;
//   - the caller's published facts (site_assistant's FACTS blocks);
//   - every approved public FAQ in the asker's language (the published answers, capped).
// It is sent as the gateway's sys_stable (the byte-stable, cacheable half of the system prompt) and is cached per
// worker for BRIEF_TTL_MS, so a change to a FAQ or a price reaches the brief within that window.
// ponytail: the FAQ section is capped at FAQ_CAP chars a language (≈ the first ~60 FAQs by id) and, since 3 Nov 2026, at
// what BRIEF_TOKEN_CAP leaves; rank FAQs by how often they are asked if the cap starts cutting answers people need.
// THE CORE AND ONE TRADE PACK (it_engineer, 3 Nov 2026; scripts/kb/compile_brief.mjs says what each holds). Measured
// before, ai_cost_log 30 Oct-3 Nov: every reply carried all 32 knowledge files, 140-150k Sonnet prompt tokens a reply
// (wa_inbound 1,450 calls, mean 144,310), USD 0.022-0.031 each. A reply now carries the core (~21k), the supplier how-to
// only when a supplier reads it (~5k), and AT MOST ONE trade pack (7-10k) chosen here by code from the trade the
// conversation names (tradeIn). With a pack, the price guide carries only that trade family's lines. The whole brief is
// held under BRIEF_TOKEN_CAP by construction: the FAQ takes what is left, and a pack that does not fit is left out.
// prevented by: _shared/company_brief.test.ts, _shared/brief_budget.test.ts, scripts/checks/every_brief_line_reaches_a_reply.test.mjs
import { BRIEF_PACKS, BRIEF_PART_IDS, BRIEF_PART_TEXT, BRIEF_SUPPLIER, BRIEF_TEXT } from './brief.generated.ts';
import { tradeIn } from './conversation_trade.ts';

/** Estimated Sonnet tokens (scripts/kb/compile_brief.mjs approxTokens, calibrated on production 3 Nov 2026: the cheapest
 *  wa_inbound call's whole old prompt was 139,874 tokens; this formula gives 142,228, about 2% high, on purpose). */
export const approxTokens = (t: string): number => { const ar = (String(t).match(/[\u0600-\u06FF]/g) || []).length; return Math.ceil((String(t).length - ar) / 2.55 + ar / 1.9); };
/** No reply path sends more brief than this (core, supplier part, pack, live company block, price guide, facts, FAQ). */
export const BRIEF_TOKEN_CAP = 40_000;

const PART = new Map(BRIEF_PART_IDS.map((id, i) => [id, BRIEF_PART_TEXT[i]]));
const PACKS = new Map(BRIEF_PACKS.map(([code, family, ...ids]) => [code, { family, text: ids.map((id) => PART.get(id) ?? '').join('\n\n') }]));
const FAMILY = new Map<string, string[]>();
for (const [code, family] of BRIEF_PACKS) FAMILY.set(family, [...(FAMILY.get(family) ?? []), code]);
/** The trade pack of a category code ('' when it has none). */
export const packOf = (trade?: string | null): string => (trade && PACKS.get(trade)?.text) || '';
export const hasPack = (trade: string): boolean => PACKS.has(trade);
/** Every trade playbook, for the portal's conversation plan (never sent as such). */
export const PLAYBOOK_TEXT = BRIEF_PART_IDS.map((id, i) => (id.startsWith('conversation/') ? BRIEF_PART_TEXT[i] : '')).filter(Boolean).join('\n\n');
/** Every compiled knowledge block: the core, the supplier part and every pack part. */
export const KNOWLEDGE_TEXT = [BRIEF_TEXT, BRIEF_SUPPLIER, ...BRIEF_PART_TEXT].join('\n\n');

/** THE TRADE IS STICKY (review of this change, 3 Nov 2026). The pack is for the first trade the person named in their last
 *  TRADE_WINDOW turns, then the message, then the caller's facts, as the portal's plan picks its playbook (tradeOf): a
 *  passing word in a later message ("the cabinets should match the floor tiles") does not swap a kitchen job's pack. A
 *  new job takes over once its turns fill the window. `earlier` is the person's own turns, oldest first. */
export const TRADE_WINDOW = 12;
export const conversationTrade = (message: string, earlier: string[] = [], facts?: string | null): string | null =>
  tradeIn([...earlier.slice(-TRADE_WINDOW), message, facts], hasPack);

/** The published price guide with a pack: its heading and notes, the lines of the pack's trade family, and the lines of
 *  any code that is no trade (fn_price_brief's `general` rows: MDF, plywood, cement and other materials, measured 3 Nov
 *  2026), which any job may ask about. Only another trade's lines are left out. */
export function pricesFor(guide: string, trade?: string | null): string {
  const fam = trade ? FAMILY.get(PACKS.get(trade)?.family ?? '') : undefined;
  if (!fam || !guide) return guide;
  return guide.split('\n').filter((l) => { const c = l.match(/^- ([a-z]+(?:-[a-z]+)*):/)?.[1]; return !c || !PACKS.has(c) || fam.includes(c); }).join('\n');
}

/** The text whose numbers the figure check accepts: the brief WITHOUT the authored knowledge (the core, the supplier
 *  part, the pack: every <<<FILE ...>>> block). Measured 13 Oct 2026: with the knowledge counted, "The reveal fee is
 *  5%." passed the check, because the regulation digests state a 5% VAT. Fees and prices come from the live sources
 *  (fn_company_context, fn_price_brief, FAQ); the knowledge informs the answer but never licenses a money figure. */
// AND IT ACCEPTS EXACTLY WHAT IT ACCEPTED BEFORE 3 NOV (review of this change): the price lines of other trade families
// and the FAQ rows the budget left out of the prompt are still published sources, so a figure from them (a kitchen range
// already given before the customer asked "where do I sign up?") is accepted as it always was. companyBrief records that
// unsent text against the brief it built; the prompt is smaller, the check is unchanged.
const UNSENT = new Map<string, string>();
export const figureSource = (brief: string): string =>
  brief.replace(/<<<FILE knowledge\/brief\/[^>\n]*>>>[\s\S]*?<<<END>>>/g, '') + (UNSENT.has(brief) ? '\n\n' + UNSENT.get(brief) : '');

/** ONE CACHED PREFIX FOR EVERY LANGUAGE AND CHANNEL (13 Oct 2026, coordinator's option a). The core is the brief's
 *  FIRST part and identical for every caller, so it is sent as the gateway's sys_shared with its own cache breakpoint;
 *  the rest (supplier part, trade pack, company block, price guide, FAQ, the caller's facts) is sys_stable, the same
 *  bytes for every caller that names the same trade. Language rules live in the caller's sys, after both breakpoints. */
export const BRIEF_SHARED = BRIEF_TEXT;
export function splitBrief(brief: string): { shared: string; stable: string } {
  return brief.startsWith(BRIEF_TEXT) ? { shared: BRIEF_TEXT, stable: brief.slice(BRIEF_TEXT.length) } : { shared: '', stable: brief };
}

export const FAQ_CAP = 16_000;
export const BRIEF_TTL_MS = 5 * 60_000;

type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>;
type Faq = { id?: unknown; question?: unknown; answer?: unknown; language?: unknown };

// MORE CACHED BLOCKS: a second knowledge block (next: the UAE regulations digest, mandatory codes per trade) is passed
// as `blocks` — each is appended after the FAQ inside the same byte-stable, cacheable prefix. Its numbers become figures
// the check accepts, so a block must hold published facts only.
/** One language's published FAQ, by id, capped at FAQ_CAP (the same rows that language's asker always received). */
// faqTokens: the FAQ's share of BRIEF_TOKEN_CAP, per language (companyBrief); the first rows by id that fit are kept.
function faqSection(faqs: Faq[], lang: 'en' | 'ar', faqTokens = Infinity): string {
  const mine = faqs.filter((f) => (f.language ?? 'en') === lang && f.question && f.answer)
    .sort((a, b) => Number(a.id ?? 0) - Number(b.id ?? 0));
  let faq = ''; let tokens = 0;
  for (const f of mine) {
    const line = `Q: ${String(f.question).trim()}\nA: ${String(f.answer).trim()}\n\n`;
    if (faq.length + line.length > FAQ_CAP || tokens + approxTokens(line) > faqTokens) break;
    faq += line; tokens += approxTokens(line);
  }
  return faq.trim();
}

// lang 'all' (13 Oct 2026, #1407 review): ONE brief for every language that loses nothing. The Arabic FAQ is not a
// provable translation of the English one (measured: 150 English rows, 152 Arabic, no shared id, section, sort or
// source key), so both sections ride in the one brief, each exactly as its own asker received it before.
// knowledge: the compiled blocks that ride in the stable half before the live ones (the supplier part, the trade pack).
export function composeBrief(o: { company: string; facts: string; faqs: Faq[]; lang: 'en' | 'ar' | 'all'; blocks?: string[]; knowledge?: string[]; faqTokens?: number }): string {
  const faq = o.lang === 'all' ? faqSection(o.faqs, 'en', o.faqTokens) : faqSection(o.faqs, o.lang, o.faqTokens);
  const faqAr = o.lang === 'all' ? faqSection(o.faqs, 'ar', o.faqTokens) : '';
  return [
    ...(o.knowledge ?? []).filter(Boolean),
    '# QUOTESDONE COMPANY BRIEF — everything you state about the company, its fees, terms, rules and contacts comes from here.',
    o.company.trim(),
    o.facts.trim(),
    '## PUBLISHED FAQ (the approved answers)\n' + faq,
    ...(faqAr ? ['## PUBLISHED FAQ IN ARABIC (the approved Arabic answers; the same rules apply)\n' + faqAr] : []),
    ...(o.blocks ?? []).map((b) => b.trim()),
  ].filter(Boolean).join('\n\n');
}

const cache = new Map<string, { at: number; brief: string }>();
/** 32-bit FNV-1a, hex: a content key for the per-worker cache (not security). */
export function fnv1a(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16) + ':' + s.length;
}
/** Who reads the reply and what it is about: the trade code chooses the one pack (null or unknown: none); a supplier
 *  reader also gets the supplier how-to. */
export interface BriefFor { trade?: string | null; supplier?: boolean }
/** The brief, rebuilt from the live sources at most every BRIEF_TTL_MS per worker. ONE brief for every language
 *  (13 Oct 2026): the published FAQ in both languages, each as its asker always received it (FAQ_CAP each, inside what
 *  BRIEF_TOKEN_CAP leaves), and the model answers in the person's language, set by the caller's rules after the cache
 *  breakpoints. `_lang` is kept for callers. */
export async function companyBrief(rpc: Rpc, faqs: Faq[], facts: string, _lang: 'en' | 'ar', blocks: string[] = [], now = Date.now(), o: BriefFor = {}): Promise<string> {
  const lang = 'all' as const;
  const trade = o.trade && hasPack(o.trade) ? o.trade : null;
  // Keyed on the CONTENT (review of #1330): two callers whose facts or blocks differ only in wording never share a
  // brief. The FAQ list is the same live table for every caller; its edits reach the brief within BRIEF_TTL_MS.
  const key = lang + ':' + (trade ?? '') + ':' + (o.supplier ? 's' : '') + ':' + fnv1a([facts, ...blocks].join('\u0001'));
  const hit = cache.get(key);
  if (hit && now - hit.at < BRIEF_TTL_MS) return hit.brief;
  const { company, guide } = await liveSources(rpc);
  const supplier = o.supplier ? BRIEF_SUPPLIER : '';
  // THE CAP BY CONSTRUCTION: the pack rides only if the core, the supplier part, the live blocks and the caller's facts
  // leave it room (measured: only a supplier on the website chat, with its three FACTS blocks, leaves none); the FAQ then
  // takes what is left, split evenly between its two languages.
  const fixed = (k: string[], prices: string) => approxTokens([BRIEF_TEXT, ...k, company, facts, prices, ...blocks].join('\n\n')) + 200;   // 200: headings and joins
  const withPack = trade ? [supplier, packOf(trade)] : [supplier];
  const fits = !trade || fixed(withPack, pricesFor(guide, trade)) <= BRIEF_TOKEN_CAP;
  const knowledge = fits ? withPack : [supplier];
  const prices = fits ? pricesFor(guide, trade) : guide;
  const faqTokens = Math.max(0, Math.floor((BRIEF_TOKEN_CAP - fixed(knowledge, prices)) / 2));
  // BRIEF_TEXT FIRST, byte-identical for every caller: splitBrief() hands it to the gateway as its own cached block.
  const brief = BRIEF_TEXT + '\n\n' + composeBrief({ company, facts, faqs, lang, knowledge, faqTokens, blocks: [prices, ...blocks].filter(Boolean) });
  // what the prompt left out but the figure check still accepts (figureSource): other families' price lines, FAQ rows past the budget
  const unsent = [prices === guide ? '' : guide, composeBrief({ company: '', facts: '', faqs, lang })].filter(Boolean).join('\n\n');
  const old = cache.get(key)?.brief;
  if (old !== undefined && old !== brief) UNSENT.delete(old);
  UNSENT.set(brief, unsent);
  cache.set(key, { at: now, brief });
  return brief;
}

/** The two live reads every brief carries: the company block and the PUBLISHED PRICE GUIDE (fn_price_brief: every
 *  price_benchmark range). One read per `rpc` (a request's own client), so a caller can start them before it knows the
 *  trade (warmBrief) and companyBrief reuses them. A failed read leaves that part out; the figure check then accepts none
 *  of its numbers, which is the safe side. */
// a long-lived rpc (a module-level client) re-reads after BRIEF_TTL_MS, so a price edit still reaches the brief in that window
const LIVE = new WeakMap<Rpc, { at: number; p: Promise<{ company: string; guide: string }> }>();
function liveSources(rpc: Rpc): Promise<{ company: string; guide: string }> {
  const hit = LIVE.get(rpc);
  if (hit && Date.now() - hit.at < BRIEF_TTL_MS) return hit.p;
  const read = async (fn: string, args: Record<string, unknown>) => { try { return (await rpc(fn, args)).data; } catch (_e) { return null; } };
  const p = Promise.all([read('fn_company_context', { p_max_chars: 8000, p_audience: 'public' }), read('fn_price_brief', {})])
    .then(([cc, pb]) => ({ company: String((cc as { block?: string } | null)?.block || ''), guide: typeof pb === 'string' ? pb : '' }));
  LIVE.set(rpc, { at: Date.now(), p });
  return p;
}
/** Start the live reads now, for a caller that learns the trade later (the portal reads its conversation first). */
export const warmBrief = (rpc: Rpc): void => { void liveSources(rpc); };

// ── the figure check ── (number AND unit; review of #1330, twice)
// Digits: Arabic-Indic ٠-٩ and Persian ۰-۹ become Western; the Arabic decimal mark ٫ becomes "." and the Arabic
// thousands mark ٬ is dropped. Numbers written in words (one…twenty, half; واحد…عشرون, نصف) are read as digits for the
// check only — the reply itself is never changed.
const DIGITS = '٠١٢٣٤٥٦٧٨٩', PERSIAN = '۰۱۲۳۴۵۶۷۸۹';
// Number words, read as one number per run of words ("two thousand five hundred", "خمسة وعشرون", "ثلاثة آلاف"):
// units and teens and tens ADD, hundred/thousand MULTIPLY what came before (review of #1330). "half" alone is 0.5.
const EN_UNITS: Record<string, number> = { zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
  twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90 };
const EN_SCALE: Record<string, number> = { hundred: 100, thousand: 1000, million: 1000000 };
// Each entry is the value, then its Arabic spellings.
const AR_UNITS: [number, string[]][] = [
  [1, ['واحد', 'واحدة', 'أحد', 'إحدى', 'احدى']], [2, ['اثنان', 'اثنين', 'اثنتان', 'اثنتين', 'اثنا', 'اثني', 'اثنتا']],
  [3, ['ثلاثة', 'ثلاث']], [4, ['أربعة', 'أربع', 'اربعة', 'اربع']], [5, ['خمسة', 'خمس']], [6, ['ستة', 'ست']], [7, ['سبعة', 'سبع']],
  [8, ['ثمانية', 'ثماني', 'ثمان']], [9, ['تسعة', 'تسع']], [10, ['عشرة', 'عشر']],
  [20, ['عشرون', 'عشرين']], [30, ['ثلاثون', 'ثلاثين']], [40, ['أربعون', 'أربعين', 'اربعون', 'اربعين']], [50, ['خمسون', 'خمسين']],
  [60, ['ستون', 'ستين']], [70, ['سبعون', 'سبعين']], [80, ['ثمانون', 'ثمانين']], [90, ['تسعون', 'تسعين']],
  [200, ['مئتان', 'مئتين', 'مائتان', 'مائتين']], [2000, ['ألفان', 'ألفين', 'الفان', 'الفين']], [2000000, ['مليونان', 'مليونين']],
];
const AR_SCALE: [number, string[]][] = [[100, ['مئة', 'مائة']], [1000, ['ألف', 'الف', 'آلاف', 'الاف']], [1000000, ['مليون', 'ملايين']]];
const AR_VALUE = new Map<string, number>(AR_UNITS.flatMap(([n, ws]) => ws.map((w) => [w, n] as [string, number])));
const AR_MULT = new Map<string, number>(AR_SCALE.flatMap(([n, ws]) => ws.map((w) => [w, n] as [string, number])));
// "ثلاثمئة", "خمسمائة": a unit written into the hundred
for (const [n, ws] of AR_UNITS) if (n < 10) for (const w of ws) for (const h of ['مئة', 'مائة']) AR_VALUE.set(w + h, n * 100);
const evalWords = (tokens: { add?: number; mult?: number }[]): number => {
  let total = 0, current = 0;
  for (const t of tokens) {
    if (t.add !== undefined) current += t.add;
    else if (t.mult === 100) current = (current || 1) * 100;
    else if (t.mult) { total += (current || 1) * t.mult; current = 0; }   // thousand, million
  }
  return total + current;
};
const EN_WORD = '(?:' + [...Object.keys(EN_UNITS), ...Object.keys(EN_SCALE)].join('|') + ')';
const EN_RUN = new RegExp('\\b' + EN_WORD + '(?:(?:\\s+|-)(?:and\\s+)?' + EN_WORD + ')*\\b', 'gi');
const AR_WORDS = [...AR_VALUE.keys(), ...AR_MULT.keys()].sort((x, y) => y.length - x.length).join('|');
const AR_RUN = new RegExp('(?<![\\p{L}])(?:' + AR_WORDS + ')(?:\\s+(?:و)?(?:' + AR_WORDS + '))*(?![\\p{L}])', 'gu');
const wordsToDigits = (t: string) => t
  .replace(/\bhalf\b/gi, '0.5')
  .replace(EN_RUN, (run) => String(evalWords(run.toLowerCase().split(/[\s-]+/).filter((w) => w !== 'and')
    .map((w) => w in EN_SCALE ? { mult: EN_SCALE[w] } : { add: EN_UNITS[w] }))))
  .replace(/(?<![\p{L}])نصف(?![\p{L}])/gu, '0.5')
  .replace(AR_RUN, (run) => String(evalWords(run.split(/\s+/).map((w) => w.replace(/^و(?=.)/, (m) => (AR_VALUE.has(w) || AR_MULT.has(w)) ? m : ''))
    .map((w) => AR_MULT.has(w) ? { mult: AR_MULT.get(w)! } : { add: AR_VALUE.get(w) ?? 0 }))));
const toWestern = (s: string) => {
  const t = s.replace(/[٠-٩]/g, (d) => String(DIGITS.indexOf(d))).replace(/[۰-۹]/g, (d) => String(PERSIAN.indexOf(d))).replace(/٫/g, '.').replace(/٬/g, '');
  return wordsToDigits(t);
};
const num = (s: string) => String(Number(s.replace(/,/g, '')));
// A range end must be a money figure too: "AED 1,000 - 5 working days" is NOT a range (the 5 counts days).
const NOT_MONEY = '(?!\\s*(?:working|business|calendar|days?|hours?|weeks?|months?|years?|mins?|minutes?|mm|cm|m\\b|kg|sqm|يوم|أيام|ايام|ساعة|ساعات|أسبوع|أسابيع|شهر|أشهر|سنة|سنوات))';
const N = '(\\d[\\d,]*(?:\\.\\d+)?)';
const TO = '\\s*(?:to|-|–|—|إلى|الى)\\s*';
const AED_U = '(?:(?:uae\\s+)?(?:aed|dhs?|dirhams?)\\b|درهم|دراهم|د\\.\\s?إ|د\\.\\s?ا)';
const PCT_U = '(?:%|٪|percent\\b|per\\s?cent\\b|في المائة|بالمائة|في المئة|بالمئة)';
const FEE_W = '(?:fees?|charges?|commission|surcharge|subscriptions?|prices?|costs?|رسوم|رسم|عمولة|اشتراك|سعر|تكلفة|كلفة)';
const FIGURES: { kind: 'aed' | 'pct' | 'fee'; re: RegExp }[] = [
  { kind: 'aed', re: new RegExp(AED_U + '\\s*' + N + '(?:' + TO + N + NOT_MONEY + ')?', 'gi') },   // AED 35 / AED 35 to 70
  { kind: 'aed', re: new RegExp(N + '(?:' + TO + N + ')?\\s*' + AED_U, 'gi') },                      // 35 to 70 AED / 500 درهم
  { kind: 'pct', re: new RegExp(N + '(?:' + TO + N + ')?\\s*' + PCT_U, 'gi') },                      // 3% / 10-12 % / خمسة بالمئة
  // a unit-less figure stated as a fee: "the fee is 5", "رسوم قدرها 5" — it must be one the brief states in AED or %
  { kind: 'fee', re: new RegExp(FEE_W + '\\s+(?:is|are|of|=|:|هي|قدرها|بنسبة|تبلغ|بقيمة)?\\s*' + N + '(?![\\d.,])(?!\\s*' + AED_U + ')(?!\\s*' + PCT_U + ')' + NOT_MONEY, 'gi') },
];
/** Every money or rate figure in a text, as "aed:<n>", "pct:<n>" or "fee:<n>" (a fee with no unit), normalised. */
export function figuresOf(text: string): string[] {
  const t = toWestern(String(text || ''));
  const out: string[] = [];
  for (const f of FIGURES) for (const m of t.matchAll(f.re)) for (const n of [m[1], m[2]]) if (n) { const k = f.kind + ':' + num(n); if (!out.includes(k)) out.push(k); }
  return out;
}
/** The figures the brief states, each with its unit. */
export function briefNumbers(brief: string): Set<string> {
  return new Set(figuresOf(brief));
}
/** The money/rate figures in a reply that the brief does not state WITH THAT UNIT (a unit-less fee figure must be a
 *  dirham amount or a percentage the brief states). Empty = the reply may go out as written. */
export function moneyFiguresNotInBrief(text: string, known: Set<string>): string[] {
  return figuresOf(text).filter((k) => {
    if (!k.startsWith('fee:')) return !known.has(k);
    const n = k.slice(4);
    return !known.has('aed:' + n) && !known.has('pct:' + n);
  }).map((k) => k.startsWith('pct:') ? k.slice(4) + '%' : k.startsWith('aed:') ? 'AED ' + k.slice(4) : 'a fee of ' + k.slice(4));
}

// ── the policy-claim check: false statements that carry no number ─────────────────────────────────
// A reply can be wrong without a figure: "a card fee is added", "VAT applies on the fee", "we will refund you",
// "QuotesDone is liable for the work". The brief says the opposite of each (no card fee, no VAT on the reveal fee,
// every refund is the CEO's decision, the platform is not a party to the work). A sentence that AFFIRMS one of these
// goes back to the model for a rewrite; a sentence that denies it ("no card fee is added") passes.
const NEG = /\b(no|not|never|without|nor|isn'?t|aren'?t|won'?t|doesn'?t|don'?t)\b|لا |ليس|ليست|بدون|دون|لن |غير /i;
// Ruling 1207 (13 Oct 2026): a supplier's quotation may state anything (a discount, VAT included or +5% VAT, a card
// surcharge, any terms) and is shown as stated. The no-card-fee / no-VAT rule is about OUR 3% fee only, so a sentence
// about the supplier's price or terms that does not also speak of our fee is never contradicted by these two claims.
// عرض alone also means show/display, so only its quotation forms count (review of #1356).
const SUPPLIER_TERMS = /\b(?:suppliers?|quot(?:e|es|ed|ation|ations)|prices?|discount(?:ed)?)\b|\u0627\u0644\u0645\u0648\u0631\u062F|\u0639\u0631\u0636 (?:\u0627\u0644)?\u0633\u0639\u0631|\u0639\u0631\u0648\u0636 (?:\u0627\u0644)?\u0623\u0633\u0639\u0627\u0631|(?:\u0627\u0644)?\u0633\u0639\u0631|\u062E\u0635\u0645/i;
// Any fee word that is not tied to the supplier ("supplier's fee", رسوم المورد) is about OUR fee (review of #1356:
// "The service fee includes VAT, like the quoted price" must still be caught).
const SUPPLIER_FEE = /\bsupplier'?s?'?\s+(?:own\s+)?(?:fees?|charges?|commission|surcharges?)\b|(?:\u0631\u0633\u0648\u0645|\u0639\u0645\u0648\u0644\u0629)\s+(?:\u0627\u0644)?\u0645\u0648\u0631\u062F/gi;
const OUR_FEE = /\breveal\b|\bQuotesDone\b|\bour\b|\bwe\b|\b3\s?%|\u0663\s?\u066A|\bfees?\b|\bcommission\b|\bplatform\b|\u0627\u0644\u0643\u0634\u0641|\u0631\u0633\u0648\u0645|\u0639\u0645\u0648\u0644\u0629|\u0627\u0644\u0645\u0646\u0635\u0629/i;
// A sentence whose subject is the supplier or its quote, with none of OUR markers, is the supplier's: its bare fee word
// ("The supplier charges a 5% installation fee plus VAT") is the supplier's fee (review of #1356). "quoted" is not a subject.
// Only a sentence that BEGINS with the supplier (an Arabic verb may come first: يفرض المورد) has it as subject; a
// supplier or quote mentioned later ("To unlock a quote you pay a fee plus VAT") does not shield a claim (review of #1356).
const SUPPLIER_SUBJECT = /^\s*(?:the\s+)?suppliers?(?:'s?)?\b|^\s*(?:\S+\s+)?\u0627\u0644\u0645\u0648\u0631\u062F/i;
const OUR_MARK = /\breveal\b|\bQuotesDone\b|\bour\b|\bwe\b|\bplatform\b|\byou\s+pay\b|\b3\s?%|\u0663\s?\u066A|\u0627\u0644\u0643\u0634\u0641|\u0627\u0644\u0645\u0646\u0635\u0629|\u0631\u0633\u0648\u0645\u0646\u0627|\u0639\u0645\u0648\u0644\u062A\u0646\u0627|\u062A\u062F\u0641\u0639/i;
const aboutSupplierOnly = (s: string) =>
  (SUPPLIER_SUBJECT.test(s) && !OUR_MARK.test(s)) || (SUPPLIER_TERMS.test(s) && !OUR_FEE.test(s.replace(SUPPLIER_FEE, ' ')));
// Ruling 1208: our fee is taken on the supplier's final price BEFORE / excluding VAT. A sentence giving that basis
// states policy, not VAT on our fee (the Arabic alternatives are \u escapes, so this line is not an Arabic message).
const FEE_BASIS_EX_VAT = /\b(?:before|excluding|ex)[\s-]VAT\b|\u0642\u0628\u0644 (?:\u0627\u0644)?\u0636\u0631\u064A\u0628\u0629|\u063A\u064A\u0631 \u0634\u0627\u0645\u0644/gi;
// Exempt only when the fee-basis phrase is the SOLE VAT mention: strip it, and any VAT left ("and VAT is added to it")
// is still a claim (review of #1364 at 2b2ac40).
const feeBasisOnly = (s: string) => { FEE_BASIS_EX_VAT.lastIndex = 0; if (!FEE_BASIS_EX_VAT.test(s)) return false; FEE_BASIS_EX_VAT.lastIndex = 0;
  return !/\bVAT\b|\u0636\u0631\u064A\u0628\u0629/i.test(s.replace(FEE_BASIS_EX_VAT, ' ')); };
const CLAIMS: { problem: string; re: RegExp; unless?: RegExp | ((s: string) => boolean) }[] = [
  { problem: 'it says a card fee is added (the brief: no card fee is ever added)', re: /card (?:payment |processing )?(?:fee|surcharge|charge)|\u0631\u0633\u0648\u0645 (?:\u0639\u0644\u0649 )?(?:\u0627\u0644\u062F\u0641\u0639 (?:\u0628|\u0639\u0628\u0631 )?)?\u0627\u0644\u0628\u0637\u0627\u0642\u0629|\u0631\u0633\u0648\u0645 \u0627\u0644\u0628\u0637\u0627\u0642\u0629/i, unless: aboutSupplierOnly },
  { problem: 'it says VAT is charged on the fee (the brief: no VAT on the reveal fee; the company is not VAT-registered)', re: /\bVAT\b[^.!?\u061F]*\b(?:fee|charge|reveal)|\b(?:fee|reveal)[^.!?\u061F]*\bVAT\b|\u0636\u0631\u064A\u0628\u0629 \u0627\u0644\u0642\u064A\u0645\u0629 \u0627\u0644\u0645\u0636\u0627\u0641\u0629/i, unless: (s: string) => aboutSupplierOnly(s) || feeBasisOnly(s) },
  { problem: 'it promises a refund (every refund is the CEO\'s decision)', re: /\b(?:we|we'?ll|we will|you will|you'?ll)\b[^.!?؟]*\b(?:refund|get your money back|be refunded)|سن(?:عيد|رد) (?:لك|إليك|لكم)? ?(?:المبلغ|أموالك|رسوم)|ستسترد|سيتم (?:رد|استرداد)/i,
    // the published non-response rule is conditional ("if the supplier does not respond, you are refunded"): that is policy, not a promise
    unless: /\b(?:if|when|unless)\b|إذا|إن |في حال|عند /i },
  { problem: 'it admits liability for the work (QuotesDone is not a party to the work between customer and supplier)', re: /\b(?:we are|we're|quotesdone is)\b[^.!?؟]*\b(?:liable|responsible) for\b|(?:نتحمل|تتحمل QuotesDone) المسؤولية/i },
];
/** The policy claims a reply affirms that the brief contradicts. Empty = none. */
export function policyProblems(text: string): string[] {
  const out: string[] = [];
  for (const sentence of String(text || '').split(/(?<=[.!?؟\n])\s*/)) {
    // NEG counts only in the clause that holds the claim ("Suppliers pay no fee and you pay a fee with VAT" is caught);
    // a claim that spans clauses falls back to the whole sentence (review of #1356).
    const clauses = sentence.split(/[,;\u060C\u061B]|\b(?:and|but|while)\b|\u0644\u0643\u0646/i);
    const holding = (re: RegExp) => clauses.filter((k) => re.test(k));
    const affirmed = (re: RegExp) => { const h = holding(re); return h.length ? h.some((k) => !NEG.test(k)) : re.test(sentence) && !NEG.test(sentence); };
    for (const c of CLAIMS) if (affirmed(c.re) && !(typeof c.unless === 'function' ? c.unless(sentence) : c.unless?.test(sentence)) && !out.includes(c.problem)) out.push(c.problem);
  }
  return out;
}

// ── a stated 3% fee says what is NOT added (zero tolerance; coordinator, 12-13 Oct 2026; review of #1356) ──
// Checked on the WHOLE reply. It applies when a SENTENCE states a 3% fee: a 3% figure (3%, ٣٪, "three percent", "ثلاثة
// بالمئة") together with a fee word, and none of the words of a quote's own terms or the non-response charge (a 3%
// discount, retention, advance, slope, interest, the non-response charge ...). Then the reply must NEGATE the card fee and the VAT in so
// many words: "no card fee", "without card fees", "not charged a card fee", "لا يُضاف أي مبلغ عند الدفع بالبطاقة",
// "بدون رسوم بطاقة"; "no VAT", "VAT is not charged", "لا تُفرض ضريبة". A negation elsewhere in the sentence does not
// count ("the VAT certificate is not required", "never share your card details"). Missing either: the model rewrites.
const FEE_SENTENCE = /\bfees?\b|\bcharges?\b|\bcommission\b|رسوم|رسم|عمولة/i;
// Whole words only (review of #1356): "ميل" must not match inside العميل, التحميل or جميل. Arabic terms may carry ال.
// A refund is NOT an exemption: "the 3% reveal fee is refunded if ..." still states the fee and must say no card fee / VAT.
const NOT_THE_FEE_EN = /\b(?:discounts?|retentions?|advances?|deposits?|down ?payments?|slopes?|gradients?|falls?|tolerances?|interest|penalt(?:y|ies)|non-?response)\b/i;
const NOT_THE_FEE_AR = /(?<![\p{L}])(?:ال)?(?:خصم|تخفيض|احتجاز|محتجز|ميل|انحدار|فائدة|غرامة)(?![\p{L}])|عدم الاستجابة|دفعة مقدمة/u;
const NOT_THE_FEE = { test: (t: string) => NOT_THE_FEE_EN.test(t) || NOT_THE_FEE_AR.test(t) };
const CARD_NEG = /\b(?:no|without|zero|not\s+(?:charged\s+)?(?:an?|any))\s+(?:extra\s+|additional\s+)?(?:credit\s+|debit\s+)?card\s*(?:payment\s+|processing\s+)?(?:fees?|surcharges?|charges?)\b|\bcard\s*(?:payment\s+|processing\s+)?(?:fees?|surcharges?|charges?)\s+(?:is|are)\s+(?:not|never)\b|\bnothing\s+(?:is\s+)?added\s+for\s+(?:paying\s+(?:by|with)\s+)?(?:a\s+)?card\b|بدون\s+رسوم\s+(?:على\s+)?(?:الدفع\s+)?(?:ب|عبر\s+)?(?:ال)?بطاقة|لا\s+رسوم\s+(?:على\s+)?(?:الدفع\s+)?(?:ب|عبر\s+)?(?:ال)?بطاقة|لا\s+(?:تُضاف|تضاف|يُضاف|يضاف)\s+(?:أي\s+)?(?:رسوم|مبلغ)[^.،؛]{0,25}بطاقة/i;
const VAT_NEG = /\b(?:no|without|zero)\s+VAT\b|\bVAT\s+(?:is|are)\s+not\s+(?:charged|added|applied|payable)\b|\bnot\s+(?:charged|subject\s+to)\s+VAT\b|\bno\s+value[- ]added\s+tax\b|لا\s+(?:تُفرض|تفرض|تُضاف|تضاف|تُطبق|تطبق)\s+(?:أي\s+)?ضريبة|(?:بدون|دون)\s+ضريبة|لا\s+ضريبة|غير\s+خاضع(?:ة)?\s+(?:ل)?(?:ل)?ضريبة/i;
const sentencesOf = (t: string) => t.split(/(?<=[.!?؟\n؛;])\s*/);
/** Does this sentence state a 3% fee (not a quote's discount, a slope, interest or the non-response charge)? */
export function statesThreePercentFee(sentence: string): boolean {
  return figuresOf(sentence).includes('pct:3') && FEE_SENTENCE.test(sentence) && !NOT_THE_FEE.test(sentence);
}
export function revealFeeIncomplete(text: string): string[] {
  const t = String(text || '');
  if (!sentencesOf(t).some(statesThreePercentFee)) return [];
  const out: string[] = [];
  if (!CARD_NEG.test(t)) out.push('it states the 3% fee without saying, in so many words, that no card fee is added');
  if (!VAT_NEG.test(t)) out.push('it states the 3% fee without saying, in so many words, that no VAT is charged on it');
  return out;
}

/** Complete sentences off the front of a growing buffer, and what is left. Newlines end a sentence too.
 *  A full stop between two digits ("2.5 ton", "3.2 m") is part of the number, not the end of a sentence: until 27 Oct
 *  2026 the sticky match stopped there, so everything after the first decimal stayed in `rest` and was checked (and, for
 *  the portal, filtered) as ONE piece at the end of the stream (run 91fb819d: a whole recommendation was dropped with the
 *  question at its end). */
export function takeSentences(buf: string): { done: string[]; rest: string } {
  const done: string[] = [];
  const re = /(?:[^.!?؟\n]|(?<=\d)\.(?=\d))*(?:[.!?؟]+["')\]]*\s+|\n+)/y;
  let i = 0; let m: RegExpExecArray | null;
  re.lastIndex = 0;
  while ((m = re.exec(buf))) { if (!m[0]) break; done.push(m[0]); i = re.lastIndex; }
  return { done, rest: buf.slice(i) };
}
