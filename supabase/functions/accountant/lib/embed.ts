// accountant — the free in-region embedding (gte-small), and the one session it keeps per isolate.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).

// Embedding is FREE and in-region — Supabase.ai's gte-small, 384-dim, not a paid OpenRouter route.
// It runs before any gate because it costs nothing and because a seat that cannot embed cannot
// search its own knowledge. Returns null on failure so fn_accountant_assist can fall back to its
// lexical bar rather than the call dying.
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
