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

// ── the figure check ────────────────────────────────────────────────────────────────────────────
const AR_DIGITS = /[٠-٩]/g;
const toWestern = (s: string) => s.replace(AR_DIGITS, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)));
const num = (s: string) => String(Number(s.replace(/[,٬]/g, '')));
/** Every number in the brief, normalised (1,000 -> 1000; 3.00 -> 3; Arabic digits -> Western). */
export function briefNumbers(brief: string): Set<string> {
  return new Set((toWestern(brief).match(/\d[\d,]*(?:\.\d+)?/g) ?? []).map(num));
}
// A money or rate figure: a number next to %, AED, Dhs, dirham(s) or درهم, either side.
const MONEY = /(?:(?:aed|dhs?|درهم|دراهم)\s*(\d[\d,]*(?:\.\d+)?)|(\d[\d,]*(?:\.\d+)?)\s*(?:%|٪|percent|في المائة|بالمائة|aed|dhs?|dirhams?|درهم|دراهم))/gi;
/** The money/rate figures in a reply that the brief does not state. Empty = the reply may go out as written. */
export function moneyFiguresNotInBrief(text: string, known: Set<string>): string[] {
  const out: string[] = [];
  for (const m of toWestern(text).matchAll(MONEY)) {
    const n = num(m[1] ?? m[2]);
    if (!known.has(n) && !out.includes(n)) out.push(n);
  }
  return out;
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
