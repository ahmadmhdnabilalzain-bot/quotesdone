import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string | undefined) || undefined; }
Deno.serve(async (req) => {
  const b = await req.json().catch(() => ({} as any));
  if (b.__secret !== (await sec('inbound_secret'))) return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403, headers: { 'Content-Type': 'application/json' } });
  let q = admin.from('qd_i18n').select('source, slug, title, html, status');
  if (b.source) q = q.eq('source', b.source);
  if (b.slug) q = q.eq('slug', b.slug);
  const { data } = await q;
  return new Response(JSON.stringify({ ok: true, rows: data || [] }), { headers: { 'Content-Type': 'application/json' } });
});