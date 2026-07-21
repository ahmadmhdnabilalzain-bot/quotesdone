import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function uidByEmail(email: string){ try { const { data } = await admin.rpc('auth_uid_by_email', { p_email: email }); return (data as string) || null; } catch { return null; } }
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error:'forbidden' }, 403);
    const email = String(body.email||'').trim().toLowerCase();
    const password = String(body.password||'');
    if (!email || password.length < 12) return J({ error:'email + password (min 12) required' }, 400);
    // Restrict to the admin allowlist: admin_provision may only (re)provision admin/owner accounts,
    // never arbitrary customer/supplier auth users (closes account-takeover via the shared inbound_secret).
    const allow = (await sec('admin_emails')||'').split(',').map((s)=>s.trim().toLowerCase()).filter(Boolean);
    if (!allow.includes(email)) return J({ error:'admin_provision restricted to admin_emails allowlist' }, 403);
    let uid = await uidByEmail(email);
    if (uid) { const up = await admin.auth.admin.updateUserById(uid, { password, email_confirm: true }); if (up.error) return J({ error: up.error.message }, 500); }
    else { const cr = await admin.auth.admin.createUser({ email, password, email_confirm: true }); if (cr.error || !cr.data?.user) return J({ error: cr.error?.message || 'create failed' }, 500); uid = cr.data.user.id; }
    return J({ ok:true, uid, email });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});