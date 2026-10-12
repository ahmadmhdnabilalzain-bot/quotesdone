import { draftDisputes } from '../_shared/dispute_draft.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { CHECKOUT_EVENTS, FAILED_CHECKOUT_EVENTS, REFUND_EVENTS, INVOICE_EVENTS, DISPUTE_EVENTS, stripeEventMode, signingSecretFor, refundsInEvent } from '../_shared/stripe_events.ts';
import { handleRevealInvoiceEvent } from './invoice_event.ts';
import { recordRevealSale } from '../_shared/reveal_sale.ts';
import { absorbedStripeCost } from '../_shared/reveal_fee.ts';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const TOLERANCE_SECONDS = 600; // reject events whose signature timestamp is older/newer than this (replay guard)
async function secret(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
function toHex(buf: ArrayBuffer) { return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join(''); }

// THE STRIPE INVOICE, FETCHED AND FILED (9 Sep 2026). The founder, instruction 28: "stripe
// automatically generates an invoice as far as i know, our accountant need to retrieve that and be
// connected, then add it to his records, sync it with back up on dropbox."
//
// stripe_checkout now sets invoice_creation[enabled]=true on the reveal-fee session, so
// checkout.session.completed carries an `invoice` id. Retrieval happens HERE, on the one
// signature-verified path a reveal fee travels, rather than on a poll: a payment and its document
// arrive together or the gap is visible in fn_revenue_document_coverage.
//
// THREE THINGS THIS DELIBERATELY DOES NOT DO.
//   1. It does not write to public.transactions. fn_transaction_attach_invoice owns the rules --
//      the in_... id shape, the stripe.com URL guard on both links, the invoices/ path prefix, and
//      write-once on the invoice identity. Same delegation as fn_refund_attach_receipt, same
//      reason: a second implementation in TypeScript is a second set of rules to keep in step.
//   2. It never throws into the payment path. A reveal fee that was RECORDED must not be un-recorded
//      because Stripe was slow to finalise a PDF. Every failure is logged and returns; the sale
//      stands and reads 'missing' or 'reference_only' in the coverage function until it is repaired.
//   3. It does not enqueue the Dropbox mirror. fn_enqueue_doc_backups queues on doc_path being
//      non-null, so the mirror follows from the record rather than from this handler remembering.
//
// The reference is attached even when the file cannot be fetched, because "Stripe billed this sale
// under invoice X and we have not got the PDF" is a strictly better record than silence.
async function captureInvoice(
  sk: string, txId: string, invoiceId: string,
  logRun: (s: string, c: Record<string, unknown>, n: string) => Promise<void>,
): Promise<void> {
  try {
    const r = await timedFetch('https://api.stripe.com/v1/invoices/' + encodeURIComponent(invoiceId),
      { headers: { Authorization: 'Bearer ' + sk } });
    const inv = await r.json().catch(() => ({}));
    if (!r.ok || !inv?.id) {
      await logRun('error', { transaction: txId, invoice: invoiceId, http: r.status },
        'INVOICE NOT RETRIEVED - the sale is recorded but Stripe would not return invoice ' + invoiceId
        + '. It reads as missing in fn_revenue_document_coverage until refetched.');
      return;
    }
    // The FILE. A finalised invoice carries invoice_pdf; a moment-old one may not yet, and that is
    // a wait rather than an error - the reference below still lands.
    let docPath: string | null = null, docName: string | null = null;
    const pdfUrl = String(inv.invoice_pdf || '');
    if (pdfUrl) {
      try {
        const pr = await timedFetch(pdfUrl, {}, 20_000);
        const buf = pr.ok ? new Uint8Array(await pr.arrayBuffer()) : null;
        if (buf && buf.length) {
          const day = new Date().toISOString().slice(0, 10);
          const label = String(inv.number || inv.id).replace(/[^A-Za-z0-9._-]/g, '_');
          docName = label + '.pdf';
          const path = 'invoices/stripe/' + day + '/' + String(inv.id) + '_' + docName;
          const { error: upErr } = await admin.storage.from('finance-docs')
            .upload(path, buf, { contentType: 'application/pdf', upsert: true });
          if (upErr) {
            await logRun('error', { transaction: txId, invoice: invoiceId, path },
              'INVOICE PDF NOT STORED - fetched from Stripe but finance-docs refused it: ' + upErr.message);
          } else { docPath = path; }
        } else {
          await logRun('error', { transaction: txId, invoice: invoiceId, http: pr.status },
            'INVOICE PDF NOT DOWNLOADED - invoice_pdf returned no bytes; the reference is recorded without the file.');
        }
      } catch (e) {
        await logRun('error', { transaction: txId, invoice: invoiceId },
          'invoice pdf download failed: ' + String((e as Error)?.message || e));
      }
    }
    const { data: att, error: attErr } = await admin.rpc('fn_transaction_attach_invoice', {
      p_transaction_id: txId, p_invoice: inv,
      p_doc_path: docPath, p_doc_name: docName,
      p_doc_content_type: docPath ? 'application/pdf' : null,
    });
    if (attErr || (att as Record<string, unknown> | null)?.ok !== true) {
      await logRun('error', { transaction: txId, invoice: invoiceId, result: att },
        'INVOICE NOT ATTACHED - the database refused it: '
        + String(attErr?.message || (att as Record<string, unknown> | null)?.reason || 'unknown'));
      return;
    }
    await logRun('ok', { transaction: txId, invoice: invoiceId, number: String(inv.number || ''),
      stored: Boolean(docPath), state: (att as Record<string, unknown>).state }, '');
  } catch (e) {
    await logRun('error', { transaction: txId, invoice: invoiceId },
      'invoice capture threw: ' + String((e as Error)?.message || e));
  }
}

// WHAT STRIPE ACTUALLY KEPT (14 Sep 2026, agent: accountant). Since 24 Sep 2026 the customer pays the 3% only and
// QuotesDone bears Stripe's fee (Cabinet Res. 66/2023 Art. 5(3); _shared/reveal_fee.ts). The
// real fee depends on the card, and is only known from the balance transaction, so it is read here
// and stored beside the sale. Best-effort and write-once: it is a record, never a reason to fail.
async function recordStripeFee(sk: string, txId: string, pi: string,
  logRun: (s: string, c: Record<string, unknown>, n: string) => Promise<void>): Promise<void> {
  if (!/^pi_/.test(pi)) return;
  try {
    const r = await timedFetch('https://api.stripe.com/v1/payment_intents/' + encodeURIComponent(pi)
      + '?expand[]=latest_charge.balance_transaction', { headers: { Authorization: 'Bearer ' + sk } });
    const j = await r.json().catch(() => ({}));
    const bt = j?.latest_charge?.balance_transaction;
    if (!r.ok || !bt || typeof bt.fee !== 'number') {
      await logRun('error', { transaction: txId, payment_intent: pi, http: r.status }, 'STRIPE FEE NOT READ - no balance transaction on the payment yet; stripe_fee_fils stays empty.');
      return;
    }
    await admin.from('transactions').update({ stripe_fee_fils: bt.fee, stripe_fee_details: bt.fee_details || null })
      .eq('id', txId).is('stripe_fee_fils', null);
    // ABSORBED, NOT RECOVERED (24 Sep 2026). The card fee plus Stripe's separately billed Invoicing fee is
    // QuotesDone's cost, booked to 6100 by fn_gl_sync_business from stripe_fee_fils. Recorded here, never an incident.
    const { data: sale } = await admin.from('transactions').select('total_charged').eq('id', txId).maybeSingle();
    if (sale?.total_charged != null) {
      await logRun('ok', { transaction: txId, absorbed_stripe_cost_aed: absorbedStripeCost({ total_charged: Number(sale.total_charged), actual_card_fee_fils: Number(bt.fee) }) },
        'Stripe fee absorbed (expense 6100); the customer paid the reveal fee only');
    }
  } catch (e) {
    await logRun('error', { transaction: txId }, 'stripe fee read threw: ' + String((e as Error)?.message || e));
  }
}

// Observability: every exit path leaves a row in agent_runs so a payment that lands but
// records nothing is visible instead of silent. Fire-and-forget so it can never fail the webhook.
function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'stripe_webhook', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break payment handling */ }
  };
}

