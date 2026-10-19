import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { jobNoOf } from '../_shared/quote_documents.ts';
import { observe } from '../_shared/observe.ts';
import { siteReturnBase, siteCors } from '../_shared/site_origins.ts';
import { revealCharge } from '../_shared/reveal_fee.ts';
import { asLocale } from '../_shared/registered_locale.ts';
import { recordRevealSale } from '../_shared/reveal_sale.ts';
import { payReveal, priceToken, type StripeCall } from './element_pay.ts';
import { isDemoEmail, stripeKeyNames } from '../_shared/demo_identity.ts';
import { canReveal } from '../_shared/reveal_guard.ts';
import { readRevealRate, recordRateUnreadable } from '../_shared/reveal_rate.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function secret(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// 6 Sep 2026 (founder): the reveal fee is 3% of the quotation value with NO discount, NO promotional rate
// and NO cap. This is the amount Stripe charges, so it computes the standard rate and nothing else, the
// same as public.reveal_fee(); pricing_config forbids a promo or a cap by constraint.
function revealFee(amount: number, cfg: any): number { if (!amount || amount <= 0) return 0; return Math.round(amount * Number(cfg?.standard_reveal_rate) * 100) / 100; }

// Observability: a customer who cannot reach Stripe checkout is lost revenue with no trace.
// Config and Stripe-side failures are logged as errors; auth rejections are not (normal traffic).
function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'stripe_checkout', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging block checkout */ }
  };
}

