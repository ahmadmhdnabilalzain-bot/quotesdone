// os_incidents — Phase 5 incident capture, escalation, and runbook library.
// Admin-gated. "Get help" opens an incident and notifies the founder (via fn_os_incident_open).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
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
    // 3 SEP 2026 — THE INTERNAL CALLER. The action dispatcher (fn_action_invoke_dispatch) invokes this
    // function as the incident_fix executor with a body-carried __secret and no JWT, and was answered
    // 401 three times a night: every incident_fix action dead-lettered, and the org_task behind it
    // never closed. The same door boost_recommend and the other executors carry: an internal
    // credential scoped to os_incidents (fn_internal_auth) is accepted, and acts as a NAMED system
    // identity — never as the founder's email. Admin JWT and build mode are unchanged.
    const b = await req.json().catch(() => ({} as any));
    let viaBuildMode = false, viaInternal = false;
    if (!token && b?.__secret) {
      const __auth = await requireInternal(admin, b.__secret, 'os_incidents');
      if (__auth.ok) viaInternal = true; else return J({ error: 'forbidden' }, 403);
    }
    if (!token && !viaInternal) { if (await openAccess()) viaBuildMode = true; else return J({ error: 'unauthorized' }, 401); }
    const { data: u, error: uerr } = (viaBuildMode || viaInternal) ? { data: null as any, error: null as any } : await admin.auth.getUser(token);
    let email = u?.user?.email || '';
    if (!viaBuildMode && !viaInternal && (uerr || !email)) { if (await openAccess()) viaBuildMode = true; else return J({ error: 'unauthorized' }, 401); }
    if (viaInternal) email = 'system.action_dispatcher@quotesdone.local';
    else if (viaBuildMode) email = 'build-mode@quotesdone.local';
    else if (!(await isAdmin(email))) return J({ error: 'forbidden' }, 403);

    const action = String(b?.action || '');

    // 4 SEP 2026 — THE incident_fix EXECUTOR, CALLED BY A WORKFLOW STEP. fn_action_invoke_dispatch posts
    // the step's request (workflow_run_id, step_no, actor, input) with no `action`, and this function
    // answered 400 unknown_action, which the collector filed as a failed step and the run as failed.
    // What the ops director's step "Assign an owner and open the incident" means, deterministically:
    // one register row per workflow run, owned by the step's actor; the engineer's later incident_fix
    // step ("Fix and verify the metric recovers") resolves that same row. Opened DIRECTLY, not through
    // fn_os_incident_open: that routine pages the founder over alert_founder, which is the human
    // "get help" button's job — an automated workflow opening its own incident record must not page him
    // (the health.degraded event that started the run is already the signal). Nothing here is a model.
    if (viaInternal && !action && b?.workflow_run_id) {
      const runId = String(b.workflow_run_id);
      const stepNo = Number(b.step_no) || 0;
      const actor = String(b.actor || 'ops_director');
      const stepText = String(b?.input?.step || 'incident step');
      const { data: existing } = await admin.from('os_incidents').select('id,status,detail')
        .contains('detail', { workflow_run_id: runId }).order('id', { ascending: false }).limit(1);
      const cur = (existing || [])[0] as { id: number; status: string } | undefined;
      if (!cur) {
        const { data: run } = await admin.from('workflow_run').select('context,workflow_key').eq('id', runId).maybeSingle();
        const ctx = (run?.context ?? {}) as Record<string, unknown>;
        const title = ('Incident: ' + String(ctx.title || ctx.metric || ctx.check || ctx.reason || ctx.event_type
          || (run?.workflow_key ? run.workflow_key + ' run ' + runId.slice(0, 8) : 'workflow ' + runId.slice(0, 8)))).slice(0, 200);
        const { data: ins, error: insErr } = await admin.from('os_incidents').insert({
          title, kind: 'workflow', severity: String(ctx.severity || 'medium'), status: 'open',
          detail: { workflow_run_id: runId, step_no: stepNo, step: stepText, actor, trigger: ctx, opened_by_executor: 'incident_fix' },
          opened_by: email, owner: actor,
        }).select('id').single();
        if (insErr) return J({ ok: false, error: insErr.message }, 500);
        await admin.from('os_audit_log').insert({ actor: email, action: 'incident_open', entity: 'incident', entity_id: String(ins.id),
          detail: { title, workflow_run_id: runId, step_no: stepNo, owner: actor, paged: false }, ok: true });
        return J({ ok: true, opened: ins.id, owner: actor, used_llm: false,
          note: 'Opened OS incident #' + ins.id + ' for workflow run ' + runId.slice(0, 8) + ', owner ' + actor + '. Not paged: the triggering event is the signal.' });
      }
      if (cur.status !== 'resolved') {
        const { data: res, error: resErr } = await admin.rpc('fn_os_incident_resolve', {
          p_id: cur.id, p_resolution: 'step ' + stepNo + ' "' + stepText + '" completed by ' + actor + ' in the incident_response workflow (run ' + runId + ')', p_actor: email });
        if (resErr) return J({ ok: false, error: resErr.message }, 500);
        return J({ ok: true, resolved: cur.id, used_llm: false, result: res,
          note: 'Resolved OS incident #' + cur.id + ' at step ' + stepNo + ' (' + stepText + ').' });
      }
      return J({ ok: true, incident: cur.id, already_resolved: true, used_llm: false,
        note: 'OS incident #' + cur.id + ' for this run is already resolved; nothing to do at step ' + stepNo + '.' });
    }

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
