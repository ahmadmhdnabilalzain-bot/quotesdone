// refunds_api v4 — founder actions on reveal-fee complaints/refunds.
// Actions: list_pending · list_recent · resolve {transaction_id, decision:'approve'|'reject', note}
// Auth: __secret == inbound_secret OR admin-email JWT.
// v4 CORRECTNESS FIX: 'resolve' previously returned ok:true even when the transactions UPDATE failed,
//    so the founder was told a refund was applied when nothing had changed. It now returns ok:false on
//    failure AND raises a founder_alert + notification, so the failure reaches a human even if the admin
//    UI ignores the response body. HTTP stays 200 so existing UI error handling is not disturbed.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any) { if (body.__secret && body.__secret === (await sec('inbound_secret'))) return true; const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false; const { data: { user } } = await admin.auth.getUser(jwt); const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }

const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'refunds_api', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break a refund decision */ }
}
// Out-of-band escalation: does not depend on the admin UI rendering the response.
async function escalate(subject: string, detail: string) {
  try { await admin.from('founder_alerts').insert({ level: 'high', event: 'refund_action_failed', detail: String(detail).slice(0, 900), channel: 'email' }); } catch (_e) { /* */ }
  try {
    const owner = ((await sec('admin_emails')) || 'management@quotesdone.com').split(',')[0].trim();
    await admin.from('notifications').insert({ type: 'refund_action_failed', to_email: owner, to_role: 'admin', channel: 'email', subject, body: detail, status: 'queued' });
  } catch (_e) { /* */ }
}

