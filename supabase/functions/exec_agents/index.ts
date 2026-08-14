// exec_agents — Executive Intelligence layer. Each officer reads live metrics and writes a
// prioritized action plan into exec_reports. Secret-gated (cron/internal). Action: run {officer} | run_all.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(s: string): any { if (!s) return null; const m = s.match(/\{[\s\S]*\}/); if (!m) return null; try { return JSON.parse(m[0]); } catch { return null; } }
const llm = makeLlm(SONNET_FIRST, { max: 1600, temperature: 0.25 }); // shared OpenRouter client (Sonnet-first + 25s timeout)

const OFFICERS: Record<string, { name: string; rpc: string; brief: string }> = {
  strategy: { name: 'AI Strategy Officer', rpc: 'fn_strategy_metrics', brief: 'You continuously IMPROVE the business (not run it). From the metrics identify: categories with high demand but too few suppliers; coverage gaps (categories without engineered requirements, playbooks or mapped regulations); funnel leaks (abandoned RFQs, low response rate, slow first quote). Output a prioritized action plan the founder can approve.' },
  operations: { name: 'Operations Director', rpc: 'fn_ops_metrics', brief: 'You run the marketplace. From the metrics find what is slowing it down: RFQs open with no quotes, suppliers matched but not quoting, slow first-response, stuck pipeline stages, overdue activities. Recommend concrete unblocking actions.' },
  procurement_quality: { name: 'Procurement Quality Officer', rpc: 'fn_quality_metrics', brief: 'You protect quality. From the metrics flag: RFQs missing category/scope/emirate; RFQs with too few suppliers invited; low quote completeness scores; RFQs that are not comparable (only one quote). Recommend fixes that raise quote quality and comparability.' },
  data_science: { name: 'Data Scientist', rpc: 'fn_data_metrics', brief: 'You analyze trends. From the metrics identify category demand growth/decline, most competitive categories, price spread/volatility, and seasonality. Recommend where to invest supply/marketing and any pricing guidance.' },
  product_ux: { name: 'Product & UX Officer', rpc: 'fn_voice_metrics', brief: 'You are the voice of the customer. From the metrics (low ratings + comments, disputes, abandoned RFQs, repeat customers) infer friction and product/UX issues. Recommend product changes and where users drop off.' },
  competitive: { name: 'Competitive Intelligence Officer', rpc: 'fn_strategy_metrics', brief: 'Assess QuotesDone competitive position from internal proxies (category coverage vs demand, response rate, savings). Note explicitly that live competitor tracking needs an external data connector (SEO/ads/traffic) to be complete, and list what to monitor.' }
};

// ELEVEN STRATEGIC REPORTS A DAY, EACH, ABOUT A MARKETPLACE WITH NO ACTIVITY (14 Aug 2026).
//
// MEASURED ON PRODUCTION over the four days 10-13 Aug: exec_reports holds 44-45 rows per officer —
// about ELEVEN per officer per day, six officers — and exec_agents made 379 model calls in that
// window for AED 18.44, 15.5% of all AI spend. Over the same four days the marketplace took 0
// inquiries, 0 quotes and 0 trades, so `metrics` was very often byte-identical between runs.
//
// Only ONE of them is ever read. exec-intel-quantified-recommendation, and every other consumer,
// reads the NEWEST report per officer — this function's own header says so. So ten of every eleven
// reports per officer per day were synthesised, billed, filed, and never looked at.
//
// The table already says what the intended cadence was: exec_reports.period is a DATE. One report
// per officer per period is what the schema has always implied; nothing enforced it.
//
// THE GUARD IS ON THE INPUT, NOT THE CLOCK, WHICH MATTERS. Refusing by time alone would suppress a
// genuine report when something real happened at 11am. This compares the METRICS: if a report
// already exists for this officer and period AND the metrics rpc returns exactly what that report
// was built from, there is nothing new to say and the model is not called. The moment a single
// number moves, a fresh report is produced immediately, on the same tick, with no delay.
//
// So the officers keep their hourly heartbeat and stop paying for it when nothing has changed.
// Trading will make the metrics move constantly and the reports will resume at full rate by
// themselves — this throttles silence, not work.
function metricsFingerprint(m: unknown): string {
  // Stable across key order, so a jsonb round-trip cannot look like a change.
  const norm = (v: any): any =>
    Array.isArray(v) ? v.map(norm)
      : (v && typeof v === 'object')
        ? Object.keys(v).sort().reduce((o: any, kk) => { o[kk] = norm(v[kk]); return o; }, {})
        : v;
  try { return JSON.stringify(norm(m ?? {})); } catch { return ''; }
}

