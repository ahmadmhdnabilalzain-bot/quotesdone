import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
function b64(b: string){ const bin=atob(b); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({}));
    const { data: sec } = await admin.from('app_secrets').select('value').eq('key','inbound_secret').maybeSingle();
    if (!sec?.value || body.__secret !== sec.value) return J({ error:'forbidden' }, 403);
    const bucket = String(body.bucket||'brand'); const path = String(body.path||''); const mime = String(body.mime||'application/octet-stream');
    if (!path || !body.b64) return J({ error:'path and b64 required' }, 400);
    const { error } = await admin.storage.from(bucket).upload(path, b64(String(body.b64)), { contentType: mime, upsert: true });
    if (error) return J({ error: error.message }, 500);
    const { data } = admin.storage.from(bucket).getPublicUrl(path);
    return J({ ok:true, url: data.publicUrl });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