async function enrich(txs: any[]) {
  const sids = [...new Set(txs.map((t) => t.supplier_id).filter(Boolean))];
  const cids = [...new Set(txs.map((t) => t.customer_id).filter(Boolean))];
  const iids = [...new Set(txs.map((t) => t.inquiry_id).filter(Boolean))];
  const [{ data: leads }, { data: custs }, { data: inqs }] = await Promise.all([
    sids.length ? admin.from('leads').select('id,company_name,email,phone,rv_response_rate,rv_nonresponse_refunds,matching_blocked').in('id', sids) : Promise.resolve({ data: [] } as any),
    cids.length ? admin.from('customers').select('id,full_name,email,phone').in('id', cids) : Promise.resolve({ data: [] } as any),
    iids.length ? admin.from('inquiries').select('id,summary,category,emirate').in('id', iids) : Promise.resolve({ data: [] } as any),
  ]);
  const lm = new Map((leads || []).map((l: any) => [Number(l.id), l]));
  const cm = new Map((custs || []).map((c: any) => [String(c.id), c]));
  const im = new Map((inqs || []).map((i: any) => [String(i.id), i]));
  return txs.map((t) => { const l = lm.get(Number(t.supplier_id)) || {}; const c = cm.get(String(t.customer_id)) || {}; const i = im.get(String(t.inquiry_id)) || {}; return {
    transaction_id: t.id, inquiry_id: t.inquiry_id, reveal_fee: t.reveal_fee, quote_amount: t.quote_amount,
    revealed_at: t.revealed_at, refund_requested_at: t.refund_requested_at, refund_status: t.refund_status, refund_note: t.refund_note,
    supplier_ack_at: t.supplier_ack_at,
    supplier: { id: t.supplier_id, company: l.company_name, email: l.email, phone: l.phone, response_rate: l.rv_response_rate, prior_nonresponse: l.rv_nonresponse_refunds, blocked: l.matching_blocked },
    customer: { name: c.full_name, email: c.email, phone: c.phone },
    inquiry: { summary: i.summary, category: i.category, emirate: i.emirate },
  }; });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) { await logRun('error', { action: String(body?.action || '') }, 'forbidden: refund API called without valid secret or admin JWT'); return J({ error: 'forbidden' }, 403); }
    const action = String(body.action || '');

    if (action === 'list_pending') {
      const { data } = await admin.from('transactions').select('id,inquiry_id,supplier_id,customer_id,reveal_fee,quote_amount,revealed_at,refund_requested_at,refund_status,refund_note,supplier_ack_at').eq('refund_status', 'requested').order('refund_requested_at', { ascending: true }).limit(200);
      return J({ ok: true, rows: await enrich(data || []) });
    }
    if (action === 'list_recent') {
      const { data } = await admin.from('transactions').select('id,inquiry_id,supplier_id,customer_id,reveal_fee,quote_amount,revealed_at,refund_requested_at,refund_status,refund_note,supplier_ack_at').not('refund_status', 'is', null).order('refund_requested_at', { ascending: false }).limit(100);
      return J({ ok: true, rows: await enrich(data || []) });
    }
    if (action === 'resolve') {
      const id = String(body.transaction_id || ''); const decision = String(body.decision || ''); const note = String(body.note || '').slice(0, 500);
      if (!id || !['approve', 'reject'].includes(decision)) return J({ error: 'transaction_id and decision(approve|reject) required' }, 400);
      const { data: tx } = await admin.from('transactions').select('id,refund_status,supplier_id,reveal_fee').eq('id', id).maybeSingle();
      if (!tx) { await logRun('error', { transaction_id: id, decision }, 'transaction_not_found - refund decision could not be applied'); return J({ error: 'transaction_not_found' }, 404); }
      const prevStatus = String(tx.refund_status || '');
      const newStatus = decision === 'approve' ? 'refunded' : 'rejected';
      // 'refunded' fires the DB trigger: creates the 3% non-response due + blocks the supplier
      const { error: uErr } = await admin.from('transactions').update({ refund_status: newStatus, refund_note: note || null, refund_resolved_at: new Date().toISOString() }).eq('id', id);
      if (uErr) {
        // v4: the caller is now told the truth, and a founder alert fires regardless of the UI.
        await logRun('error', { transaction_id: id, decision, supplier_id: tx.supplier_id, reveal_fee: tx.reveal_fee },
          'REFUND DECISION NOT APPLIED - transactions update failed: ' + uErr.message);
        await escalate('Refund decision did NOT apply: ' + id,
          'A refund decision was submitted but the database update failed, so NOTHING changed.\n\n' +
          'Transaction: ' + id + '\nDecision: ' + decision + '\nCurrent status remains: ' + (prevStatus || 'unknown') +
          '\nReveal fee: ' + String(tx.reveal_fee ?? '') + '\nSupplier id: ' + String(tx.supplier_id ?? '') +
          '\n\nDatabase error: ' + uErr.message + '\n\nPlease retry this refund decision in the admin panel.');
        return J({ ok: false, applied: false, error: 'update_failed', detail: uErr.message, transaction_id: id, refund_status: prevStatus || null });
      }
      let due: any = null, blocked: boolean | null = null;
      if (decision === 'approve') {
        const { data: d } = await admin.from('supplier_dues').select('amount_due,status,due_date').eq('transaction_id', id).order('created_at', { ascending: false }).maybeSingle();
        due = d || null;
        const { data: l } = await admin.from('leads').select('matching_blocked').eq('id', tx.supplier_id).maybeSingle();
        blocked = l?.matching_blocked ?? null;
        if (!due) {
          await logRun('error', { transaction_id: id, supplier_id: tx.supplier_id }, 'refund approved but no supplier_dues row was created - the 3% non-response trigger may not have fired');
          await escalate('Refund approved but supplier was not charged: ' + id,
            'A refund was approved for transaction ' + id + ', but no supplier_dues row was created, so the 3% non-response charge may not have been applied to supplier ' + String(tx.supplier_id ?? '') + '.\n\nThe refund itself DID apply. Please check the supplier charge manually.');
        }
      }
      await logRun('ok', { transaction_id: id, decision, from_status: prevStatus, to_status: newStatus, supplier_id: tx.supplier_id, reveal_fee: tx.reveal_fee, charge_created: !!due, supplier_blocked: blocked }, note ? ('note: ' + note) : '');
      return J({ ok: true, applied: true, transaction_id: id, refund_status: newStatus, non_response_charge: due, supplier_blocked: blocked });
    }

    await logRun('error', { action }, 'unknown_action');
    return J({ error: 'unknown_action' }, 400);
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
});
