// os_api — backend for QuotesDone OS. JWT-gated; owner/admin only (or a read-only x-os-key preview bypass). + audit trail. + secretary console passthrough.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, x-os-key', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
const esc = (s: string) => String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' } as any)[c]);
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }

async function isAdmin(email: string): Promise<boolean> {
  if (!email) return false;
  const em = email.toLowerCase();
  try { const { data } = await admin.rpc('fn_role_of', { p_email: em }); if (['owner', 'admin'].includes(String(data || '').toLowerCase())) return true; } catch (_e) { /* ignore */ }
  try { const { data } = await admin.from('app_secrets').select('value').eq('key', 'admin_emails').maybeSingle(); const list = String((data as any)?.value || '').toLowerCase().split(/[,;\s]+/).filter(Boolean); if (list.includes(em)) return true; } catch (_e) { /* ignore */ }
  return false;
}

const WS: Record<string, string> = {
  'ws.exec': 'fn_ws_exec', 'ws.marketplace': 'fn_ws_marketplace', 'ws.customers': 'fn_ws_customers',
  'ws.operations': 'fn_ws_operations', 'ws.ai': 'fn_ws_ai', 'ws.knowledge': 'fn_ws_knowledge',
  'ws.documents': 'fn_ws_documents', 'ws.analytics': 'fn_ws_analytics', 'ws.company': 'fn_ws_company',
  'ws.finance': 'fn_ws_finance', 'ws.agents': 'fn_ws_agents', 'ws.marketing': 'fn_ws_marketing',
  'ws.ea': 'fn_ws_ea', 'ws.reports': 'fn_ws_reports', 'ws.strategy': 'fn_ws_strategy', 'ws.governance': 'fn_ws_governance',
  'ws.fraud': 'fn_ws_fraud', 'ws.refunds': 'fn_ws_refunds',
};
const OSAPI_MUTATIONS = new Set(['inbox_send','fraud_resolve','refund_resolve','prompt_approve','prompt_rollback','prompt_gate','comment_add','review_decide','blog_publish','knowledge_dispatch','knowledge_refresh','exam_run','exam_revert']);
// Every action below that only READS. Anything not on this list is refused when the caller arrived
// through the x-os-key preview bypass (see the OS BYPASS note in Deno.serve). Derived by walking the
// action handlers in this file one by one, not by name: each RPC listed here was checked in the
// database and performs no persistent write (fn_ws_agents fills a `create temp ... on commit drop`
// table and nothing else). Deliberately NOT here, even though they read something first:
//   report_pdf     - renders and stores a PDF object in the finance-reports bucket
//   extract_doc    - reads no record; hands caller-supplied bytes to extract_text under inbound_secret
//   secretary_chat - drives the secretary agent, which acts
// and the thirteen entries of OSAPI_MUTATIONS above. An unknown action is not on the list either, so
// the bypass cannot reach a handler added later without someone deciding it is a read.
const READONLY = new Set([
  'ping','dashboard','viz','suppliers_board','rfq_board','customers_board','agents_board','activity','nav',
  'inbox','search','record','files','file','prompt_view','marketing_studio','knowledge_gaps','exam_summary','knowledge_export',
  'ws.suppliers','ws.supplier','ws.customer','ws.agent','ws.rfq',
  'ws.exec','ws.marketplace','ws.customers','ws.operations','ws.ai','ws.knowledge','ws.documents','ws.analytics',
  'ws.company','ws.finance','ws.agents','ws.marketing','ws.ea','ws.reports','ws.strategy','ws.governance','ws.fraud','ws.refunds',
]);

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') return J({ ok: true });
    const authHeader = req.headers.get('Authorization') || '';
    let email = '';
    // OS BYPASS FIX 28 Jul 2026. os_ops was hardened on 27 Jul; this twin was missed. A single static
    // app_secrets.os_bypass_key in an x-os-key header skipped the entire admin identity check on a
    // function that runs with verify_jwt:false, so anyone holding that string could send from the
    // inbox, resolve a fraud case or a refund, approve or roll back a prompt, publish a blog post,
    // dispatch knowledge, run or revert an exam, comment or decide a review - and the audit row named
    // 'os-preview@quotesdone.com', a fabricated person, so the log read as if a colleague had done it.
    // Nothing reads through this key and no app_secrets row for it exists today, which is the only
    // reason the hole was inert: creating that row alone would have opened it. It is now read-only
    // (see the READONLY gate below) and it is recorded under its own name, never as an email address.
    let viaBypass = false;
    const osKey = req.headers.get('x-os-key') || '';
    if (osKey && osKey === (await sec('os_bypass_key'))) { email = 'os_bypass_key (no human identity)'; viaBypass = true; }
    else {
      const token = authHeader.replace(/^Bearer\s+/i, '').trim();
      if (!token) return J({ error: 'unauthorized' }, 401);
      const { data: u, error: uerr } = await admin.auth.getUser(token);
      email = u?.user?.email || '';
      if (uerr || !email) return J({ error: 'unauthorized' }, 401);
      if (!(await isAdmin(email))) return J({ error: 'forbidden' }, 403);
    }

    const body = await req.json().catch(() => ({} as any));
    const action = (body?.action as string) || 'ping';

    // ---- audit trail for os_api mutations (never block) ----
    // A non-read action arriving on the preview key is audited here too, even when it is not one of
    // OSAPI_MUTATIONS: an attempt to mutate with the static key is exactly the event worth having on
    // record, so it is logged first and refused second.
    if (OSAPI_MUTATIONS.has(action) || (viaBypass && !READONLY.has(action))) {
      try {
        const det: any = { ...body }; delete det.action;
        const ent = String(body?.subject_type || (body?.transaction_id ? 'transactions' : '') || (body?.key ? 'prompt' : ''));
        const eid = String(body?.subject_id ?? body?.transaction_id ?? body?.id ?? body?.key ?? '');
        await admin.from('os_audit_log').insert({ actor: email, action, entity: ent || null, entity_id: eid || null, detail: det });
      } catch (_e) { /* audit must never break the operation */ }
    }
    // Deliberately after the audit insert, for the reason given above.
    if (viaBypass && !READONLY.has(action)) return J({ error: 'forbidden', hint: 'the x-os-key preview key is read-only — sign in with an admin account to make changes' }, 403);

    // ---- OBSERVE MODE / CONTROL MODE (2 Aug 2026, Phase 1.4) ----------------------------------
    // The founder's stated architecture is "monitor and issue rare high-level instructions". This
    // function exposes 14 actions that approve suppliers, resolve refunds and fraud, publish public
    // content, change agent prompts and send mail as the company - with, until now, no distinction
    // between looking and acting. One stolen session or one mis-tap on a phone was enough.
    //
    // Observe Mode is not a setting; it is the ABSENCE of a Control Mode session, so it is where you
    // are unless you did something deliberate. Control Mode is short-lived (15 min), needs a fresh
    // phone code that cannot be replayed, and needs a written reason stored beside whatever you then
    // change. Both the grant and every refusal go into control_mode_audit.
    if (action === 'control_mode_status') {
      const { data, error } = await admin.rpc('fn_control_mode_status', { p_actor_email: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, user: email, data });
    }
    if (action === 'control_mode_open') {
      const { data, error } = await admin.rpc('fn_control_mode_open', {
        p_actor_email: email, p_reason: String(body?.reason || ''),
        p_phone: String(body?.phone || ''), p_code: String(body?.code || ''),
        p_user_id: (u?.user?.id as string) || null,
        p_ip: req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || null,
        p_ua: req.headers.get('user-agent') || null,
      });
      if (error) return J({ error: error.message }, 500);
      // deno-lint-ignore no-explicit-any
      const r = data as any;
      return J(r?.ok ? { ok: true, user: email, data: r } : { error: r?.error || 'control_mode_denied', hint: r?.message }, r?.ok ? 200 : 403);
    }
    if (action === 'control_mode_close') {
      const { data, error } = await admin.rpc('fn_control_mode_close', { p_actor_email: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, user: email, data });
    }
    // The gate itself. The registry (public.control_mode_action) decides which actions need it, so
    // adding a mutating action here without registering it shows up in the audit as an unregistered
    // action rather than sliding past unnoticed.
    try {
      const { data: gate } = await admin.rpc('fn_control_mode_require', { p_actor_email: email, p_action: action });
      // deno-lint-ignore no-explicit-any
      const g = gate as any;
      if (g && g.allowed === false) {
        return J({ error: 'control_mode_required', mode: 'observe',
                   hint: g.message || 'This changes something. Open Control Mode with a phone code and a reason first.' }, 403);
      }
    } catch (_e) { /* a lookup failure must not block reads; mutations still carry their own checks */ }

    if (action === 'ping') return J({ ok: true, user: email });
    if (action === 'dashboard') { const { data, error } = await admin.rpc('fn_os_command'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'viz') { const { data, error } = await admin.rpc('fn_os_dashboard_viz'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'suppliers_board') { const { data, error } = await admin.rpc('fn_suppliers_board', { p_search: String(body?.search || ''), p_sector: String(body?.sector || ''), p_limit: Number(body?.limit || 60), p_offset: Number(body?.offset || 0) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'rfq_board') { const { data, error } = await admin.rpc('fn_rfq_board', { p_search: String(body?.search || ''), p_limit: Number(body?.limit || 80), p_offset: Number(body?.offset || 0) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'customers_board') { const { data, error } = await admin.rpc('fn_customers_board', { p_search: String(body?.search || ''), p_limit: Number(body?.limit || 80), p_offset: Number(body?.offset || 0) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'agents_board') { const { data, error } = await admin.rpc('fn_agents_board'); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'activity') { const { data, error } = await admin.rpc('fn_entity_activity', { p_entity: String(body?.entity || ''), p_id: String(body?.id || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'comment_add') { const { data, error } = await admin.rpc('fn_entity_comment_add', { p_entity: String(body?.entity || ''), p_id: String(body?.id || ''), p_author: email, p_body: String(body?.body || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'nav') { const { data, error } = await admin.rpc('fn_os_nav'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'ws.suppliers') { const { data, error } = await admin.rpc('fn_ws_suppliers', { p: body?.params || {} }); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'ws.supplier') { const { data, error } = await admin.rpc('fn_ws_supplier_360', { p_id: Number(body?.id) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'ws.customer') { const { data, error } = await admin.rpc('fn_ws_customer_360', { p_id: String(body?.id) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'ws.agent') { const { data, error } = await admin.rpc('fn_ws_agent_ops', { p_agent: String(body?.key) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'ws.rfq') { const { data, error } = await admin.rpc('fn_ws_rfq_360', { p_id: String(body?.id) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'inbox') { const { data, error } = await admin.rpc('fn_inbox_list'); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'inbox_send') { const { data, error } = await admin.rpc('fn_inbox_send', { p_id: Number(body?.id), p_body: String(body?.body || ''), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'search') { const { data, error } = await admin.rpc('fn_os_search', { p_q: String(body?.q || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'record') { const { data, error } = await admin.rpc('fn_os_record', { p_entity: String(body?.entity || ''), p_id: String(body?.id || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }

    if (action === 'secretary_chat') {
      const payload: any = { __secret: await sec('inbound_secret'), actor_email: email };
      for (const k of ['message','history','attachments','confirm_token','decision']) if (body?.[k] !== undefined) payload[k] = body[k];
      const r = await fetch(`${BASE}/secretary_act`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const jd = await r.json().catch(() => ({})); if (!r.ok && jd?.error) return J({ error: jd.error }, 502); return J({ ok: true, data: jd });
    }
    if (action === 'extract_doc') {
      const r = await fetch(`${BASE}/extract_text`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), filename: String(body?.filename || 'document'), mime: String(body?.mime || ''), b64: String(body?.b64 || '') }) });
      const jd = await r.json().catch(() => ({})); return J({ ok: true, data: jd });
    }

    if (action === 'fraud_resolve') {
      const { data, error } = await admin.rpc('fn_fraud_resolve', { p_subject_type: String(body?.subject_type || ''), p_subject_id: String(body?.subject_id || ''), p_action: String(body?.op || 'dismiss'), p_by: email });
      if (error) return J({ error: error.message }, 500); return J({ ok: true, data });
    }
    if (action === 'refund_resolve') {
      const fwd = authHeader || ('Bearer ' + (await sec('os_service_jwt')));
      const r = await fetch(`${BASE}/refunds_api`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': fwd }, body: JSON.stringify({ action: 'resolve', transaction_id: body?.transaction_id, decision: String(body?.op || ''), note: body?.note || '' }) });
      const jd = await r.json().catch(() => ({})); if (!r.ok) return J({ error: jd?.error || ('refunds_api ' + r.status) }, 502); return J({ ok: true, data: jd });
    }

    if (action === 'files') { const { data, error } = await admin.rpc('fn_entity_files', { p_entity: String(body?.entity || ''), p_id: String(body?.id || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'file') { const bucket = String(body?.bucket || 'supplier-docs'); const path = String(body?.path || '').replace(/^\/+/, ''); if (!path) return J({ error: 'path_required' }, 400); const { data, error } = await admin.storage.from(bucket).createSignedUrl(path, 300); if (error || !data?.signedUrl) return J({ error: error?.message || 'could_not_sign' }, 500); return J({ ok: true, data: { url: data.signedUrl } }); }
    if (action === 'report_pdf') {
      const id = Number(body?.id); const src = String(body?.src || 'board'); let title = 'Report'; let text = '';
      if (src === 'exec') { const { data } = await admin.from('exec_reports').select('officer,period,summary,findings,recommendations').eq('id', id).maybeSingle(); if (!data) return J({ error: 'not_found' }, 404); title = `${(data as any).officer} — ${(data as any).period}`; text = String((data as any).summary || ''); if ((data as any).findings) text += '\n\nFINDINGS\n' + JSON.stringify((data as any).findings, null, 2); if ((data as any).recommendations) text += '\n\nRECOMMENDATIONS\n' + JSON.stringify((data as any).recommendations, null, 2); }
      else { const { data } = await admin.from('board_reports').select('title,body').eq('id', id).maybeSingle(); if (!data) return J({ error: 'not_found' }, 404); title = String((data as any).title || 'Report'); text = String((data as any).body || ''); }
      let hb = ''; for (const raw of text.split('\n')) { const t = raw.replace(/\s+$/, ''); if (!t) { hb += '<div style="height:6px"></div>'; continue; } if (/^[=\-_]{3,}$/.test(t)) continue; if (t === t.toUpperCase() && /[A-Z]/.test(t) && t.length < 64) hb += `<h3>${esc(t)}</h3>`; else hb += `<p>${esc(t)}</p>`; }
      const html = `<html><head><title>${esc(title)}</title></head><body><h1>${esc(title)}</h1>${hb}</body></html>`;
      const r = await fetch(`${BASE}/make_pdf`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), html, title, name: 'report-' + id, bucket: 'finance-reports', folder: 'reports' }) });
      const jd = await r.json().catch(() => ({})); if (!jd?.url) return J({ error: jd?.error || 'render_failed' }, 500); return J({ ok: true, data: { url: jd.url, path: jd.path } });
    }

    if (action === 'prompt_view') {
      const r = await fetch(`${BASE}/prompt_gate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), action: 'view', key: String(body?.key || ''), version: body?.version }) });
      const jd = await r.json().catch(() => ({})); return J({ ok: true, data: jd });
    }
    if (action === 'prompt_gate') {
      const p = fetch(`${BASE}/prompt_gate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), action: 'gate', key: String(body?.key || ''), version: body?.version }) });
      try { (globalThis as any).EdgeRuntime?.waitUntil?.(p); } catch (_e) { /* ignore */ }
      return J({ ok: true, data: { queued: true } });
    }
    if (action === 'prompt_approve') { const { data, error } = await admin.rpc('fn_prompt_approve_draft', { p_key: String(body?.key || ''), p_version: Number(body?.version), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'prompt_rollback') { const { data, error } = await admin.rpc('fn_prompt_rollback', { p_key: String(body?.key || ''), p_to_version: Number(body?.to_version), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }

    if (action === 'marketing_studio') { const { data, error } = await admin.rpc('fn_marketing_studio'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'review_decide') { const { data, error } = await admin.rpc('fn_review_decide', { p_kind: String(body?.kind || ''), p_ref_id: Number(body?.ref_id), p_decision: String(body?.decision || ''), p_comment: String(body?.comment || ''), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'blog_publish') { const { data, error } = await admin.rpc('fn_marketing_blog_publish', { p_id: String(body?.id || ''), p_published: Boolean(body?.published), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }

    if (action === 'knowledge_gaps') { const { data, error } = await admin.rpc('fn_knowledge_gaps'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'knowledge_dispatch') { const { data, error } = await admin.rpc('fn_dispatch_agent_knowledge_gaps'); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'knowledge_refresh') { const r = await fetch(`${BASE}/gen_category_knowledge`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), slug: String(body?.slug || '') }) }); const jd = await r.json().catch(() => ({})); if (!r.ok && jd?.error) return J({ error: jd.error }, 502); return J({ ok: true, data: jd }); }
    if (action === 'exam_summary') { const { data, error } = await admin.rpc('fn_knowledge_exam_summary'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'exam_run') { const r = await fetch(`${BASE}/knowledge_exam`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), agent_key: body?.agent_key || undefined, generate: Number(body?.generate ?? 6), answer: Number(body?.answer ?? 8) }) }); const jd = await r.json().catch(() => ({})); if (!r.ok && jd?.error) return J({ error: jd.error }, 502); return J({ ok: true, data: jd }); }
    if (action === 'exam_revert') { const { data, error } = await admin.rpc('fn_exam_revert', { p_agent_key: body?.agent_key || null }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'knowledge_export') {
      const ak = String(body?.agent_key || '').trim();
      let sel = admin.from('agent_knowledge').select('agent_key,topic,content,priority,updated_at').order('agent_key').order('priority', { ascending: false });
      if (ak) sel = sel.in('agent_key', ak.startsWith('cat:') ? [ak] : [ak, 'cat:' + ak]);
      const { data, error } = await sel; if (error) return J({ error: error.message }, 500);
      const rows = (data as any[]) || [];
      const groups: Record<string, any[]> = {}; for (const r of rows) { (groups[r.agent_key] = groups[r.agent_key] || []).push(r); }
      let md = '# QuotesDone — Agent Knowledge Export\n\n' + (ak ? 'Agent: `' + ak + '`\n' : 'All agents\n') + 'Generated: ' + new Date().toISOString() + '\nItems: ' + rows.length + '\n';
      for (const [key, items] of Object.entries(groups)) {
        md += '\n\n---\n\n## ' + key + '  (' + items.length + ' item' + (items.length === 1 ? '' : 's') + ')\n';
        for (const it of items) { md += '\n**' + (it.topic || 'general') + '**' + (String(it.topic || '').startsWith('exam:') ? ' _(exam-verified)_' : '') + '  \n' + String(it.content || '').trim() + '\n'; }
      }
      const filename = 'knowledge-' + (ak ? ak.replace(/[^a-z0-9-]+/gi, '_') : 'all-agents') + '.md';
      return J({ ok: true, data: { filename, markdown: md, count: rows.length } });
    }

    if (WS[action]) { const { data, error } = await admin.rpc(WS[action]); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
