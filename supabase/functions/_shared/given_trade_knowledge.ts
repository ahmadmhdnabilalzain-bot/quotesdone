// given_trade_knowledge.ts — the verified trade packs are GIVEN to the chat model (seat: sales_engineer, 19 Oct 2026).
//
// Measured 19 Oct 2026: site_assistant built its prompt from the company brief alone ("trade and market knowledge is
// the model's own"), so the 3,284 verified pack entries (spec checklists, UAE standards, product distinctions, lead
// times) never reached a customer's answer. Asked "used European vs new Chinese injection moulding machine, what lead
// time?", it answered from memory and declined the lead time the pack carries. Founder ruling 1195: "company rules and
// knowledge are GIVEN to the agent; the agent thinks and replies" — so the knowledge is handed over, not searched by the
// model and never returned as text by code. The nearest verified rows (fn_reason_retrieve_ml, which reads only
// runtime-eligible rows, fusing the multilingual and gte-small spaces) are placed in the prompt as a block the model
// reasons from. A failure returns '' and the reply goes on exactly as before.
export interface GivenDeps {
  embed: (t: string, space: 'gte' | 'ml') => Promise<number[] | null>;
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
  gteReads: (t: string) => boolean;
}
export interface GivenRow { source?: string; id?: string; title?: string; excerpt?: string; similarity?: number }

/** Rows below this similarity are not about the question; the multilingual space's corroboration floor (think.ts). */
export const GIVEN_FLOOR = 0.80;
/** The answer never waits on this: past it the reply goes on without the block (homepage speed rule). */
export const GIVEN_TIMEOUT_MS = 1500;
// CUSTOMER-SAFE SCOPE (release review of #1520): the customer_support read scope, which reaches sales_knowledge only for
// rows tagged to a trade (the verified trade packs), and of those only source sales_knowledge is kept: no support, seat
// or library row. A row carrying a money figure or anything that identifies a party (a phone, an email, a link, a
// company suffix) is dropped whole, never trimmed, so a price or a supplier can never reach a customer through it.
const MONEY = /(?:AED|USD|EUR|GBP|Dhs?\.?|dirhams?|درهم|\$|€|£)\s?[\d٠-٩]|[\d٠-٩][\d٠-٩,.]*\s?(?:(?:AED|USD|EUR|GBP|Dhs?|dirhams?|fils)\b|درهم|دراهم|فلس)/i;
const PARTY = /\+?\d[\d\s-]{7,}\d|[\w.+-]+@[\w-]+\.[\w.]+|https?:\/\/|www\.|\b(?:LLC|L\.L\.C|FZE|FZCO|FZ-LLC)\b|ذ\.م\.م/i;
export const customerSafe = (r: GivenRow): boolean => r.source === 'sales_knowledge' && !MONEY.test(String(r.excerpt) + ' ' + String(r.title ?? '')) && !PARTY.test(String(r.excerpt) + ' ' + String(r.title ?? ''));
function withTimeout<T>(p: Promise<T>, ms: number, fallback: T): Promise<T> {
  let t: ReturnType<typeof setTimeout> | undefined;
  return Promise.race([p, new Promise<T>((res) => { t = setTimeout(() => res(fallback), ms); })]).finally(() => clearTimeout(t));
}
const vec = (v: number[]) => '[' + v.join(',') + ']';

export function givenTradeKnowledge(deps: GivenDeps, question: string, k = 6, ms = GIVEN_TIMEOUT_MS): Promise<GivenRow[]> {
  return withTimeout(fetchGiven(deps, question, k), ms, []);
}
async function fetchGiven(deps: GivenDeps, question: string, k: number): Promise<GivenRow[]> {
  try {
    const v = await deps.embed(question, 'ml');
    if (!v) return [];
    const vg = deps.gteReads(question) ? await deps.embed(question, 'gte') : null;
    const { data, error } = await deps.rpc('fn_reason_retrieve_ml', { p_seat: 'customer_support', p_embedding: vec(v), p_embedding_gte: vg ? vec(vg) : null, p_k: k });
    if (error || !Array.isArray(data)) return [];
    return (data as GivenRow[]).filter((r) => Number(r.similarity) >= GIVEN_FLOOR && r.excerpt && customerSafe(r));
  } catch { return []; }
}

/** The prompt block. Empty when nothing relevant was found, so the prompt is then the prompt it always was. */
export function givenBlock(rows: GivenRow[]): string {
  if (!rows.length) return '';
  return '\n\nTRADE KNOWLEDGE (verified, given to you for this question; reason from it where it applies, it outranks your memory on UAE specifics such as approvals, lead times and what a quote must state; never quote it as a list):\n'
    + rows.map((r) => `- ${String(r.title ?? '').slice(0, 160)}: ${String(r.excerpt).replace(/\s+/g, ' ').slice(0, 1100)}`).join('\n');
}
