// sales_engineer — the free in-region embedding (gte-small), with its one lazily built session.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).

// EMBEDDING IS FREE AND IS NOT OpenRouter. ai_gateway serves {action:'embed'} at its line 204,
// BEFORE routing and before fn_kernel_paid_provider_gate, from Supabase.ai.Session('gte-small') —
// an in-region 384-dim model with no bill and no route. Those are the same six lines, run here
// rather than across a network hop that would also need a second scoped credential for a local
// model. Verified 9 Sep 2026 by reading ai_gateway/index.ts:54-63.
// deno-lint-ignore no-explicit-any
let _emb: any = null;
export async function embed(text: string): Promise<string | null> {
  try {
    // deno-lint-ignore no-explicit-any
    if (_emb === null) _emb = new (globalThis as any).Supabase.ai.Session('gte-small');
    const v = await _emb.run(String(text).slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
    return '[' + v.join(',') + ']';
  } catch (_e) { return null; }
}
