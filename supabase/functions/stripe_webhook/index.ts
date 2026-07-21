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
  const whsec = await secret('stripe_webhook_secret');
  if (!whsec) { await logRun('error', {}, 'not_configured: stripe_webhook_secret missing'); return new Response('not_configured', { status: 400 }); }
  if (!(await verifySig(sig, raw, whsec))) { await logRun('error', {}, 'bad_signature (rejected before parsing)'); return new Response('bad signature', { status: 400 }); }
  let event: any; try { event = JSON.parse(raw); } catch { await logRun('error', {}, 'bad_json from Stripe'); return new Response('bad json', { status: 400 }); }
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
          const YEAR_MS = 365 * 24 * 60 * 60 * 1000;
          const { data: settled, error: rErr } = await admin.from('leads')
            .update({ registration_status: 'paid', registration_fee_due: 0, registration_paid_at: new Date().toISOString(), registration_expires_at: new Date(Date.now() + YEAR_MS).toISOString() })
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
              const { data: dl } = await admin.rpc('add_working_days', { start_ts: new Date().toISOString(), n: cfg?.refund_window_working_days ?? 3 });
              const fee = Number(md.reveal_fee || (s.amount_total ? s.amount_total / 100 : 0));
              const amount = Number(md.quote_amount || q.quote_amount);
              const payRef = String(s.payment_intent || s.id);
              await admin.from('quotes').update({ status: 'revealed' }).eq('id', qid);
              await admin.from('inquiries').update({ status: 'revealed' }).eq('id', q.inquiry_id);
              const { error: e2 } = await admin.from('transactions').insert({ quote_id: qid, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id, customer_id: inq?.customer_id || md.customer_id || null, quote_amount: amount, reveal_fee: fee, app_fee: fee, customer_price: amount, paid_by: 'customer', payment_ref: payRef, fee_status: 'paid', revealed_at: new Date().toISOString(), refund_deadline: dl });
              if (e2) { await logRun('error', { quote_id: qid, reveal_fee: fee }, 'PAID BUT NOT RECORDED - transaction insert failed: ' + e2.message + ' | payment_ref: ' + payRef); return new Response('insert failed: ' + e2.message, { status: 500 }); }
              let notified = false;
              try { const { data: sup } = await admin.from('leads').select('email').eq('id', q.supplier_id).maybeSingle(); if (sup?.email && /@/.test(sup.email)) { await admin.from('notifications').insert([{ type: 'quote_accepted', to_email: sup.email, to_role: 'supplier', lead_id: q.supplier_id, inquiry_id: q.inquiry_id, quote_id: qid, subject: 'A customer revealed your quote on QuotesDone', body: 'A customer paid to reveal your contact for: ' + ((inq?.summary) || '') + '. Please respond promptly — if you do not respond within 3 working days the customer may be refunded.' }]); notified = true; } } catch (_e) { /* */ }
              await logRun('ok', { quote_id: qid, reveal_fee: fee, quote_amount: amount, supplier_notified: notified }, notified ? '' : 'transaction recorded but supplier email not sent');
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
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return new Response('handler error: ' + m, { status: 500 }); }
  return new Response(JSON.stringify({ received: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
});
