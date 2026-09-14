// refunds_api v5 — founder actions on reveal-fee complaints/refunds.
// Actions: list_pending · list_recent · resolve {transaction_id, decision:'approve'|'reject', note}
// Auth: __secret == inbound_secret OR admin-email JWT.
// v4 CORRECTNESS FIX: 'resolve' previously returned ok:true even when the transactions UPDATE failed,
//    so the founder was told a refund was applied when nothing had changed. It now returns ok:false on
//    failure AND raises a founder_alert + notification, so the failure reaches a human even if the admin
//    UI ignores the response body. HTTP stays 200 so existing UI error handling is not disturbed.
// v5 THE REFUND NOW ACTUALLY REFUNDS (27 Jul 2026). Until today approving a refund did nothing but
//    set refund_status='refunded'. No code anywhere in the repository called Stripe's refund API —
//    a source scan found only /v1/checkout/sessions and /v1/account. The customer therefore received
//    nothing, while the status change fired the DB trigger that creates supplier_dues, sets
//    matching_blocked and starts the collections_legal ladder. One click cost a customer their money,
//    a supplier their standing, and the company a chargeback.
//    Approve now calls Stripe FIRST and only writes 'refunded' once Stripe confirms. If Stripe fails,
//    NOTHING changes: no status flip, no supplier debt, no block, no collections. Fail closed.
//    Idempotency-Key is the transaction id, so a double-click or a retry cannot refund twice.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any) { if (body?.__secret && (await requireInternal(admin, body.__secret, 'refunds_api')).ok) return true; const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false; const { data: { user } } = await admin.auth.getUser(jwt); const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }

const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'refunds_api', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break a refund decision */ }
}
// Out-of-band escalation: does not depend on the admin UI rendering the response.
// 14 Sep 2026: customer_support is the only seat that sends email or WhatsApp, so this money exception
// is handed to it (accountant -> customer_support, recipient the founder) instead of written to the
// outbox from here. founder_mail_policy kind finance_alert routes it.
async function escalate(subject: string, detail: string) {
  try { await admin.from('founder_alerts').insert({ level: 'high', event: 'refund_action_failed', detail: String(detail).slice(0, 900), channel: 'email' }); } catch (_e) { /* */ }
  try {
    await admin.rpc('fn_seat_handoff', { p_from: 'accountant', p_to: 'customer_support', p_type: 'delivery.request',
      p_subject_table: 'founder', p_subject_id: 'refund_action_failed:' + subject.slice(0, 120),
      p_payload: { recipient_role: 'founder', kind: 'finance_alert', level: 'high', event: subject.slice(0, 200), detail: String(detail).slice(0, 1500),
                   dedupe_key: 'refund_action_failed:' + subject.slice(0, 120) } });
  } catch (_e) { /* */ }
}

