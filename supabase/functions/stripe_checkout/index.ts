import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
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

Deno.serve(observe('stripe_checkout', async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const { data: cust } = await admin.from('customers').select('id').eq('email', user.email.toLowerCase()).maybeSingle();
    if (!cust) { await logRun('error', {}, 'no_customer_profile for authenticated user - cannot start checkout'); return J({ error: 'No customer profile' }, 403); }
    const body = await req.json().catch(() => ({}));
    const qid = String(body.quote_id || '');
    const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount').eq('id', qid).maybeSingle();
    if (!q) { await logRun('error', { quote_id: qid }, 'quote not found - customer cannot pay to reveal'); return J({ error: 'Quote not found' }, 404); }
    const { data: inq } = await admin.from('inquiries').select('id,customer_id').eq('id', q.inquiry_id).maybeSingle();
    if (!inq || inq.customer_id !== cust.id) { await logRun('error', { quote_id: qid }, 'ownership violation: customer attempted checkout on another customer inquiry'); return J({ error: 'Not your inquiry' }, 403); }
    const { data: existing } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle();
    if (existing) { await logRun('ok', { quote_id: qid, already_revealed: true }, ''); return J({ already_revealed: true }); }
    const sk = await secret('stripe_secret_key');
    // note: this returns HTTP 200 so the client does not treat it as a hard failure,
    // which is exactly why it needs to be loud in agent_runs
    if (!sk) { await logRun('error', { quote_id: qid }, 'CHECKOUT BLOCKED - stripe_secret_key missing from app_secrets; all reveals are failing'); return J({ error: 'stripe_not_configured' }, 200); }
    const { data: cfg } = await admin.from('pricing_config').select('*').eq('id', 1).maybeSingle();
    const fee = revealFee(Number(q.quote_amount), cfg || {});
    if (!(fee > 0)) { await logRun('error', { quote_id: qid, quote_amount: q.quote_amount, fee, has_pricing_config: !!cfg }, 'invalid_fee computed - checkout blocked (check pricing_config rates/caps and quote_amount)'); return J({ error: 'invalid_fee' }, 400); }
    const fils = Math.round(fee * 100);
    // 27 Jul 2026 — two defects fixed here.
    // (1) OPEN REDIRECT. return_url was taken verbatim from the request body, so a crafted call
    //     sent the paying customer to any domain with the Checkout Session id in the query string.
    //     The host is now allowlisted and anything else falls back to the canonical site.
    // (2) DEAD RETURN PAGE. success_url was `<return_url>/app?paid=…`. The portal passes
    //     `location.origin + '/me'`, so customers landed on https://quotesdone.com/me/app — a route
    //     that does not exist — and the query parameter was named `paid`, while CustomerPortal.tsx:417
    //     reads `session_id`. The browser-side confirmation path (stripe_confirm) was therefore
    //     unreachable and settlement depended entirely on the webhook.
    const safeBase = (raw: unknown): string => {
      const FALLBACK = 'https://quotesdone.com';
      try {
        const u = new URL(String(raw || FALLBACK));
        if (u.protocol !== 'https:') return FALLBACK;
        const h = u.hostname.toLowerCase();
        const ok = h === 'quotesdone.com' || h === 'www.quotesdone.com' || h.endsWith('.vercel.app');
        return ok ? (u.origin + u.pathname).replace(/\/+$/, '') : FALLBACK;
      } catch { return FALLBACK; }
    };
    const base = safeBase(body.return_url) || 'https://quotesdone.com';
    const portal = /\/me$/.test(base) ? base : (base + '/me');
    const success = portal + '?session_id={CHECKOUT_SESSION_ID}&reveal=' + encodeURIComponent(qid);
    const cancel = portal;
    const form = new URLSearchParams();
    form.set('mode', 'payment');
    form.set('success_url', success);
    form.set('cancel_url', cancel);
    form.set('client_reference_id', qid);
    form.set('customer_email', user.email);
    form.set('line_items[0][quantity]', '1');
    form.set('line_items[0][price_data][currency]', 'aed');
    form.set('line_items[0][price_data][unit_amount]', String(fils));
    form.set('line_items[0][price_data][product_data][name]', 'QuotesDone reveal fee');
    form.set('line_items[0][price_data][product_data][description]', 'One-time fee to reveal the chosen supplier contact details');
    form.set('metadata[quote_id]', qid);
    form.set('metadata[inquiry_id]', String(q.inquiry_id));
    form.set('metadata[customer_id]', String(cust.id));
    form.set('metadata[supplier_id]', String(q.supplier_id));
    form.set('metadata[reveal_fee]', String(fee));
    form.set('metadata[quote_amount]', String(q.quote_amount));
    form.set('payment_intent_data[metadata][quote_id]', qid);
    const r = await fetch('https://api.stripe.com/v1/checkout/sessions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + sk, 'Content-Type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    const sj = await r.json();
    if (!r.ok) { await logRun('error', { quote_id: qid, fee, http: r.status }, 'stripe session create failed: ' + String(sj?.error?.message || '').slice(0, 250)); return J({ error: 'stripe_error', detail: String(sj?.error?.message || '').slice(0, 300) }, 502); }
    await logRun('ok', { quote_id: qid, fee, session: String(sj?.id || '') }, '');
    return J({ ok: true, url: sj.url, fee, currency: 'AED' });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}));
