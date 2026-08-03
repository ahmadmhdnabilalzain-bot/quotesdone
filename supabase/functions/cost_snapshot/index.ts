import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function cnt(tbl: string, col: string, sinceIso?: string, extra?: (q: any) => any) { let q = admin.from(tbl).select(col, { count: 'exact', head: true }); if (sinceIso) q = q.gte('created_at', sinceIso); if (extra) q = extra(q); const { count } = await q; return count || 0; }

async function logRun(startedIso: string, status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'cost_snapshot', status, counts,
      note: String(note || '').slice(0, 500), started_at: startedIso, finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}

Deno.serve(async (req) => {
  const started = new Date().toISOString();
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* */ }

  // SECURITY FIX 19 Jul 2026 -----------------------------------------------------------------
  // The gate used to read:
  //     if (body.__secret !== undefined && body.__secret !== await sec('inbound_secret')) -> 403
  // The reject branch only fired when a secret was SUPPLIED AND WRONG. An empty POST ({}) left
  // body.__secret undefined, so the condition short-circuited and the request sailed through.
  // Anyone who knew the URL could therefore read all-time revenue, reveal counts, supplier
  // growth and live OpenRouter spend, and could also queue an email to the owner on every call
  // (the notifications insert below), i.e. use this endpoint as an unauthenticated mailer.
  // Now fails CLOSED: a correct secret is required. Both cron callers (cost_snapshot_weekly)
  // already pass it, so this changes nothing for legitimate traffic.
  const expected = await sec('inbound_secret');
  if (!expected) {
    await logRun(started, 'error', { authorised: 0, secret_lookup_ok: 0 }, 'cost_snapshot refused every caller because inbound_secret could not be read from app_secrets. The weekly burn/revenue snapshot did NOT run and no owner email was queued - this is an auth-infrastructure failure, not a quiet week with no spend to report.');
    return J({ error: 'secret unavailable' }, 503);
  }
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'cost_snapshot');
  if (!__auth.ok) {
    await logRun(started, 'error', { authorised: 0, bad_or_missing_secret: 1 }, 'cost_snapshot rejected an unauthenticated caller (403). Before 19 Jul 2026 a request with no __secret at all was ACCEPTED and returned full revenue and spend figures, so a rejection here may be a scanner finding the old hole - or a legitimate internal caller that was never updated to send the secret.');
    return J({ error: 'forbidden' }, 403);
  }

  const d7 = new Date(Date.now() - 7 * 864e5).toISOString();
  const d30 = new Date(Date.now() - 30 * 864e5).toISOString();
  // --- real OpenRouter spend ---
  let or: any = { ok: false };
  try { const key = await sec('openrouter_api_key'); if (key) { const r = await fetch('https://openrouter.ai/api/v1/credits', { headers: { 'Authorization': 'Bearer ' + key } }); const j = await r.json(); const dt = j?.data || {}; or = { ok: true, total_credits: dt.total_credits, total_usage: dt.total_usage, remaining: (Number(dt.total_credits || 0) - Number(dt.total_usage || 0)) }; } } catch (e) { or = { ok: false, error: String((e as Error)?.message || e).slice(0, 80) }; }

  // --- BURN RATE + RUNWAY, and an alarm that actually fires -------------------------------
  // WHY THIS EXISTS. On 29 Jul 2026 the balance was found at $1.48 with nobody warned. Nothing
  // was broken: the figure was being measured correctly and reported accurately - into a WEEKLY
  // email. Two things made that useless. A balance that empties in about ten days cannot be
  // guarded by a seven-day check, and a number sitting in a summary is not an alarm; no threshold
  // was ever compared, so no message could ever say "act now". Every agent, the Secretary,
  // document reading, translation and matching all stop at zero, so this is the single point of
  // failure for the whole company. Runway is derived from the previous snapshot rather than
  // guessed, so the warning can say how many days are left, not just that the number looks small.
  let burnPerDay = 0; let daysLeft: number | null = null;
  try {
    const { data: prev } = await admin.from('agent_runs')
      .select('started_at, counts').eq('agent', 'cost_snapshot').eq('status', 'ok')
      .order('started_at', { ascending: false }).limit(6);
    const prevRow = (prev || []).find((r: any) => Number(r?.counts?.openrouter_usd?.spent_total) > 0);
    if (or.ok && prevRow) {
      const prevSpent = Number(prevRow.counts.openrouter_usd.spent_total);
      const days = Math.max((Date.now() - new Date(prevRow.started_at).getTime()) / 864e5, 0.01);
      const delta = Number(or.total_usage || 0) - prevSpent;
      if (delta > 0 && days >= 0.2) {
        burnPerDay = delta / days;
        daysLeft = burnPerDay > 0 ? Number(or.remaining || 0) / burnPerDay : null;
      }
    }
  } catch (_e) { /* runway is advisory - never fail the snapshot for it */ }

  const minUsd = Number((await sec('openrouter_min_usd')) || 20);
  let alerted = 0; let alertErr = '';
  if (or.ok && Number(or.remaining) <= minUsd) {
    try {
      const runway = daysLeft != null
        ? (' At the current burn of about $' + burnPerDay.toFixed(2) + ' a day that is roughly ' + daysLeft.toFixed(1) + ' days left.')
        : '';
      const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/alert_founder', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          __secret: expected,
          // level 'critical' also sends WhatsApp via alert_founder, and it de-dupes for 6h,
          // so a daily check cannot turn into a daily nag.
          level: 'critical',
          dedupe_key: 'openrouter_credit_low',
          event: 'AI credit low: $' + Number(or.remaining).toFixed(2) + ' left',
          detail: 'Every AI call in the company - all agents, the Secretary, document reading, translation and supplier matching - runs on one OpenRouter balance. They all stop when it reaches zero.'
            + runway + ' Top up at https://openrouter.ai/credits. This warning fires below $' + minUsd
            + '; change that with app_secrets.openrouter_min_usd.',
        }),
      });
      const jr = await r.json().catch(() => ({}));
      alerted = jr?.notified ? 1 : 0;
      if (!jr?.ok) alertErr = String(jr?.error || 'alert_founder did not confirm').slice(0, 120);
    } catch (e) { alertErr = String((e as Error)?.message || e).slice(0, 120); }
  }

  // --- revenue (paid reveal fees) ---
  async function rev(sinceIso?: string) { let q = admin.from('transactions').select('reveal_fee').eq('fee_status', 'paid'); if (sinceIso) q = q.gte('revealed_at', sinceIso); const { data } = await q; return (data || []).reduce((s: number, t: any) => s + Number(t.reveal_fee || 0), 0); }
  const revenue_7d = await rev(d7); const revenue_30d = await rev(d30); const revenue_all = await rev();
  // --- activity ---
  const inquiries_7d = await cnt('inquiries', 'id', d7);
  const reveals_7d = await admin.from('transactions').select('id', { count: 'exact', head: true }).gte('revealed_at', d7).then((r: any) => r.count || 0);
  const emails_7d = await cnt('notifications', 'id', d7, (q: any) => q.eq('channel', 'email').eq('status', 'sent'));
  const ai_runs_7d = await admin.from('agent_runs').select('id', { count: 'exact', head: true }).gte('started_at', d7).then((r: any) => r.count || 0);
  const new_suppliers_7d = await admin.from('leads').select('id', { count: 'exact', head: true }).eq('claimed', true).gte('created_at', d7).then((r: any) => r.count || 0);
  const fmt = (n: number) => 'AED ' + Number(n || 0).toLocaleString('en-AE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const snapshot = {
    generated_at: new Date().toISOString(),
    openrouter_usd: or.ok
      ? { spent_total: or.total_usage, credits_total: or.total_credits, remaining: or.remaining,
          burn_per_day: Number(burnPerDay.toFixed(4)), days_left: daysLeft == null ? null : Number(daysLeft.toFixed(1)),
          alert_threshold: minUsd, low_balance_alert_sent: alerted === 1 }
      : or,
    revenue: { last_7d: revenue_7d, last_30d: revenue_30d, all_time: revenue_all },
    activity_7d: { inquiries: inquiries_7d, reveals: reveals_7d, new_suppliers: new_suppliers_7d, emails_sent: emails_7d, ai_runs: ai_runs_7d },
    note: 'OpenRouter is the only provider with a live spend API wired. Apify / Twilio / Resend / Supabase balances require their own keys + endpoints to add.'
  };

  // email:false is the daily balance-watch call - it checks the balance and alerts if low
  // WITHOUT sending the full summary, so making the watch daily does not turn a weekly report
  // into daily noise. The Monday job still sends the summary.
  let emailQueued = 0; let emailErr = '';
  if (body.email !== false) {
    try {
      const owner = (await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
      const runwayLine = or.ok && daysLeft != null ? (' Burn is about $' + burnPerDay.toFixed(2) + '/day, roughly ' + daysLeft.toFixed(1) + ' days of credit left.') : '';
      const orLine = or.ok ? ('OpenRouter (AI): $' + Number(or.total_usage || 0).toFixed(2) + ' spent total, $' + Number(or.remaining || 0).toFixed(2) + ' credit remaining.' + runwayLine) : 'OpenRouter: spend API unavailable.';
      const bodyTxt = 'QuotesDone weekly burn + revenue snapshot\n\n'
        + 'REVENUE (paid reveal fees)\n  Last 7 days: ' + fmt(revenue_7d) + '\n  Last 30 days: ' + fmt(revenue_30d) + '\n  All time: ' + fmt(revenue_all) + '\n\n'
        + 'ACTIVITY (last 7 days)\n  Inquiries: ' + inquiries_7d + '\n  Reveals (paid): ' + reveals_7d + '\n  New onboarded suppliers: ' + new_suppliers_7d + '\n  Emails sent: ' + emails_7d + '\n  AI/agent runs: ' + ai_runs_7d + '\n\n'
        + 'COSTS\n  ' + orLine + '\n  (Apify, Twilio, Resend, Supabase: check each dashboard - no live API wired.)\n';
      if (owner) { const { error: nErr } = await admin.from('notifications').insert([{ type: 'cost_snapshot', to_email: owner, to_role: 'admin', channel: 'email', subject: 'QuotesDone weekly burn + revenue snapshot', body: bodyTxt }]); if (nErr) emailErr = String(nErr.message).slice(0, 140); else emailQueued = 1; }
    } catch (e) { emailErr = String(e).slice(0, 140); }
  }

  const counts = { ...snapshot, authorised: 1, email_queued: emailQueued, openrouter_ok: or.ok ? 1 : 0, low_balance_alert: alerted };
  if (alertErr) await logRun(started, 'error', counts, 'cost_snapshot found the AI credit at or below the $' + minUsd + ' threshold but FAILED to raise the founder alert (' + alertErr + '). The balance figure is in agent_runs but nobody was told, which is exactly the failure this alarm exists to prevent.');
  else if (emailErr) await logRun(started, 'error', counts, 'cost_snapshot computed the weekly burn/revenue figures but FAILED to queue the owner email (' + emailErr + '). The numbers exist in agent_runs but nobody was told - absence of the weekly email this week means delivery broke, not that there was nothing to report.');
  else if (!or.ok) await logRun(started, 'error', counts, 'cost_snapshot ran and emailed the weekly summary, but the OpenRouter spend API was unreachable (' + String(or.error || 'no key configured') + '), so AI cost shows as unavailable rather than zero. Do not read the missing figure as "no AI spend this week".');
  else await logRun(started, 'ok', counts, 'cost_snapshot ran cleanly: revenue computed, OpenRouter spend fetched' + (daysLeft != null ? (', runway ' + daysLeft.toFixed(1) + ' days') : '') + (alerted ? ', LOW BALANCE ALERT SENT' : '') + (emailQueued ? ', owner email queued' : ', summary email skipped (balance-watch run)') + '.');

  return J({ ok: true, snapshot });
});