async function verifySig(sigHeader: string, payload: string, key: string): Promise<boolean> {
  const parts: Record<string, string> = {};
  for (const kv of String(sigHeader || '').split(',')) { const i = kv.indexOf('='); if (i > 0) parts[kv.slice(0, i).trim()] = kv.slice(i + 1).trim(); }
  const t = parts['t']; const v1 = parts['v1'];
  if (!t || !v1) return false;
  // Replay / timestamp-tolerance check. Stripe re-signs every delivery attempt with a fresh `t`,
  // so a generous window is safe across retries while still rejecting captured/stale replays.
  const ts = parseInt(t, 10);
  if (!Number.isFinite(ts)) return false;
  const nowSec = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSec - ts) > TOLERANCE_SECONDS) return false;
  const enc = new TextEncoder();
  const ck = await crypto.subtle.importKey('raw', enc.encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', ck, enc.encode(t + '.' + payload));
  const expected = toHex(mac);
  if (expected.length !== v1.length) return false;
  let diff = 0; for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ v1.charCodeAt(i);
  return diff === 0;
}
// Whether a verified TEST-mode event is about demo data only. Fails closed: anything it cannot trace to a
// demo account (customers.is_demo, leads.is_demo, fn_inquiry_is_demo) answers false and is ignored.
//   reveal / invoice   metadata.quote_id   -> the quote's request -> fn_inquiry_is_demo
//   supplier payments  metadata.supplier_id -> leads.is_demo
//   refunds / charges  payment_intent       -> the transaction it reverses -> its customer
// deno-lint-ignore no-explicit-any
async function testEventIsDemo(event: any): Promise<boolean> {
  try {
    const o = event?.data?.object || {};
    const md = o.metadata || {};
    const qid = String(md.quote_id || '');
    if (qid) {
      const { data: q } = await admin.from('quotes').select('inquiry_id').eq('id', qid).maybeSingle();
      if (!q?.inquiry_id) return false;
      const { data } = await admin.rpc('fn_inquiry_is_demo', { p_inquiry: q.inquiry_id });
      return data === true;
    }
    const supId = Number(md.supplier_id || 0);
    if (supId > 0) {
      const { data: l } = await admin.from('leads').select('is_demo').eq('id', supId).maybeSingle();
      return l?.is_demo === true;
    }
    const pi = String(o.payment_intent || (o.object === 'payment_intent' ? o.id : '') || '');
    if (pi) {
      const { data: t } = await admin.from('transactions').select('customer_id').eq('payment_ref', pi).maybeSingle();
      if (!t?.customer_id) return false;
      const { data: c } = await admin.from('customers').select('is_demo').eq('id', t.customer_id).maybeSingle();
      return c?.is_demo === true;
    }
    return false;
  } catch (_e) { return false; }
}

