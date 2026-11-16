// verify_cost.mjs — the AI cost and routing gate.
//
// Phase 6's real defect is not that cost is unrecorded. fn_llm_log DOES write ai_cost_log and it
// works. The defect is that `cost_aed` is 0.00 on every staging row and on 238 of 589 production
// rows, because two pricing tables disagree about which models exist:
//
//     fn_ai_route / fn_model_cost_usd  price from  model_registry   (in_per_mtok_usd)
//     fn_llm_log                       prices from model_rate       (in_aed_per_mtok)
//
// model_rate has 0 rows in staging and, in production, contains no `google/*` entries at all - so
// 100% of both Gemini models bill at zero, and `department_budget.spent_aed` never moves, because
// fn_llm_log only updates the budget `if p_dept is not null and v_cost > 0`. A model missing from
// model_rate does not fail loudly; it reports as free.
//
// Everything in the default run is pure SQL against staging: no model call, no spend, nothing to
// clean up. It is meant to gate every commit.
//
//     node scripts/archive/staging/verify_cost.mjs           the zero-cost gate
//     node scripts/archive/staging/verify_cost.mjs --live    also spends ~0.001 AED to prove the meter
import { supabaseAccessToken } from '../../lib/supabase_token.mjs';
import { assertNotProduction, mgmtRead, mgmtWrite } from '../../lib/qd_guard.mjs';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// REHOMED 15 AUG 2026: this defaulted to 'pglpqrhvozwepymcuunn', a project deleted that morning.
// The target now comes from demo_factory, which is the single place that decides it.
import { REF } from '../../lib/demo_factory.mjs';
import { pickApiKey } from '../../lib/supabase_keys.mjs';   // new keys first; legacy only as a temporary fallback (27 Oct 2026)
const BASE = `https://${REF}.supabase.co`;
const LIVE = process.argv.includes('--live');

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(44)} ${detail}`);
};

// ---- 1. the two pricing tables must agree about the models the policy actually uses -----------
const missingRegistry = await mgmtRead(REF, `
  select p.task_class, p.model_primary
    from public.model_policy p
   where coalesce(p.active,true) and p.tier <> 'none'
     and p.model_primary is not null and p.model_primary <> 'none'
     and not exists (select 1 from public.model_registry r
                      where r.model_id = p.model_primary and coalesce(r.active,true))
   order by 1`);
step('every policy model is in model_registry', missingRegistry.length === 0,
  missingRegistry.length
    ? missingRegistry.map((r) => `${r.task_class}->${r.model_primary}`).join(', ')
    : 'all active tier<>none policies resolve');

const missingRate = await mgmtRead(REF, `
  select p.task_class, p.model_primary
    from public.model_policy p
   where coalesce(p.active,true) and p.tier <> 'none'
     and p.model_primary is not null and p.model_primary <> 'none'
     and not exists (select 1 from public.model_rate m where m.model = p.model_primary)
   order by 1`);
step('every policy model is in model_rate', missingRate.length === 0,
  missingRate.length
    ? `${missingRate.length} unpriced: ` + [...new Set(missingRate.map((r) => r.model_primary))].join(', ')
    : 'every model the policy can select has an AED rate');

// The fallback is what a retry actually bills against, so an unpriced fallback is the same defect
// one layer down - and harder to notice, because it only shows up on the runs that failed once.
const missingFallback = await mgmtRead(REF, `
  select p.task_class, p.model_fallback
    from public.model_policy p
   where coalesce(p.active,true) and p.tier <> 'none'
     and p.model_fallback is not null and p.model_fallback <> 'none'
     and (not exists (select 1 from public.model_rate m where m.model = p.model_fallback)
       or not exists (select 1 from public.model_registry r
                       where r.model_id = p.model_fallback and coalesce(r.active,true)))
   order by 1`);
step('every fallback model is priced too', missingFallback.length === 0,
  missingFallback.length
    ? `${missingFallback.length} unpriced fallback(s): ` + [...new Set(missingFallback.map((r) => r.model_fallback))].join(', ')
    : 'fallbacks resolve in both tables');

const badRates = await mgmtRead(REF, `
  select model from public.model_rate
   where in_aed_per_mtok is null or out_aed_per_mtok is null
      or in_aed_per_mtok <= 0 or out_aed_per_mtok <= 0
   order by 1`);
step('no model_rate row prices at zero or null', badRates.length === 0,
  badRates.length ? badRates.map((r) => r.model).join(', ')
                  : `${(await mgmtRead(REF, 'select count(*)::int n from public.model_rate'))[0].n} rate row(s), all positive`);

// ---- 2. every gateway call site routes somewhere deliberate ------------------------------------
// The `fn` literals are read out of the repo rather than hard-coded, so a call site added next
// month is checked the day it lands instead of the day someone remembers to update a list.
function gatewayFnLiterals(dir) {
  const found = new Set();
  const walk = (d) => {
    for (const e of readdirSync(d)) {
      const p = join(d, e);
      if (statSync(p).isDirectory()) { walk(p); continue; }
      if (!/\.ts$/.test(e)) continue;
      const src = readFileSync(p, 'utf8');
      if (!src.includes('ai_gateway')) continue;   // only files that actually call the gateway
      for (const m of src.matchAll(/\bfn\s*:\s*['"]([a-z0-9_][a-z0-9_.-]*)['"]/g)) found.add(m[1]);
    }
  };
  walk(dir);
  return [...found].sort();
}
const sites = gatewayFnLiterals('supabase/functions');
const siteValues = sites.map((s) => `('${s.replace(/'/g, "''")}')`).join(',');
const routed = await mgmtRead(REF, `
  with sites(fn) as (values ${siteValues})
  select s.fn,
         (public.fn_ai_route(null,null,null,s.fn)->>'why') like '%UNMAPPED%' as unmapped
    from sites s order by 1`);
