import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const TOLERANCE_SECONDS = 600; // reject events whose signature timestamp is older/newer than this (replay guard)
async function secret(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
function toHex(buf: ArrayBuffer) { return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join(''); }

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
Deno.serve(async (req) => {
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
  let sigMode = '';
  if (whsecLive && await verifySig(sig, raw, whsecLive)) sigMode = 'live';
  else if (whsecTest && await verifySig(sig, raw, whsecTest)) sigMode = 'test';
  if (!sigMode) { await logRun('error', {}, 'bad_signature (rejected before parsing)'); return new Response('bad signature', { status: 400 }); }
  let event: any; try { event = JSON.parse(raw); } catch { await logRun('error', {}, 'bad_json from Stripe'); return new Response('bad json', { status: 400 }); }
  // Ledger (Finding 7): record every signature-verified delivery for audit + reconciliation and
  // count retries. Best-effort and non-blocking — correctness is still enforced by the conditional
  // updates below, so a ledger failure can never drop a payment.
  try {
    const evId = String(event?.id || '');
    if (evId) await admin.rpc('fn_stripe_event_seen', { p_event_id: evId, p_type: String(event?.type || ''), p_status: String(event?.data?.object?.payment_status || '') });
  } catch (_e) { /* ledger is best-effort */ }
  try {
    if (event.type === 'checkout.session.completed') {
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
            .update({ status: 'paid', paid_at: new Date().toISOString(), payment_ref: payRef })
            .in('id', ids).is('paid_at', null).select('id,amount_due,supplier_id');

          if (uErr) { await logRun('error', { kind: 'supplier_dues', due_ids: ids, amount: paidAmount }, 'SUPPLIER PAID BUT NOT RECORDED - failed to mark supplier_dues paid (' + uErr.message + '). Payment ref ' + payRef + '. The supplier has been charged and will still be chased for the debt until this is reconciled by hand.'); return new Response('due update failed: ' + uErr.message, { status: 500 }); }

          const n = (settled || []).length;
          if (n === 0) { await logRun('ok', { kind: 'supplier_dues', duplicate: true, due_ids: ids }, 'Duplicate Stripe delivery for supplier dues ignored - those dues were already settled.'); }
          else {
            // Push the collection straight into the ledger rather than waiting for the next cron.
            let posted = 0; try { const { data: gp } = await admin.rpc('fn_gl_sync_business'); posted = Number(gp || 0); } catch (_e) { /* cron will catch up */ }
            try {
              const supId = (settled || [])[0]?.supplier_id;
              const { data: sup } = await admin.from('leads').select('email,company_name').eq('id', supId).maybeSingle();
              if (sup?.email && /@/.test(sup.email)) await admin.from('notifications').insert([{ type: 'dues_paid', to_email: sup.email, to_role: 'supplier', lead_id: supId, subject: 'Payment received - thank you', body: 'We have received your payment of AED ' + paidAmount.toFixed(2) + ' settling ' + n + ' commission item(s). Your account is now up to date.' }]);
            } catch (_e) { /* */ }
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
            try { const sup = (settled || [])[0]; if (sup?.email && /@/.test(sup.email)) await admin.from('notifications').insert([{ type: 'registration_paid', to_email: sup.email, to_role: 'supplier', lead_id: supId, subject: 'Registration confirmed - thank you', body: 'We have received your registration payment of AED ' + paidAmount.toFixed(2) + '. Your QuotesDone supplier account is registered for the next 12 months.' }]); } catch (_e) { /* */ }
            await logRun('ok', { kind: 'supplier_registration', supplier_id: supId, amount: paidAmount }, 'Supplier ' + supId + ' paid the registration fee of AED ' + paidAmount.toFixed(2) + ' via Stripe (ref ' + payRef + ').');
          }
          return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
        }

        // ---- CUSTOMER REVEAL FEE (existing behaviour) ---------------------------------------
        const qid = String(md.quote_id || '');
        if (qid) {
          const { data: existing } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle();
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
              const { error: e2 } = await admin.from('transactions').insert({ quote_id: qid, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id, customer_id: inq?.customer_id || md.customer_id || null, quote_amount: amount, reveal_fee: fee, app_fee: fee, customer_price: amount, paid_by: 'customer', payment_ref: payRef, fee_status: 'paid', revealed_at: new Date().toISOString(), refund_deadline: dl });
              if (e2) { await logRun('error', { quote_id: qid, reveal_fee: fee }, 'PAID BUT NOT RECORDED - transaction insert failed: ' + e2.message + ' | payment_ref: ' + payRef); return new Response('insert failed: ' + e2.message, { status: 500 }); }
              // 3 SEP 2026: the supplier's email used to be queued HERE, which meant a reveal recorded by
              // any other path told the supplier nothing. All four reveal messages (email + WhatsApp to
              // both parties) are queued by trg_reveal_receipt on transactions.revealed_at — the one
              // door every reveal goes through (scripts/sql/reveal_notifies_both_parties_on_both_channels.sql).
              const { count: queued } = await admin.from('notifications').select('id', { count: 'exact', head: true }).eq('quote_id', qid).in('type', ['reveal_receipt', 'quote_accepted']);
              await logRun('ok', { quote_id: qid, reveal_fee: fee, quote_amount: amount, reveal_messages_queued: queued || 0 }, (queued || 0) >= 2 ? '' : 'transaction recorded but fewer than 2 reveal messages were queued by trg_reveal_receipt (' + String(queued || 0) + ')');
            } else {
              // Money taken at Stripe but the quote row is gone - previously silent.
              await logRun('error', { quote_id: qid, amount_total: s.amount_total }, 'PAID BUT NOT RECORDED - quote_id not found in quotes: ' + qid);
            }
          } else {
            await logRun('ok', { quote_id: qid, duplicate: true }, 'duplicate delivery ignored (transaction already exists)');
          }
        } else {
          // Paid session with no quote_id and no supplier_dues marker - previously silent.
          await logRun('error', { amount_total: s.amount_total, session: String(s.id || '') }, 'PAID BUT NOT RECORDED - checkout session has neither metadata.quote_id nor metadata.kind=supplier_dues');
        }
      }
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
    if (event.type === 'charge.refunded' || event.type === 'refund.updated'
        || event.type === 'refund.created' || event.type === 'refund.failed') {
      const o = event.data?.object || {};
      // charge.refunded delivers a charge with a refunds list; refund.* deliver the refund itself.
      const refunds = Array.isArray(o?.refunds?.data) ? o.refunds.data : (o?.object === 'refund' ? [o] : []);
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
                const lookup = await fetch('https://api.stripe.com/v1/refunds/' + encodeURIComponent(String(rf.id)),
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
            await logRun('ok', { refund: String(rf?.id || ''), result: data, type: event.type }, '');
          }
        } catch (e) {
          await logRun('error', { refund: String(rf?.id || ''), type: event.type },
            'REFUND NOT RECORDED - exception while settling: ' + String((e as Error)?.message || e));
        }
      }
    }
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return new Response('handler error: ' + m, { status: 500 }); }
  return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
});
