import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function b64ToBytes(b64: string){ const raw = atob(String(b64).replace(/^data:[^;]+;base64,/, '')); const a = new Uint8Array(raw.length); for (let i=0;i<raw.length;i++) a[i]=raw.charCodeAt(i); return a; }
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('content_secret'))) return J({ error:'forbidden' }, 403);
    const bucket = String(body.bucket || 'brand');
    const path = String(body.path || '');
    const mime = String(body.mime || 'application/octet-stream');
    if (!path || !body.b64) return J({ error:'path and b64 required' }, 400);
    const bytes = b64ToBytes(String(body.b64));
    const up = await admin.storage.from(bucket).upload(path, bytes, { contentType: mime, upsert: true });
    if (up.error) return J({ error: up.error.message }, 500);
    const { data } = admin.storage.from(bucket).getPublicUrl(path);
    return J({ ok:true, path, url: data?.publicUrl || null, bytes: bytes.length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});