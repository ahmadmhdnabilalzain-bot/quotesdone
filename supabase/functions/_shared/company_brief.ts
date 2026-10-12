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
/** The brief for a language, rebuilt from the live sources at most every BRIEF_TTL_MS per worker. */
export async function companyBrief(rpc: Rpc, faqs: Faq[], facts: string, lang: 'en' | 'ar', blocks: string[] = [], now = Date.now()): Promise<string> {
  const key = [lang, facts.length, ...blocks.map((b) => b.length)].join('\u0001');
  const hit = cache.get(key);
  if (hit && now - hit.at < BRIEF_TTL_MS) return hit.brief;
  let company = '';
  try { const { data } = await rpc('fn_company_context', { p_max_chars: 8000, p_audience: 'public' }); company = String((data as { block?: string } | null)?.block || ''); } catch (_e) { company = ''; }
  const brief = composeBrief({ company, facts, faqs, lang, blocks });
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

/** Complete sentences off the front of a growing buffer, and what is left. Newlines end a sentence too. */
export function takeSentences(buf: string): { done: string[]; rest: string } {
  const done: string[] = [];
  const re = /[^.!?؟\n]*(?:[.!?؟]+["')\]]*\s+|\n+)/y;
  let i = 0; let m: RegExpExecArray | null;
  re.lastIndex = 0;
  while ((m = re.exec(buf))) { if (!m[0]) break; done.push(m[0]); i = re.lastIndex; }
  return { done, rest: buf.slice(i) };
}
