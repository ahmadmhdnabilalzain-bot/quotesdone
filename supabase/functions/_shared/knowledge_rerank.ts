// THE KNOWLEDGE RERANK: a cheap matrix model re-orders the fused candidates think() retrieved (12 Oct 2026, it_engineer).
//
// Why. fn_reason_retrieve_ml fuses two free embedders (multilingual-e5-small and gte-small). On the blind market
// questions the expected entry is often in the top 20 but outside the top 5: a sibling entry of the same trade
// (brands vs products vs sizes) wins by ~0.003 cosine, which is inside the noise of the embedding runtime. Writing the
// entries with the questions in view would be teaching to the test, and a bigger embedder in embed_ml costs egress on
// every worker cold start (#1297). A reader that judges meaning closes the gap instead.
//
// What. The routine is asked for up to 20 candidates (p_k 10). The model gets the question and each candidate's title
// and the first EXCERPT characters, and returns the five that best answer it, best first. The rest keep their fused
// order behind them. Any failure, refusal, hold or malformed reply returns the fused order unchanged: the rerank can
// only reorder what retrieval found, never add or drop knowledge, and never stops an answer.
//
// Cost. The call runs on the task class think() already uses for the seat's own reasoning (internal_judgement: the
// founder's matrix routes it to openai/gpt-6-luna, USD 0.10 / 0.50 per million tokens, gemini-3.8-flash behind it),
// with a hard output cap of MAX_OUT tokens and the input capped by EXCERPT x 20 candidates. ai_gateway logs every call
// to ai_cost_log (fn, task class, model, tokens, cost) and caches it for CACHE_TTL_MIN by the hash of the prompt, so
// the same question over the same candidates is paid once. Measured cost and recall are in the PR that added this file.
export const RERANK_K = 10;            // fn_reason_retrieve_ml p_k: up to 2 x k = 20 candidates
export const RERANK_TOP = 5;           // the model returns this many, best first
export const EXCERPT = 300;            // characters of each candidate's text the model reads
export const MAX_OUT = 400;            // output-token cap per call: the reply needs ~20, but at 60 the reasoning route returned empty completions (measured 12 Oct, 14 of 14 on luna) and tripped the shared breaker
export const CACHE_TTL_MIN = 10080;    // a week: the knowledge changes by load, the question text repeats

export const RERANK_SYSTEM = 'You rank knowledge entries for a UAE B2B procurement marketplace. You get a buyer question ' +
  '(English or Arabic) and numbered knowledge entries. Return ONLY JSON {"ranking":[n1,n2,n3,n4,n5]}: the numbers of the five ' +
  'entries that best answer the question, best first. Judge by meaning, not by shared words; an entry about a different trade ' +
  'or a different subject ranks below one about the question\'s own trade and subject.';

export interface Candidate { title?: string | null; excerpt?: string | null }

/** The prompt input: the question and the numbered candidates, each cut to EXCERPT characters. */
export function rerankInput(question: string, cands: Candidate[]): string {
  const items = cands.map((c, i) =>
    `${i + 1}. ${String(c.title ?? '').slice(0, 150)} — ${String(c.excerpt ?? '').replace(/\s+/g, ' ').slice(0, EXCERPT)}`);
  return `QUESTION: ${question}\n\nENTRIES:\n${items.join('\n')}`;
}

/** The candidates in their new order: the model's picks first (valid, de-duplicated), then the rest in fused order.
 *  Anything unusable in the reply returns the fused order unchanged. */
export function applyRanking<T>(cands: T[], reply: string | null | undefined): { order: T[]; reranked: boolean } {
  let picks: number[] = [];
  try {
    const j = JSON.parse(String(reply ?? '').replace(/^\s*```(?:json)?|```\s*$/g, ''));
    picks = Array.isArray(j?.ranking) ? j.ranking.map(Number) : [];
  } catch { picks = []; }
  const idx = [...new Set(picks.filter((n) => Number.isInteger(n) && n >= 1 && n <= cands.length).map((n) => n - 1))].slice(0, RERANK_TOP);
  if (!idx.length) return { order: cands, reranked: false };
  return { order: [...idx.map((i) => cands[i]), ...cands.filter((_, i) => !idx.includes(i))], reranked: true };
}
