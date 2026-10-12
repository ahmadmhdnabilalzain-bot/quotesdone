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
// ponytail: the FAQ section is capped at FAQ_CAP chars (≈ the first ~60 FAQs by id) to keep the brief near 8k tokens;
// rank FAQs by how often they are asked if the cap starts cutting answers people need.
// prevented by: _shared/company_brief.test.ts
export const FAQ_CAP = 16_000;
export const BRIEF_TTL_MS = 5 * 60_000;

type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>;
type Faq = { id?: unknown; question?: unknown; answer?: unknown; language?: unknown };

// MORE CACHED BLOCKS: a second knowledge block (next: the UAE regulations digest, mandatory codes per trade) is passed
// as `blocks` — each is appended after the FAQ inside the same byte-stable, cacheable prefix. Its numbers become figures
// the check accepts, so a block must hold published facts only.
export function composeBrief(o: { company: string; facts: string; faqs: Faq[]; lang: 'en' | 'ar'; blocks?: string[] }): string {
  const mine = o.faqs.filter((f) => (f.language ?? 'en') === o.lang && f.question && f.answer)
    .sort((a, b) => Number(a.id ?? 0) - Number(b.id ?? 0));
  let faq = '';
  for (const f of mine) {
    const line = `Q: ${String(f.question).trim()}\nA: ${String(f.answer).trim()}\n\n`;
    if (faq.length + line.length > FAQ_CAP) break;
    faq += line;
  }
  return [
    '# QUOTESDONE COMPANY BRIEF — everything you state about the company, its fees, terms, rules and contacts comes from here.',
    o.company.trim(),
    o.facts.trim(),
    '## PUBLISHED FAQ (the approved answers)\n' + faq.trim(),
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
/** The brief for a language, rebuilt from the live sources at most every BRIEF_TTL_MS per worker. */
export async function companyBrief(rpc: Rpc, faqs: Faq[], facts: string, lang: 'en' | 'ar', blocks: string[] = [], now = Date.now()): Promise<string> {
  // Keyed on the CONTENT (review of #1330): two callers whose facts or blocks differ only in wording never share a
  // brief. The FAQ list is the same live table for every caller; its edits reach the brief within BRIEF_TTL_MS.
  const key = lang + ':' + fnv1a([facts, ...blocks].join('\u0001'));
  const hit = cache.get(key);
  if (hit && now - hit.at < BRIEF_TTL_MS) return hit.brief;
  // The company block and the PUBLISHED PRICE GUIDE (fn_price_brief: every price_benchmark range, read live), together.
  // A failed read leaves that part out; the figure check then accepts none of its numbers, which is the safe side.
  const read = async (fn: string, args: Record<string, unknown>) => { try { return (await rpc(fn, args)).data; } catch (_e) { return null; } };
  const [cc, pb] = await Promise.all([read('fn_company_context', { p_max_chars: 8000, p_audience: 'public' }), read('fn_price_brief', {})]);
  const company = String((cc as { block?: string } | null)?.block || '');
  const prices = typeof pb === 'string' ? pb : '';
  const brief = composeBrief({ company, facts, faqs, lang, blocks: [prices, ...blocks].filter(Boolean) });
  cache.set(key, { at: now, brief });
  return brief;
}

// ── the figure check ── (number AND unit; review of #1330, twice)
// Digits: Arabic-Indic ٠-٩ and Persian ۰-۹ become Western; the Arabic decimal mark ٫ becomes "." and the Arabic
// thousands mark ٬ is dropped. Numbers written in words (one…twenty, half; واحد…عشرون, نصف) are read as digits for the
// check only — the reply itself is never changed.
const DIGITS = '٠١٢٣٤٥٦٧٨٩', PERSIAN = '۰۱۲۳۴۵۶۷۸۹';
const WORDS_EN: Record<string, string> = { half: '0.5', one: '1', two: '2', three: '3', four: '4', five: '5', six: '6', seven: '7', eight: '8',
  nine: '9', ten: '10', eleven: '11', twelve: '12', thirteen: '13', fourteen: '14', fifteen: '15', sixteen: '16', seventeen: '17', eighteen: '18',
  nineteen: '19', twenty: '20' };
// Each entry is the digit, then the Arabic words for it (longest first, so "خمسة عشر" is read before "خمسة").
const WORDS_AR: [RegExp, string][] = ([
  ['0.5', 'نصف'], ['1', 'واحد(?:ة)'], ['1', 'واحد'], ['2', 'اثنان|اثنين|اثنتان|اثنتين'], ['3', 'ثلاثة|ثلاث'], ['4', 'أربعة|أربع|اربعة|اربع'],
  ['5', 'خمسة|خمس'], ['6', 'ستة|ست'], ['7', 'سبعة|سبع'], ['8', 'ثمانية|ثماني|ثمان'], ['9', 'تسعة|تسع'], ['10', 'عشرة|عشر'],
  ['11', 'أحد عشر|احدى عشرة|إحدى عشرة'], ['12', 'اثنا عشر|اثني عشر|اثنتا عشرة'], ['15', 'خمسة عشر|خمس عشرة'], ['20', 'عشرون|عشرين'],
] as [string, string][]).sort((x, y) => y[1].length - x[1].length).map(([n, w]) => [new RegExp('(?<![\\p{L}])(?:' + w + ')(?![\\p{L}])', 'gu'), n]);
const toWestern = (s: string) => {
  let t = s.replace(/[٠-٩]/g, (d) => String(DIGITS.indexOf(d))).replace(/[۰-۹]/g, (d) => String(PERSIAN.indexOf(d))).replace(/٫/g, '.').replace(/٬/g, '');
  t = t.replace(/\b(half|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)\b/gi, (w) => WORDS_EN[w.toLowerCase()]);
  for (const [re, n] of WORDS_AR) t = t.replace(re, n);
  return t;
};
const num = (s: string) => String(Number(s.replace(/,/g, '')));
// A range end must be a money figure too: "AED 1,000 - 5 working days" is NOT a range (the 5 counts days).
const NOT_MONEY = '(?!\\s*(?:working|business|calendar|days?|hours?|weeks?|months?|years?|mins?|minutes?|mm|cm|m\\b|kg|sqm|يوم|أيام|ايام|ساعة|ساعات|أسبوع|أسابيع|شهر|أشهر|سنة|سنوات))';
const N = '(\\d[\\d,]*(?:\\.\\d+)?)';
const TO = '\\s*(?:to|-|–|—|إلى|الى)\\s*';
const AED_U = '(?:(?:uae\\s+)?(?:aed|dhs?|dirhams?)\\b|درهم|دراهم|د\\.\\s?إ|د\\.\\s?ا)';
const PCT_U = '(?:%|٪|percent\\b|per\\s?cent\\b|في المائة|بالمائة|في المئة|بالمئة)';
const FEE_W = '(?:fees?|charges?|commission|surcharge|رسوم|رسم|عمولة)';
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
const CLAIMS: { problem: string; re: RegExp; unless?: RegExp }[] = [
  { problem: 'it says a card fee is added (the brief: no card fee is ever added)', re: /card (?:payment |processing )?(?:fee|surcharge|charge)|رسوم (?:على )?(?:الدفع (?:ب|عبر )?)?البطاقة|رسوم البطاقة/i },
  { problem: 'it says VAT is charged on the fee (the brief: no VAT on the reveal fee; the company is not VAT-registered)', re: /\bVAT\b[^.!?؟]*\b(?:fee|charge|reveal)|\b(?:fee|reveal)[^.!?؟]*\bVAT\b|ضريبة القيمة المضافة/i },
  { problem: 'it promises a refund (every refund is the CEO\'s decision)', re: /\b(?:we|we'?ll|we will|you will|you'?ll)\b[^.!?؟]*\b(?:refund|get your money back|be refunded)|سن(?:عيد|رد) (?:لك|إليك|لكم)? ?(?:المبلغ|أموالك|رسوم)|ستسترد|سيتم (?:رد|استرداد)/i,
    // the published non-response rule is conditional ("if the supplier does not respond, you are refunded"): that is policy, not a promise
    unless: /\b(?:if|when|unless)\b|إذا|إن |في حال|عند /i },
  { problem: 'it admits liability for the work (QuotesDone is not a party to the work between customer and supplier)', re: /\b(?:we are|we're|quotesdone is)\b[^.!?؟]*\b(?:liable|responsible) for\b|(?:نتحمل|تتحمل QuotesDone) المسؤولية/i },
];
/** The policy claims a reply affirms that the brief contradicts. Empty = none. */
export function policyProblems(text: string): string[] {
  const out: string[] = [];
  for (const sentence of String(text || '').split(/(?<=[.!?؟\n])\s*/)) {
    for (const c of CLAIMS) if (c.re.test(sentence) && !NEG.test(sentence) && !(c.unless?.test(sentence)) && !out.includes(c.problem)) out.push(c.problem);
  }
  return out;
}

/** Complete sentences off the front of a growing buffer, and what is left. Newlines end a sentence too. */
export function takeSentences(buf: string): { done: string[]; rest: string } {
  const done: string[] = [];
  const re = /[^.!?؟\n]*(?:[.!?؟]+["')\]]*\s+|\n+)/y;
  let i = 0; let m: RegExpExecArray | null;
  re.lastIndex = 0;
  while ((m = re.exec(buf))) { if (!m[0]) break; done.push(m[0]); i = re.lastIndex; }
  return { done, rest: buf.slice(i) };
}
