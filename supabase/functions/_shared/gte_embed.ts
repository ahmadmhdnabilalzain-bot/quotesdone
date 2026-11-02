// gte-small inside the edge runtime — free, in-region, not OpenRouter. Seat: sales_engineer. 21 Sep 2026.
//
// The same six lines sales_engineer (index.ts:181-188) carries (ai_gateway carried them too until 2 Nov 2026 and now
// asks embed_ml, after its in-process run hit the 2 s CPU cap: ai_gateway/embed_is_remote.test.ts), here
// once for the supplier-facing meaning layer (service_meaning.ts) so supplier_api does not make a network
// hop to embed a line. Module scope on purpose: building the session per request is what killed kb_embed
// with WORKER_RESOURCE_LIMIT on 28 Jul. Outside the edge runtime (tests, Node) there is no Supabase.ai,
// and this returns null — the caller reports the layer as unavailable rather than guessing.
// deno-lint-ignore no-explicit-any
let session: any = null;
export async function embedLine(text: string): Promise<number[] | null> {
  try {
    // deno-lint-ignore no-explicit-any
    const ai = (globalThis as any).Supabase?.ai;
    if (!ai) return null;
    if (session === null) session = new ai.Session('gte-small');
    const v = await session.run(String(text).slice(0, 1200), { mean_pool: true, normalize: true });
    return Array.isArray(v) ? v as number[] : null;
  } catch (_e) { return null; }
}
