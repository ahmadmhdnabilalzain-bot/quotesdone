import { siteCors } from '../_shared/site_origins.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { isDemoEmail, stripeKeyNames } from '../_shared/demo_identity.ts';
import { canReveal } from '../_shared/reveal_guard.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function secret(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }

// Observability: this is the browser-side confirmation path that records a paid reveal.
// It duplicates stripe_webhook, so a failure here can still be covered by the webhook -
// logging both makes it clear which one actually recorded the money.
function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'stripe_confirm', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break reveal confirmation */ }
  };
}

Deno.serve(siteCors(observe('stripe_confirm', async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const { data: cust } = await admin.from('customers').select('id').eq('email', user.email.toLowerCase()).maybeSingle();
    if (!cust) { await logRun('error', {}, 'no_customer_profile for authenticated user'); return J({ error: 'No customer profile' }, 403); }
    const body = await req.json().catch(() => ({}));
    const sid = String(body.session_id || '');
    if (!sid) return J({ error: 'missing session_id' }, 400);
    // A demo account's session lives in the Stripe TEST account, so it is read with the test key
    // and never the live one (see stripe_checkout; the mode is derived from the account, 14 Sep 2026).
    const keys = stripeKeyNames(isDemoEmail(user.email));
    const sk = await secret(keys.secret);
    // 503, not an HTTP 200 carrying a code (customer-portal audit CP-10, 22 Sep 2026).
    if (!sk && keys.mode === 'test') { await logRun('ok', { session_id: sid, mode: 'test' }, 'demo account: stripe test keys are not configured - confirmation refused, live key never used'); return J({ ok: false, error: 'stripe_test_not_configured', code: 'stripe_test_not_configured', mode: 'test', message: 'Card payments are not available on this test account.', message_ar: 'الدفع بالبطاقة غير متاح على هذا الحساب التجريبي.' }, 503); }
    if (!sk) { await logRun('error', { session_id: sid }, 'CONFIRM BLOCKED - stripe_secret_key missing from app_secrets'); return J({ ok: false, error: 'stripe_not_configured', code: 'stripe_not_configured', message: 'We could not confirm your payment just now. Nothing is lost — please reload in a moment.', message_ar: 'تعذّر تأكيد دفعتك الآن. لم يُفقد شيء — يُرجى تحديث الصفحة بعد لحظات.' }, 503); }
    const r = await timedFetch('https://api.stripe.com/v1/checkout/sessions/' + encodeURIComponent(sid), { headers: { 'Authorization': 'Bearer ' + sk } });
    const s = await r.json();
    if (!r.ok) { await logRun('error', { session_id: sid, http: r.status }, 'stripe session fetch failed: ' + String(s?.error?.message || '').slice(0, 250)); return J({ error: 'stripe_error', detail: String(s?.error?.message || '').slice(0, 300) }, 502); }
    const md = s.metadata || {};
    const qid = String(md.quote_id || '');
    if (!qid) { await logRun('error', { session_id: sid, payment_status: String(s?.payment_status || '') }, 'session has no metadata.quote_id - cannot record reveal'); return J({ error: 'no quote in session' }, 400); }
    const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount').eq('id', qid).maybeSingle();
    if (!q) { await logRun('error', { quote_id: qid, session_id: sid }, 'quote_id from Stripe session not found in quotes'); return J({ error: 'Quote not found' }, 404); }
    const { data: inq } = await admin.from('inquiries').select('id,customer_id,summary').eq('id', q.inquiry_id).maybeSingle();
    if (!inq || inq.customer_id !== cust.id) { await logRun('error', { quote_id: qid }, 'ownership violation: customer confirmed another customer inquiry'); return J({ error: 'Not your inquiry' }, 403); }
    // founder instruction 516, 18 Sep 2026: a sanctioned party is never shown to a customer, and
    // this is the last door identity leaves by. Returning null here is deliberate and visible —
    // customer_api's reveal refuses before the charge, so reaching this branch means the ban landed
    // between the payment and the confirmation.
    //
    // The DISCLOSURE goes through the same guard customer_api and stripe_checkout use
    // (_shared/reveal_guard.ts, audit CP-09). The RECORDING never does: the money has moved, so a
    // ban that lands mid-payment must still leave a transaction to refund against.
    // THE FILE IS IDENTITY TOO (review of #850, 22 Sep 2026). The contact card was gated and the
    // signed URL to the supplier's OWN quotation PDF was not, so a refusal handed back nothing but
    // a one-hour link to the letterhead it had just refused to name. One function now returns the
    // whole disclosure — contact, file URL and file name — or nothing at all.
    const disclose = async (): Promise<{ supplier: unknown }> => {
      const g = await canReveal(admin, { quoteId: qid, customerId: String(cust.id) });
      if (!g.ok) { await logRun('error', { quote_id: qid, disclosure_refused: g.code }, 'the payment is recorded but the supplier was NOT disclosed (' + g.code + '); the customer must be refunded or told.'); return { supplier: null }; }
      const { data: sup } = await admin.from('leads').select('company_name,phone,whatsapp,email,website,emirate').eq('id', q.supplier_id).maybeSingle();
      return { supplier: sup }; /* rulings 1228/1229: the customer only ever gets our template quotation as a PDF, never the supplier's own file */
    };
    const { data: existing } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle();
    if (existing) { await logRun('ok', { quote_id: qid, already_revealed: true }, 'already recorded (likely by stripe_webhook)'); return J({ ok: true, already_revealed: true, ...(await disclose()) }); }
    if (s.payment_status !== 'paid') { await logRun('ok', { quote_id: qid, payment_status: String(s.payment_status || '') }, 'session not paid yet - returned pending'); return J({ ok: false, pending: true }); }
    const { data: cfg } = await admin.from('pricing_config').select('refund_window_working_days').eq('id', 1).maybeSingle();
    const { data: dl } = await admin.rpc('fn_add_working_days', { p_from: new Date().toISOString(), p_days: cfg?.refund_window_working_days ?? 3 });
    const fee = Number(md.reveal_fee || (s.amount_total ? s.amount_total / 100 : 0));
    const amount = Number(md.quote_amount || q.quote_amount);
    const payRef = String(s.payment_intent || s.id);
    await admin.from('quotes').update({ status: 'revealed' }).eq('id', qid);
    await admin.from('inquiries').update({ status: 'revealed' }).eq('id', q.inquiry_id);
    // total_charged is what a refund returns (founder, 14 Sep 2026): since 24 Sep 2026 the 3% alone.
    const totalCharged = s.amount_total ? s.amount_total / 100 : Number(md.total_charged || fee);
    const processing = md.processing_fee != null ? Number(md.processing_fee) : Math.round((totalCharged - fee) * 100) / 100;
    const { error: e2 } = await admin.from('transactions').insert({ quote_id: qid, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id, customer_id: cust.id, quote_amount: amount, reveal_fee: fee, app_fee: fee, processing_fee: processing, total_charged: totalCharged, customer_price: amount, paid_by: 'customer', payment_ref: payRef, fee_status: 'paid', revealed_at: new Date().toISOString(), refund_deadline: dl });
    if (e2) { const { data: again } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle(); if (!again) { await logRun('error', { quote_id: qid, reveal_fee: fee }, 'PAID BUT NOT RECORDED - insert failed and no row present: ' + e2.message + ' | payment_ref: ' + payRef); return J({ error: 'record_failed', detail: e2.message }, 500); } await logRun('ok', { quote_id: qid, raced: true }, 'insert conflicted but row exists - stripe_webhook won the race'); }
    // 14 Sep 2026: the supplier's "a customer revealed you" message is no longer queued here. The
    // insert above goes through z20_reveal_receipt, which hands the paid reveal from the accountant to
    // the sales engineer, whose words customer_support delivers -- the same door the webhook uses, so a
    // supplier is told once whichever path recorded the payment.
    if (!e2) await logRun('ok', { quote_id: qid, reveal_fee: fee, quote_amount: amount }, 'recorded by stripe_confirm (browser path)');
    return J({ ok: true, ...(await disclose()) });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
})));
