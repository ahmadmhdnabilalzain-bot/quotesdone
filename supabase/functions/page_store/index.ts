import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('POST only', { status: 405 });
  const body = await req.json().catch(() => ({}));
  const { data: sec } = await admin.from('app_secrets').select('value').eq('key', 'content_secret').maybeSingle();
  if (!sec?.value || body.__secret !== sec.value) return new Response('forbidden', { status: 403 });
  const slug = String(body.slug || ''); const b64 = String(body.b64 || '');
  if (!slug || !b64) return new Response('missing slug/b64', { status: 400 });
  let html;
  try { html = new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))); }
  catch (e) { return new Response('bad base64: ' + String(e), { status: 400 }); }
  const { error } = await admin.from('pages').upsert({ slug, html, updated_at: new Date().toISOString() });
  return new Response(JSON.stringify({ ok: !error, error: error?.message || null, bytes: html.length }), { headers: { 'Content-Type': 'application/json' } });
});