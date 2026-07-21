// sup_dob — persist supplier owner date-of-birth (KYC) for the caller's claimed company.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const b = await req.json().catch(() => ({}));
    const dob = String(b.owner_dob || '').slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dob)) return J({ error: 'bad_date' }, 400);
    const { error } = await admin.from('leads').update({ owner_dob: dob }).eq('claimed_by', user.email.toLowerCase());
    if (error) return J({ error: error.message }, 500);
    return J({ ok: true });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
