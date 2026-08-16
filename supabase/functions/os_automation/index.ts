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
    // BUILD MODE — the same open door os_api has carried since 15 Aug 2026. Its absence here is
    // exactly why this tab answered "Session expired" while the console beside it worked: five
    // surfaces were each written with their own auth preamble, and only one of them was taught
    // about the open door. The gate is READ, never cached, so "activate the credentials" closes
    // all of them at once with the single INSERT it was always meant to be. Absent any row it is
    // CLOSED, and a gate that cannot be read is CLOSED — a fresh database is never open by
    // accident. The identity is NAMED rather than borrowed: an open door that signed the audit log
    // with the founder's own email would make every row of it a lie.
    const BUILD_IDENTITY = 'build-mode@quotesdone.local';
    let viaBuildMode = false;
    const openAccess = async () => {
      try { const { data } = await admin.rpc('fn_os_open_access'); return data === true; }
      catch (_e) { return false; }
    };

    if (!token) { if (await openAccess()) { viaBuildMode = true; } else return J({ error: 'unauthorized' }, 401); }
    const { data: u, error: uerr } = viaBuildMode ? { data: null, error: null } : await admin.auth.getUser(token);
    let email = u?.user?.email || '';
    if (!email) { if (viaBuildMode || await openAccess()) { viaBuildMode = true; email = BUILD_IDENTITY; } else return J({ error: 'unauthorized' }, 401); }
    if (uerr && !viaBuildMode) return J({ error: 'unauthorized' }, 401);
    // Build mode is its own authorisation: the open door was opened deliberately and is recorded
    // in os_open_access_log, so a named build-mode identity does not also have to appear on the
    // admin allow-list. Without this the request passes the session gate and is then refused 403
    // by isAdmin, which is the same locked tab with a different status code.
    if (!viaBuildMode && !(await isAdmin(email))) return J({ error: 'forbidden' }, 403);

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
