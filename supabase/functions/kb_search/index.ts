// kb_search — hybrid knowledge retrieval: semantic (gte-small vector) + full-text, merged with
// reciprocal-rank fusion so keyword precision and semantic recall combine robustly (also while the
// embedding backfill is still running). Secret-guarded. Input: { query, k?, category? }.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const RRF_K = 60;
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);
    const query = String(body.query || '').slice(0, 800);
    if (!query) return J({ error: 'query required' }, 400);
    const k = Math.min(Math.max(Number(body.k) || 8, 1), 20);
    const category = body.category ? String(body.category) : null;
    const pool = 20;
    const rec: Record<number, any> = {};
    const add = (r: any, rank: number, tag: string) => {
      const e = rec[r.id] || (rec[r.id] = { id: r.id, category: r.category, title: r.title, citation: r.citation, snippet: String(r.content || '').slice(0, 400), score: 0, via: [] as string[], similarity: null as number | null });
      e.score += 1 / (RRF_K + rank);
      if (!e.via.includes(tag)) e.via.push(tag);
      if (typeof r.similarity === 'number') e.similarity = Math.round(r.similarity * 1000) / 1000;
    };
    // 1) semantic (only over embedded rows)
    try {
      // deno-lint-ignore no-explicit-any
      const model = new (globalThis as any).Supabase.ai.Session('gte-small');
      const emb = await model.run(query, { mean_pool: true, normalize: true }) as number[];
      const { data: vec } = await admin.rpc('kb_match', { query_embedding: '[' + emb.join(',') + ']', match_count: pool, p_category: category });
      (vec || []).forEach((r: any, i: number) => add(r, i, 'semantic'));
    } catch (_e) { /* semantic optional; fall back to keyword */ }
    // 2) full-text
    let ftsQ = admin.from('kb_chunks').select('id, category, title, citation, content').textSearch('fts', query, { type: 'websearch', config: 'english' }).limit(pool);
    if (category) ftsQ = ftsQ.eq('category', category);
    const { data: fts } = await ftsQ;
    (fts || []).forEach((r: any, i: number) => add(r, i, 'keyword'));
    const results = Object.values(rec).sort((a: any, b: any) => b.score - a.score).slice(0, k)
      .map((e: any) => ({ id: e.id, category: e.category, title: e.title, citation: e.citation, snippet: e.snippet, similarity: e.similarity, via: e.via.join('+') }));
    return J({ ok: true, query, count: results.length, results });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
