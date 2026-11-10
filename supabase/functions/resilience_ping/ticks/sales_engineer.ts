// resilience_ping ticks owned by the sales_engineer seat. Moved out of index.ts unchanged (9 Nov 2026);
// the order they run in is still set in index.ts (STEP_RUN).
import { FN, admin, sec } from '../shared.ts';

// NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321). Once a pass, sales_engineer checks
// the inquiries whose quote window closed (or whose invited suppliers all quoted), opens an offer
// where no eligible quote matches a mandatory requested value, and sends the due reminders and
// lapses through customer_support. The loop's state and timing live in Postgres
// (fn_spec_offer_candidates / fn_spec_offer_due), so calling it every pass is correct. sales_engineer
// is deployed with verify_jwt on, so the service key goes to the gateway; __secret decides the caller.
export async function specOfferTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const r = await fetch(FN + '/sales_engineer', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ __secret: secret, action: 'spec_offer_sweep', limit: 20 }), signal: AbortSignal.timeout(55000),
    });
    return { status: r.status, result: await r.json().catch(() => null) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// A REQUEST THE MATCHER COULD NOT REACH IS MATCHED AGAIN (sales_engineer, 10 Nov 2026; customer_api/lib/rematch.ts).
// It rides the specoffer step — the sales engineer's existing 15-minute beat — rather than a new step or cron: both are
// "a request is waiting on the sales engineer, ask again when its clock comes". The two run side by side and the step is
// nested, so a failing re-match is its own finding (duty:heartbeat:specoffer.rematch), never hidden by a passing offer.
export async function rematchTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const r = await fetch(FN + '/customer_api', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ __secret: secret, action: 'rematch_waiting', limit: 5 }), signal: AbortSignal.timeout(50000),
    });
    const j = await r.json().catch(() => null);
    return j && j.ok === false ? { ok: false, error: String(j.error || 'rematch failed'), result: j } : { status: r.status, result: j };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

export async function specOfferAndRematchTick(): Promise<unknown> {
  const [spec_offer, rematch] = await Promise.all([specOfferTick(), rematchTick()]);
  return { spec_offer, rematch };
}

// THE SALES ENGINEER'S DAILY SUPPLIER OUTREACH LEFT THIS TICK ON 28 OCT 2026 (sales_engineer). It ran here as the step
// `supplierOutreach` from 21 Sep, through PostgREST, where the authenticator's statement_timeout is 8 s. The held path
// fits; an open day does not (measured 28 Oct: enqueue_supplier_invites alone took 13.4 s), so on the first open day
// every beat from 09:16 Dubai was cancelled and nothing was invited. fn_sales_engineer_supplier_outreach_tick is now the
// seat duty sales_engineer.supplier_outreach on its own 60 s pg_cron job
// (the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.sql). Do not bring it back here.

// A BOUNCE REPORT IS PROVEN TO ARRIVE EVERY DAY (21 Sep 2026, customer_support). Before the supplier
// campaign the last bounce resend_webhook had recorded was 15 Aug, and nothing could tell "no bounces"
// from "reports stopped arriving" -- the campaign's 5% brake reads zero either way. Once a day, while real
// mail is going out, this queues one mail to Resend's bounce test sink (the outbox drain later in the same
// tick sends it) and judges the previous one: silence 30 minutes after sending is the IT finding
// delivery_feedback:bounce_reports_silent (a_bounce_report_is_proven_to_arrive_every_day_or_it_is_a_finding.sql).
export async function deliveryCanaryTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_delivery_feedback_canary_tick');
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
