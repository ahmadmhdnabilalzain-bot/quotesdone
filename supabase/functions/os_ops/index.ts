// os_ops — operational layer for QuotesDone OS. Admin-gated (JWT or x-os-key preview bypass). + audit + content editor.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, x-os-key', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function isAdmin(email: string): Promise<boolean> {
  if (!email) return false; const em = email.toLowerCase();
  try { const { data } = await admin.rpc('fn_role_of', { p_email: em }); if (['owner','admin'].includes(String(data||'').toLowerCase())) return true; } catch (_e) {}
  try { const { data } = await admin.from('app_secrets').select('value').eq('key','admin_emails').maybeSingle(); const list = String((data as any)?.value||'').toLowerCase().split(/[,;\s]+/).filter(Boolean); if (list.includes(em)) return true; } catch (_e) {}
  return false;
}
async function dbxToken(): Promise<string> {
  const key = await sec('dropbox_app_key'); const secret = await sec('dropbox_app_secret'); const refresh = await sec('dropbox_refresh_token');
  const r = await fetch('https://api.dropboxapi.com/oauth2/token', { method:'POST', headers:{ 'Content-Type':'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type:'refresh_token', refresh_token: refresh, client_id: key, client_secret: secret }) });
  const j = await r.json().catch(()=>({})); return (j as any)?.access_token || '';
}
const EDITABLE: Record<string,{ table:string; idcol:string; fields:Record<string,string> }> = {
  inquiries: { table:'inquiries', idcol:'id', fields:{ deal_owner:'text', expected_value:'num', pipeline_stage:'text', lost_reason:'text' } },
  suppliers: { table:'leads', idcol:'id', fields:{ contact_name:'text', notes:'text' } },
  tasks: { table:'crm_tasks', idcol:'id', fields:{ priority:'text', due_date:'date', title:'text', detail:'text', status:'text' } },
  expenses: { table:'expenses', idcol:'id', fields:{ category:'text', note:'text', vendor:'text', amount:'num' } },
};
// Rich content editable from the OS Content editor (multi-field textareas).
const CONTENT: Record<string,{ table:string; fields:string[] }> = {
  board_report:   { table:'board_reports',  fields:['title','body'] },
  exec_report:    { table:'exec_reports',   fields:['summary','status'] },
  finance_report: { table:'finance_reports', fields:['summary'] },
  agent_issue:    { table:'agent_actions',  fields:['title','recommendation','status','escalation_reason'] },
  security_event: { table:'security_events', fields:['severity','subject'] },
};
const READONLY = new Set(['','list','detail','supplier_stats','customer_stats','expiring_docs','dropbox','dropbox_link','files','file','stages_list','audit_log','content_get']);
Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') return J({ ok: true });
    let email = '';
    // OS BYPASS FIX 27 Jul 2026. A single static app_secrets.os_bypass_key in an x-os-key header
    // skipped the entire admin identity check, so anyone holding that string could approve or ban a
    // supplier, cancel an inquiry, post to the GL or rewrite board reports - and the audit row named
    // 'os-preview@quotesdone.com', a fabricated person, so the log read as if a colleague had done it.
    // Corrected 28 Jul 2026: an earlier version of this note claimed the key stays live "because the
    // preview surfaces read through it". That was not true and read as an instruction to create the
    // key - nothing reads through it, and app_secrets has no os_bypass_key row, which is the only
    // reason the branch is currently unreachable. Do NOT create that row to make a preview work; it
    // is a static bearer secret on an admin surface. The branch is kept only so that a key created in
    // future cannot mutate anything: it is read-only (see the READONLY gate below) and it is recorded
    // under its own name, never as an email address. os_api carries the same gate.
    let viaBypass = false;
    const osKey = req.headers.get('x-os-key') || '';
    if (osKey && osKey === (await sec('os_bypass_key'))) { email = 'os_bypass_key (no human identity)'; viaBypass = true; }
    else {
      const token = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'').trim();
      if (!token) return J({ error: 'unauthorized' }, 401);
      const { data: u, error: uerr } = await admin.auth.getUser(token);
      email = u?.user?.email || ''; if (uerr || !email) return J({ error: 'unauthorized' }, 401);
      if (!(await isAdmin(email))) return J({ error: 'forbidden' }, 403);
    }
    const b = await req.json().catch(() => ({} as any));
    const action = (b?.action as string) || '';
    const now = () => new Date().toISOString();

    // ---- audit trail: record every mutating action (never block on failure) ----
    if (!READONLY.has(action)) {
      try {
        const det: any = { ...b }; delete det.action;
        const ent = String(b.entity || b.type || (b.inquiry ? 'inquiries' : '') || (b.po ? 'purchase_orders' : ''));
        const eid = String(b.id ?? b.inquiry ?? b.po ?? b.revision ?? b.customer ?? '');
        await admin.from('os_audit_log').insert({ actor: email, action, entity: ent || null, entity_id: eid || null, detail: det });
      } catch (_e) { /* audit must never break the operation */ }
    }
    // Deliberately after the audit insert: an attempt to mutate with the static preview key is exactly
    // the event worth having on record, so it is logged first and refused second.
    if (viaBypass && !READONLY.has(action)) return J({ error: 'forbidden', hint: 'the x-os-key preview key is read-only — sign in with an admin account to make changes' }, 403);

    // ---- PHASE 1 EMERGENCY CONTAINMENT — hotfix/phase1-emergency-containment, 2 Aug 2026 ----
    // Independent audit finding 3.1: os_ops dispatches 18 mutating actions (supplier_decide,
    // po_approve, gl_post, kb_approve, doc_review_decide, cancel_inquiry, field_set, ...) behind
    // isAdmin() alone. Not one of them exists in public.control_mode_action, so an admin in Observe
    // Mode can approve a supplier, post to the general ledger or decide a document review without
    // ever opening Control Mode. Until every mutating action is registered and gated, os_ops is
    // read-only. This FAILS CLOSED: anything outside the explicit READONLY allow-list is refused,
    // including an action this file does not recognise. Placed deliberately after the audit insert
    // above, so the attempt is on record before it is refused.
    // Reverse: delete this block and redeploy. See supabase/rollback/phase1_containment_down.sql.
    if (!READONLY.has(action)) {
      return J({ error: 'containment_mutations_disabled', action,
        hint: 'Phase 1 emergency containment: os_ops mutating actions are disabled until they are registered in control_mode_action and gated by Control Mode. Read-only actions are unaffected.' }, 503);
    }

    if (action === 'audit_log') {
      const lim = Math.min(Number(b.limit || 200), 1000);
      let q = admin.from('os_audit_log').select('id,at,actor,action,entity,entity_id,detail').order('at', { ascending: false }).limit(lim);
      if (b.actor) q = q.eq('actor', String(b.actor));
      if (b.act) q = q.eq('action', String(b.act));
      if (b.entity) q = q.eq('entity', String(b.entity));
      const { data, error } = await q;
      if (error) return J({ error: error.message }, 500);
      const rows = (data || []).map((r: any) => ({ at: r.at, actor: r.actor, action: r.action, entity: r.entity, entity_id: r.entity_id, detail: r.detail ? JSON.stringify(r.detail).slice(0, 220) : '' }));
      return J({ ok: true, data: { columns: ['at','actor','action','entity','entity_id','detail'], rows, total: rows.length } });
    }

    if (action === 'content_get') {
      const cfg = CONTENT[String(b.type || '')]; if (!cfg) return J({ error: 'unknown_content_type' }, 400);
      const { data, error } = await admin.from(cfg.table).select(['id', ...cfg.fields].join(',')).eq('id', Number(b.id)).maybeSingle();
      if (error) return J({ error: error.message }, 500); if (!data) return J({ error: 'not_found' }, 404);
      return J({ ok: true, data });
    }
    if (action === 'content_save') {
      const cfg = CONTENT[String(b.type || '')]; if (!cfg) return J({ error: 'unknown_content_type' }, 400);
      const vals = (b.values || {}) as any; const patch: any = {};
      for (const k of cfg.fields) { if (k in vals) patch[k] = vals[k]; }
      if (!Object.keys(patch).length) return J({ error: 'no_fields' }, 400);
      const { error } = await admin.from(cfg.table).update(patch).eq('id', Number(b.id));
      if (error) return J({ error: error.message }, 500); return J({ ok: true });
    }

    if (action === 'list') { const { data, error } = await admin.rpc('fn_os_list', { p_entity: String(b.entity||''), p_params: b.params||{} }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'detail') { const { data, error } = await admin.rpc('fn_os_detail', { p_entity: String(b.entity||''), p_id: String(b.id||'') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'supplier_stats') { const { data, error } = await admin.rpc('fn_supplier_stats', { p_supplier_id: Number(b.id) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'customer_stats') { const { data, error } = await admin.rpc('fn_customer_stats', { p_customer: String(b.id) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'expiring_docs') { const { data, error } = await admin.rpc('fn_expiring_docs', { p_days: Number(b.days||60) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'dropbox') { const { data, error } = await admin.rpc('fn_dropbox_list', { p_prefix: String(b.prefix||'') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'dropbox_link') { const path = String(b.path||''); if (!path) return J({ error: 'path_required' }, 400); const at = await dbxToken(); if (!at) return J({ error: 'dbx_auth_failed' }, 502); const r = await fetch('https://api.dropboxapi.com/2/files/get_temporary_link', { method:'POST', headers:{ 'Authorization':'Bearer '+at, 'Content-Type':'application/json' }, body: JSON.stringify({ path }) }); const j = await r.json().catch(()=>({})); if (!(j as any)?.link) return J({ error: (j as any)?.error_summary || 'dbx_link_failed' }, 502); return J({ ok: true, data: { url: (j as any).link } }); }
    if (action === 'files') { const { data, error } = await admin.rpc('fn_entity_files', { p_entity: String(b.entity||''), p_id: String(b.id||'') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'file') { const bucket = String(b.bucket||'supplier-docs'); const path = String(b.path||'').replace(/^\/+/,''); if (!path) return J({ error: 'path_required' }, 400); const { data, error } = await admin.storage.from(bucket).createSignedUrl(path, 300); if (error || !data?.signedUrl) return J({ error: error?.message || 'sign_failed' }, 500); return J({ ok: true, data: { url: data.signedUrl } }); }
    if (action === 'stages_list') { const { data, error } = await admin.from('crm_stages').select('key,label,sort_order,probability,is_won,is_lost,active').eq('active', true).order('sort_order'); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }

    if (action === 'kb_approve') { const { data, error } = await admin.rpc('fn_kb_approve', { p_revision: Number(b.revision), p_reviewer: email, p_notes: b.note||null, p_publish: b.publish!==false }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'kb_reject') { const { error } = await admin.from('kb_revisions').update({ status:'rejected', reviewer: email, review_notes: b.note||null, decided_at: now() }).eq('id', Number(b.revision)); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'kb_gov') { const { data, error } = await admin.rpc('fn_kb_gov_approve', { p_kind: String(b.kind||''), p_id: String(b.id||''), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'po_approve') { const { data, error } = await admin.rpc('fn_po_approve', { p_po: Number(b.po), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'cancel_inquiry') { const { data, error } = await admin.rpc('fn_cancel_inquiry', { p_inquiry: String(b.inquiry||''), p_customer: String(b.customer||''), p_reason: b.reason||null }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'prompt_reject') { const { data, error } = await admin.rpc('fn_prompt_reject_draft', { p_key: String(b.key||''), p_version: Number(b.version), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'action_decide') { const op = String(b.op||''); const st = op==='approve'?'approved':(op==='reject'?'rejected':op); const { error } = await admin.from('agent_actions').update({ status: st, decided_by: email, decided_at: now() }).eq('id', Number(b.id)); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    // VERIFIED FIX 27 Jul 2026. Approving here set approval_status only and never touched
    // leads.verified, so the two flags drifted apart: supplier_api's save_profile read `verified` and
    // demoted an admin-approved supplier back to 'pending' on their next profile save, silently
    // revoking an admin decision and their ability to quote. verified now moves with the decision -
    // true on approve, false on reject and ban - so the two columns can no longer disagree. unban is
    // left alone on purpose: lifting a suspension is not a re-approval, and approval_status still rules.
    if (action === 'supplier_decide') { const op = String(b.op||''); const id = Number(b.id); let patch: any; if (op==='approve') patch={ approval_status:'approved', approved_at:now(), approval_decided_by:email, matching_blocked:false, rejection_reason:null, verified:true }; else if (op==='reject') patch={ approval_status:'rejected', approved_at:now(), approval_decided_by:email, rejection_reason:b.note||null, verified:false }; else if (op==='ban') patch={ banned:true, banned_reason:b.note||null, matching_blocked:true, verified:false }; else if (op==='unban') patch={ banned:false, matching_blocked:false }; else return J({ error:'bad_op' },400); const { error } = await admin.from('leads').update(patch).eq('id', id); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'customer_decide') { const op = String(b.op||''); const patch = op==='ban'?{ banned:true, banned_reason:b.note||null }:{ banned:false }; const { error } = await admin.from('customers').update(patch).eq('id', String(b.id)); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'doc_review_decide') { const op = String(b.op||''); const st = op==='approve'?'approved':(op==='reject'?'rejected':op); const { error } = await admin.from('doc_reviews').update({ status: st, decided_by: email, decided_at: now() }).eq('id', Number(b.id)); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'note_add') { const { error } = await admin.from('crm_notes').insert({ entity: String(b.entity||''), entity_id: String(b.id||''), body: String(b.body||''), author: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'task_create') { const { error } = await admin.from('crm_tasks').insert({ title: String(b.title||''), detail: b.detail||null, priority: b.priority||'normal', entity: b.entity||null, entity_id: b.entity_id||null, due_date: b.due_date||null, status: 'open', source: 'os' }); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'task_done') { const st = String(b.op||'done')==='reopen'?'open':'done'; const { error } = await admin.from('crm_tasks').update({ status: st, done_at: st==='done'?now():null }).eq('id', Number(b.id)); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'rfq_stage') { const { error } = await admin.from('inquiries').update({ pipeline_stage: String(b.stage||''), stage_changed_at: now() }).eq('id', String(b.inquiry||'')); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'rfq_outcome') { const patch: any = { outcome: String(b.outcome||'') }; if (b.lost_reason) patch.lost_reason = b.lost_reason; if (['completed','won'].includes(String(b.outcome))) patch.completed_at = now(); const { error } = await admin.from('inquiries').update(patch).eq('id', String(b.inquiry||'')); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }
    if (action === 'field_set') { const ent=String(b.entity||''); const field=String(b.field||''); const w=EDITABLE[ent]; if (!w || !w.fields[field]) return J({ error:'field_not_editable' },400); let val:any=b.value; if (w.fields[field]==='num') val=(val===''||val==null)?null:Number(val); if (w.fields[field]==='date'&&(val===''||val==null)) val=null; const { error } = await admin.from(w.table).update({ [field]: val }).eq(w.idcol, String(b.id)); if (error) return J({ error: error.message }, 500); return J({ ok: true }); }

    if (action === 'gl_post') {
      const lines = Array.isArray(b?.lines) ? b.lines : [];
      if (lines.length < 2) return J({ error: 'need_two_lines' }, 400);
      let dr = 0, cr = 0; const clean: any[] = [];
      for (const ln of lines) {
        const acct = String(ln?.account || ln?.account_code || '').trim();
        const debit = Number(ln?.debit || 0), credit = Number(ln?.credit || 0);
        if (!acct) return J({ error: 'missing_account' }, 400);
        if (!(debit >= 0) || !(credit >= 0)) return J({ error: 'bad_amount' }, 400);
        dr += debit; cr += credit; clean.push({ account_code: acct, debit, credit, memo: ln?.memo || null });
      }
      if (Math.round((dr - cr) * 100) !== 0) return J({ error: 'out_of_balance', debits: dr, credits: cr }, 400);
      if (Math.round(dr * 100) === 0) return J({ error: 'zero_amount' }, 400);
      const codes = [...new Set(clean.map((x) => x.account_code))];
      const { data: accts } = await admin.from('gl_accounts').select('code').in('code', codes);
      const known = new Set((accts || []).map((a: any) => a.code));
      const bad = codes.filter((x) => !known.has(x));
      if (bad.length) return J({ error: 'unknown_account:' + bad.join(',') }, 400);
      const { data: jr, error: je } = await admin.from('gl_journal').insert({ entry_date: (b?.date || now().slice(0, 10)), memo: String(b?.memo || 'OS entry'), source: 'os', currency: 'AED', created_by: email, status: 'draft' }).select('id').single();
      if (je || !jr) return J({ error: je?.message || 'journal_insert_failed' }, 500);
      const jid = (jr as any).id;
      const rows = clean.map((x, i) => ({ journal_id: jid, line_no: i + 1, account_code: x.account_code, debit: x.debit, credit: x.credit, memo: x.memo }));
      const { error: le } = await admin.from('gl_journal_lines').insert(rows);
      if (le) { try { await admin.from('gl_journal').delete().eq('id', jid); } catch (_e) {} return J({ error: le.message }, 500); }
      const { error: pe } = await admin.rpc('fn_gl_post', { p_journal: jid });
      if (pe) return J({ error: pe.message }, 500);
      return J({ ok: true, data: { journal: jid } });
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
