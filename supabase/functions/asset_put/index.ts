// asset_put - secret-gated upload of a text asset to an allow-listed bucket (CRM SPA publish + demo/admin tooling).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
const ALLOW = ['brand','quote-files','supplier-docs','agent-docs','drawing-files'];
Deno.serve(async (req) => {
  try {
    const b = await req.json().catch(() => ({} as any));
    if (b.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const path = String(b.path || ''); const content = String(b.content || ''); const ct = String(b.content_type || 'text/html; charset=utf-8');
    const bucket = String(b.bucket || 'brand');
    if (!ALLOW.includes(bucket)) return J({ error: 'bucket_not_allowed' }, 400);
    if (!path || !content) return J({ error: 'path and content required' }, 400);
    const bytes = new TextEncoder().encode(content);
    const { error } = await admin.storage.from(bucket).upload(path, bytes, { contentType: ct, upsert: true });
    if (error) return J({ error: error.message }, 500);
    return J({ ok: true, bucket, path, bytes: bytes.length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