Deno.serve(observe('stripe_webhook', async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method !== 'POST') return new Response('POST only', { status: 405 });
  const raw = await req.text();
  const sig = req.headers.get('Stripe-Signature') || '';
  // TWO ENDPOINTS, TWO SIGNING SECRETS (2 Aug 2026). Refund behaviour has to be provable without
  // refunding real customer payments, so a Stripe TEST-MODE endpoint points at this same handler.
  // Stripe issues a separate signing secret per endpoint, so the function has to accept either -
  // and each is tried in full, so a test-mode delivery can never be validated by the live secret or
  // the reverse. Neither secret is ever logged; only which mode verified.
  //
  // Order is deliberate: live first, so the common case costs one HMAC and a test-mode delivery
  // costs two. If only one secret is configured, only that one is accepted.
  const whsecLive = await secret('stripe_webhook_secret');
  const whsecTest = await secret('stripe_webhook_secret_test');
  if (!whsecLive && !whsecTest) {
    await logRun('error', {}, 'not_configured: neither stripe_webhook_secret nor stripe_webhook_secret_test is set');
    return new Response('not_configured', { status: 400 });
  }
  // THE EVENT'S OWN MODE PICKS THE SECRET (14 Sep 2026, agent: accountant). Every Stripe event states
  // `livemode`, and that field is inside the signed payload. So the body is read once to learn which
  // mode it CLAIMS, it is verified with that mode's secret alone, and a claim the signature does not
  // back is rejected. A test delivery can never be accepted by the live secret, nor the reverse, and
  // the livemode the code acts on is the one Stripe signed. Nothing is written before this passes.
  let event: any; try { event = JSON.parse(raw); } catch { await logRun('error', {}, 'bad_json (rejected before verification)'); return new Response('bad json', { status: 400 }); }
  const claimedMode = stripeEventMode(event) ?? '';
  const whsecForMode = signingSecretFor(stripeEventMode(event), { live: whsecLive, test: whsecTest });
  let sigMode = '';
  if (whsecForMode && await verifySig(sig, raw, whsecForMode)) sigMode = claimedMode;
  // Only facts about the attempt reach the log (which mode it claimed, whether that mode has a secret
  // configured), computed before the log call so no secret-bearing name is ever handed to it.
  const modeConfigured = whsecForMode.length > 0;
  if (!sigMode) { await logRun('error', { claimed_mode: claimedMode || 'none', mode_configured: modeConfigured }, 'bad_signature (rejected before any write)'); return new Response('bad signature', { status: 400 }); }
  // A TEST-MODE EVENT MAY ONLY EVER TOUCH DEMO DATA. The test account exists so the e2e harness can pay
  // as a demo customer; a verified test event about a real customer, a real supplier or a real payment
  // is logged and ignored, never allowed to write a real ledger row.
  if (sigMode === 'test' && !(await testEventIsDemo(event))) {
    await logRun('ok', { mode: 'test', type: String(event?.type || ''), ignored: 'test_event_not_demo' }, 'TEST-mode event ignored: its subject is not a demo account, so it may not write a real ledger row.');
    return new Response(JSON.stringify({ received: true, ignored: 'test_event_not_demo' }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }
  // Ledger (Finding 7): record every signature-verified delivery for audit + reconciliation and
  // count retries. Best-effort and non-blocking — correctness is still enforced by the conditional
  // updates below, so a ledger failure can never drop a payment.
  try {
    const evId = String(event?.id || '');
    if (evId) await admin.rpc('fn_stripe_event_seen', { p_event_id: evId, p_type: String(event?.type || ''), p_status: String(event?.data?.object?.payment_status || '') });
  } catch (_e) { /* ledger is best-effort */ }
  try {
    if ((CHECKOUT_EVENTS as readonly string[]).includes(String(event.type))) {
      const s = event.data?.object || {};
      if (s.payment_status === 'paid') {
        const md = s.metadata || {};

        // ---- SUPPLIER COMMISSION SETTLEMENT (added 19 Jul 2026) ----------------------------
        // This is the ONLY place supplier_dues.paid_at is ever written. supplier_pay merely
        // creates the Checkout Session; a due is settled only once Stripe confirms payment on a
        // signature-verified event, so a supplier cannot clear their own debt by calling our API.
        if (String(md.kind || '') === 'supplier_dues') {
          const ids = String(md.due_ids || '').split(',').map((x) => Number(x.trim())).filter((n) => Number.isFinite(n) && n > 0);
          const payRef = String(s.payment_intent || s.id);
          const paidAmount = Number(s.amount_total ? s.amount_total / 100 : 0);
          if (!ids.length) { await logRun('error', { kind: 'supplier_dues', amount_total: s.amount_total, session: String(s.id || '') }, 'SUPPLIER PAID BUT NOTHING SETTLED - a supplier_dues checkout session completed with no metadata.due_ids, so no due could be marked paid. The money is with Stripe but the supplier still shows as owing it, and will keep receiving overdue reminders and legal escalation. Reconcile manually against session ' + String(s.id || '')); return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } }); }

          // Only settle rows that are genuinely still outstanding - makes duplicate deliveries a no-op.
          const { data: settled, error: uErr } = await admin.from('supplier_dues')
            // stripe_session_id = the session that was PAID (a supplier may have opened a later one): the settlement
            // row reads that session's stored per-due amount (supplier_due_checkouts, written by supplier_pay)
            .update({ status: 'paid', paid_at: new Date().toISOString(), payment_ref: payRef, stripe_session_id: String(s.id) })
            .in('id', ids).is('paid_at', null).select('id,amount_due,supplier_id');

          if (uErr) { await logRun('error', { kind: 'supplier_dues', due_ids: ids, amount: paidAmount }, 'SUPPLIER PAID BUT NOT RECORDED - failed to mark supplier_dues paid (' + uErr.message + '). Payment ref ' + payRef + '. The supplier has been charged and will still be chased for the debt until this is reconciled by hand.'); return new Response('due update failed: ' + uErr.message, { status: 500 }); }

          const n = (settled || []).length;
          if (n === 0) { await logRun('ok', { kind: 'supplier_dues', duplicate: true, due_ids: ids }, 'Duplicate Stripe delivery for supplier dues ignored - those dues were already settled.'); }
          else {
            // Push the collection straight into the ledger rather than waiting for the next cron.
            let posted = 0; try { const { data: gp } = await admin.rpc('fn_gl_sync_business'); posted = Number(gp || 0); } catch (_e) { /* cron will catch up */ }
            // The supplier is thanked by the sales engineer, through customer_support: the accountant
            // hands the settled payment over rather than writing to the outbox itself (14 Sep 2026).
            try {
              const supId = (settled || [])[0]?.supplier_id;
              await admin.rpc('fn_seat_handoff', { p_from: 'accountant', p_to: 'sales_engineer', p_type: 'payment.received',
                p_subject_table: 'supplier_dues', p_subject_id: payRef,
                p_payload: { supplier_id: supId, kind: 'supplier_dues', msg_type: 'dues_paid', amount_aed: paidAmount.toFixed(2), items: n } });
            } catch (_e) { /* the payment is recorded; a failed handoff is visible in agent_actions */ }
            await logRun('ok', { kind: 'supplier_dues', settled: n, amount: paidAmount, gl_entries_posted: posted }, 'Supplier settled ' + n + ' commission due(s) totalling AED ' + paidAmount.toFixed(2) + ' via Stripe (ref ' + payRef + ').');
          }
          return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
        }

        // ---- SUPPLIER REGISTRATION FEE (added 21 Jul 2026) --------------------------------
        // This is the ONLY place leads.registration_status is set to 'paid'.
        // supplier_api.pay_registration previously wrote it directly, with no payment taken and
        // no Stripe involved, so any supplier with a valid JWT could clear their own AED 1,000
        // fee with a single POST. That endpoint now only creates a Checkout Session; settlement
        // happens here on a signature-verified event, exactly as it does for supplier_dues.
        if (String(md.kind || '') === 'supplier_registration') {
          const supId = Number(md.supplier_id || 0);
          const payRef = String(s.payment_intent || s.id);
          const paidAmount = Number(s.amount_total ? s.amount_total / 100 : 0);
          if (!supId) { await logRun('error', { kind: 'supplier_registration', amount_total: s.amount_total, session: String(s.id || '') }, 'SUPPLIER PAID BUT NOTHING RECORDED - a supplier_registration checkout session completed with no metadata.supplier_id, so no lead could be marked registered. The money is with Stripe but the supplier still shows the fee as outstanding. Reconcile manually against session ' + String(s.id || '')); return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } }); }

          // Only settle a lead that is genuinely still unpaid. This makes duplicate deliveries a
          // no-op, and stops a repeat webhook silently pushing the expiry out by another year.
          // AUDIT 4.2 (3 Aug 2026). This block wrote registration_status='paid' and an expiry
          // timestamp, but NOTHING anywhere in the codebase ever wrote leads.subscription_paid_until
          // - the column the exemption/paid/due rule actually reads. A supplier who paid was
          // therefore recorded as paid in one column and unpaid in the one that decides whether
          // they may quote, and would have gone back to 'due' on the next write to their row.
          // subscription_paid_until is now the settlement of record; registration_status and
          // registration_fee_due are derived from it by trg_bz_supplier_registration_state, so
          // they are deliberately NOT set here - the trigger overwrites them either way.
          const YEAR_MS = 365 * 24 * 60 * 60 * 1000;
          const paidUntil = new Date(Date.now() + YEAR_MS);
          const { data: settled, error: rErr } = await admin.from('leads')
            .update({ subscription_paid_until: paidUntil.toISOString().slice(0, 10), registration_paid_at: new Date().toISOString(), registration_expires_at: paidUntil.toISOString() })
            .eq('id', supId).neq('registration_status', 'paid').select('id,email,company_name');

          if (rErr) { await logRun('error', { kind: 'supplier_registration', supplier_id: supId, amount: paidAmount }, 'SUPPLIER PAID BUT NOT RECORDED - failed to mark registration paid (' + rErr.message + '). Payment ref ' + payRef + '. The supplier has been charged and still shows as unregistered, so they may be blocked from quoting until this is reconciled by hand.'); return new Response('registration update failed: ' + rErr.message, { status: 500 }); }

          const n = (settled || []).length;
          if (n === 0) { await logRun('ok', { kind: 'supplier_registration', duplicate: true, supplier_id: supId }, 'Duplicate Stripe delivery for supplier registration ignored - that supplier was already marked paid.'); }
          else {
            // What the supplier's invoice and receipt print (supplier_payment_documents.ts, 22 Sep 2026):
            // the amount and the payment reference. A SEPARATE, best-effort write so a missing column
            // (scripts/sql/the_suppliers_annual_listing_fee_keeps_what_was_paid.sql not yet applied) can
            // never undo the settlement above.
            try { await admin.from('leads').update({ registration_payment_ref: payRef, registration_amount_aed: paidAmount }).eq('id', supId); } catch (_e) { /* the settlement stands */ }
            try {
              await admin.rpc('fn_seat_handoff', { p_from: 'accountant', p_to: 'sales_engineer', p_type: 'payment.received',
                p_subject_table: 'leads', p_subject_id: payRef,
                p_payload: { supplier_id: supId, kind: 'supplier_registration', msg_type: 'registration_paid', amount_aed: paidAmount.toFixed(2) } });
            } catch (_e) { /* the payment is recorded; a failed handoff is visible in agent_actions */ }
            await logRun('ok', { kind: 'supplier_registration', supplier_id: supId, amount: paidAmount }, 'Supplier ' + supId + ' paid the registration fee of AED ' + paidAmount.toFixed(2) + ' via Stripe (ref ' + payRef + ').');
          }
          return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
        }

        // ---- CUSTOMER REVEAL FEE (existing behaviour) ---------------------------------------
        const qid = String(md.quote_id || '');
        if (qid) {
          const { data: existing } = await admin.from('transactions').select('id,doc_path').eq('quote_id', qid).maybeSingle();
          if (!existing) {
            const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount').eq('id', qid).maybeSingle();
            if (q) {
              const { data: inq } = await admin.from('inquiries').select('customer_id,summary').eq('id', q.inquiry_id).maybeSingle();
              const { data: cfg } = await admin.from('pricing_config').select('refund_window_working_days').eq('id', 1).maybeSingle();
              const { data: dl } = await admin.rpc('fn_add_working_days', { p_from: new Date().toISOString(), p_days: cfg?.refund_window_working_days ?? 3 });
              const fee = Number(md.reveal_fee || (s.amount_total ? s.amount_total / 100 : 0));
              const amount = Number(md.quote_amount || q.quote_amount);
              const payRef = String(s.payment_intent || s.id);
              await admin.from('quotes').update({ status: 'revealed' }).eq('id', qid);
              await admin.from('inquiries').update({ status: 'revealed' }).eq('id', q.inquiry_id);
              // total_charged is what a refund returns (founder, 14 Sep 2026): everything the customer paid.
              const totalCharged = s.amount_total ? s.amount_total / 100 : Number(md.total_charged || fee);
              const processing = md.processing_fee != null ? Number(md.processing_fee) : Math.round((totalCharged - fee) * 100) / 100;
              const { data: tx, error: e2 } = await admin.from('transactions').insert({ quote_id: qid, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id, customer_id: inq?.customer_id || md.customer_id || null, quote_amount: amount, reveal_fee: fee, app_fee: fee, processing_fee: processing, total_charged: totalCharged, customer_price: amount, paid_by: 'customer', payment_ref: payRef, fee_status: 'paid', revealed_at: new Date().toISOString(), refund_deadline: dl }).select('id').single();
              if (e2) { await logRun('error', { quote_id: qid, reveal_fee: fee }, 'PAID BUT NOT RECORDED - transaction insert failed: ' + e2.message + ' | payment_ref: ' + payRef); return new Response('insert failed: ' + e2.message, { status: 500 }); }
              // THE INVOICE (9 Sep 2026). invoice_creation is on for reveal-fee sessions, so a paid
              // session names its Invoice. Awaited rather than fired-and-forgotten, because an edge
              // function that has already returned 200 is a function that may be frozen mid-fetch -
              // and the whole point is that the document arrives with the payment. It cannot fail
              // the payment: captureInvoice swallows everything into agent_runs.
              const invoiceId = String(s.invoice || '');
              const modeKey = sigMode === 'test' ? (await secret('stripe_secret_key_test')) || '' : await secret('stripe_secret_key');
              if (modeKey && tx?.id) await recordStripeFee(modeKey, String(tx.id), payRef, logRun);
              if (invoiceId && tx?.id) {
                const invKey = modeKey;
                if (invKey) await captureInvoice(invKey, String(tx.id), invoiceId, logRun);
                else await logRun('error', { quote_id: qid, invoice: invoiceId }, 'INVOICE NOT RETRIEVED - no Stripe secret key for the ' + sigMode + ' mode this event arrived on.');
              } else if (!invoiceId) {
                // Said out loud rather than assumed. A paid reveal with no invoice id means
                // invoice_creation was off for that session, and the sale will read 'missing'.
                await logRun('error', { quote_id: qid, session: String(s.id || '') }, 'NO INVOICE ON A PAID REVEAL - checkout.session.completed carried no invoice id, so nothing can be filed for the accountant. Check invoice_creation on stripe_checkout.');
              }
              // 3 SEP 2026: the supplier's email used to be queued HERE, which meant a reveal recorded by
              // any other path told the supplier nothing. transactions.revealed_at is still the one door
              // every reveal goes through, but the trigger on it no longer writes the messages itself —
              // CORRECTED 22 Sep 2026, measured on production: trg_reveal_receipt calls fn_seat_handoff
              // ('accountant' -> 'sales_engineer', 'reveal.paid'), and the handoff's consumer composes the
              // four messages through fn_sales_engineer_writes, which customer_support delivers
              // (scripts/sql/payments_are_the_accountant_and_the_seats_close_every_refund_together.sql).
              // So this count is one hop further down the chain than it used to be: it reads what the
              // consumer actually queued, which is exactly what it should be checking. Measured on the
              // live table: 3 reveal_receipt and 4 quote_accepted notifications, all carrying quote_id.
              const { count: queued } = await admin.from('notifications').select('id', { count: 'exact', head: true }).eq('quote_id', qid).in('type', ['reveal_receipt', 'quote_accepted']);
              await logRun('ok', { quote_id: qid, reveal_fee: fee, quote_amount: amount, reveal_messages_queued: queued || 0 }, (queued || 0) >= 2 ? '' : 'transaction recorded but fewer than 2 reveal messages were queued by the reveal.paid handoff trg_reveal_receipt opened (' + String(queued || 0) + ')');
            } else {
              // Money taken at Stripe but the quote row is gone - previously silent.
              await logRun('error', { quote_id: qid, amount_total: s.amount_total }, 'PAID BUT NOT RECORDED - quote_id not found in quotes: ' + qid);
            }
          } else {
            // A RE-DELIVERY IS THE REPAIR PATH (9 Sep 2026). The sale is already recorded and stays
            // recorded — that part is still ignored. But if it carries no stored invoice, this is
            // the chance to fetch one: Stripe finalises the invoice PDF moments after the session
            // completes, so a first delivery that arrived a beat too early leaves a sale reading
            // 'reference_only' with nothing to fix it. Resending the event from the Stripe dashboard
            // now repairs it, using machinery that already exists rather than a new endpoint.
            // fn_transaction_attach_invoice is write-once on identity, so this can never rewrite an
            // invoice that is already attached.
            const dupInvoice = String(s.invoice || '');
            if (dupInvoice && existing?.id && !existing?.doc_path) {
              const dupKey = sigMode === 'test' ? (await secret('stripe_secret_key_test')) || '' : await secret('stripe_secret_key');
              if (dupKey) await captureInvoice(dupKey, String(existing.id), dupInvoice, logRun);
            }
            await logRun('ok', { quote_id: qid, duplicate: true, invoice_repair_attempted: Boolean(dupInvoice && existing?.id && !existing?.doc_path) }, 'duplicate delivery ignored (transaction already exists)');
          }
        } else {
          // Paid session with no quote_id and no supplier_dues marker - previously silent.
          await logRun('error', { amount_total: s.amount_total, session: String(s.id || '') }, 'PAID BUT NOT RECORDED - checkout session has neither metadata.quote_id nor metadata.kind=supplier_dues');
        }
      }
    }
    // ---- A REVEAL PAYMENT THAT DID NOT COMPLETE (14 Sep 2026) ------------------------------
    // An expired session or a delayed payment that failed took no money. The accountant hands it to
    // the sales engineer (payment.failed), who tells the customer nothing was charged and how to try
    // again; customer_support delivers it. Only reveal sessions (metadata.quote_id) are handed off: a
    // supplier's own unfinished payment leaves their balance where it was and they see it in Billing.
    if ((FAILED_CHECKOUT_EVENTS as readonly string[]).includes(String(event.type))) {
      const s = event.data?.object || {};
      const md = s.metadata || {};
      if (md.quote_id && s.payment_status !== 'paid') {
        const { error: hErr } = await admin.rpc('fn_seat_handoff', {
          p_from: 'accountant', p_to: 'sales_engineer', p_type: 'payment.failed',
          p_subject_table: 'checkout_session', p_subject_id: String(s.id || md.quote_id),
          p_payload: { quote_id: md.quote_id, inquiry_id: md.inquiry_id || null, customer_id: md.customer_id || null,
                       reason: String(event.type), session: String(s.id || '') },
        });
        await logRun(hErr ? 'error' : 'ok', { type: event.type, quote_id: md.quote_id },
          hErr ? 'payment.failed handoff refused: ' + hErr.message : 'reveal checkout did not complete; handed to the sales engineer');
      } else if (String(md.kind || '') === 'supplier_registration' && Number(md.supplier_id) > 0 && s.payment_status !== 'paid') {
        // 14 Sep 2026 (agent: accountant, duty 3): a subscription payment that did not complete is dunning,
        // not silence. The sales engineer tells the supplier nothing was charged and how to pay.
        const { error: sErr } = await admin.rpc('fn_accountant_subscription_payment_failed', {
          p_supplier_id: Number(md.supplier_id), p_session: String(s.id || ''), p_reason: String(event.type) });
        await logRun(sErr ? 'error' : 'ok', { type: event.type, supplier_id: Number(md.supplier_id) },
          sErr ? 'subscription payment failure not handed on: ' + sErr.message : 'supplier subscription checkout did not complete; handed to the sales engineer');
      }
    }
    // ---- CARD DISPUTES (14 Sep 2026, agent: accountant, duty 7) --------------------------------
    // Recorded the moment Stripe opens or moves one; the accountant runtime answers it with evidence
    // before due_by. fn_accountant_dispute_record ignores a TEST-mode dispute not on a demo payment.
    if ((DISPUTE_EVENTS as readonly string[]).includes(String(event.type))) {
      const dp = event.data?.object || {};
      const { data: rec, error: dErr } = await admin.rpc('fn_accountant_dispute_record', { p_dispute: dp, p_livemode: sigMode === 'live' });
      await logRun(dErr ? 'error' : 'ok', { type: event.type, dispute: String(dp.id || ''), result: rec ?? null },
        dErr ? 'DISPUTE NOT RECORDED - ' + dErr.message + '. The accountant runtime re-reads open disputes daily, but until then the evidence clock runs unwatched.' : '');
      // 13 Oct 2026: a NEW dispute gets its evidence pack built and saved at Stripe as a draft now (submit=false),
      // and the CEO's review item filed, rather than at the next hourly duty (which stays the backstop).
      if (!dErr && event.type === 'charge.dispute.created' && rec?.dispute) {
        const k = sigMode === 'test' ? (await secret('stripe_secret_key_test')) || '' : await secret('stripe_secret_key');
        try {
          const drafted = await draftDisputes(admin, sigMode === 'test' ? { test: k } : { live: k }, String(dp.id));
          await logRun('ok', { type: event.type, dispute: String(dp.id), drafted }, '');
        } catch (e) { await logRun('error', { type: event.type, dispute: String(dp.id) }, 'evidence draft failed, the hourly duty retries: ' + String((e as Error)?.message || e)); }
      }
    }
    // ---- THE REVEAL-FEE INVOICE, ONCE STRIPE HAS FINALISED IT (14 Sep 2026, agent: accountant) --
    // checkout.session.completed often arrives before Stripe has finalised the invoice PDF, which
    // left the sale 'reference_only' until someone resent the event. invoice.finalized and
    // invoice.paid carry the finished invoice; the rules for WHETHER to file are in invoice_event.ts.
    if ((INVOICE_EVENTS as readonly string[]).includes(String(event.type))) {
      const inv = event.data?.object || {};
      const invKey = sigMode === 'test' ? (await secret('stripe_secret_key_test')) || '' : await secret('stripe_secret_key');
      // THE PAYMENT ELEMENT REVEAL (14 Sep 2026). That flow has no Checkout Session, so its sale is
      // recorded HERE on invoice.paid when the browser path (stripe_checkout element_pay/settle) did
      // not already do it. recordRevealSale is idempotent on quote_id; the fee is written once.
      if (String(event.type) === 'invoice.paid' && inv?.metadata?.flow === 'element' && inv?.metadata?.quote_id && invKey) {
        const md = inv.metadata;
        const ip = await timedFetch('https://api.stripe.com/v1/invoice_payments?invoice=' + encodeURIComponent(String(inv.id)), { headers: { Authorization: 'Bearer ' + invKey } })
          .then((r) => r.json()).catch(() => ({}));
        const pi = String(ip?.data?.[0]?.payment?.payment_intent || '');
        const sale = await recordRevealSale(admin, { quoteId: String(md.quote_id), customerId: md.customer_id || null,
          baseFee: Number(md.base_fee), processingFee: Number(md.processing_fee), totalCharged: Number(inv.amount_paid) / 100,
          paymentRef: pi || String(inv.id) });
        if ('error' in sale) await logRun('error', { invoice: String(inv.id), quote_id: md.quote_id }, 'PAID BUT NOT RECORDED - element invoice.paid: ' + sale.error);
        else if (pi) await recordStripeFee(invKey, sale.id, pi, logRun);
      }
      const res = await handleRevealInvoiceEvent({
        findSale: async (quoteId) => {
          const { data } = await admin.from('transactions').select('id,doc_path,stripe_invoice_id').eq('quote_id', quoteId).maybeSingle();
          return data ? { id: String(data.id), doc_path: data.doc_path, stripe_invoice_id: data.stripe_invoice_id } : null;
        },
        capture: async (saleId, invoiceId) => {
          if (invKey) await captureInvoice(invKey, saleId, invoiceId, logRun);
          else await logRun('error', { sale: saleId, invoice: invoiceId }, 'INVOICE NOT RETRIEVED - no Stripe secret key for the ' + sigMode + ' mode this event arrived on.');
        },
      }, inv);
      await logRun(res.action === 'other_invoice' ? 'error' : 'ok', { type: event.type, invoice: String(inv?.id || ''), ...res }, res.action === 'other_invoice' ? 'invoice event names a sale already billed under a different invoice - left untouched' : '');
    }
    // ---- REFUNDS (2 Aug 2026, Phase 1.7) ---------------------------------------------------
    // Until now the only Stripe event this function understood was checkout.session.completed, so
    // money going OUT was invisible: a refund issued here or in the Stripe dashboard produced no
    // record at all, and refund rate, reason, approver and reconciliation were unanswerable. The
    // ledger (public.refunds) now settles from these three events.
    //
    // fn_refund_settle is idempotent on stripe_refund_id because Stripe retries webhooks, and a
    // refund settled twice reads as two refunds. A refund that arrives with no matching request -
    // one issued straight from the Stripe dashboard - is RECORDED rather than dropped, because an
    // unrecorded refund is precisely the money that never reconciles.
    // refund.failed added 2 Aug 2026. Stripe emits it when a refund that was accepted later fails -
    // typically the customer's bank rejecting the credit days after the fact. Without it the ledger
    // would keep a refund reading 'processing' forever and finance would chase money that never
    // moved. It carries the same bare refund object as refund.created/updated.
    if ((REFUND_EVENTS as readonly string[]).includes(String(event.type))) {
      const o = event.data?.object || {};
      // refund.* deliver the refund itself; charge.refunded's Charge may not embed its refunds, so they
      // are asked of Stripe by charge id with the key of the event's mode (refundsInEvent).
      const where = refundsInEvent(String(event.type), o);
      // deno-lint-ignore no-explicit-any
      let refunds: any[] = 'refunds' in where ? where.refunds : [];
      if ('lookup' in where) {
        try {
          const sk = sigMode === 'test' ? (await secret('stripe_secret_key_test')) || '' : await secret('stripe_secret_key');
          if (sk) {
            const lj = await timedFetch('https://api.stripe.com/v1/refunds?limit=100&charge=' + encodeURIComponent(where.lookup),
              { headers: { Authorization: 'Bearer ' + sk } }).then((r) => r.json()).catch(() => ({}));
            if (Array.isArray(lj?.data)) refunds = lj.data;
          }
        } catch (_e) { /* falls through to the quarantine below, which names it */ }
      }
      if (!refunds.length) {
        await logRun('error', { type: event.type, id: String(o?.id || '') },
          'REFUND EVENT WITH NO REFUND OBJECT - nothing settled; check the Stripe payload shape');
        try {
          await admin.rpc('fn_refund_quarantine', {
            p_stripe_refund_id: null, p_event_type: event.type,
            p_reason: 'event contained no refund object',
            p_payload: { object: o?.object || null, id: o?.id || null },
            p_stripe_event_id: String(event?.id || '') || null,
          });
        } catch (_e) { /* quarantining must never break the 200 back to Stripe */ }
      }
      for (const rf of refunds) {
        try {
          // ASK STRIPE RATHER THAN GUESS (2 Aug 2026). An earlier version stored 1 fils when an
          // event carried no amount, to satisfy a CHECK. That put a fabricated number in the
          // ledger. The amount is now either known or NULL - and before accepting NULL, we ask
          // Stripe for the refund by id, which is the authoritative answer and costs one call on a
          // path that almost never fires.
          let amountFils: number | null = Number(rf?.amount || 0) || null;
          let amountSource = 'webhook_event';
          if (amountFils === null && rf?.id) {
            try {
              // The lookup must use the key for the MODE the event arrived on. A test-mode refund id
              // queried with the live key returns 404, which would look like "Stripe has no amount"
              // and quarantine a refund that was perfectly well-formed.
              const sk = sigMode === 'test'
                ? (await secret('stripe_secret_key_test')) || ''
                : await secret('stripe_secret_key');
              if (sk) {
                const lookup = await timedFetch('https://api.stripe.com/v1/refunds/' + encodeURIComponent(String(rf.id)),
                  { headers: { Authorization: 'Bearer ' + sk } });
                const lj = await lookup.json().catch(() => ({}));
                const n = Number(lj?.amount || 0) || null;
                if (n !== null) { amountFils = n; amountSource = 'stripe_api'; }
                else {
                  await logRun('error', { refund: String(rf.id), http: lookup.status },
                    'REFUND AMOUNT UNKNOWN - not in the event and Stripe returned none. Recorded as unknown and quarantined.');
                }
              }
            } catch (e) {
              await logRun('error', { refund: String(rf?.id || '') },
                'refund amount lookup against Stripe failed: ' + String((e as Error)?.message || e));
            }
          }
          const { data, error } = await admin.rpc('fn_refund_settle', {
            p_stripe_refund_id: String(rf?.id || ''),
            p_status: String(rf?.status || 'pending'),
            p_amount_fils: amountFils,
            p_payment_intent: String(rf?.payment_intent || o?.payment_intent || '') || null,
            p_charge_id: String(rf?.charge || o?.id || '') || null,
            p_failure_reason: rf?.failure_reason ? String(rf.failure_reason) : null,
            p_amount_source: amountSource,
            p_stripe_event_id: String(event?.id || '') || null,
          });
          if (error) {
            await logRun('error', { refund: String(rf?.id || ''), type: event.type },
              'REFUND NOT RECORDED - the money left Stripe but the ledger rejected it: ' + error.message);
          } else {
            // THE DOCUMENT REFERENCE (9 Sep 2026). The founder wants the Stripe document held with
            // the record. stripe_checkout uses mode=payment with no invoice_creation, so Stripe
            // makes no Invoice and there is no invoice_pdf to fetch; the artefact that DOES exist is
            // the CHARGE's receipt_url, and charge.refunded is the one event that carries it (the
            // bare refund.* payloads do not). Recorded when it is there, never invented when it is
            // not. Best-effort: a refund that settled must not be un-settled by a missing link.
            const receiptUrl = String(o?.receipt_url || '');
            const settledId = Number((data as Record<string, unknown> | null)?.refund_id || 0);
            // THE HANDLER ASKS; THE DATABASE DECIDES. This was a direct table update against the
            // refunds table for a few hours today and the standing check
            // (NOTE: the previous wording of this comment quoted the forbidden call shape verbatim,
            // and the check — which greps this file — matched its own explanation. A comment is not
            // a code path, but a text search cannot tell the difference, so the shape is described
            // here rather than spelled.)
            // `settlement is delegated to the database, not reimplemented in the handler` refused
            // it. The write was benign — a link, guarded against overwrite — but the rule is that
            // the handler does not write to `refunds` AT ALL, and it holds precisely because the
            // next direct write would be argued for on the same "but this one is harmless" grounds.
            // fn_refund_attach_receipt also refuses a URL that is not Stripe's, which a payload
            // could otherwise have set on a column the founder opens as evidence.
            if (receiptUrl && settledId > 0) {
              try {
                await admin.rpc('fn_refund_attach_receipt',
                  { p_refund_id: settledId, p_receipt_url: receiptUrl });
              } catch (_e) { /* the reference is evidence, not settlement */ }
            }
            await logRun('ok', { refund: String(rf?.id || ''), result: data, type: event.type,
              receipt_url_recorded: Boolean(receiptUrl && settledId > 0) }, '');
          }
        } catch (e) {
          await logRun('error', { refund: String(rf?.id || ''), type: event.type },
            'REFUND NOT RECORDED - exception while settling: ' + String((e as Error)?.message || e));
        }
      }
    }
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return new Response('handler error: ' + m, { status: 500 }); }
  return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
}));
