// os_settings — Phase 1 Settings & Admin console backend.
// Admin-gated (Supabase JWT -> fn_role_of / admin_emails). Isolated from os_api/os_ops.
// Business-editable settings only; secret keys are structurally unreachable (the SQL
// helpers refuse any key not in os_settings_meta). Every change is audit-logged.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

async function isAdmin(email: string): Promise<boolean> {
  if (!email) return false; const em = email.toLowerCase();
  try { const { data } = await admin.rpc('fn_role_of', { p_email: em }); if (['owner', 'admin'].includes(String(data || '').toLowerCase())) return true; } catch (_e) { /* */ }
  try { const { data } = await admin.from('app_secrets').select('value').eq('key', 'admin_emails').maybeSingle(); const list = String((data as any)?.value || '').toLowerCase().split(/[,;\s]+/).filter(Boolean); if (list.includes(em)) return true; } catch (_e) { /* */ }
  return false;
}

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') return J({ ok: true });
    const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
    if (!token) return J({ error: 'unauthorized' }, 401);
    const { data: u, error: uerr } = await admin.auth.getUser(token);
    const email = u?.user?.email || '';
    if (uerr || !email) return J({ error: 'unauthorized' }, 401);
    if (!(await isAdmin(email))) return J({ error: 'forbidden' }, 403);

    const b = await req.json().catch(() => ({} as any));
    const action = String(b?.action || '');

    if (action === 'list') {
      const { data, error } = await admin.rpc('fn_os_settings_list');
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data: { settings: data || [] } });
    }
    if (action === 'set') {
      const key = String(b.key || ''); if (!key) return J({ error: 'key_required' }, 400);
      const { data, error } = await admin.rpc('fn_os_settings_set', { p_key: key, p_value: b.value == null ? '' : String(b.value), p_actor: email, p_confirm: !!b.confirm });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    if (action === 'history') {
      const key = String(b.key || ''); if (!key) return J({ error: 'key_required' }, 400);
      const { data, error } = await admin.rpc('fn_os_settings_history', { p_key: key });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data: { history: data || [] } });
    }
    if (action === 'revert') {
      const key = String(b.key || ''); if (!key) return J({ error: 'key_required' }, 400);
      const { data, error } = await admin.rpc('fn_os_settings_revert', { p_key: key, p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