async function runOfficer(k: string): Promise<any> {
  const cfg = OFFICERS[k]; if (!cfg) return { error: 'unknown officer' };
  const { data: metrics } = await admin.rpc(cfg.rpc);

  // NOTHING NEW TO SAY. See the block above.
  const period = new Date().toISOString().slice(0, 10);
  try {
    const { data: prior } = await admin.from('exec_reports')
      .select('id,metrics').eq('officer', k).eq('period', period)
      .order('created_at', { ascending: false }).limit(1).maybeSingle();
    if (prior && metricsFingerprint(prior.metrics) === metricsFingerprint(metrics)) {
      // note is a TRUE SENTENCE here, not null. fn_action_invoke_collect fills
      // org_tasks.result.deliverable from this field, and ten routines read it. The failure path
      // below returns null on purpose — a deliverable synthesised from a run that reached no model
      // would be a lie. This is the opposite case: the run succeeded, the officer looked, and the
      // finding is that nothing has changed. Saying so is the deliverable.
      return { officer: k, report_id: prior.id, filed: false, unchanged: true,
               recommendations: 0, ai: false, attempts: 0,
               note: cfg.name + ' reviewed the live metrics and they are identical to report '
                   + prior.id + ', already filed for ' + period + '. Nothing has changed since that '
                   + 'report, so it stands as this period\'s position and no new synthesis was '
                   + 'commissioned.',
               reason: 'metrics unchanged since report ' + prior.id + ' for ' + period
                     + '; no model was called' };
    }
  } catch (_e) { /* a failed lookup must not stop an officer reporting */ }

  const sys = 'You are ' + cfg.name + ' for QuotesDone, the UAE anonymous B2B quotation marketplace. ' + cfg.brief + ' Be concrete, specific to the numbers, and honest about small sample sizes. Return ONLY JSON: {"summary":string,"findings":[string],"recommendations":[{"action":string,"impact":"high|medium|low","effort":"high|medium|low","confidence":number}]}. 3-6 findings, 3-6 recommendations, most important first.';
  // ONE RETRY, THEN THE TRUTH. Measured on production 9 Aug 2026: three of six officers —
  // competitive, product_ux and strategy — had filed reports carrying the fallback summary
  // "Metrics captured; AI synthesis unavailable this run.", zero findings and zero
  // recommendations. parseJson had returned null, and the run was still written to agent_runs as
  // status 'ok'. product_ux had produced five findings on an earlier run, so this is intermittent,
  // not an officer that cannot work — which is exactly the shape a single attempt handles badly.
  //
  // The most likely cause is a response that does not close: parseJson takes the first `{` to the
  // last `}` and JSON.parse throws on a truncated object. So the retry asks for a SMALLER object
  // rather than simply asking again, and says why.
  const user = 'LIVE METRICS (JSON):\n' + JSON.stringify(metrics || {});
  let raw = await llm(sys, user, 1800);
  let parsed = parseJson(raw || '');
  let attempts = 1;
  if (!parsed || !Array.isArray(parsed.recommendations) || !parsed.recommendations.length) {
    attempts = 2;
    const strict = sys + ' Your previous response could not be parsed into that object. Return ONLY the'
      + ' JSON object — no prose, no markdown fence, no commentary before or after. Keep it to exactly'
      + ' 3 findings and 3 recommendations so the object closes inside the token budget.';
    const retry = await llm(strict, user, 1800);
    const reparsed = parseJson(retry || '');
    if (reparsed && Array.isArray(reparsed.recommendations) && reparsed.recommendations.length) {
      parsed = reparsed; raw = retry;
    } else if (!parsed && reparsed) { parsed = reparsed; raw = retry; }
  }
  const row: any = { officer: k, period, metrics: metrics || {},
    summary: parsed?.summary || ('Metrics captured; AI synthesis unavailable this run.'),
    findings: Array.isArray(parsed?.findings) ? parsed.findings : [],
    recommendations: Array.isArray(parsed?.recommendations) ? parsed.recommendations : [] };
  const produced = row.recommendations.length > 0;

  // AN EMPTY REPORT IS NOT A REPORT, AND FILING IT DOES ACTIVE HARM (12 Aug 2026).
  // This used to insert unconditionally, so a run that reached no model still left an exec_reports
  // row carrying "Metrics captured; AI synthesis unavailable this run." with no findings and no
  // recommendations. Proven the day this changed: OpenRouter refused sonnet-5 and opus-4.8 for
  // credits (HTTP 402), three invocations filed SEVEN such rows in two minutes, and because
  // exec-intel-quantified-recommendation reads the NEWEST report per officer, six officers went
  // from "carries a numeric recommendation" to "filed an empty recommendation" — a green check
  // turned red by reports that contain nothing. The company's last real reports were still there,
  // one row further down, saying something useful.
  //
  // Same rule action_worker already follows one queue over: an unresolved item gets looked at, a
  // false success never does. Nothing is lost by not filing — `metrics` is a live rpc that can be
  // re-read at any time, and the agent_runs row below already records the failure WITH its reason,
  // which is the honest artefact. A period with no report from an officer reads as "this officer
  // produced nothing", which is true. An empty report reads as "this officer had nothing to say",
  // which is not.
  let ins: { id?: number } | null = null;
  if (produced) {
    const r = await admin.from('exec_reports').insert(row).select('id').maybeSingle();
    ins = r.data;
  }

  // An officer report with no recommendations is a FAILED run, not a quiet one. Recording it as
  // 'ok' is why three officers could file nothing for a week with no signal anywhere.
  try {
    await admin.from('agent_runs').insert({ agent: 'exec:' + k,
      started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
      status: produced ? 'ok' : 'error',
      counts: { recs: row.recommendations.length, findings: row.findings.length, attempts, filed: produced },
      note: produced ? null
        : ('Officer ' + k + ' produced NO recommendations after ' + attempts
           + ' attempt(s) and NO report was filed: the model response could not be parsed into the'
           + ' required object, so this officer contributes nothing to the executive intelligence'
           + ' layer this period. An empty report is not filed because it would displace this'
           + " officer's last real one."
           + ' First 200 characters of the last response: ' + String(raw || '(empty)').slice(0, 200)).slice(0, 500) });
  } catch (_e) { /* never let logging break the officer */ }
  // WHAT THE OFFICER ACTUALLY CONCLUDED, RETURNED (12 Aug 2026). This returned six counters and no
  // prose, so fn_action_invoke_collect — which fills org_tasks.result.deliverable from the response
  // body and is read by ten routines — found nothing to extract on all 15 succeeded invocations in
  // the last 7 days. The synthesis was written to exec_reports and stopped there. `note` carries
  // the officer's own summary and its lead recommendation, which is the same text already filed,
  // not a new claim.
  //
  // NULL when nothing was filed, deliberately. The block above refuses to file an empty report
  // because "an empty report reads as 'this officer had nothing to say', which is not true" — and
  // a deliverable synthesised from a failed run would be the same lie in the learning loop.
  const lead = row.recommendations[0]?.action;
  return { officer: k, report_id: ins?.id ?? null, filed: produced,
           note: produced
             ? (String(row.summary) + (lead ? ' Lead recommendation: ' + String(lead) : '')
                + ' (' + row.findings.length + ' finding(s), ' + row.recommendations.length + ' recommendation(s).)')
             : null,
           recommendations: row.recommendations.length, ai: !!parsed, attempts };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } });
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'exec_agents');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || 'run_all');
    if (action === 'run') return J(await runOfficer(String(body.officer || 'strategy')));
    // SIX OFFICERS IN SERIES WAS THE WHOLE FAILURE (11 Aug 2026). This was
    // `for (const k of ...) out.push(await runOfficer(k))` — every officer waited for the one
    // before it, in a single HTTP request, and each officer costs one model call plus a retry when
    // the JSON does not parse.
    //
    // MEASURED ON PRODUCTION: exec_agents made 344 model calls in 14 days at a median of 16.4s and
    // a MAXIMUM of 31.5s — no single call is slow and not one failed. But grouped per invocation it
    // is 4.9 calls on average and up to 17, summing to 84.8s typically and 289.8s at worst. The
    // org_action_executor row for exec_review allows 140s. Twelve of seventy invocations exceeded
    // that on model time alone, and 25 of the 40 exec_review dispatches FAILED — every one with
    // "Timeout of 140000 ms reached". Because max_attempts is 1, each timeout permanently failed a
    // strategic_review run at step 4, "Decide and record rationale". The engine's own decision step.
    //
    // The officers are independent: each reads its own metrics rpc and writes its own exec_reports
    // and agent_runs row, sharing no mutable state, and runOfficer has no caller outside this file.
    // Serialising them bought nothing. In parallel the wall time is the SLOWEST officer rather than
    // the SUM — about 35s against 204s — which fits inside 140s with room for the retry path.
    //
    // allSettled, not all: one officer throwing must not discard the five reports that succeeded.
    // runOfficer already swallows its own logging errors and returns a shape either way, so a
    // rejection here means something unexpected, and it is reported per officer instead of losing
    // the batch.
    if (action === 'run_all') {
      const keys = Object.keys(OFFICERS);
      const settled = await Promise.allSettled(keys.map((k) => runOfficer(k)));
      const out = settled.map((r, i) => r.status === 'fulfilled'
        ? r.value
        : { officer: keys[i], error: String((r.reason as Error)?.message ?? r.reason) });
      return J({ ok: true, ran: out });
    }
    if (action === 'latest') { const { data } = await admin.from('exec_reports').select('*').order('created_at', { ascending: false }).limit(Math.min(Number(body.limit) || 12, 50)); return J({ ok: true, reports: data || [] }); }
    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