const unmapped = routed.filter((r) => r.unmapped === true).map((r) => r.fn);
step('every gateway call site has a task class', unmapped.length === 0,
  unmapped.length
    ? `${unmapped.length}/${sites.length} UNMAPPED -> general_drafting: ${unmapped.join(', ')}`
    : `${sites.length} call site(s), 0 falling through to general_drafting`);

// ---- 2b. caller-side max overrides -------------------------------------------------------------
// ai_gateway computes maxTok = min(body.max ?? route.max_tokens, route.max_tokens), so a hard-coded
// `max` in a calling function can only ever LOWER the policy ceiling, never raise it. That makes
// model_policy.max_tokens decorative wherever a caller sets its own - including the raises made in
// session 8. doc_extract's max:2000 was measured at 1,996-2,170 actual output tokens and returned
// extraction_null; that is this pattern biting, not a model problem.
//
// The pairing is a heuristic: a file that mentions ai_gateway and contains exactly one `fn:'…'`
// literal has its `max:` values attributed to that fn. Files with several fn literals are skipped
// and named, so the check never claims coverage it does not have.
function callerMaxes(dir) {
  const found = [];
  const skipped = [];
  const walk = (d) => {
    for (const e of readdirSync(d)) {
      const p = join(d, e);
      if (statSync(p).isDirectory()) { walk(p); continue; }
      if (!/\.ts$/.test(e)) continue;
      const raw = readFileSync(p, 'utf8');
      if (!raw.includes('ai_gateway')) continue;
      // Strip comments first. Without this the scan reads the prose EXPLAINING a removed override
      // as the override itself - doc_extract's fix documents the old `max:2000` in a comment, and
      // the audit duly reported it as still present.
      const src = raw.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
      const fns = [...new Set([...src.matchAll(/\bfn\s*:\s*['"]([a-z0-9_][a-z0-9_.-]*)['"]/g)].map((m) => m[1]))];
      const maxes = [...new Set([...src.matchAll(/[^_a-zA-Z]max\s*:\s*(\d+)/g)].map((m) => Number(m[1])))];
      if (!maxes.length) continue;
      if (fns.length !== 1) { skipped.push(`${e}(${fns.length} fn literals)`); continue; }
      for (const mx of maxes) found.push({ fn: fns[0], max: mx });
    }
  };
  walk(dir);
  return { found, skipped };
}
const { found: callerMax, skipped: ambiguous } = callerMaxes('supabase/functions');
const capValues = callerMax.map((c) => `('${c.fn.replace(/'/g, "''")}',${c.max})`).join(',');
const overrides = capValues ? await mgmtRead(REF, `
  with sites(fn, caller_max) as (values ${capValues})
  select s.fn, s.caller_max, p.task_class, p.max_tokens policy_max
    from sites s
    join public.fn_task_class t on t.fn = s.fn and t.active
    join public.model_policy p on p.task_class = t.task_class and coalesce(p.active,true)
   where p.tier <> 'none' and s.caller_max < p.max_tokens
   order by (s.caller_max::numeric / p.max_tokens), s.fn`) : [];

// This is a catalogue, not a pass/fail on each site: a caller may legitimately want a tighter budget
// than its class allows. What is asserted is that the LIST HAS NOT GROWN - a new override, or an
// existing one dropping further below its policy, is a deliberate decision that should show up here.
// 11 -> 9 on 5 Aug 2026. Two of the eleven were measured and removed:
//   extract_text  4000/8000 — the prompt says "Extract ALL readable text... Do not summarise" and
//                 the caller declared a 16,000-char result buffer, ~4,000 tokens, EXACTLY the
//                 ceiling it imposed on the model. Any document filling the buffer was cut and
//                 returned ok:true.
//   route_inquiry 1800/2500 — output grows with the candidate pool; measured max 1591 = 88% of its
//                 own cap, and a truncation there makes parseJson falsy, so the retry loop bills
//                 TWICE and both attempts truncate identically.
// The nine that remain were each read and judged deliberate — agent_brain's 160 is a classifier,
// not a truncation. quote_review 2600/10000 stays on the list untouched ON PURPOSE: it looks like
// the worst offender at 26% of its class, but the function has NO CALLER anywhere in the repo, so
// raising it would be maintenance on dead code. Measure before removing the rest.
const KNOWN_OVERRIDES = 9;
step('no new caller-side max override below its policy ceiling',
  overrides.length <= KNOWN_OVERRIDES,
  `${overrides.length} of ${callerMax.length} call-site max values sit below their task class ` +
  `(known ${KNOWN_OVERRIDES}). Tightest: ` +
  overrides.slice(0, 3).map((o) => `${o.fn} ${o.caller_max}/${o.policy_max}`).join(', ') +
  (ambiguous.length ? `. Unattributed: ${ambiguous.length} file(s)` : ''));

// ---- 3. the monitoring views must read the table that is actually written ----------------------
// llm_calls is dead legacy with one writer left in the repo (site_assistant/index.ts:25). A view
// over it returns zero rows forever and reads as "no off-policy calls" rather than "not measured".
const deadViews = await mgmtRead(REF, `
  select viewname from pg_views
   where schemaname='public' and definition ~* '\\mllm_calls\\M'
   order by 1`);
step('no monitoring view reads the dead llm_calls table', deadViews.length === 0,
  deadViews.length ? deadViews.map((v) => v.viewname).join(', ') + ' still read llm_calls'
                   : 'v_llm_model_mix and friends read ai_cost_log');

// ---- 4. drift alarm: calls that were billed at zero -------------------------------------------
const zero = (await mgmtRead(REF, `
  select count(*)::int total,
         count(*) filter (where coalesce(cost_aed,0) = 0)::int zero_cost
    from public.ai_cost_log
   where not coalesce(cached,false) and coalesce(ok,true) and coalesce(model_used,'none') <> 'none'`))[0];
step('no billable call is recorded at zero cost', Number(zero.zero_cost) === 0,
  `${zero.zero_cost}/${zero.total} uncached successful calls have cost_aed = 0`);

// ---- 5. LIVE: one real inference, and the meter that must move with it -------------------------
// Everything above is free. This section is opt-in because it spends money, and it is the only
// thing that proves the chain end to end: gateway -> fn_llm_log -> ai_cost_log -> department_budget.
const PROBE_FN = 'qd_cost_probe';
const PROBE_DEPT = 'qd_probe_dept';
if (LIVE) {
  const cred = (await mgmtRead(REF, "select value from public.app_secrets where key='cred_fn_ai'"))[0]?.value;
  const anon = await (async () => {
    const mgmt = supabaseAccessToken();
    const k = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`,
      { headers: { Authorization: 'Bearer ' + mgmt } })).json();
    return pickApiKey(k, 'publishable');
  })();

  const gw = async (payload) => {
    const r = await fetch(`${BASE}/functions/v1/ai_gateway`, {
      method: 'POST',
      headers: { apikey: anon, Authorization: 'Bearer ' + anon, 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: cred, ...payload }),
      signal: AbortSignal.timeout(120000),
    });
    const t = await r.text();
    try { return { status: r.status, json: JSON.parse(t) }; }
    catch { return { status: r.status, json: null, text: t.slice(0, 200) }; }
  };

  try {
    // A department with a real ceiling, so the spend has somewhere to land and be counted.
    await mgmtWrite(REF,
      `insert into public.department_budget (dept_key, monthly_aed, spent_aed, period_label, degrade_at_pct, halt_at_pct)
       values ('${PROBE_DEPT}', 100, 0, to_char(now(),'YYYY-MM'), 70, 95)
       on conflict (dept_key) do update set monthly_aed=100, spent_aed=0, degrade_at_pct=70, halt_at_pct=95`,
      'probe dept');

    const before = Number((await mgmtRead(REF,
      `select coalesce(spent_aed,0) s from public.department_budget where dept_key='${PROBE_DEPT}'`))[0].s);

    const r = await gw({
      fn: PROBE_FN, dept: PROBE_DEPT, task_class: 'json_extraction',
      sys: 'You return only compact JSON.',
      input: 'Return exactly {"ok":true} and nothing else.',
    });
    step('live gateway call succeeded', r.status === 200 && r.json?.ok === true,
      `HTTP ${r.status} outcome=${r.json?.outcome ?? '-'} model=${r.json?.model ?? '-'} ` +
      `finish=${r.json?.finish_reason ?? '-'} truncated=${r.json?.truncated ?? '-'}`);

    const logRow = (await mgmtRead(REF, `
      select model_used, cost_aed, prompt_tokens, output_tokens, task_class, ok
        from public.ai_cost_log where fn='${PROBE_FN}' order by occurred_at desc limit 1`))[0];
    step('the call landed a priced ai_cost_log row',
      !!logRow && Number(logRow.cost_aed) > 0 &&
      (Number(logRow.prompt_tokens) + Number(logRow.output_tokens)) > 0,
      logRow ? `model=${logRow.model_used} cost_aed=${logRow.cost_aed} ` +
               `tokens=${logRow.prompt_tokens}+${logRow.output_tokens} class=${logRow.task_class}`
             : 'no ai_cost_log row for the probe fn');

    const after = Number((await mgmtRead(REF,
      `select coalesce(spent_aed,0) s from public.department_budget where dept_key='${PROBE_DEPT}'`))[0].s);
    const moved = Number((after - before).toFixed(6));
    const cost = logRow ? Number(Number(logRow.cost_aed).toFixed(6)) : NaN;
    step('department_budget moved by exactly the logged cost', moved === cost && moved > 0,
      `spent_aed ${before} -> ${after} (delta ${moved}), logged cost ${cost}`);

    // The halt. fn_ai_route computes
    //     v_pct = 100 * sum(ai_cost_log.cost_aed this month for the dept) / monthly_aed
    // and halts when v_pct >= halt_at_pct, so the ceiling has to be set RELATIVE TO WHAT WAS
    // ACTUALLY SPENT. The brief proposed monthly_aed=0.01 with halt_at_pct=95; a flash-lite call
    // costs about 0.000043 AED, which is 0.43% of that ceiling, so the halt never fires and the
    // test reads as a broken halt when the halt is fine. Setting the ceiling to exactly the amount
    // already spent puts the department at 100% and makes the next call the one that must refuse.
    await mgmtWrite(REF,
      `update public.department_budget
          set monthly_aed = ${cost}, halt_at_pct = 95
        where dept_key='${PROBE_DEPT}'`, 'probe dept halt');
    const halted = await gw({
      fn: PROBE_FN, dept: PROBE_DEPT, task_class: 'json_extraction',
      sys: 'You return only compact JSON.', input: 'Return exactly {"ok":true}.',
    });
    step('an over-budget department is halted before it spends',
      halted.status === 200 && halted.json?.used_llm === false &&
      String(halted.json?.outcome ?? '').includes('budget'),
      `HTTP ${halted.status} outcome=${halted.json?.outcome ?? '-'} used_llm=${halted.json?.used_llm}`);
  } finally {
    // The probe is demo data and gets deleted like any other.
    await mgmtWrite(REF, `delete from public.ai_cost_log where fn='${PROBE_FN}'`, 'probe cleanup log');
    await mgmtWrite(REF, `delete from public.department_budget where dept_key='${PROBE_DEPT}'`, 'probe cleanup dept');
    console.log(`\ncleaned up probe rows (fn='${PROBE_FN}', dept_key='${PROBE_DEPT}')`);
  }
}

const pass = checks.filter((c) => c.ok).length;
console.log(`\nCOST GATE ${pass}/${checks.length} on ${REF}${LIVE ? ' (with live probe)' : ' (zero spend)'}`);
process.exitCode = pass === checks.length ? 0 : 1;
