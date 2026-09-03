// meta_ads v1 — platform connector for Meta (Facebook/Instagram) ad campaigns.
// SAFETY: only ever creates PAUSED objects. It NEVER activates a campaign or spends budget.
// Activation stays a human action in Meta Ads Manager. Auth: __secret == inbound_secret.
// Secrets (founder adds later): meta_ad_account_id (digits only), meta_access_token (ads_management),
//   optional meta_api_version.
// Actions:
//   test          -> read the ad account (verifies token + account)
//   quick_campaign-> create a PAUSED campaign + PAUSED ad set (traffic to the site, geo UAE)
//   list          -> list recent campaigns
//   insights      -> account-level performance (last N days)
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  const body = await req.json().catch(() => ({} as any));
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'meta_ads');
  if (!__auth.ok) return J({ error: 'forbidden' }, 403);
  const [token, acctRaw, ver] = await Promise.all([sec('meta_access_token'), sec('meta_ad_account_id'), sec('meta_api_version')]);

  // 3 SEP 2026 — execute_decisions: the AD SPEND AUTOPILOT's hands (scripts/sql/ad_spend_autopilot.sql).
  // fn_ads_manage() writes every activate / pause / set_daily_budget as an ad_decision row, behind a
  // BEFORE INSERT ceiling guard; this action carries out the unexecuted rows, oldest first. With
  // meta_access_token + meta_ad_account_id it posts to Graph (status on the campaign, daily_budget on
  // the ad set, in fils) and records the response; WITHOUT them it executes in SANDBOX mode — the
  // decision is stamped executed with {simulated:true} and the manager's picture of Meta is updated
  // exactly as a live call would update it — so the whole loop is provable before the token exists.
  // The token is the only switch. A refused live call leaves the decision unexecuted (the manager
  // skips that campaign until it clears) and is logged as an error for the failed-run reader.
  if (String(body.action || '') === 'execute_decisions') {
    const started0 = new Date().toISOString();
    const live = !!(token && acctRaw);
    const acct0 = live ? 'act_' + String(acctRaw).replace(/^act_/, '') : '';
    const G0 = 'https://graph.facebook.com/' + (ver || 'v21.0');
    const { data: pending, error: qErr } = await admin.from('ad_decision').select('id,campaign_id,action,amount_aed,rule_key').is('executed_at', null).order('id', { ascending: true }).limit(Math.max(1, Math.min(200, Number(body.limit) || 50)));
    if (qErr) { await admin.from('agent_runs').insert({ agent: 'meta_ads', started_at: started0, finished_at: new Date().toISOString(), status: 'error', note: ('execute_decisions could not read ad_decision: ' + qErr.message).slice(0, 300) }); return J({ ok: false, error: qErr.message }, 200); }
    const rows = (pending || []) as Array<{ id: number; campaign_id: string; action: string; amount_aed: number | null; rule_key: string }>;
    let executed = 0, failed = 0; const failures: string[] = [];
    for (const d of rows) {
      let resp: Record<string, unknown> = { simulated: true, account: acct0 || null }; let ok = true;
      if (live) {
        const { data: st } = await admin.from('ad_campaign_state').select('adset_id').eq('campaign_id', d.campaign_id).maybeSingle();
        const path = d.action === 'set_daily_budget' ? '/' + String(st?.adset_id || d.campaign_id) : '/' + d.campaign_id;
        const params: Record<string, string> = d.action === 'set_daily_budget'
          ? { daily_budget: String(Math.round(Number(d.amount_aed) * 100)) }
          : { status: d.action === 'activate' ? 'ACTIVE' : 'PAUSED' };
        const form = new URLSearchParams({ ...params, access_token: String(token) });
        const r = await fetch(G0 + path, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form });
        const j = await r.json().catch(() => ({})); ok = r.ok; resp = { status: r.status, path, body: j };
      }
      if (ok) {
        const { error } = await admin.rpc('fn_ad_decision_mark_executed', { p_id: d.id, p_mode: live ? 'live' : 'sandbox', p_response: resp });
        if (error) { ok = false; resp = { rpc_error: error.message }; }
      }
      if (ok) executed++; else { failed++; failures.push(String(d.id) + ' ' + d.rule_key + '/' + d.action + ' on ' + d.campaign_id + ': ' + JSON.stringify(resp).slice(0, 140)); }
    }
    if (rows.length) await admin.from('agent_runs').insert({
      agent: 'meta_ads', started_at: started0, finished_at: new Date().toISOString(), status: failed ? 'error' : 'ok',
      counts: { decisions: rows.length, executed, failed, mode: live ? 'live' : 'sandbox' },
      note: failed
        ? ('Meta refused ' + failed + ' of ' + rows.length + ' ad decision(s); they stay unexecuted and their campaigns are not re-judged until they clear: ' + failures.join(' | ')).slice(0, 500)
        : (executed + ' ad decision(s) executed ' + (live ? 'on Meta' : 'in sandbox mode (no meta_access_token): the ledger and ad_campaign_state were updated exactly as a live call would')),
    });
    return J({ ok: failed === 0, mode: live ? 'live' : 'sandbox', decisions: rows.length, executed, failed, failures });
  }

  if (!token || !acctRaw) return J({ ok: false, error: 'meta_not_configured', need: ['meta_access_token', 'meta_ad_account_id'] }, 200);
  const acct = 'act_' + String(acctRaw).replace(/^act_/, '');
  const V = ver || 'v21.0';
  const G = 'https://graph.facebook.com/' + V;
  const started = new Date().toISOString();

  const post = async (path: string, params: Record<string, string>) => {
    const form = new URLSearchParams({ ...params, access_token: token });
    const r = await fetch(G + path, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form });
    const j = await r.json().catch(() => ({})); return { ok: r.ok, status: r.status, j };
  };
  const get = async (path: string, query: Record<string, string> = {}) => {
    const qs = new URLSearchParams({ ...query, access_token: token }).toString();
    const r = await fetch(G + path + '?' + qs); const j = await r.json().catch(() => ({})); return { ok: r.ok, status: r.status, j };
  };

  try {
    const action = String(body.action || 'test');

    if (action === 'test') {
      const r = await get('/' + acct, { fields: 'name,account_status,currency,timezone_name,amount_spent,balance' });
      return J({ ok: r.ok, status: r.status, account: r.j });
    }

    if (action === 'list') {
      const r = await get('/' + acct + '/campaigns', { fields: 'name,objective,status,effective_status,daily_budget,created_time', limit: '25' });
      return J({ ok: r.ok, campaigns: r.j?.data || r.j });
    }

    if (action === 'insights') {
      const days = Math.max(1, Math.min(90, Number(body.days) || 30));
      const r = await get('/' + acct + '/insights', { date_preset: days <= 7 ? 'last_7d' : (days <= 30 ? 'last_30d' : 'last_90d'), fields: 'spend,impressions,clicks,cpc,ctr,reach,actions' });
      return J({ ok: r.ok, insights: r.j?.data || r.j });
    }

    if (action === 'quick_campaign') {
      const name = String(body.name || 'QuotesDone Campaign').slice(0, 120);
      const objective = ['OUTCOME_TRAFFIC', 'OUTCOME_LEADS', 'OUTCOME_ENGAGEMENT', 'OUTCOME_AWARENESS', 'OUTCOME_SALES'].includes(String(body.objective)) ? String(body.objective) : 'OUTCOME_TRAFFIC';
      const dailyAed = Math.max(20, Number(body.daily_budget_aed) || 50); // Meta minimum varies; floor at AED 20
      const dailyMinor = Math.round(dailyAed * 100); // AED has 2 decimals -> fils
      const countries = Array.isArray(body.countries) && body.countries.length ? body.countries : ['AE'];

      // 1) PAUSED campaign
      const c = await post('/' + acct + '/campaigns', { name, objective, status: 'PAUSED', special_ad_categories: JSON.stringify([]) });
      if (!c.ok || !c.j?.id) { await admin.from('agent_runs').insert({ agent: 'meta_ads', started_at: started, finished_at: new Date().toISOString(), status: 'error', note: JSON.stringify(c.j).slice(0, 200) }); return J({ ok: false, step: 'campaign', error: c.j?.error?.message || c.j }, 200); }
      const campaign_id = c.j.id;

      // 2) PAUSED ad set — traffic/link clicks to the site, UAE, no pixel/page required
      const targeting = { geo_locations: { countries }, age_min: 18, age_max: 65 };
      const adsetParams: Record<string, string> = {
        name: name + ' — Ad set', campaign_id, daily_budget: String(dailyMinor),
        billing_event: 'IMPRESSIONS', optimization_goal: objective === 'OUTCOME_AWARENESS' ? 'REACH' : 'LINK_CLICKS',
        bid_strategy: 'LOWEST_COST_WITHOUT_CAP', targeting: JSON.stringify(targeting), status: 'PAUSED',
      };
      const a = await post('/' + acct + '/adsets', adsetParams);
      await admin.from('agent_runs').insert({ agent: 'meta_ads', started_at: started, finished_at: new Date().toISOString(), status: a.ok ? 'ok' : 'error', counts: { campaign: 1, adset: a.ok ? 1 : 0 }, note: a.ok ? null : JSON.stringify(a.j).slice(0, 200) });
      return J({ ok: a.ok, campaign_id, adset_id: a.j?.id || null, status: 'PAUSED', note: 'Created PAUSED. Add the ad creative + review targeting/budget in Meta Ads Manager, then switch it on to start spending.', adset_error: a.ok ? null : (a.j?.error?.message || a.j) });
    }

    return J({ error: 'unknown_action' }, 400);
  } catch (e) {
    await admin.from('agent_runs').insert({ agent: 'meta_ads', started_at: started, finished_at: new Date().toISOString(), status: 'error', note: String(e).slice(0, 200) });
    return J({ error: String((e as Error)?.message || e) }, 200);
  }
});
