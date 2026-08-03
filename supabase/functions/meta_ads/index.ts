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