Deno.serve(siteCors(observe('stripe_checkout', async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const { data: cust } = await admin.from('customers').select('id,locale').eq('email', user.email.toLowerCase()).maybeSingle();
    if (!cust) { await logRun('error', {}, 'no_customer_profile for authenticated user - cannot start checkout'); return J({ error: 'No customer profile' }, 403); }
    const body = await req.json().catch(() => ({}));
    const qid = String(body.quote_id || '');
    // NOTHING IS CHARGED THAT COULD NOT BE REVEALED (customer-portal audit CP-09, 22 Sep 2026).
    // This checked ownership and nothing else: no sanctions ban (instruction 516 — a customer must
    // never pay 3% to be handed a permanently closed party), no quote status, no request status,
    // and not the completeness hold that keeps the same quote out of the comparison. The four
    // checks live in _shared/reveal_guard.ts, which customer_api's own `reveal` calls, so the
    // dialog the customer confirms and the charge that follows it cannot disagree.
    const gate = await canReveal(admin, { quoteId: qid, customerId: String(cust.id) });
    if (!gate.ok) {
      await logRun(gate.code === 'not_your_inquiry' || gate.code === 'quote_not_found' ? 'error' : 'ok', { quote_id: qid, refused: gate.code },
        'checkout refused before any charge (' + gate.code + '): ' + gate.message);
      return J({ ok: false, error: gate.error, code: gate.code, message: gate.message, message_ar: gate.message_ar }, gate.status);
    }
    const q = gate.quote; const inq = gate.inquiry;
    if (gate.already_revealed) { await logRun('ok', { quote_id: qid, already_revealed: true }, ''); return J({ already_revealed: true }); }
    // DEMO ACCOUNTS PAY ONLY IN STRIPE TEST MODE (14 Sep 2026, it_engineer's tooling for the ceo).
    // The e2e harness signs in as demo customers on the one production project, which holds the
    // LIVE keys. The mode is derived HERE from the signed-in account's email - a reserved RFC 2606
    // domain nobody can receive mail at, so no real customer can ever hold one - and never from
    // anything the browser sends. A demo account is served only stripe_secret_key_test /
    // stripe_publishable_key_test; when those are absent the answer is "not configured", and there
    // is deliberately no fall-through to the live key. A real account is never served the test pair.
    const keys = stripeKeyNames(isDemoEmail(user.email));
    const sk = await secret(keys.secret);
    // A PAYMENT THAT CANNOT BE TAKEN IS A 503, NOT AN HTTP 200 (customer-portal audit CP-10,
    // 22 Sep 2026). These answered 200 with a code, so the browser, every log and every probe read
    // "the reveal worked". The portal reads the body (errText), so the status costs it nothing.
    if (!sk && keys.mode === 'test') { await logRun('ok', { quote_id: qid, mode: 'test' }, 'demo account: stripe test keys are not configured, so the payment is refused - the live key is never used for a demo account'); return J({ ok: false, error: 'stripe_test_not_configured', code: 'stripe_test_not_configured', mode: 'test', message: 'Card payments are not available on this test account.', message_ar: 'الدفع بالبطاقة غير متاح على هذا الحساب التجريبي.' }, 503); }
    if (!sk) { await logRun('error', { quote_id: qid }, 'CHECKOUT BLOCKED - stripe_secret_key missing from app_secrets; all reveals are failing'); return J({ ok: false, error: 'stripe_not_configured', code: 'stripe_not_configured', message: 'Card payments are briefly unavailable. Your quotes are safe — please try again shortly.', message_ar: 'الدفع بالبطاقة غير متاح مؤقتًا. عروضك محفوظة — يُرجى المحاولة بعد قليل.' }, 503); }
    // The one rate reader (../_shared/reveal_rate.ts): unreadable or outside 0 < rate < 1 refuses the checkout.
    const rateRead = await readRevealRate(admin);
    if (!rateRead.ok) { await recordRateUnreadable(admin, 'stripe_checkout -> pricing_config', rateRead.error, { quote_id: qid }); await logRun('error', { quote_id: qid, error: rateRead.error }, 'reveal rate unreadable - checkout blocked'); return J({ error: 'invalid_fee' }, 400); }
    const cfg = rateRead.cfg;
    const fee = revealFee(Number(q.quote_amount), cfg);
    if (!(fee > 0)) { await logRun('error', { quote_id: qid, quote_amount: q.quote_amount, fee, has_pricing_config: true }, 'invalid_fee computed - checkout blocked (check pricing_config rates/caps and quote_amount)'); return J({ error: 'invalid_fee' }, 400); }
    // 14 Sep 2026 (founder): "3% plus stripe fees included". The 3% line is unchanged; card
    // processing is its own line so the invoice says what each part is. No tax on either line.
    const ch = revealCharge(Number(q.quote_amount), Number(cfg?.standard_reveal_rate));
    if (ch.base_fee !== fee) { await logRun('error', { quote_id: qid, fee, base: ch.base_fee }, 'reveal fee disagreement between revealFee and revealCharge - checkout blocked'); return J({ error: 'invalid_fee' }, 400); }
    // "Reveal fee — QD-XXXXXXXX / Supplier B": the letter is the one the customer's card shows,
    // the place among the LIVE quotes by ascending price (customer_api letterOf).
    const { data: sibs } = await admin.from('quotes').select('id').eq('inquiry_id', q.inquiry_id).neq('status', 'draft').order('quote_amount', { ascending: true });
    const idx = Math.max(0, (sibs || []).findIndex((x: { id: string }) => x.id === q.id));
    const letter = String.fromCharCode(65 + (idx % 26));
    // The job number (inquiries.rfq_no): what the customer's card statement says must match the portal (21 Sep 2026).
    const requestRef = 'QD-' + jobNoOf({ id: String(q.inquiry_id || ''), rfq_no: inq?.rfq_no });
    // 27 Jul 2026 — two defects fixed here.
    // (1) OPEN REDIRECT. return_url was taken verbatim from the request body, so a crafted call
    //     sent the paying customer to any domain with the Checkout Session id in the query string.
    //     The host is now allowlisted and anything else falls back to the canonical site.
    // (2) DEAD RETURN PAGE. success_url was `<return_url>/app?paid=…`. The portal passes
    //     `location.origin + '/me'`, so customers landed on https://quotesdone.com/me/app — a route
    //     that does not exist — and the query parameter was named `paid`, while CustomerPortal.tsx:417
    //     reads `session_id`. The browser-side confirmation path (stripe_confirm) was therefore
    //     unreachable and settlement depended entirely on the webhook.
    // 14 Sep 2026: the allowlist now lives in _shared/site_origins.ts and includes quotesdone.ae, so
    // a customer who pays from .ae returns to .ae, where their session is.
    const base = siteReturnBase(req, body.return_url);
    const portal = /\/me$/.test(base) ? base : (base + '/me');

    // ---- THE PAYMENT ELEMENT REVEAL: priced on the card actually used (14 Sep 2026) -------------
    // element_init  -> publishable key + the safest total, so the Payment Element can render.
    // element_quote -> the exact total for the card in this ConfirmationToken. Nothing is charged.
    // element_pay   -> reprice, refuse if it differs from what the customer saw, invoice and pay.
    // element_settle-> after 3-D Secure: record the sale once the invoice reads paid.
    // The Checkout Session below stays as the fallback, charged at the safest rate.
    const action = String(body.action || '');
    if (action.startsWith('element_')) {
      const stripe: StripeCall = async (path, form, idem) => {
        const r = await timedFetch('https://api.stripe.com/v1/' + path, {
          method: form ? 'POST' : 'GET',
          headers: { Authorization: 'Bearer ' + sk, ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}), ...(idem ? { 'Idempotency-Key': idem } : {}) },
          body: form ? form.toString() : undefined,
        });
        return { ok: r.ok, status: r.status, j: await r.json().catch(() => ({})) };
      };
      const rate = Number(cfg?.standard_reveal_rate);
      if (action === 'element_init') {
        const pk = await secret(keys.publishable);
        if (!pk) { const code = keys.mode === 'test' ? 'stripe_test_not_configured' : 'stripe_not_configured'; await logRun(keys.mode === 'test' ? 'ok' : 'error', { quote_id: qid, mode: keys.mode }, 'ELEMENT BLOCKED - ' + keys.publishable + ' missing'); return J({ ok: false, error: code, code, mode: keys.mode, message: 'Card payments are briefly unavailable. Your quotes are safe — please try again shortly.', message_ar: 'الدفع بالبطاقة غير متاح مؤقتًا. عروضك محفوظة — يُرجى المحاولة بعد قليل.' }, 503); }
        return J({ ok: true, mode: keys.mode, publishable_key: pk, currency: 'aed', amount_fils: Math.round(ch.total_charged * 100),
          base_fee: ch.base_fee, safest_total: ch.total_charged });
      }
      if (action === 'element_quote') {
        const p = await priceToken(stripe, String(body.confirmation_token || ''), Number(q.quote_amount), rate);
        if (!p.ok) return J({ error: p.error }, p.status);
        return J({ ok: true, ...p.priced.charge, total_fils: Math.round(p.priced.charge.total_charged * 100),
          fee_basis: p.priced.basis.basis, card_country: p.priced.basis.card_country, wallet: p.priced.basis.wallet });
      }
      if (action === 'element_pay') {
        const res = await payReveal(stripe, {
          ct: String(body.confirmation_token || ''), quoteAmount: Number(q.quote_amount), rate,
          expectedTotalFils: Number(body.expected_total_fils), email: user.email, qdCustomerId: String(cust.id),
          quoteId: qid, inquiryId: String(q.inquiry_id), supplierId: String(q.supplier_id),
          requestRef, letter, returnUrl: portal + '?reveal=' + encodeURIComponent(qid),
        });
        const counts = { quote_id: qid, status: res.status, ...(res.priced ? { total: res.priced.charge.total_charged, basis: res.priced.basis.basis, card_country: res.priced.basis.card_country, wallet: res.priced.basis.wallet } : {}) };
        if (res.status === 'succeeded') {
          const sale = await recordRevealSale(admin, { quoteId: qid, customerId: String(cust.id), baseFee: res.priced.charge.base_fee,
            processingFee: res.priced.charge.processing_fee, totalCharged: res.priced.charge.total_charged, paymentRef: res.payment_intent, invoiceId: res.invoice });
          await logRun('error' in sale ? 'error' : 'ok', { ...counts, invoice: res.invoice, sale }, 'error' in sale ? 'PAID BUT NOT RECORDED by element_pay - stripe_webhook invoice.paid will retry: ' + sale.error : '');
        } else {
          await logRun(res.status === 'failed' ? 'error' : 'ok', counts, res.status === 'failed' ? 'element payment failed: ' + res.error : '');
        }
        if (res.status === 'failed') return J({ ok: false, status: 'failed', error: res.error });
        return J({ ok: true, status: res.status, ...res.priced.charge, total_fils: Math.round(res.priced.charge.total_charged * 100),
          fee_basis: res.priced.basis.basis, ...('client_secret' in res ? { client_secret: res.client_secret, invoice: res.invoice } : {}) });
      }
      if (action === 'element_settle') {
        const invId = String(body.invoice || '');
        if (!/^in_[A-Za-z0-9]+$/.test(invId)) return J({ error: 'bad_invoice' }, 400);
        const r = await stripe('invoices/' + invId + '?expand[]=payments');
        const inv = r.j || {};
        // The invoice must be this customer's reveal of THIS quote before anything is recorded.
        if (!r.ok || inv.metadata?.quote_id !== qid || inv.metadata?.customer_id !== String(cust.id)) { await logRun('error', { quote_id: qid, invoice: invId }, 'element_settle refused - invoice is not this customer\'s reveal of this quote'); return J({ error: 'Not your payment' }, 403); }
        if (inv.status !== 'paid') return J({ ok: false, pending: true });
        const pi = String(inv.payments?.data?.[0]?.payment?.payment_intent || invId);
        const sale = await recordRevealSale(admin, { quoteId: qid, customerId: String(cust.id), baseFee: Number(inv.metadata.base_fee),
          processingFee: Number(inv.metadata.processing_fee), totalCharged: Number(inv.amount_paid) / 100, paymentRef: pi, invoiceId: invId });
        await logRun('error' in sale ? 'error' : 'ok', { quote_id: qid, invoice: invId, sale }, '');
        return 'error' in sale ? J({ error: 'record_failed' }, 500) : J({ ok: true });
      }
      return J({ error: 'unknown_action' }, 400);
    }
    const success = portal + '?session_id={CHECKOUT_SESSION_ID}&reveal=' + encodeURIComponent(qid);
    // A cancelled checkout used to land on the bare portal with nothing on screen, which reads as
    // "did it charge me?". The marker lets the portal say plainly that nothing was paid.
    const cancel = portal + '?payment=cancelled&reveal=' + encodeURIComponent(qid);
    const form = new URLSearchParams();
    form.set('mode', 'payment');
    form.set('success_url', success);
    form.set('cancel_url', cancel);
    form.set('client_reference_id', qid);
    form.set('customer_email', user.email);
    // The hosted page follows the REGISTERED language, not the browser's: an English-registered
    // customer is pinned to 'en'. The portal's own reveal path (RevealPayment, Payment Element) passes
    // 'ar' for an Arabic-registered customer; this hosted fallback is left on Stripe's default for them
    // rather than risk a locale value the hosted page may refuse and so fail the payment outright.
    if (asLocale(cust?.locale) === 'en') form.set('locale', 'en');
    form.set('line_items[0][quantity]', '1');
    form.set('line_items[0][price_data][currency]', 'aed');
    form.set('line_items[0][price_data][unit_amount]', String(Math.round(ch.base_fee * 100)));
    form.set('line_items[0][price_data][product_data][name]', 'Reveal fee (3% of AED ' + Number(q.quote_amount).toFixed(2) + ')');
    form.set('line_items[0][price_data][product_data][description]', requestRef + ' / Supplier ' + letter);
    // ONE LINE ONLY (24 Sep 2026): no card-processing line may be added to a buyer's charge (Cabinet Res. 66/2023 Art. 5(3)).
    if (ch.processing_fee !== 0) { await logRun('error', { quote_id: qid, processing_fee: ch.processing_fee }, 'card surcharge refused'); return J({ ok: false, error: 'card_surcharge_refused' }, 500); }
    // STRIPE ISSUES THE INVOICE (9 Sep 2026). The founder: "stripe automatically generates an
    // invoice as far as i know, our accountant need to retrieve that and be connected, then add it
    // to his records". He is right that Stripe does this and I was wrong to describe it as
    // unavailable — it is a setting, and it was off. A `mode=payment` Checkout Session creates no
    // Invoice object unless invoice_creation is enabled, which is why the only artefact the estate
    // could hold was a link to the hosted receipt page.
    //
    // With this on, every reveal fee produces a real Stripe Invoice with an `invoice_pdf` the
    // accountant can fetch, store in finance-docs and mirror to Dropbox, exactly like the 48
    // expense receipts it already holds.
    //
    // THAT FILE IS NEVER THE CUSTOMER'S DOCUMENT (22 Sep 2026; founder instructions 568, 569). It is
    // the accountant's source record and its NUMBER is printed on OUR invoice and receipt
    // (_shared/reveal_fee_documents.ts, served by reveal_invoice). Whether Stripe also EMAILS its own
    // invoice/receipt is not a per-session API choice: it is the account's Dashboard setting
    // Settings → Business → Customer emails → "Successful payments" (and "Refunds"), which must stay
    // OFF in live. No code here or anywhere sets receipt_email or sends an invoice; checked by
    // scripts/checks/every_pdf_we_issue_is_on_our_template.mjs (check E).
    //
    // The description is what appears on the customer's invoice, so it says what they bought in
    // their words, not ours: they paid to unlock a supplier's details on a specific request.
    form.set('invoice_creation[enabled]', 'true');
    form.set('invoice_creation[invoice_data][description]', 'Reveal fee — ' + requestRef + ' / Supplier ' + letter);
    form.set('invoice_creation[invoice_data][metadata][quote_id]', qid);
    form.set('invoice_creation[invoice_data][metadata][inquiry_id]', String(q.inquiry_id));
    form.set('invoice_creation[invoice_data][metadata][base_fee]', String(ch.base_fee));
    form.set('invoice_creation[invoice_data][metadata][processing_fee]', String(ch.processing_fee));
    form.set('invoice_creation[invoice_data][metadata][total_charged]', String(ch.total_charged));
    // The footer carries the licence, because a UAE buyer's finance team will ask who issued this.
    // No TRN and no tax: the company is not VAT-registered (founder, 14 Sep 2026).
    form.set('invoice_creation[invoice_data][footer]',
      'QuotesDone Technologies · DET licence 1633275 · TDRA NOL-26-100000665 · not registered for VAT, no VAT charged');

    form.set('metadata[quote_id]', qid);
    form.set('metadata[inquiry_id]', String(q.inquiry_id));
    form.set('metadata[customer_id]', String(cust.id));
    form.set('metadata[supplier_id]', String(q.supplier_id));
    form.set('metadata[reveal_fee]', String(fee));
    form.set('metadata[processing_fee]', String(ch.processing_fee));
    form.set('metadata[total_charged]', String(ch.total_charged));
    form.set('metadata[quote_amount]', String(q.quote_amount));
    form.set('payment_intent_data[metadata][quote_id]', qid);
    const r = await timedFetch('https://api.stripe.com/v1/checkout/sessions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + sk, 'Content-Type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    const sj = await r.json();
    if (!r.ok) { await logRun('error', { quote_id: qid, fee, http: r.status }, 'stripe session create failed: ' + String(sj?.error?.message || '').slice(0, 250)); return J({ error: 'stripe_error', detail: String(sj?.error?.message || '').slice(0, 300) }, 502); }
    await logRun('ok', { quote_id: qid, fee, processing_fee: ch.processing_fee, total_charged: ch.total_charged, session: String(sj?.id || '') }, '');
    return J({ ok: true, url: sj.url, fee, processing_fee: ch.processing_fee, total_charged: ch.total_charged, currency: 'AED' });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
})));
