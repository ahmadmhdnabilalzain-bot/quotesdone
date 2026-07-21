import { createClient } from 'jsr:@supabase/supabase-js@2';
const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

Deno.serve(async (req) => {
  // Gated: require inbound_secret (previously unauthenticated — OPEN_ISSUES #2).
  try {
    const body = await req.json().catch(() => ({} as any));
    const { data: s } = await sb.from('app_secrets').select('value').eq('key', 'inbound_secret').maybeSingle();
    if (!s?.value || body?.__secret !== s.value) return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403, headers: { 'Content-Type': 'application/json' } });
  } catch (_e) {
    return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403, headers: { 'Content-Type': 'application/json' } });
  }
  const model = new Supabase.ai.Session('gte-small');
  const t0 = Date.now();
  let total = 0;
  try {
    while (Date.now() - t0 < 50000) {
      const { data, error } = await sb.from('leads')
        .select('id, capability_summary, company_name')
        .is('embedding_gte', null).limit(120);
      if (error) return new Response(JSON.stringify({ error: error.message, total }), { status: 500, headers: { 'Content-Type': 'application/json' } });
      if (!data || data.length === 0) return new Response(JSON.stringify({ done: true, total }), { headers: { 'Content-Type': 'application/json' } });
      for (const r of data) {
        const text = String(r.capability_summary || r.company_name || '').slice(0, 800);
        const emb = await model.run(text, { mean_pool: true, normalize: true }) as number[];
        await sb.from('leads').update({ embedding_gte: '[' + emb.join(',') + ']' }).eq('id', r.id);
        total++;
      }
    }
    return new Response(JSON.stringify({ partial: true, total }), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e), total }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
