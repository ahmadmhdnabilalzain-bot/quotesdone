// supplier_pay v2 - lets a supplier settle what they owe, by Stripe.
//
// WHAT A SUPPLIER OWES (corrected 19 Jul 2026). v1 called this "commission", which was wrong and
// appeared on the customer-facing Stripe receipt. Suppliers pay NO commission on jobs they win.
// A balance arises in exactly two situations:
//
//   1. REFUND CLAWBACK - a customer was refunded because the supplier did not respond. QuotesDone
//      pays that refund out of its own balance immediately so the customer is not left waiting,
//      then recovers it from the supplier: the 3% reveal fee + a AED 250 admin fee, plus monthly
//      interest once past due. Unpaid for 90 days -> ban + legal escalation.
//   2. ANNUAL SUBSCRIPTION - AED 1,000/year from 1 Aug 2027, except the first 1,000 registrants,
//      who are exempt permanently. Handled by fn_subscription_billing_run, not by this endpoint.
//
// AUTH: supplier JWT only (signed-in email must match leads.claimed_by), same as
// supplier_api/supplier_portal. Due ids in the request are re-checked against the caller's own
// supplier_id before pricing, so passing another supplier's id cannot create a session for it.
//
// MONEY SAFETY: this endpoint only CREATES a Stripe Checkout Session. It never marks anything
// paid. supplier_dues is settled solely by stripe_webhook once Stripe confirms payment on a
// signature-verified event, so a supplier cannot clear their own debt by calling the API.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function secret(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'supplier_pay', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging block a payment */ }
}
// Everything a supplier owes on one due: the refunded reveal fee + admin fee + accrued interest
// (+ any legacy fine_amount). These are separate GL lines, so they are kept separate here too.
function owed(d: any): number {
  return Math.round((Number(d.amount_due || 0) + Number(d.admin_fee || 0)
    + Number(d.interest_amount || 0) + Number(d.fine_amount || 0)) * 100) / 100;
}

