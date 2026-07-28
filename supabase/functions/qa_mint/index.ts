import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);
    // M13 (OS audit): qa_mint creates confirmed auth users with an arbitrary email — a standing account-creation
    // primitive. Keep it OFF in production unless the founder explicitly enables it for a test session.
    if ((await sec('qa_mint_enabled')) !== 'true') return J({ error: 'qa_mint disabled (set qa_mint_enabled=true to use)' }, 403);
    const email = String(body.email||'').toLowerCase(); const password = String(body.password||'');
    if (!email || password.length < 8) return J({ error: 'bad_input' }, 400);
    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (error) return J({ ok:false, error: error.message }, 200);
    return J({ ok:true, user_id: data.user?.id });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
