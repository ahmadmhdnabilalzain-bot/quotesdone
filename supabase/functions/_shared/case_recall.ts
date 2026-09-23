// "WE DID THAT BEFORE — WHAT DID WE DO, WAS IT FINALISED?" Seat: it_engineer (shared platform). 23 Sep 2026.
//
// The founder, 23 Sep 2026: a seat that meets a case like one it handled before must remember it, the
// way a real employee does, and it must be structural for every seat. Standing rule: by MEANING, never
// by word matching. This is the one call every seat makes BEFORE it decides:
//
//   const memory = await recallCases(admin, { seat, path, situation, trade });
//
// It embeds the situation with the in-runtime gte-small session (free, in-region, not OpenRouter —
// gte_embed.ts) and asks public.fn_case_recall for the nearest past cases above the measured floor
// (0.84; paraphrases scored 0.847-0.924, unrelated cases 0.760-0.816 — the SQL file carries the
// numbers). The cases come back masked: another customer's name, e-mail or phone never leaves here.
//
// WHAT THE SEAT MUST DO WITH IT: `memory.rule` is the instruction. Where a FINALISED prior case exists
// the seat references it by its case number, or states why this case differs. A model path puts
// `precedentBlock(memory)` into its system prompt; a deterministic path returns `memory` as evidence
// in its answer. When the vector cannot be computed the result says so (available:false) — it never
// pretends there was nothing to remember.
//
// scripts/checks/every_seat_recalls_before_it_decides.test.mjs fails if a decision path loses its call.
//
// TWO SPACES (23 Sep 2026). When fn_ml_read_space answers 'ml', the situation is embedded with
// multilingual-e5-small by ai_gateway (ml_embed_client.ts: the model never loads in this worker) and put to fn_case_recall_ml, so an Arabic situation meets its English
// precedent. A vector a caller passes in `embedding` is a gte-small vector (every caller computes it with
// embedLine for its own gte knowledge search), so it is used only on the gte path. If the multilingual
// embedder cannot answer, the call falls back to gte-small and fn_case_recall.
import { embedLine } from './gte_embed.ts';
import { embedQueryMlRemote, readSpace } from './ml_embed_client.ts';

export type RecalledCase = {
  case_id: number; seat: string; case_kind: string; trade: string | null; situation: string;
  decision: string | null; reasoning: string | null; outcome: string | null; finalised: boolean;
  finalised_at: string | null; lessons: string[]; correction: string | null; corrected_by: string | null;
  similarity: number; opened_at: string; source: string | null;
};
export type CaseMemory = {
  seat: string; path: string; available: boolean; reason?: string;
  cases: RecalledCase[]; finalised_precedent: boolean; rule: string | null;
};

export const RECALL_EMBED_MS = 1500;
// The gateway may be loading the multilingual model on a cold worker; past this the call takes the gte path.
export const RECALL_EMBED_ML_MS = 8000;

export function precedentRule(cases: RecalledCase[]): string | null {
  const fin = cases.filter((c) => c.finalised);
  if (fin.length) {
    return `A finalised prior case exists (${fin.map((c) => '#' + c.case_id).join(', ')}). Reference it by its number and follow what was decided, or state plainly why this case differs.`;
  }
  if (cases.length) {
    return `A similar prior case was started but never finalised (${cases.map((c) => '#' + c.case_id).join(', ')}). Say so, and do not treat its unfinished decision as settled.`;
  }
  return null;
}

// deno-lint-ignore no-explicit-any
type Rpc = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: any; error: { message: string } | null }> };

export async function recallCases(admin: Rpc, o: {
  seat: string; path: string; situation: string; trade?: string | null; k?: number;
  caseKind?: string | null; otherSeats?: boolean; exclude?: { table: string; id: string } | null;
  embedding?: number[] | string | null;
}): Promise<CaseMemory> {
  const base = { seat: o.seat, path: o.path, cases: [] as RecalledCase[], finalised_precedent: false, rule: null };
  const text = String(o.situation || '').trim();
  if (!text) return { ...base, available: false, reason: 'no_situation' };
  try {
    // A caller that already embedded (or tried to) passes `embedding`, even null: a second gte-small
    // session in the same worker is memory the edge runtime does not have to spare.
    const ml = (await readSpace(admin)) === 'ml' ? await embedQueryMlRemote(admin, text, 'case_recall:' + o.seat, RECALL_EMBED_ML_MS) : null;
    const vec = ml ?? ('embedding' in o ? o.embedding : await Promise.race([embedLine(text), new Promise<null>((r) => setTimeout(() => r(null), RECALL_EMBED_MS))]));
    if (!vec) return { ...base, available: false, reason: 'embedding_unavailable' };
    const { data, error } = await admin.rpc(ml ? 'fn_case_recall_ml' : 'fn_case_recall', {
      p_seat: o.seat, p_embedding: typeof vec === 'string' ? vec : '[' + vec.join(',') + ']',
      p_trade: o.trade ?? null, p_k: o.k ?? 5, p_case_kind: o.caseKind ?? null,
      p_other_seats: o.otherSeats ?? true,
      p_exclude_source_table: o.exclude?.table ?? null, p_exclude_source_id: o.exclude?.id ?? null,
    });
    if (error) return { ...base, available: false, reason: 'recall_failed: ' + error.message };
    const cases = (Array.isArray(data?.cases) ? data.cases : []) as RecalledCase[];
    return { ...base, available: true, cases, finalised_precedent: cases.some((c) => c.finalised), rule: precedentRule(cases) };
  } catch (e) {
    return { ...base, available: false, reason: 'recall_failed: ' + String((e as Error)?.message || e) };
  }
}

/** The block a model path puts in its system prompt. Empty when there is nothing to remember. */
export function precedentBlock(m: CaseMemory): string {
  if (!m.cases.length) return '';
  const lines = m.cases.map((c) => [
    `#${c.case_id} [${c.seat}/${c.case_kind}${c.trade ? ', ' + c.trade : ''}] similarity ${c.similarity}, ${c.finalised ? 'FINALISED' : 'NOT finalised'}`,
    `  situation: ${c.situation.slice(0, 400)}`,
    c.decision ? `  decided: ${c.decision.slice(0, 300)}` : '',
    c.outcome ? `  outcome: ${c.outcome.slice(0, 300)}` : '',
    c.correction ? `  CORRECTED (${c.corrected_by}): ${c.correction.slice(0, 300)}` : '',
    c.lessons?.length ? `  lessons: ${c.lessons.slice(0, 3).join(' / ').slice(0, 400)}` : '',
  ].filter(Boolean).join('\n'));
  return `\n\nPAST CASES LIKE THIS ONE (institutional memory; identities are masked and must stay masked):\n${lines.join('\n')}\n${m.rule ?? ''}`;
}

/** What goes into a log or a customer-safe answer: case numbers only, never the text. */
export const recallTrace = (m: CaseMemory) => ({
  available: m.available, reason: m.reason ?? null,
  cases: m.cases.map((c) => ({ case_id: c.case_id, similarity: c.similarity, finalised: c.finalised })),
  finalised_precedent: m.finalised_precedent,
});
