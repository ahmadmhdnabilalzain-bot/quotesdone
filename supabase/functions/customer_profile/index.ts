import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const auth = req.headers.get('Authorization') || '';
    const jwt = auth.replace(/^Bearer\s+/i, '');
    if (!jwt) return J({ error: 'not signed in' }, 401);
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'not signed in' }, 401);
    const email = user.email.toLowerCase();
    const body = await req.json().catch(() => ({}));

    if (body.action === 'get') {
      const { data } = await admin.from('customers').select('full_name,phone,phone_verified').eq('email', email).maybeSingle();
      return J({ ok: true, full_name: data?.full_name || null, phone: data?.phone || null, phone_verified: !!data?.phone_verified });
    }

    if (body.action === 'set') {
      const name = String(body.full_name || '').trim().slice(0, 80);
      if (name.length < 2) return J({ error: 'Please enter your name' }, 400);
      const { data: ex } = await admin.from('customers').select('id').eq('email', email).maybeSingle();
      if (ex) { await admin.from('customers').update({ full_name: name }).eq('id', ex.id); }
      else { await admin.from('customers').insert({ email, full_name: name }); }
      return J({ ok: true, full_name: name });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 200); }
});
