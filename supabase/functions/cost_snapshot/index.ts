import { createClient } from 'jsr:@supabase/supabase-js@2';
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
  if (!secretOk(expected) || body.__secret !== expected) {
    await logRun(started, 'error', { authorised: 0, bad_or_missing_secret: 1 }, 'cost_snapshot rejected an unauthenticated caller (403). Before 19 Jul 2026 a request with no __secret at all was ACCEPTED and returned full revenue and spend figures, so a rejection here may be a scanner finding the old hole - or a legitimate internal caller that was never updated to send the secret.');
    return J({ error: 'forbidden' }, 403);
  }

  const d7 = new Date(Date.now() - 7 * 864e5).toISOString();
  const d30 = new Date(Date.now() - 30 * 864e5).toISOString();
  // --- real OpenRouter spend ---
  let or: any = { ok: false };
  try { const key = await sec('openrouter_api_key'); if (key) { const r = await fetch('https://openrouter.ai/api/v1/credits', { headers: { 'Authorization': 'Bearer ' + key } }); const j = await r.json(); const dt = j?.data || {}; or = { ok: true, total_credits: dt.total_credits, total_usage: dt.total_usage, remaining: (Number(dt.total_credits || 0) - Number(dt.total_usage || 0)) }; } } catch (e) { or = { ok: false, error: String((e as Error)?.message || e).slice(0, 80) }; }
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
    openrouter_usd: or.ok ? { spent_total: or.total_usage, credits_total: or.total_credits, remaining: or.remaining } : or,
    revenue: { last_7d: revenue_7d, last_30d: revenue_30d, all_time: revenue_all },
    activity_7d: { inquiries: inquiries_7d, reveals: reveals_7d, new_suppliers: new_suppliers_7d, emails_sent: emails_7d, ai_runs: ai_runs_7d },
    note: 'OpenRouter is the only provider with a live spend API wired. Apify / Twilio / Resend / Supabase balances require their own keys + endpoints to add.'
  };

  let emailQueued = 0; let emailErr = '';
  if (body.email !== false) {
    try {
      const owner = (await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
      const orLine = or.ok ? ('OpenRouter (AI): $' + Number(or.total_usage || 0).toFixed(2) + ' spent total, $' + Number(or.remaining || 0).toFixed(2) + ' credit remaining.') : 'OpenRouter: spend API unavailable.';
      const bodyTxt = 'QuotesDone weekly burn + revenue snapshot\n\n'
        + 'REVENUE (paid reveal fees)\n  Last 7 days: ' + fmt(revenue_7d) + '\n  Last 30 days: ' + fmt(revenue_30d) + '\n  All time: ' + fmt(revenue_all) + '\n\n'
        + 'ACTIVITY (last 7 days)\n  Inquiries: ' + inquiries_7d + '\n  Reveals (paid): ' + reveals_7d + '\n  New onboarded suppliers: ' + new_suppliers_7d + '\n  Emails sent: ' + emails_7d + '\n  AI/agent runs: ' + ai_runs_7d + '\n\n'
        + 'COSTS\n  ' + orLine + '\n  (Apify, Twilio, Resend, Supabase: check each dashboard — no live API wired.)\n';
      if (owner) { const { error: nErr } = await admin.from('notifications').insert([{ type: 'cost_snapshot', to_email: owner, to_role: 'admin', channel: 'email', subject: 'QuotesDone weekly burn + revenue snapshot', body: bodyTxt }]); if (nErr) emailErr = String(nErr.message).slice(0, 140); else emailQueued = 1; }
    } catch (e) { emailErr = String(e).slice(0, 140); }
  }

  const counts = { ...snapshot, authorised: 1, email_queued: emailQueued, openrouter_ok: or.ok ? 1 : 0 };
  if (emailErr) await logRun(started, 'error', counts, 'cost_snapshot computed the weekly burn/revenue figures but FAILED to queue the owner email (' + emailErr + '). The numbers exist in agent_runs but nobody was told - absence of the weekly email this week means delivery broke, not that there was nothing to report.');
  else if (!or.ok) await logRun(started, 'error', counts, 'cost_snapshot ran and emailed the weekly summary, but the OpenRouter spend API was unreachable (' + String(or.error || 'no key configured') + '), so AI cost shows as unavailable rather than zero. Do not read the missing figure as "no AI spend this week".');
  else await logRun(started, 'ok', counts, 'cost_snapshot ran cleanly: revenue 7d/30d/all-time computed, OpenRouter spend fetched, owner email queued.');

  return J({ ok: true, snapshot });
});
