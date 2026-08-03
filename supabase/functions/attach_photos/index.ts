// attach_photos - persists a customer's REFERENCE photos into the inquiry package so matched suppliers
// receive them (anonymised) and can quote from them. Redact-only (no BOQ). Auth: customer JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const auth = req.headers.get('Authorization') || ''; const jwt = auth.replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const uid = (user.id || user.email).replace(/[^a-zA-Z0-9]/g, '').slice(0, 24) || 'anon';
    const body = await req.json().catch(() => ({}));
    const images = (Array.isArray(body.images) ? body.images : []).filter((im: any) => im && im.data && im.mime).slice(0, 24);
    if (!images.length) return J({ ok: true, paths: [] });
    const secret = await sec('cred_fn_attach_photos');
    const prefix = `refphoto/${uid}/${Date.now()}`;
    let paths: string[] = [];
    try {
      const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, images, prefix }) });
      const j = await r.json();
      if (j?.ok && Array.isArray(j.paths)) paths = j.paths.map((p: any) => String(p)).slice(0, 24);
    } catch (_e) { /* redaction best-effort */ }
    return J({ ok: true, paths });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
