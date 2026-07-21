// dispute_api - reveal-fee refunds + admin funnel + supplier approval queue.
// Auth: Supabase JWT -> email. Customer = customers.email; Admin = email in app_secrets.admin_emails.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const clip = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
// returns false when the queue insert fails, so callers can surface undelivered notifications
async function notify(rows: Record<string, unknown>[]): Promise<boolean> { try { if (rows.length) { const { error } = await admin.from('notifications').insert(rows); if (error) return false; } return true; } catch (_e) { return false; } }

// Observability: state-changing actions (refund request, refund resolution, supplier approval)
// leave an audit row in agent_runs. Read-only actions (status, lists, funnel) are not logged.
function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'dispute_api', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break a dispute decision */ }
  };
}

Deno.serve(async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');
    const adminList = (await sec('admin_emails') || '').split(',').map((x)=>x.trim().toLowerCase()).filter(Boolean);
    const isAdmin = adminList.includes(email);
    const { data: cust } = await admin.from('customers').select('id').eq('email', email).maybeSingle();

    if (action === 'status') {
      if (!cust) return J({ ok: true, state: null });
      const { data: tx } = await admin.from('transactions').select('id,refund_status,refund_deadline,revealed_at').eq('inquiry_id', body.inquiry_id).eq('supplier_id', Number(body.supplier_id)).eq('customer_id', cust.id).not('revealed_at','is',null).maybeSingle();
      if (!tx) return J({ ok: true, state: null });
      const open = tx.refund_status === 'window_open' && tx.refund_deadline && new Date(tx.refund_deadline) > new Date();
      return J({ ok: true, state: tx.refund_status, can_request: !!open, deadline: tx.refund_deadline });
    }

    if (action === 'request') {
      if (!cust) return J({ error: 'forbidden' }, 403);
      const { data: tx } = await admin.from('transactions').select('id,refund_status,refund_deadline,revealed_at,supplier_id,inquiry_id,reveal_fee').eq('inquiry_id', body.inquiry_id).eq('supplier_id', Number(body.supplier_id)).eq('customer_id', cust.id).not('revealed_at','is',null).maybeSingle();
      if (!tx) { await logRun('error', { inquiry_id: String(body.inquiry_id || ''), supplier_id: Number(body.supplier_id) || null }, 'refund request rejected: no revealed transaction found'); return J({ error: 'No revealed transaction found.' }, 404); }
      if (tx.refund_status && tx.refund_status !== 'window_open') return J({ error: 'A refund request is already '+tx.refund_status+'.' }, 409);
      if (tx.refund_deadline && new Date(tx.refund_deadline) < new Date()) { await logRun('ok', { transaction_id: tx.id, expired: true }, 'refund request refused: 72-hour window had closed'); return J({ error: 'The 72-hour refund window has closed.' }, 410); }
      const reason = clip(body.reason, 600) || 'No reason given';
      const { error: uErr } = await admin.from('transactions').update({ refund_status: 'requested', refund_reason: reason, refund_requested_at: new Date().toISOString() }).eq('id', tx.id);
      const { data: lead } = await admin.from('leads').select('company_name').eq('id', tx.supplier_id).maybeSingle();
      const mgmt = (await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
      const sent = await notify([
        { type:'refund_requested', to_email: mgmt, to_role:'admin', inquiry_id: tx.inquiry_id, subject:'Refund requested — review', body:'A customer requested a reveal-fee refund for supplier "'+(lead?.company_name||tx.supplier_id)+'". Reason: '+reason },
        { type:'refund_ack', to_email: email, to_role:'customer', inquiry_id: tx.inquiry_id, subject:'We received your refund request', body:'Thanks — we have logged your reveal-fee refund request and will review it within 2 working days. We will email you with the outcome.' }
      ]);
      if (uErr) await logRun('error', { transaction_id: tx.id, reveal_fee: tx.reveal_fee }, 'REFUND REQUEST NOT SAVED - update failed but customer was told ok: ' + uErr.message);
      else if (!sent) await logRun('error', { transaction_id: tx.id }, 'refund request saved but admin/customer notification insert failed - founder may never see it');
      else await logRun('ok', { transaction_id: tx.id, supplier_id: tx.supplier_id, reveal_fee: tx.reveal_fee }, 'refund requested by customer');
      return J({ ok: true, state: 'requested' });
    }

    if (action === 'admin_list') {
      if (!isAdmin) return J({ error: 'forbidden' }, 403);
      const { data: rows } = await admin.from('transactions').select('id,inquiry_id,supplier_id,customer_id,reveal_fee,refund_status,refund_reason,refund_requested_at,revealed_at').in('refund_status', ['requested']).order('refund_requested_at', { ascending: true }).limit(100);
      const out: any[] = [];
      for (const t of (rows||[])) {
        const { data: lead } = await admin.from('leads').select('company_name').eq('id', t.supplier_id).maybeSingle();
        const { data: c } = await admin.from('customers').select('email').eq('id', t.customer_id).maybeSingle();
        const { count: supReplied } = await admin.from('messages').select('id',{count:'exact',head:true}).eq('inquiry_id', t.inquiry_id).eq('supplier_id', t.supplier_id).eq('sender','supplier');
        out.push({ ...t, supplier: lead?.company_name||null, customer: c?.email||null, supplier_replied: (supReplied||0)>0 });
      }
      return J({ ok: true, requests: out });
    }

    if (action === 'admin_resolve') {
      if (!isAdmin) { await logRun('error', { action }, 'forbidden: non-admin attempted admin_resolve'); return J({ error: 'forbidden' }, 403); }
      const decision = body.decision === 'refunded' ? 'refunded' : 'declined';
      const { data: tx } = await admin.from('transactions').select('id,inquiry_id,customer_id,supplier_id,reveal_fee').eq('id', body.transaction_id).maybeSingle();
      if (!tx) { await logRun('error', { transaction_id: String(body.transaction_id || ''), decision }, 'admin_resolve: transaction not found'); return J({ error: 'not found' }, 404); }
      const { error: uErr } = await admin.from('transactions').update({ refund_status: decision, refund_note: clip(body.note, 600), refund_resolved_at: new Date().toISOString() }).eq('id', tx.id);
      const { data: c } = await admin.from('customers').select('email').eq('id', tx.customer_id).maybeSingle();
      let sent = true;
      if (c?.email) sent = await notify([{ type:'refund_'+decision, to_email: c.email, to_role:'customer', inquiry_id: tx.inquiry_id, subject: decision==='refunded' ? 'Your reveal fee has been refunded' : 'Update on your refund request', body: decision==='refunded' ? ('We have approved your reveal-fee refund of AED '+(tx.reveal_fee||0)+'. It will be returned to your original payment method.'+(body.note?(' Note: '+clip(body.note,300)):'')) : ('After review we are unable to refund your reveal fee for this request.'+(body.note?(' Reason: '+clip(body.note,300)):'')+' Reply to this email if you would like to discuss.') }]);
      if (uErr) await logRun('error', { transaction_id: tx.id, decision, reveal_fee: tx.reveal_fee }, 'REFUND DECISION NOT APPLIED - update failed but caller was told ok: ' + uErr.message);
      else if (!sent) await logRun('error', { transaction_id: tx.id, decision, reveal_fee: tx.reveal_fee }, 'refund resolved as ' + decision + ' but the customer notification failed to queue');
      else await logRun('ok', { transaction_id: tx.id, decision, reveal_fee: tx.reveal_fee, supplier_id: tx.supplier_id, customer_notified: !!c?.email }, clip(body.note, 200));
      return J({ ok: true, state: decision });
    }

    if (action === 'funnel') {
      if (!isAdmin) return J({ error: 'forbidden' }, 403);
      const d30 = await admin.rpc('funnel_metrics', { days: Number(body.days) || 30 });
      const dall = await admin.rpc('funnel_metrics', { days: 36500 });
      const { count: pendingRefunds } = await admin.from('transactions').select('id',{count:'exact',head:true}).eq('refund_status','requested');
      const { count: pendingSuppliers } = await admin.from('leads').select('id',{count:'exact',head:true}).eq('approval_status','pending').not('registration_submitted_at','is',null);
      return J({ ok: true, window: d30.data, all_time: dall.data, pending_refunds: pendingRefunds || 0, pending_suppliers: pendingSuppliers || 0 });
    }

    if (action === 'suppliers_pending') {
      if (!isAdmin) return J({ error: 'forbidden' }, 403);
      const { data: rows } = await admin.from('leads').select('id,company_name,emirate,sector,contact_name,trade_license_no,license_authority,trn,ai_review_notes,ai_review_flags,registration_submitted_at,claimed_by,phone').eq('approval_status','pending').not('registration_submitted_at','is',null).order('registration_submitted_at',{ascending:true}).limit(50);
      return J({ ok:true, suppliers: rows||[] });
    }

    if (action === 'supplier_decision') {
      if (!isAdmin) { await logRun('error', { action }, 'forbidden: non-admin attempted supplier_decision'); return J({ error: 'forbidden' }, 403); }
      const decision = body.decision === 'approved' ? 'approved' : 'rejected';
      const lead_id = Number(body.lead_id||0);
      const { data: lead } = await admin.from('leads').select('id,company_name,claimed_by').eq('id', lead_id).maybeSingle();
      if (!lead) { await logRun('error', { lead_id, decision }, 'supplier_decision: lead not found'); return J({ error:'not found' }, 404); }
      const { error: uErr } = await admin.from('leads').update({ approval_status: decision, verified: decision==='approved', ai_reviewed_at: new Date().toISOString() }).eq('id', lead_id);
      let sent = true;
      if (lead.claimed_by) sent = await notify([{ type:'supplier_'+decision, to_email: lead.claimed_by, to_role:'supplier', lead_id, subject: decision==='approved'?'Your QuotesDone supplier account is approved':'Update on your QuotesDone registration', body: decision==='approved' ? ('Good news — '+(lead.company_name||'your company')+' is approved. You can now receive job requests and submit quotes. Log in to your supplier portal to get started.') : ('After review we were unable to approve '+(lead.company_name||'your company')+' at this time.'+(body.note?(' Reason: '+clip(body.note,300)):'')+' Reply to this email if you would like to discuss or resubmit.') }]);
      if (uErr) await logRun('error', { lead_id, decision }, 'SUPPLIER DECISION NOT APPLIED - update failed but caller was told ok: ' + uErr.message);
      else if (!sent) await logRun('error', { lead_id, decision }, 'supplier ' + decision + ' but the notification failed to queue - supplier was never told');
      else await logRun('ok', { lead_id, decision, company: lead.company_name || '', supplier_notified: !!lead.claimed_by }, '');
      return J({ ok:true, state: decision });
    }

    await logRun('error', { action }, 'unknown action');
    return J({ error: 'unknown action' }, 400);
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
});