Deno.serve(observe('supplier_pay', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const email = user.email.toLowerCase();

    const { data: lead } = await admin.from('leads').select('id,company_name,email').eq('claimed_by', email).maybeSingle();
    if (!lead) { await logRun('error', { authorised: 0 }, 'supplier_pay called by ' + email + ' but no lead is claimed by that address, so their balance could not be looked up. If this is a real supplier they cannot pay - check leads.claimed_by.'); return J({ error: 'No supplier profile for this account' }, 403); }

    const body = await req.json().catch(() => ({} as any));
    const action = String(body.action || 'list');

    const { data: dues, error: dErr } = await admin.from('supplier_dues')
      .select('id,amount_due,admin_fee,interest_amount,fine_amount,currency,status,due_date,paid_at,quote_id,reveal_date,legal_stage')
      .eq('supplier_id', lead.id)
      .not('status', 'in', '("paid","settled","waived","cancelled")')
      .is('paid_at', null)
      .order('due_date', { ascending: true });
    if (dErr) { await logRun('error', { supplier_id: lead.id }, 'supplier_pay could not read supplier_dues (' + String(dErr.message).slice(0,140) + '). The supplier was shown no outstanding balance, which looks identical to owing nothing - they may believe they are settled when they are not, and keep accruing interest.'); return J({ error: 'temporarily_unavailable' }, 503); }

    const outstanding = (dues || []).filter((d) => owed(d) > 0);
    const totalOwed = Math.round(outstanding.reduce((s, d) => s + owed(d), 0) * 100) / 100;

    if (action === 'list') {
      await logRun('ok', { supplier_id: lead.id, outstanding: outstanding.length, total_owed: totalOwed }, '');
      return J({ ok: true, company: lead.company_name, currency: 'AED', total_owed: totalOwed,
        dues: outstanding.map((d) => ({ id: d.id, amount: owed(d),
          refunded_fee: Number(d.amount_due || 0),
          admin_fee: Number(d.admin_fee || 0),
          interest: Number(d.interest_amount || 0) + Number(d.fine_amount || 0),
          due_date: d.due_date, status: d.status, in_legal: d.legal_stage ? true : false })) });
    }

    if (action !== 'checkout') return J({ error: 'unknown action' }, 400);
    if (!outstanding.length) return J({ ok: true, nothing_to_pay: true, total_owed: 0 });

    let selected = outstanding;
    if (Array.isArray(body.due_ids) && body.due_ids.length) {
      const want = new Set(body.due_ids.map((x: unknown) => Number(x)));
      selected = outstanding.filter((d) => want.has(Number(d.id)));
      if (selected.length !== want.size) {
        await logRun('error', { supplier_id: lead.id, requested: want.size, allowed: selected.length }, 'supplier_pay was asked to bill due ids that are not outstanding for this supplier. Only their own unpaid dues were included. This is the shape of a caller trying to pay (or probe) another supplier balance.');
      }
      if (!selected.length) return J({ error: 'no payable dues in selection' }, 400);
    }

    const amount = Math.round(selected.reduce((s, d) => s + owed(d), 0) * 100) / 100;
    if (!(amount > 0)) return J({ ok: true, nothing_to_pay: true, total_owed: 0 });

    const sk = await secret('stripe_secret_key');
    if (!sk) { await logRun('error', { supplier_id: lead.id, amount }, 'SUPPLIER PAYMENT BLOCKED - stripe_secret_key missing from app_secrets, so no supplier can settle. Balances will keep accruing interest and ageing toward the 90-day ban for a configuration reason, not because the supplier refused to pay.'); return J({ error: 'stripe_not_configured' }, 503); }

    const ids = selected.map((d) => Number(d.id));
    const fils = Math.round(amount * 100);
    const base = String(body.return_url || 'https://quotesdone.com').replace(/\/+$/, '');
    const form = new URLSearchParams();
    form.set('mode', 'payment');
    form.set('success_url', base + '/portal?dues_paid={CHECKOUT_SESSION_ID}');
    form.set('cancel_url', base + '/portal');
    form.set('client_reference_id', 'dues:' + lead.id);
    if (lead.email && /@/.test(String(lead.email))) form.set('customer_email', String(lead.email));
    form.set('line_items[0][quantity]', '1');
    form.set('line_items[0][price_data][currency]', 'aed');
    form.set('line_items[0][price_data][unit_amount]', String(fils));
    // Wording matters: this is a refund the customer already received, recovered under the supplier
    // terms - NOT commission. Suppliers keep 100% of the value of jobs they win.
    form.set('line_items[0][price_data][product_data][name]', 'QuotesDone account settlement');
    form.set('line_items[0][price_data][product_data][description]', 'Settlement of ' + ids.length + ' outstanding charge(s): refunded reveal fee, administration fee and any accrued interest');
    form.set('metadata[due_ids]', ids.join(','));
    form.set('metadata[supplier_id]', String(lead.id));
    form.set('metadata[kind]', 'supplier_dues');
    form.set('payment_intent_data[metadata][due_ids]', ids.join(','));
    form.set('payment_intent_data[metadata][kind]', 'supplier_dues');

    const r = await fetch('https://api.stripe.com/v1/checkout/sessions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + sk, 'Content-Type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    const sj = await r.json();
    if (!r.ok) { await logRun('error', { supplier_id: lead.id, amount, http: r.status }, 'Stripe session create failed for a supplier trying to settle: ' + String(sj?.error?.message || '').slice(0, 200) + '. The supplier cannot pay right now and interest keeps accruing.'); return J({ error: 'stripe_error', detail: String(sj?.error?.message || '').slice(0, 300) }, 502); }

    try { await admin.from('supplier_dues').update({ stripe_session_id: String(sj.id) }).in('id', ids); } catch (_e) { /* non-fatal */ }

    await logRun('ok', { supplier_id: lead.id, amount, dues: ids.length, session: String(sj?.id || '') }, 'Supplier ' + (lead.company_name || lead.id) + ' started checkout for ' + amount + ' AED across ' + ids.length + ' outstanding charge(s). Nothing is marked paid until stripe_webhook confirms.');
    return J({ ok: true, url: sj.url, amount, currency: 'AED', dues: ids.length });
  } catch (e) {
    const m = String((e as Error)?.message || e);
    await logRun('error', { unhandled_exception: 1 }, 'supplier_pay threw: ' + m.slice(0, 200));
    return J({ error: m }, 500);
  }
}));
