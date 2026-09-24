// supplier_pay v2 - lets a supplier settle what they owe, by Stripe.
//
// WHAT A SUPPLIER OWES (corrected 19 Jul 2026). v1 called this "commission", which was wrong and
// appeared on the customer-facing Stripe receipt. Suppliers pay NO commission on jobs they win.
// A balance arises in exactly two situations:
//
//   1. REFUND CLAWBACK - a customer was refunded because the supplier did not respond. QuotesDone
//      pays that refund out of its own balance immediately so the customer is not left waiting,
//      then recovers it from the supplier: the exact amount refunded (3% reveal fee + card processing fee) + the clause 33(b) administrative fee of the version the supplier signed, plus monthly
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
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { siteReturnBase } from '../_shared/site_origins.ts';
import { SANCTIONED_REFUSAL, sanctionedEmail } from '../_shared/sanctioned.ts';
// WHO IS CALLING, ANSWERED WITHOUT LYING (audit 22 Sep 2026, finding SP-N-08). This function called
// admin.auth.getUser directly, so the ~35 s auth outages measured on 18 and 21 Sep — documented in
// _shared/signed_in_user.ts — came back here as 401 "Not signed in": a signed-in supplier trying to clear
// a debt that is accruing interest was told their session was invalid. signedInUser bounds the call,
// refuses an impossible token locally, and answers 503 auth_unavailable when the auth server is the thing
// that failed, which observe() pages and a client retries.
import { refusalBody, signedInUser } from '../_shared/signed_in_user.ts';
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
    // main's shared identity router decides who this is; #858 keeps the stable code on the 401 so the
    // portal can translate it (SP-I-03) instead of printing "Not signed in" in English on /ar.
    const who = await signedInUser(admin, req.headers.get('Authorization'));
    if (!who.ok) return J(who.status === 401 ? { error: 'Not signed in', code: 'not_signed_in' } : refusalBody(who), who.status);
    const email = who.email;
    // A SANCTIONED PARTY CANNOT ACT (founder instruction 516, 18 Sep 2026; security review the
    // same day found this function authenticated a supplier by leads.claimed_by and asked
    // nothing about the ban). Above everything this function does, so it covers what is written
    // here next year too.
    if (await sanctionedEmail(admin, email)) return J(SANCTIONED_REFUSAL, 403);  // an ORDINARY dues ban still reaches this screen, which is the whole point of asking
    // public.sanctions_ban rather than leads.banned; a sanctions ban is not a debt to be cleared.

    const { data: lead } = await admin.from('leads').select('id,company_name,email').eq('claimed_by', email).maybeSingle();
    if (!lead) { await logRun('error', { authorised: 0 }, 'supplier_pay called by ' + email + ' but no lead is claimed by that address, so their balance could not be looked up. If this is a real supplier they cannot pay - check leads.claimed_by.'); return J({ error: 'No supplier profile for this account', code: 'no_company' }, 403); }

    const body = await req.json().catch(() => ({} as any));
    const action = String(body.action || 'list');

    // ── THE YEARLY REGISTRATION FEE (moved here from supplier_api.pay_registration, 14 Sep 2026) ──
    // Founder: "anything related to payment is under the accountant agent." This was the one Stripe
    // checkout living in a sales-engineer portal function. Same rules as before: read the single source
    // of truth (fn_supplier_registration_state), create a session only when a fee is actually due, and
    // never mark anything paid -- stripe_webhook alone writes subscription_paid_until.
    if (action === 'registration') {
      const { data: regSt, error: regErr } = await admin.rpc('fn_supplier_registration_state', { p_lead_id: lead.id });
      // deno-lint-ignore no-explicit-any
      const reg = regSt as any;
      if (regErr || !reg?.ok) { console.error('supplier_pay: registration state unavailable —', String(regErr?.message || 'lead_not_found')); return J({ error: 'registration_state_unavailable', code: 'registration_state_unavailable' }, 503); }
      if (reg.status === 'paid') return J({ ok: true, already_paid: true, paid_until: reg.paid_until, code: 'reg_paid', params: { until: reg.paid_until || null } });
      if (reg.status === 'exempt') return J({ ok: true, exempt: true, founding_rank: reg.founding_rank, code: 'reg_exempt', params: { rank: reg.founding_rank }, message: 'Your registration is permanently free - you are supplier number ' + reg.founding_rank + ', inside the founding cohort. There is no fee to pay, now or in future.' });
      if (reg.status === 'not_due') return J({ ok: true, nothing_to_pay: true, charging_starts: reg.charging_starts, code: reg.charging_starts ? null : 'reg_not_due', message: 'There is nothing to pay yet. ' + (reg.charging_starts ? 'The annual Subscription Fee starts on ' + reg.charging_starts + '.' : (reg.reason ? reg.reason.charAt(0).toUpperCase() + reg.reason.slice(1) + '.' : 'The annual Subscription Fee applies from the registration after the free count; there is no calendar start date.')) });
      const fee = Number(reg.fee_due || 0);
      if (!(fee > 0)) return J({ ok: true, nothing_to_pay: true, code: 'reg_not_due' });
      const { data: pausedReg } = await admin.rpc('fn_refunds_paused');
      if (pausedReg === true) return J({ error: 'charges_paused', code: 'payment_unavailable' }, 503);
      const skReg = await secret('stripe_secret_key');
      if (!skReg) return J({ error: 'stripe_not_configured', code: 'payment_unavailable' }, 503);
      const baseReg = siteReturnBase(req, body.return_url);
      const f = new URLSearchParams();
      f.set('mode', 'payment');
      f.set('success_url', baseReg + '/portal?registration_paid={CHECKOUT_SESSION_ID}');
      f.set('cancel_url', baseReg + '/portal');
      f.set('client_reference_id', 'registration:' + lead.id);
      if (lead.email && /@/.test(String(lead.email))) f.set('customer_email', String(lead.email));
      f.set('line_items[0][quantity]', '1');
      f.set('line_items[0][price_data][currency]', 'aed');
      f.set('line_items[0][price_data][unit_amount]', String(Math.round(fee * 100)));
      f.set('line_items[0][price_data][product_data][name]', 'QuotesDone supplier registration');
      f.set('line_items[0][price_data][product_data][description]', 'One year of supplier registration on QuotesDone');
      // NO STRIPE INVOICE (22 Sep 2026; founder instructions 568, 569: no third-party PDF is sent as
      // ours). The supplier's invoice and receipt are OURS, on the template:
      // _shared/supplier_payment_documents.ts via supplier_api receipt_pdf. Prevented by
      // scripts/checks/every_pdf_we_issue_is_on_our_template.mjs (check E).
      f.set('metadata[kind]', 'supplier_registration');
      f.set('metadata[supplier_id]', String(lead.id));
      f.set('payment_intent_data[metadata][kind]', 'supplier_registration');
      f.set('payment_intent_data[metadata][supplier_id]', String(lead.id));
      const rr = await timedFetch('https://api.stripe.com/v1/checkout/sessions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + skReg, 'Content-Type': 'application/x-www-form-urlencoded' }, body: f.toString() });
      const rj = await rr.json();
      if (!rr.ok) { await logRun('error', { supplier_id: lead.id, fee, http: rr.status }, 'registration session create failed: ' + String(rj?.error?.message || '').slice(0, 200)); return J({ error: 'stripe_error', code: 'payment_failed' }, 502); }
      await logRun('ok', { supplier_id: lead.id, registration_fee: fee, session: String(rj?.id || '') }, '');
      return J({ ok: true, url: rj.url, amount: fee, currency: 'AED' });
    }

    // Interest on an outstanding charge is recomputed from the refund record before it is shown or
    // billed (fn_supplier_dues_accrue_interest is absolute, so this changes nothing twice).
    // ONLY WHEN THIS SUPPLIER OWES SOMETHING (21 Sep 2026, campaign registration walk). The accrual is
    // absolute and covers EVERY supplier, and it ran on every Billing view: a brand-new supplier with
    // nothing owed waited 5.2 s for `list` (measured on production, EN and AR, 390 px), and a campaign
    // day of new suppliers opening Billing would have run the whole-book recompute once per view.
    // Prevented by scripts/checks/an_invited_supplier_can_finish_registering.test.mjs.
    const { count: openDues } = await admin.from('supplier_dues').select('id', { count: 'exact', head: true })
      .eq('supplier_id', lead.id).not('status', 'in', '("paid","settled","waived","cancelled")').is('paid_at', null);
    if (openDues !== 0) { try { await admin.rpc('fn_supplier_dues_accrue_interest', { p_as_of: null }); } catch (_e) { /* the stored figure stands */ } }

    const { data: dues, error: dErr } = await admin.from('supplier_dues')
      .select('id,amount_due,admin_fee,interest_amount,fine_amount,currency,status,due_date,paid_at,quote_id,reveal_date,legal_stage')
      .eq('supplier_id', lead.id)
      .not('status', 'in', '("paid","settled","waived","cancelled")')
      .is('paid_at', null)
      .order('due_date', { ascending: true });
    if (dErr) { await logRun('error', { supplier_id: lead.id }, 'supplier_pay could not read supplier_dues (' + String(dErr.message).slice(0,140) + '). The supplier was shown no outstanding balance, which looks identical to owing nothing - they may believe they are settled when they are not, and keep accruing interest.'); return J({ error: 'temporarily_unavailable', code: 'temporarily_unavailable' }, 503); }

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
      if (!selected.length) return J({ error: 'no payable dues in selection', code: 'no_payable_dues' }, 400);
    }

    const amount = Math.round(selected.reduce((s, d) => s + owed(d), 0) * 100) / 100;
    if (!(amount > 0)) return J({ ok: true, nothing_to_pay: true, total_owed: 0 });

    // THE CEO'S CIRCUIT BREAKER (14 Sep 2026): no supplier charge moves while a mismatch is open.
    const { data: paused } = await admin.rpc('fn_refunds_paused');
    if (paused === true) { await logRun('ok', { supplier_id: lead.id, amount, held: true }, 'checkout held: refunds and supplier charges are paused while the CEO resolves a mismatch'); return J({ error: 'charges_paused', code: 'payment_unavailable' }, 503); }
    const sk = await secret('stripe_secret_key');
    if (!sk) { await logRun('error', { supplier_id: lead.id, amount }, 'SUPPLIER PAYMENT BLOCKED - stripe_secret_key missing from app_secrets, so no supplier can settle. Balances will keep accruing interest and ageing toward the 90-day ban for a configuration reason, not because the supplier refused to pay.'); return J({ error: 'stripe_not_configured', code: 'payment_unavailable' }, 503); }

    const ids = selected.map((d) => Number(d.id));
    const fils = Math.round(amount * 100);
    // Allowlisted (was taken verbatim): back to the site origin the supplier paid from, .ae included.
    const base = siteReturnBase(req, body.return_url);
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
    // THE INVOICE IS OURS (22 Sep 2026, replacing "Stripe issues the invoice" of 9 Sep). A supplier
    // settling charges needs a proper invoice for their own books — and the founder ruled (instructions
    // 568, 569) that it is QuotesDone's, on the QuotesDone template, never Stripe's PDF. So Stripe
    // creates no invoice here; the invoice and receipt come from _shared/supplier_payment_documents.ts
    // (supplier_api receipt_pdf, doc 'invoice' | 'receipt'), grouped by this payment's reference.
    // Prevented by scripts/checks/every_pdf_we_issue_is_on_our_template.mjs (check E).

    form.set('metadata[due_ids]', ids.join(','));
    form.set('metadata[supplier_id]', String(lead.id));
    form.set('metadata[kind]', 'supplier_dues');
    form.set('payment_intent_data[metadata][due_ids]', ids.join(','));
    form.set('payment_intent_data[metadata][kind]', 'supplier_dues');

    const r = await timedFetch('https://api.stripe.com/v1/checkout/sessions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + sk, 'Content-Type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    const sj = await r.json();
    if (!r.ok) { await logRun('error', { supplier_id: lead.id, amount, http: r.status }, 'Stripe session create failed for a supplier trying to settle: ' + String(sj?.error?.message || '').slice(0, 200) + '. The supplier cannot pay right now and interest keeps accruing.'); return J({ error: 'stripe_error', code: 'payment_failed' }, 502); }

    try { await admin.from('supplier_dues').update({ stripe_session_id: String(sj.id) }).in('id', ids); } catch (_e) { /* non-fatal */ }

    await logRun('ok', { supplier_id: lead.id, amount, dues: ids.length, session: String(sj?.id || '') }, 'Supplier ' + (lead.company_name || lead.id) + ' started checkout for ' + amount + ' AED across ' + ids.length + ' outstanding charge(s). Nothing is marked paid until stripe_webhook confirms.');
    return J({ ok: true, url: sj.url, amount, currency: 'AED', dues: ids.length });
  } catch (e) {
    const m = String((e as Error)?.message || e);
    await logRun('error', { unhandled_exception: 1 }, 'supplier_pay threw: ' + m.slice(0, 200));
    return J({ error: m }, 500);
  }
}));
