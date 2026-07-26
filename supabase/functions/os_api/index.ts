// os_api v29 — backend for QuotesDone OS. JWT-gated; owner/admin only (or x-os-key preview bypass). + audit trail. + secretary console passthrough.
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

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') return J({ ok: true });
    const authHeader = req.headers.get('Authorization') || '';
    let email = '';
    const osKey = req.headers.get('x-os-key') || '';
    if (osKey && osKey === (await sec('os_bypass_key'))) { email = 'os-preview@quotesdone.com'; }
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
    if (OSAPI_MUTATIONS.has(action)) {
      try {
        const det: any = { ...body }; delete det.action;
        const ent = String(body?.subject_type || (body?.transaction_id ? 'transactions' : '') || (body?.key ? 'prompt' : ''));
        const eid = String(body?.subject_id ?? body?.transaction_id ?? body?.id ?? body?.key ?? '');
        await admin.from('os_audit_log').insert({ actor: email, action, entity: ent || null, entity_id: eid || null, detail: det });
      } catch (_e) { /* audit must never break the operation */ }
    }

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

    if (WS[action]) { const { data, error } = await admin.rpc(WS[action]); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