// Ask Stripe to return the money. Returns the refund object on success, or an error string.
// payment_ref is whatever the settling function stored: stripe_webhook writes
// `s.payment_intent || s.id`, so it is normally a pi_… but can be a cs_… — handle both.
async function stripeRefund(paymentRef: string, transactionId: string, amountFils: number): Promise<{ ok: true; refund: any } | { ok: false; error: string }> {
  const sk = await sec('stripe_secret_key');
  if (!sk) return { ok: false, error: 'stripe_secret_key missing from app_secrets - cannot issue a refund' };
  if (!paymentRef) return { ok: false, error: 'transaction has no payment_ref, so there is no Stripe charge to refund' };

  let pi = paymentRef;
  if (paymentRef.startsWith('cs_')) {
    try {
      const sr = await fetch('https://api.stripe.com/v1/checkout/sessions/' + encodeURIComponent(paymentRef), { headers: { Authorization: 'Bearer ' + sk } });
      const sj = await sr.json();
      if (!sr.ok || !sj?.payment_intent) return { ok: false, error: 'could not resolve a payment_intent from checkout session ' + paymentRef + ': ' + String(sj?.error?.message || sr.status) };
      pi = String(sj.payment_intent);
    } catch (e) { return { ok: false, error: 'error resolving checkout session: ' + String((e as Error)?.message || e) }; }
  }

  const form = new URLSearchParams();
  form.set('payment_intent', pi);
  form.set('reason', 'requested_by_customer');
  form.set('metadata[transaction_id]', transactionId);
  // THE AMOUNT IS STATED: total_charged, what the customer actually paid -- the 3% and the processing
  // part together (founder, 14 Sep 2026). Stated rather than left to "refund in full" so the figure
  // Stripe returns is the figure the books expect, and a charge that was partly refunded before cannot
  // turn "in full" into a different number.
  form.set('amount', String(amountFils));
  try {
    const r = await fetch('https://api.stripe.com/v1/refunds', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + sk, 'Content-Type': 'application/x-www-form-urlencoded', 'Idempotency-Key': 'qd_refund_' + transactionId },
      body: form.toString(),
    });
    const j = await r.json();
    if (!r.ok) return { ok: false, error: 'Stripe refused the refund (HTTP ' + r.status + '): ' + String(j?.error?.message || '').slice(0, 250) };
    // 'pending' is a normal terminal-ish state for some methods; 'failed'/'canceled' are not.
    if (j?.status && !['succeeded', 'pending'].includes(String(j.status))) {
      return { ok: false, error: 'Stripe refund came back with status "' + j.status + '"' };
    }
    return { ok: true, refund: j };
  } catch (e) { return { ok: false, error: 'network error calling Stripe refunds: ' + String((e as Error)?.message || e) }; }
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
  // TYPED ON PURPOSE. The empty branches above are `Promise.resolve({ data: [] } as any)`, so when
  // a batch is empty `leads`/`custs`/`inqs` infer as never[]; the Maps then infer Map<never, never>,
  // .get() returns undefined, and `undefined || {}` is `{}` — which is why all twelve property reads
  // below were TS2339 "does not exist on type '{}'". The rows really are untyped PostgREST payloads,
  // so the honest annotation is any, not a fabricated row interface.
  const lm = new Map<number, any>((leads || []).map((l: any) => [Number(l.id), l]));
  const cm = new Map<string, any>((custs || []).map((c: any) => [String(c.id), c]));
  const im = new Map<string, any>((inqs || []).map((i: any) => [String(i.id), i]));
  return txs.map((t) => { const l = lm.get(Number(t.supplier_id)) || {}; const c = cm.get(String(t.customer_id)) || {}; const i = im.get(String(t.inquiry_id)) || {}; return {
    transaction_id: t.id, inquiry_id: t.inquiry_id, reveal_fee: t.reveal_fee, quote_amount: t.quote_amount,
    revealed_at: t.revealed_at, refund_requested_at: t.refund_requested_at, refund_status: t.refund_status, refund_note: t.refund_note,
    supplier_ack_at: t.supplier_ack_at,
    supplier: { id: t.supplier_id, company: l.company_name, email: l.email, phone: l.phone, response_rate: l.rv_response_rate, prior_nonresponse: l.rv_nonresponse_refunds, blocked: l.matching_blocked },
    customer: { name: c.full_name, email: c.email, phone: c.phone },
    inquiry: { summary: i.summary, category: i.category, emirate: i.emirate },
  }; });
}

