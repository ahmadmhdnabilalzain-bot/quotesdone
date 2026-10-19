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
const vec = (v: number[]) => '[' + v.join(',') + ']';

export async function givenTradeKnowledge(deps: GivenDeps, question: string, k = 6): Promise<GivenRow[]> {
  try {
    const v = await deps.embed(question, 'ml');
    if (!v) return [];
    const vg = deps.gteReads(question) ? await deps.embed(question, 'gte') : null;
    const { data, error } = await deps.rpc('fn_reason_retrieve_ml', { p_seat: 'sales_engineer', p_embedding: vec(v), p_embedding_gte: vg ? vec(vg) : null, p_k: k });
    if (error || !Array.isArray(data)) return [];
    return (data as GivenRow[]).filter((r) => Number(r.similarity) >= GIVEN_FLOOR && r.excerpt);
  } catch { return []; }
}

/** The prompt block. Empty when nothing relevant was found, so the prompt is then the prompt it always was. */
export function givenBlock(rows: GivenRow[]): string {
  if (!rows.length) return '';
  return '\n\nTRADE KNOWLEDGE (verified, given to you for this question; reason from it where it applies, it outranks your memory on UAE specifics such as approvals, lead times and what a quote must state; never quote it as a list):\n'
    + rows.map((r) => `- ${String(r.title ?? '').slice(0, 160)}: ${String(r.excerpt).replace(/\s+/g, ' ').slice(0, 1100)}`).join('\n');
}
