// meta_sync - pulls QuotesDone Meta (Facebook/Instagram) ad campaign insights into public.meta_insights.
// Token-gated: requires app_secrets.meta_access_token (ads_read). Filters to campaigns whose name contains
// meta_campaign_filter (default 'QuotesDone') so the founder's DJ campaigns never enter QuotesDone's dashboards.
// Does NOT post to the GL. Returns {disabled:true} until a token is added.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'meta_sync', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
let INSIGHT_ERRORS = 0, EMPTY_INSIGHTS = 0, UPSERT_FAILS = 0; let LAST_ERR = '';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const GV = 'v21.0';
function resultsFrom(row: any, objective: string): number {
  const acts = Array.isArray(row?.actions) ? row.actions : [];
  const pick = (t: string) => { const a = acts.find((x: any)=>x.action_type===t); return a? Number(a.value)||0 : 0; };
  if (/LEAD/i.test(objective)) return pick('lead') || pick('onsite_conversion.lead_grouped');
  if (/LINK_CLICKS|TRAFFIC/i.test(objective)) return pick('link_click') || Number(row?.clicks)||0;
  if (/ENGAGEMENT|POST_ENGAGEMENT/i.test(objective)) return pick('post_engagement');
  if (/VIDEO/i.test(objective)) return pick('video_view');
  return Number(row?.clicks)||0;
}
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'meta_sync');
    if (!__auth.ok) { await logRun('error', { upserts: 0 }, 'call rejected: wrong or missing inbound secret; no Meta ad campaign insights were synced'); return J({ error: 'forbidden' }, 403); }
    const token = await sec('meta_access_token');
    const acct = await sec('meta_ad_account_id');
    const filter = (await sec('meta_campaign_filter')) || 'QuotesDone';
    if (!token) { await logRun('skipped', { upserts: 0, campaigns: 0, disabled: 1 }, 'Meta sync is DISABLED (no meta_access_token configured) — intentional off state, not a failure. meta_insights holds no ad spend/lead data until a token is added. Add app_secrets.meta_access_token (ads_read) to enable.'); return J({ ok: true, disabled: true, note: 'Add app_secrets.meta_access_token (ads_read) to enable Meta sync.' }); }
    if (!acct) { await logRun('skipped', { upserts: 0, campaigns: 0, disabled: 1 }, 'Meta sync is DISABLED (meta_ad_account_id not set) — intentional off state, not a failure. Set app_secrets.meta_ad_account_id to enable.'); return J({ ok: true, disabled: true, note: 'meta_ad_account_id not set.' }); }
    const act = acct.startsWith('act_') ? acct : ('act_' + acct);

    // 1) campaigns filtered to the QuotesDone name
    const cf = encodeURIComponent(JSON.stringify([{ field: 'name', operator: 'CONTAIN', value: filter }]));
    const curl = `https://graph.facebook.com/${GV}/${act}/campaigns?fields=id,name,effective_status,objective&filtering=${cf}&limit=200&access_token=${encodeURIComponent(token)}`;
    const cr = await fetch(curl); const cj = await cr.json();
    if (cj?.error) { await logRun('error', { upserts: 0, campaigns: 0 }, 'Meta Graph campaigns call FAILED (' + String(cj.error?.message || '') + '): no ad spend or lead data synced this run, meta_insights is stale and marketing reporting understates spend'); return J({ ok: false, error: 'graph_campaigns', detail: cj.error?.message }); }
    const camps = Array.isArray(cj?.data) ? cj.data.filter((c: any)=> String(c.name||'').toLowerCase().includes(filter.toLowerCase())) : [];
    let upserts = 0; const seen: string[] = [];
    for (const c of camps) {
      for (const dp of ['last_30d','maximum']) {
        const iurl = `https://graph.facebook.com/${GV}/${c.id}/insights?fields=spend,impressions,clicks,reach,ctr,cpc,actions&date_preset=${dp}&access_token=${encodeURIComponent(token)}`;
        const ir = await fetch(iurl); const ij = await ir.json();
        if (ij?.error) { INSIGHT_ERRORS++; LAST_ERR = 'insights call failed for campaign ' + String(c.id) + ' (' + dp + '): ' + String(ij.error?.message || ''); }
        else if (!(Array.isArray(ij?.data) && ij.data.length)) { EMPTY_INSIGHTS++; }
        const row = Array.isArray(ij?.data) && ij.data.length ? ij.data[0] : {};
        const rec = {
          campaign_id: String(c.id), campaign_name: c.name, effective_status: c.effective_status, objective: c.objective,
          time_window: dp, spend: Number(row?.spend)||0, impressions: Number(row?.impressions)||0, clicks: Number(row?.clicks)||0,
          reach: Number(row?.reach)||0, ctr: row?.ctr!=null?Number(row.ctr):null, cpc: row?.cpc!=null?Number(row.cpc):null,
          results: resultsFrom(row, String(c.objective||'')), currency: 'AED', synced_at: new Date().toISOString(), synced_via: 'meta_sync'
        };
        const { error } = await admin.from('meta_insights').upsert(rec, { onConflict: 'campaign_id,time_window' });
        if (error) { UPSERT_FAILS++; LAST_ERR = 'meta_insights upsert failed for campaign ' + String(c.id) + ' (' + dp + '): ' + String(error?.message || ''); }
        if (!error) upserts++;
      }
      seen.push(String(c.name));
    }
    const expected = camps.length * 2;
    let note: string;
    if (camps.length === 0) { note = 'Meta returned NO campaigns matching the "' + filter + '" name filter: nothing synced, so meta_insights has no fresh ad spend/lead data and marketing dashboards will show stale or zero figures'; }
    else if (INSIGHT_ERRORS >= expected) { note = 'every insights call failed for all ' + camps.length + ' matched campaign(s): rows were written with ZERO spend, impressions and results, which silently understates Meta ad spend and lead attribution'; }
    else if (INSIGHT_ERRORS > 0 || EMPTY_INSIGHTS > 0) { note = 'synced ' + upserts + '/' + expected + ' rows for ' + camps.length + ' campaign(s), but ' + INSIGHT_ERRORS + ' insights call(s) errored and ' + EMPTY_INSIGHTS + ' returned no data — those rows were stored as zeros and understate real spend/results'; }
    else { note = 'synced ' + upserts + '/' + expected + ' insight rows for ' + camps.length + ' matched Meta campaign(s)'; }
    if (UPSERT_FAILS > 0) { note += ' | ' + UPSERT_FAILS + ' row(s) failed to write to meta_insights'; }
    if (LAST_ERR) { note += ' | last error: ' + LAST_ERR; }
    const bad = UPSERT_FAILS > 0 || INSIGHT_ERRORS > 0 || camps.length === 0;
    await logRun(bad ? 'error' : 'ok', { campaigns: camps.length, upserts, expected_rows: expected, insight_errors: INSIGHT_ERRORS, empty_insights: EMPTY_INSIGHTS, upsert_failures: UPSERT_FAILS }, note);
    return J({ ok: true, campaigns: camps.length, upserts, sample: seen.slice(0,5) });
  } catch (e) { await logRun('error', { upserts: 0, insight_errors: INSIGHT_ERRORS, upsert_failures: UPSERT_FAILS }, 'meta_sync crashed before completing; Meta ad spend and lead data was not synced this run: ' + String((e as Error)?.message || e)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
