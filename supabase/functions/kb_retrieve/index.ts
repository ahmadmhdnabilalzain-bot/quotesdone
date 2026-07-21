// kb_retrieve — RAG retrieval endpoint over the knowledge corpus (regulations + trade + materials).
// Internal: agents call with __secret (inbound_secret). Returns ranked, cited snippets to ground answers.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const query = String(body.query || '').slice(0, 500);
    const category = body.category ? String(body.category) : null;
    const limit = Math.min(Math.max(Number(body.limit) || 8, 1), 20);
    const { data, error } = await admin.rpc('kb_query', { p_query: query, p_category: category, p_limit: limit });
    if (error) return J({ error: error.message }, 500);
    const rows = (data || []) as any[];
    const grounding = rows.map((r, i) => `[${i + 1}] ${r.title}\n${r.snippet}\nSource: ${r.citation}`).join('\n\n');
    return J({ ok: true, results: rows, grounding });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
