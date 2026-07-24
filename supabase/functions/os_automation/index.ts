// os_automation — Phase 2 Automation Control Panel backend.
// Admin-gated (Supabase JWT -> fn_role_of / admin_emails). Lets a non-developer see,
// pause/resume, re-time, and run-now the pg_cron jobs. Every mutation is audit-logged.
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
    const jobid = Number(b?.jobid);

    if (action === 'list') {
      const { data, error } = await admin.rpc('fn_os_automation_list');
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data: { jobs: data || [] } });
    }
    if (action === 'set_active') {
      if (!Number.isFinite(jobid)) return J({ error: 'jobid_required' }, 400);
      const { data, error } = await admin.rpc('fn_os_automation_set_active', { p_jobid: jobid, p_active: !!b.active, p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    if (action === 'reschedule') {
      if (!Number.isFinite(jobid)) return J({ error: 'jobid_required' }, 400);
      const { data, error } = await admin.rpc('fn_os_automation_reschedule', { p_jobid: jobid, p_schedule: String(b.schedule || ''), p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    if (action === 'run') {
      if (!Number.isFinite(jobid)) return J({ error: 'jobid_required' }, 400);
      const { data, error } = await admin.rpc('fn_os_automation_run', { p_jobid: jobid, p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
