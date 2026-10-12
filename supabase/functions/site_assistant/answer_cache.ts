// THE SAME QUESTION GETS THE SAME APPROVED ANSWER (customer_support, 12 Oct 2026). A visitor asking what we have
// already answered waited the full reasoning chain again (33-66 s). The approved reply — composed, independently
// checked, plain-language gated and guarded — is kept under an EXACT key:
//     normalised question + language + page + audience + knowledge version
// and served from the gateway's own cache layer (public.llm_cache through fn_llm_cache_lookup / fn_llm_cache_store,
// exact-hash path only: no embedding is passed, so nothing "similar" is ever served). No second cache is built.
//
// INVALIDATION IS THE KEY ITSELF. The knowledge version is a hash of what the answer was composed from on this
// request: every approved public FAQ, the passages retrieved for this question and the company block (which carries
// the live pricing figures). Edit one FAQ, one support passage or one price in pricing_config and every key changes,
// so no stale answer can be found — nothing has to be deleted.
// ponytail: the per-trade PRICE GUIDANCE (price_benchmark) is not in the version, because reading it is two model calls;
// a benchmark edit reaches a cached answer only when the TTL lapses. Add a benchmark stamp to the version if that matters.
// Only an anonymous visitor's FIRST question is cached: a signed-in answer reads that person's account, and a
// follow-up depends on the conversation before it.
// prevented by: site_assistant/answer_cache.test.ts
export const TASK_CLASS = 'site_assistant_approved_reply';
export const TTL_MIN = 24 * 60;

/** Case, Arabic diacritics and tatweel, punctuation and spacing do not make a different question. */
export function normalise(q: string): string {
  return String(q || '').normalize('NFKC').toLowerCase()
    .replace(/[ً-ْٰـ]/g, '')
    .replace(/[?؟!.,،;؛:"'`()\[\]{}…-]+/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

async function sha(s: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
  return Array.from(d, (b) => b.toString(16).padStart(2, '0')).join('');
}

export type Knowledge = { faqs: unknown[]; passages: unknown[]; company: string };
export const knowledgeVersion = (k: Knowledge) => sha(JSON.stringify([k.faqs, k.passages, k.company]));

export async function cacheKey(o: { message: string; lang: string; path: string; audience: string; knowledge: Knowledge }): Promise<string> {
  const page = String(o.path || '/').split(/[?#]/)[0].replace(/\/+$/, '') || '/';
  return 'site_assistant:v1:' + await sha([normalise(o.message), o.lang, page, o.audience, await knowledgeVersion(o.knowledge)].join('\u0001'));
}

type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>;

/** The approved reply for this exact key, or null. A failed read is a miss, never an error. */
export async function cachedReply(rpc: Rpc, key: string): Promise<string | null> {
  try {
    const { data } = await rpc('fn_llm_cache_lookup', { p_key: key, p_embedding: null, p_task_class: TASK_CLASS });
    const d = data as { hit?: boolean; kind?: string; response?: string } | null;
    return d?.hit === true && d.kind === 'exact' && typeof d.response === 'string' && d.response.trim() ? d.response : null;
  } catch (_e) { return null; }
}

export async function storeReply(rpc: Rpc, key: string, reply: string, model: string | null): Promise<void> {
  try {
    await rpc('fn_llm_cache_store', { p_key: key, p_fn: 'site_assistant', p_task_class: TASK_CLASS, p_model: model ?? 'site_assistant',
      p_response: reply, p_ttl_minutes: TTL_MIN, p_embedding: null, p_saved_usd: 0 });
  } catch (_e) { /* a missed store costs the next visitor a slower answer, nothing else */ }
}