Deno.serve(observe('refunds_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) { await logRun('error', { action: String(body?.action || '') }, 'forbidden: refund API called without valid secret or admin JWT'); return J({ error: 'forbidden' }, 403); }
    const action = String(body.action || '');

    // ---- CONTROL MODE GATE: refund_resolve ----------------------------------------------
    // 'resolve' issues a REAL Stripe refund (POST /v1/refunds). Without a gate it is reachable with
    // any address listed in app_secrets.admin_emails, or with the shared inbound_secret - a secret
    // referenced by 43 of 148 cron jobs. Moving money therefore requires a live Control Mode session
    // held by a human identity.
    //
    // This began life on 2 Aug 2026 as a Phase 1 emergency-containment block, justified at the time
    // by refund_resolve not existing in public.control_mode_action. It does now: risk=high,
    // classification=mutating, requires_control=true. So this is no longer containment - it is the
    // permanent control the refund workstream requires, and it stays after containment is removed.
    //
    // Fails closed: any error, any missing identity and any non-true gate result denies.
    // list_pending and list_recent are read-only and are deliberately left ungated.
    if (action === 'resolve') {
      let allowed = false;
      let detail = 'control_mode_unavailable';
      try {
        const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
        const { data: { user } } = await admin.auth.getUser(jwt);
        const actor = String(user?.email || '').toLowerCase();
        if (!actor) {
          detail = 'no_human_identity';
        } else {
          const { data: gate, error: gerr } = await admin.rpc('fn_control_mode_require', { p_actor_email: actor, p_action: 'refund_resolve' });
          if (gerr) throw new Error(gerr.message);
          allowed = (gate as any)?.allowed === true;
          detail = String((gate as any)?.error || (allowed ? 'allowed' : 'control_mode_required'));
        }
      } catch (_e) { allowed = false; detail = 'control_mode_unavailable'; }
      if (!allowed) {
        await logRun('error', { action, detail }, 'refund resolve refused: no valid Control Mode session');
        return J({ error: 'control_mode_required', detail,
          hint: 'Issuing a Stripe refund requires an open Control Mode session held by an authorised identity.' }, 403);
      }
    }

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
      const { data: tx } = await admin.from('transactions').select('id,refund_status,supplier_id,reveal_fee,total_charged,payment_ref,refund_stripe_id').eq('id', id).maybeSingle();
      if (!tx) { await logRun('error', { transaction_id: id, decision }, 'transaction_not_found - refund decision could not be applied'); return J({ error: 'transaction_not_found' }, 404); }
      const prevStatus = String(tx.refund_status || '');
      const newStatus = decision === 'approve' ? 'refunded' : 'rejected';

      // v5: money first, bookkeeping second. Nothing below this block runs unless Stripe
      // has actually returned the customer's money.
      const refundPatch: Record<string, unknown> = {};
      if (decision === 'approve') {
        if (prevStatus === 'refunded' && tx.refund_stripe_id) {
          await logRun('ok', { transaction_id: id, already_refunded: true, refund_stripe_id: tx.refund_stripe_id }, 'refund already issued; ignoring duplicate approval');
          return J({ ok: true, applied: false, already_refunded: true, transaction_id: id, refund_status: 'refunded', refund_stripe_id: tx.refund_stripe_id });
        }
        // THE CEO'S CIRCUIT BREAKER (14 Sep 2026). While a post-payment mismatch is open, no refund is
        // executed by any path; the playbook resumes them when every check is green again.
        const { data: paused } = await admin.rpc('fn_refunds_paused');
        if (paused === true) {
          await logRun('error', { transaction_id: id, decision }, 'refund held: the CEO has paused refunds and supplier charges while a mismatch is open');
          return J({ ok: false, applied: false, error: 'refunds_paused', transaction_id: id, refund_status: prevStatus || null });
        }
        const totalFils = Math.round(Number(tx.total_charged ?? tx.reveal_fee ?? 0) * 100);
        if (!(totalFils > 0)) return J({ ok: false, applied: false, error: 'no_amount_on_record', transaction_id: id });
        const sr = await stripeRefund(String(tx.payment_ref || ''), id, totalFils);
        if (!sr.ok) {
          await logRun('error', { transaction_id: id, decision, supplier_id: tx.supplier_id, reveal_fee: tx.reveal_fee, payment_ref: tx.payment_ref },
            'REFUND NOT ISSUED - Stripe refund failed, nothing was changed: ' + sr.error);
          await escalate('Refund could NOT be issued: ' + id,
            'A refund was approved for transaction ' + id + ' but Stripe did not return the money, so NOTHING was changed.\n\n' +
            'The customer has NOT been refunded. The supplier has NOT been charged or blocked. The transaction still reads "' + (prevStatus || 'unknown') + '".\n\n' +
            'Reveal fee: AED ' + String(tx.reveal_fee ?? '') + '\nPayment ref: ' + String(tx.payment_ref ?? '(none)') + '\nSupplier id: ' + String(tx.supplier_id ?? '') +
            '\n\nStripe said: ' + sr.error + '\n\nResolve this in the Stripe dashboard or retry once the cause is fixed. The customer is waiting.');
          return J({ ok: false, applied: false, error: 'stripe_refund_failed', detail: sr.error, transaction_id: id, refund_status: prevStatus || null });
        }
        refundPatch.refund_stripe_id = String(sr.refund?.id || '');
        refundPatch.refund_amount_aed = Number(sr.refund?.amount || 0) / 100;
        refundPatch.refund_confirmed_at = new Date().toISOString();
      }

      // 'refunded' fires the DB trigger: creates the non-response due + blocks the supplier
      const { error: uErr } = await admin.from('transactions').update({ refund_status: newStatus, refund_note: note || null, refund_resolved_at: new Date().toISOString(), ...refundPatch }).eq('id', id);
      if (uErr) {
        // v4: the caller is now told the truth, and a founder alert fires regardless of the UI.
        await logRun('error', { transaction_id: id, decision, supplier_id: tx.supplier_id, reveal_fee: tx.reveal_fee },
          'REFUND DECISION NOT APPLIED - transactions update failed: ' + uErr.message);
        const moneyMoved = decision === 'approve' && !!refundPatch.refund_stripe_id;
        await escalate((moneyMoved ? 'MONEY REFUNDED BUT NOT RECORDED: ' : 'Refund decision did NOT apply: ') + id,
          (moneyMoved
            ? 'STRIPE HAS ALREADY REFUNDED THE CUSTOMER, but the database update failed, so our records still say "' + (prevStatus || 'unknown') + '".\n\n' +
              'Stripe refund id: ' + String(refundPatch.refund_stripe_id) + ' (AED ' + String(refundPatch.refund_amount_aed) + ')\n' +
              'Do NOT approve this refund again - the money is already gone and a second approval is blocked by the idempotency key, but the record must be corrected by hand.\n\n'
            : 'A refund decision was submitted but the database update failed, so NOTHING changed.\n\n') +
          'Transaction: ' + id + '\nDecision: ' + decision + '\nCurrent status remains: ' + (prevStatus || 'unknown') +
          '\nReveal fee: ' + String(tx.reveal_fee ?? '') + '\nSupplier id: ' + String(tx.supplier_id ?? '') +
          '\n\nDatabase error: ' + uErr.message);
        return J({ ok: false, applied: false, error: 'update_failed', detail: uErr.message, transaction_id: id, refund_status: prevStatus || null, money_refunded: moneyMoved, refund_stripe_id: refundPatch.refund_stripe_id || null });
      }
      let due: any = null, blocked: boolean | null = null;
      if (decision === 'approve') {
        const { data: d } = await admin.from('supplier_dues').select('amount_due,status,due_date').eq('transaction_id', id).order('created_at', { ascending: false }).maybeSingle();
        due = d || null;
        const { data: l } = await admin.from('leads').select('matching_blocked').eq('id', tx.supplier_id).maybeSingle();
        blocked = l?.matching_blocked ?? null;
        if (!due) {
          await logRun('error', { transaction_id: id, supplier_id: tx.supplier_id }, 'refund approved but no supplier_dues row was created - the non-response trigger may not have fired');
          await escalate('Refund approved but supplier was not charged: ' + id,
            'A refund was approved for transaction ' + id + ', but no supplier_dues row was created, so the non-response charge may not have been applied to supplier ' + String(tx.supplier_id ?? '') + '.\n\nThe refund itself DID apply. Please check the supplier charge manually.');
        }
      }
      await logRun('ok', { transaction_id: id, decision, from_status: prevStatus, to_status: newStatus, supplier_id: tx.supplier_id, reveal_fee: tx.reveal_fee, charge_created: !!due, supplier_blocked: blocked, refund_stripe_id: refundPatch.refund_stripe_id || null, refunded_aed: refundPatch.refund_amount_aed ?? null },
        (decision === 'approve' ? ('Stripe refunded AED ' + String(refundPatch.refund_amount_aed) + ' (' + String(refundPatch.refund_stripe_id) + '). ') : '') + (note ? ('note: ' + note) : ''));
      return J({ ok: true, applied: true, transaction_id: id, refund_status: newStatus, non_response_charge: due, supplier_blocked: blocked, refund_stripe_id: refundPatch.refund_stripe_id || null, refunded_aed: refundPatch.refund_amount_aed ?? null });
    }

    await logRun('error', { action }, 'unknown_action');
    return J({ error: 'unknown_action' }, 400);
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}));
