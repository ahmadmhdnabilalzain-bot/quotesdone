// os_incidents — Phase 5 incident capture, escalation, and runbook library.
// Admin-gated. "Get help" opens an incident and notifies the founder (via fn_os_incident_open).
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
    // BUILD MODE — the same open door os_api has carried since 15 Aug 2026. Seven OS surfaces
    // were each written with their own auth preamble and only os_api was ever taught about the
    // open door, which is why those tabs answered "Session expired" while the console beside
    // them worked. Read every request, never cached: "activate the credentials" closes all seven
    // with one INSERT. Absent any row it is CLOSED, and a gate that cannot be read is CLOSED.
    // The identity is NAMED rather than borrowed — an open door signing the audit log with the
    // founder's own email would make every row of that log a lie.
    const openAccess = async () => {
      try { const { data } = await admin.rpc('fn_os_open_access'); return data === true; }
      catch (_e) { return false; }
    };
    let viaBuildMode = false;
    if (!token) { if (await openAccess()) viaBuildMode = true; else return J({ error: 'unauthorized' }, 401); }
    const { data: u, error: uerr } = viaBuildMode ? { data: null as any, error: null as any } : await admin.auth.getUser(token);
    let email = u?.user?.email || '';
    if (!viaBuildMode && (uerr || !email)) { if (await openAccess()) viaBuildMode = true; else return J({ error: 'unauthorized' }, 401); }
    if (viaBuildMode) email = 'build-mode@quotesdone.local';
    else if (!(await isAdmin(email))) return J({ error: 'forbidden' }, 403);

    const b = await req.json().catch(() => ({} as any));
    const action = String(b?.action || '');

    if (action === 'runbooks') {
      const { data, error } = await admin.rpc('fn_os_runbooks');
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data: { runbooks: data || [] } });
    }
    if (action === 'list') {
      const { data, error } = await admin.rpc('fn_os_incident_list', { p_status: String(b.status || '') });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data: { incidents: data || [] } });
    }
    if (action === 'open') {
      const { data, error } = await admin.rpc('fn_os_incident_open', { p_title: String(b.title || ''), p_kind: String(b.kind || 'other'), p_severity: String(b.severity || 'medium'), p_detail: { description: String(b.description || '') }, p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    if (action === 'resolve') {
      const { data, error } = await admin.rpc('fn_os_incident_resolve', { p_id: Number(b.id), p_resolution: String(b.resolution || ''), p_actor: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data });
    }
    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
