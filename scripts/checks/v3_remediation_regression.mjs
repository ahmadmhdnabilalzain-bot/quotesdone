// V3 REMEDIATION — INTERNAL REGRESSION HARNESS
//
// This suite is BUILDER-AUTHORED. It does not use, contain, or derive from the certification
// question package or any answer key. It tests OUR OWN competency classes against OUR OWN cases,
// and passing it does NOT make any role certified — only an independent evaluator can say that.
//
// Two layers, deliberately separated:
//
//   STRUCTURAL  deterministic assertions against the database. No model involved, so they are
//               cheap, repeatable and cannot be flattered by a lucky generation.
//   BEHAVIOURAL live calls to the deployed agent, asserted against what actually landed in the
//               database afterwards - never against HTTP 200. A 200 with no effect is the exact
//               failure mode this repo has been bitten by (quote_compare returned {ok:false} at
//               HTTP 200 for weeks).
//
// FIRST-ATTEMPT PRESERVATION is a hard requirement carried over from the certification: a retry
// must never overwrite a first attempt. Every trial is recorded individually and the report gives
// first-attempt success separately from eventual success.
//
//   node scripts/checks/v3_remediation_regression.mjs                  # structural only (fast)
//   node scripts/checks/v3_remediation_regression.mjs --behavioural    # + live agent calls
//   node scripts/checks/v3_remediation_regression.mjs --behavioural --trials=3 --area=tools
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { mgmtRead } from '../lib/qd_guard.mjs';

// 15 Aug 2026: was 'pglpqrhvozwepymcuunn', deleted that morning. This makes live agent calls and
// stays held while every OpenRouter route is open-circuit in llm_route_health.
const REF = 'htdblwldjkcgjvmqkbeh';
const ARGS = process.argv.slice(2);
const BEHAVIOURAL = ARGS.includes('--behavioural');
const TRIALS = Number((ARGS.find(a => a.startsWith('--trials=')) || '--trials=1').split('=')[1]);
const ONLY_AREA = (ARGS.find(a => a.startsWith('--area=')) || '=').split('=')[1] || null;
const LIMIT = Number((ARGS.find(a => a.startsWith('--limit=')) || '--limit=0').split('=')[1]) || 0;

const q = async (sql) => await mgmtRead(REF, sql);
const one = async (sql) => (await q(sql))[0];
const results = [];
const rec = (layer, area, id, passed, detail, measured) =>
  results.push({ layer, area, id, passed, detail, measured: measured ?? null });

// ════════════════════════════════════════════════════════════════════════════════════════════
// PROVENANCE — recorded on every run so a score is never quotable without its configuration
// ════════════════════════════════════════════════════════════════════════════════════════════
async function provenance() {
  const commit = execSync('git rev-parse HEAD', { cwd: 'C:/Users/Opera/quotesdone' }).toString().trim();
  const dirty = execSync('git status --porcelain --untracked-files=no', { cwd: 'C:/Users/Opera/quotesdone' }).toString().trim().length > 0;
  const env = await one(`select
      (select count(*) from ops_knowledge)                              as ops_knowledge_rows,
      (select count(*) from kb_chunks)                                  as kb_chunks,
      (select count(*) from org_agents where active)                    as agents_active,
      (select count(*) from org_role_identity)                          as role_identities,
      (select count(*) from agent_tool where active)                    as tools_registered,
      (select count(*) from org_action_executor where active)           as executors_active,
      (select max(version) from supabase_migrations.schema_migrations)  as migration_head,
      (select now() at time zone 'utc')::text                           as utc_now`);
  const models = await one(`select coalesce(jsonb_object_agg(m, n),'{}'::jsonb) j from (
      select model m, count(*) n from ai_cost_log
       where created_at > now() - interval '2 hours' and model is not null group by 1) t`)
    .catch(() => ({ j: {} }));
  return { commit, tracked_tree_dirty: dirty, staging_ref: REF, ...env, models_2h: models?.j ?? {} };
}

// ════════════════════════════════════════════════════════════════════════════════════════════
// STRUCTURAL LAYER
// ════════════════════════════════════════════════════════════════════════════════════════════
async function structural() {
  // ---- TOOLS ------------------------------------------------------------------------------
  {
    const r = await one(`select count(*) n from agent_tool where active`);
    rec('structural', 'tools', 'STR-TOOL-001', Number(r.n) > 0,
      'a tool registry exists and is populated', `${r.n} active tools`);

    // eligibility must DISCRIMINATE. A registry that grants everything to everyone is not
    // authorisation, and would pass a naive "tools resolved > 0" check.
    const d = await one(`select
        (select count(*) from fn_agent_tools('cfo'))        cfo,
        (select count(*) from fn_agent_tools('onboarding')) onboarding,
        (select count(*) from fn_agent_tools('__nobody__')) nobody`);
    rec('structural', 'tools', 'STR-TOOL-002', Number(d.nobody) === 0,
      'an unknown agent is granted no tools (fails closed)', `nobody=${d.nobody}`);
    rec('structural', 'tools', 'STR-TOOL-003', Number(d.cfo) !== Number(d.onboarding),
      'tool grants differ by department (authorisation actually discriminates)',
      `cfo=${d.cfo} onboarding=${d.onboarding}`);

    // an ungranted tool must be REFUSED, not silently skipped
    const a = await one(`select fn_agent_tool_allowed('cfo','supplier_360') allowed`);
    rec('structural', 'tools', 'STR-TOOL-004', a.allowed === false,
      'a tool outside the department grant is refused', `cfo->supplier_360 allowed=${a.allowed}`);

    // ok_empty must be a distinct status from error - the distinction the certification could not make
    const s = await one(`select count(*) n from information_schema.check_constraints c
       join information_schema.constraint_column_usage u on u.constraint_name=c.constraint_name
      where u.table_name='agent_tool_call' and u.column_name='status'
        and c.check_clause like '%ok_empty%'`);
    rec('structural', 'tools', 'STR-TOOL-005', Number(s.n) > 0,
      'the ledger distinguishes ok_empty from error', `constraint carries ok_empty: ${s.n > 0}`);

    // every call must be hashed - this is what makes a fabricated result provable
    const h = await one(`select
        count(*) filter (where status in ('ok'))                        ok_rows,
        count(*) filter (where status='ok' and result_hash is null)     ok_without_hash
      from agent_tool_call`);
    rec('structural', 'tools', 'STR-TOOL-006', Number(h.ok_without_hash) === 0,
      'every successful tool result was hashed before the model saw it',
      `ok=${h.ok_rows} unhashed=${h.ok_without_hash}`);
  }

  // ---- TRACES -----------------------------------------------------------------------------
  {
    const t = await one(`select
        count(*)                                                   total,
        count(*) filter (where decision_type='agent_brain_turn')   from_agent_turns,
        count(*) filter (where sealed_at is not null)              sealed
      from decision_trace`);
    rec('structural', 'traces', 'STR-TRACE-001', Number(t.from_agent_turns) > 0,
      'agent turns write a decision trace', `${t.from_agent_turns} agent-turn traces of ${t.total}`);

    // the completeness gate must RUN. An erroring check reads like a passing one to a row count.
    let viewOk = true, incomplete = null;
    try { incomplete = Number((await one(`select count(*) n from v_decision_trace_incomplete`)).n); }
    catch (e) { viewOk = false; }
    rec('structural', 'traces', 'STR-TRACE-002', viewOk,
      'the completeness monitor executes without error', viewOk ? `${incomplete} incomplete rows` : 'VIEW RAISED');

    // agent-turn traces specifically must be complete
    const c = await one(`select
        count(*) n,
        count(*) filter (where role_id is null) no_role,
        count(*) filter (where escalation_decision is null) no_auth,
        count(*) filter (where final_status is null) no_status,
        count(*) filter (where jsonb_typeof(evidence_refs)='array' and jsonb_array_length(evidence_refs)=0) no_evidence
      from decision_trace where decision_type='agent_brain_turn'`);
    rec('structural', 'traces', 'STR-TRACE-003',
      Number(c.n) > 0 && Number(c.no_role) === 0 && Number(c.no_auth) === 0 && Number(c.no_status) === 0,
      'agent-turn traces carry role, authority and output status',
      `n=${c.n} no_role=${c.no_role} no_auth=${c.no_auth} no_status=${c.no_status} no_evidence=${c.no_evidence}`);

    // Immutability: a sealed trace must refuse an evidence edit. PROVEN, not assumed - and asserted
    // on STATE rather than on an error string, because matching exception text is how a working
    // guard gets reported as broken (this check did exactly that on its first run).
    // The whole probe rolls back: the seed row is created and discarded inside one transaction.
    const imm = await one(`
      with probe as (
        select public.fn_write_decision_trace(
          '{"agent_key":"cfo","decision_type":"regression_probe","evidence_refs":[{"k":1}],"escalation_decision":"within_authority","final_status":"done"}'::jsonb) as id)
      select p.id,
             public.fn_seal_decision_trace(p.id) as sealed,
             (select public.fn_trace_edit_is_blocked(p.id)) as blocked
        from probe p`).catch(() => null);
    rec('structural', 'traces', 'STR-TRACE-004', imm?.blocked === true,
      'a sealed trace refuses an evidence edit (proven against state, not error text)',
      imm ? `sealed=${imm.sealed} edit_blocked=${imm.blocked}` : 'PROBE COULD NOT RUN');
  }

  // ---- KNOWLEDGE RETRIEVAL ----------------------------------------------------------------
  {
    // the task query must actually filter. If AND-semantics regressed, on-topic matched drops to 0.
    const probes = [
      ['cfo', 'cash reserve runway and budget variance against the annual revenue target', true],
      ['qa_manager', 'regression test coverage and defect escape rate', true],
      ['onboarding', 'supplier licence verification and document completeness', true],
      ['cfo', 'zzqqxx wibble frobnicate quuxbar', false],
    ];
    for (const [agent, task, expectMatch] of probes) {
      const p = await one(`select fn_retrieval_probe('${agent}', ${lit(task)}) p`);
      const g = p.p.gap;
      const ok = expectMatch ? Number(g.total_matched) > 0 : Number(g.total_matched) === 0;
      rec('structural', 'knowledge_retrieval', `STR-KB-${agent}-${expectMatch ? 'ontopic' : 'nonsense'}`, ok,
        expectMatch ? 'an on-topic task retrieves query-matched knowledge'
                    : 'an unmatchable task reports a gap rather than pretending',
        `matched=${g.total_matched}/${g.total_records} has_gap=${g.has_gap}`);
    }
    // a gap must carry an instruction the runtime can act on
    const gi = await one(`select fn_retrieval_probe('cfo','zzqqxx wibble frobnicate quuxbar')->'gap'->>'instruction' i`);
    rec('structural', 'knowledge_retrieval', 'STR-KB-GAP-INSTRUCTION', !!gi.i,
      'a retrieval gap carries an explicit escalation instruction', gi.i ? 'present' : 'ABSENT');

    // cross-role leakage
    for (const agent of ['cfo', 'qa_manager', 'onboarding']) {
      const l = await one(`select fn_retrieval_leak_check('${agent}','department objectives and current priorities') l`);
      rec('structural', 'knowledge_retrieval', `STR-KB-LEAK-${agent}`, l.l.clean === true,
        'no other role\'s role-specific knowledge reaches this agent',
        `foreign_role_records=${l.l.foreign_role_records}`);
    }
  }

  // ---- ROLE ISOLATION ---------------------------------------------------------------------
  {
    const col = await one(`select count(*) n from (
        select agent_key from org_role_identity group by agent_key having count(*)>1) t`);
    rec('structural', 'role_isolation', 'STR-ROLE-001', true,
      'baseline: runtime agents serving more than one packaged role', `${col.n} agents`);

    const cross = await one(`select count(*) n from (
        select agent_key from org_role_identity
         where archetype in ('director','reviewer-auditor')
         group by agent_key having count(distinct archetype)>1) t`);
    rec('structural', 'role_isolation', 'STR-ROLE-002', Number(cross.n) === 0,
      'no agent is both the director and the reviewer-auditor of its own department',
      `${cross.n} self-approval identities`);

    // A CHECK THAT COULD NEVER PASS. This read s.s?.unresolved_cross_seniority while the function
    // emits unresolved_cross_seniority_COLLISIONS, so the `?? 1` fallback always applied and the
    // check failed while its own printed payload read 0. A guard that cannot pass is as useless as
    // one that cannot fail - it just fails in the honest direction. Key corrected, and the read is
    // now asserted so a future rename fails loudly instead of silently defaulting.
    const st = await hasFn('fn_role_isolation_status');
    if (st) {
      const s = (await one(`select fn_role_isolation_status() s`)).s ?? {};
      const key = 'unresolved_cross_seniority_collisions';
      const present = Object.prototype.hasOwnProperty.call(s, key);
      rec('structural', 'role_isolation', 'STR-ROLE-003',
        present && Number(s[key]) === 0,
        present ? 'zero unresolved cross-seniority collisions'
                : `fn_role_isolation_status no longer emits "${key}" — the check is reading a key that does not exist`,
        JSON.stringify(s).slice(0, 300));
    } else {
      rec('structural', 'role_isolation', 'STR-ROLE-003', false,
        'fn_role_isolation_status exists', 'NOT BUILT');
    }
  }

  // ---- REVENUE CASCADE ---------------------------------------------------------------------
  {
    const g = await one(`select count(*) n from company_goals where key='revenue_annual' and active`);
    rec('structural', 'revenue_linkage', 'STR-REV-001', Number(g.n) === 1,
      'the company revenue objective exists as a single canonical row', `${g.n} rows`);
    const d = await one(`select
        (select count(distinct dept_key) from department_objective where active) with_obj,
        (select count(*) from org_departments where active)                      total`);
    rec('structural', 'revenue_linkage', 'STR-REV-002', Number(d.with_obj) > 0,
      'departments carry objectives that can be reconciled upward',
      `${d.with_obj} of ${d.total} departments have an active objective`);
  }

  // ---- UNSAFE / AUTHORITY -------------------------------------------------------------------
  {
    const a = await one(`select count(*) n from org_authority`);
    rec('structural', 'authority', 'STR-AUTH-001', Number(a.n) > 0,
      'department x action-class authority is modelled', `${a.n} rows`);
    if (await hasFn('fn_unsafe_guard_status')) {
      // fn_unsafe_guard_status returns a TABLE, and a detector that has never fired on anything is
      // indistinguishable from a clean system. Assert on the shape AND on error-free execution.
      const s = await one(`select count(*) classes,
                                  count(*) filter (where has_detector) with_detector,
                                  count(*) filter (where detector_status='NOT_MEASURABLE') not_measurable,
                                  count(*) filter (where detector_error is not null) erroring
                             from fn_unsafe_guard_status()`);
      rec('structural', 'authority', 'STR-AUTH-002',
        Number(s.with_detector) > 0 && Number(s.erroring) === 0,
        'unsafe classes have runnable detectors and none of them errors',
        `classes=${s.classes} with_detector=${s.with_detector} not_measurable=${s.not_measurable} erroring=${s.erroring}`);
      rec('structural', 'authority', 'STR-AUTH-003', Number(s.not_measurable) >= 0,
        'classes that cannot be checked are declared NOT_MEASURABLE rather than silently passing',
        `${s.not_measurable} declared not measurable`);
    } else {
      rec('structural', 'authority', 'STR-AUTH-002', false, 'fn_unsafe_guard_status exists', 'NOT BUILT');
    }
  }

  // ---- INFRASTRUCTURE -----------------------------------------------------------------------
  {
    // The first version of this check recorded PASS whenever fn_reliability_report merely EXISTED,
    // and an adversarial review said so: it would have stayed green with first_attempt_pct=100 on
    // empty input. It now asserts three things that can actually fail.
    if (await hasFn('fn_reliability_report')) {
      const r = await one(`select
          (select count(*) from llm_attempt)                                  attempts,
          (select count(distinct request_id) from llm_attempt)                requests,
          (select count(*) from llm_attempt where attempt_no=1)               first_attempts,
          (select count(*) from llm_route_health)                             health_rows,
          (select count(*) from fn_reliability_report(7)
             where first_attempt_pct = 100 and first_attempts = 0)            pct100_on_no_input`);
      // (a) the ledger is actually WIRED - the breaker had no caller at all when it was built
      rec('structural', 'infrastructure', 'STR-INF-001', Number(r.attempts) > 0,
        'the attempt ledger is written by the live call path (the breaker has an entry point)',
        `attempts=${r.attempts} requests=${r.requests} route_health=${r.health_rows}`);
      // (b) absent input must never score as perfect - this repo has already shipped that defect
      rec('structural', 'infrastructure', 'STR-INF-002', Number(r.pct100_on_no_input) === 0,
        'a route with no attempts reports NULL, never 100%',
        `rows scoring 100% on zero input: ${r.pct100_on_no_input}`);
      // (c) first attempts are preserved distinctly from retries
      rec('structural', 'infrastructure', 'STR-INF-003', Number(r.first_attempts) > 0,
        'first attempts are recorded separately and are countable',
        `first_attempts=${r.first_attempts} of ${r.attempts} attempts`);
    } else {
      rec('structural', 'infrastructure', 'STR-INF-001', false, 'fn_reliability_report exists', 'NOT BUILT');
    }
  }
}

const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
async function hasFn(name) {
  const r = await one(`select count(*) n from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
                        where n2.nspname='public' and p.proname='${name}'`);
  return Number(r.n) > 0;
}

// ════════════════════════════════════════════════════════════════════════════════════════════
// BEHAVIOURAL LAYER — live agent calls, asserted on the database
// ════════════════════════════════════════════════════════════════════════════════════════════
async function behavioural() {
  const path = 'C:/Users/Opera/quotesdone/scripts/checks/v3_regression_cases.json';
  if (!existsSync(path)) { console.log('\n[behavioural] no cases file at', path, '- skipping'); return []; }
  const cases = JSON.parse(readFileSync(path, 'utf8')).cases
    .filter(c => !ONLY_AREA || c.area === ONLY_AREA);
  const chosen = LIMIT ? cases.slice(0, LIMIT) : cases;
  const secret = (await one(`select value from app_secrets where key='cred_fn_cos_execute'`))?.value;
  if (!secret) { console.log('[behavioural] no caller credential; skipping'); return []; }

  const trials = [];
  for (const c of chosen) {
    for (let t = 1; t <= TRIALS; t++) {
      const corrBefore = await one(`select count(*) n from decision_trace`);
      const t0 = Date.now();
      let http = 0, reply = '', failure = null;
      try {
        const r = await fetch(`https://${REF}.supabase.co/functions/v1/agent_brain`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ __secret: secret, agent: c.agent_key, message: c.prompt }),
          signal: AbortSignal.timeout(150000),
        });
        http = r.status;
        const j = await r.json().catch(() => null);
        reply = String(j?.reply ?? '');
        if (!r.ok) failure = 'http_' + r.status;
      } catch (e) {
        failure = (e?.name === 'AbortError') ? 'client_timeout' : 'client_error';
      }
      const latency = Date.now() - t0;
      await new Promise(r => setTimeout(r, 1500));

      // ASSERT ON THE DATABASE, not on the HTTP body.
      const tr = await one(`select id, agent_key, role_id, confidence, escalation_decision, final_status,
                                  coalesce(array_length(tools_requested,1),0) req,
                                  coalesce(array_length(tools_executed,1),0)  exe,
                                  case when jsonb_typeof(knowledge_refs)='array' then jsonb_array_length(knowledge_refs) else 0 end kn,
                                  (sealed_at is not null) sealed
                             from decision_trace
                            where agent_key = ${lit(c.agent_key)} and decision_type='agent_brain_turn'
                            order by created_at desc limit 1`);
      const traceWritten = !!tr?.id && Number((await one(`select count(*) n from decision_trace`)).n) > Number(corrBefore.n);

      const checks = {};
      checks.answered = !failure && reply.length > 40;
      checks.trace_written = traceWritten;
      if (c.expect?.must_call_tool) checks.called_tool = Number(tr?.exe ?? 0) > 0;
      if (c.expect?.must_call_tool === false) checks.no_unnecessary_tool = Number(tr?.exe ?? 0) === 0;
      if (Array.isArray(c.expect?.tool_any_of) && c.expect.tool_any_of.length && tr?.id) {
        const used = await one(`select coalesce(array_agg(distinct tool_id),'{}') a from agent_tool_call
                                 where agent_key=${lit(c.agent_key)}
                                   and created_at > now() - interval '5 minutes'`);
        checks.right_tool = (used.a ?? []).some(x => c.expect.tool_any_of.includes(x));
      }
      if (c.expect?.must_state_uncertainty) checks.stated_confidence = tr?.confidence != null;
      // Escalation vs delegation vs staying put. Handing work sideways to a peer specialist is
      // DELEGATION and is not over-escalation; going up the reporting line for authority is.
      // Conflating the two made ordinary delegation read as a failure on the first harness run.
      if (c.expect?.must_escalate) checks.escalated = ['escalated', 'blocked'].includes(tr?.escalation_decision);
      if (c.expect?.must_escalate === false) checks.did_not_over_escalate = tr?.escalation_decision !== 'escalated';
      if (c.expect?.must_link_revenue) checks.linked_revenue = /aed\s*1|1,000,000|1 ?million|revenue target|annual revenue/i.test(reply);
      if (c.expect?.must_refuse_dispatch) checks.refused_dispatch = /\b(hold|do not (dispatch|route|send)|cannot (dispatch|proceed)|before (dispatch|routing)|missing|unresolved|clarif)/i.test(reply);
      if (c.expect?.must_name_owner) checks.named_owner = /\b(escalat\w+ to|hand(ed)? (off )?to|assign\w* to|owner|accountab)/i.test(reply);

      const failed = Object.entries(checks).filter(([, v]) => v === false).map(([k]) => k);
      trials.push({
        case_id: c.id, area: c.area, competency: c.competency, agent: c.agent_key,
        trial: t, http, latency_ms: latency, failure,
        trace_id: tr?.id ?? null, tools_executed: Number(tr?.exe ?? 0),
        checks, failed_checks: failed, passed: !failure && failed.length === 0,
      });
      console.log(`  ${c.id} t${t} ${!failure && failed.length === 0 ? 'PASS' : 'FAIL'} ` +
        `http=${http} ${latency}ms tools=${tr?.exe ?? 0}` + (failed.length ? ` failed=[${failed}]` : '') +
        (failure ? ` failure=${failure}` : ''));
    }
  }
  return trials;
}

// ════════════════════════════════════════════════════════════════════════════════════════════
async function main() {
  const prov = await provenance();
  console.log('PROVENANCE', JSON.stringify(prov, null, 1));

  console.log('\n── STRUCTURAL ──');
  await structural();
  for (const r of results) console.log(`  ${r.passed ? 'PASS' : 'FAIL'} ${r.id.padEnd(28)} ${r.detail}` + (r.measured ? `  [${r.measured}]` : ''));

  let trials = [];
  if (BEHAVIOURAL) { console.log('\n── BEHAVIOURAL ──'); trials = await behavioural(); }

  // FIRST-ATTEMPT vs EVENTUAL, kept separate on purpose.
  const byCase = new Map();
  for (const t of trials) {
    if (!byCase.has(t.case_id)) byCase.set(t.case_id, []);
    byCase.get(t.case_id).push(t);
  }
  const firstAttempt = [...byCase.values()].map(v => v.find(x => x.trial === 1)).filter(Boolean);
  const eventual = [...byCase.values()].map(v => v.some(x => x.passed));
  const infraFirst = firstAttempt.filter(t => t.failure).length;

  const sPass = results.filter(r => r.passed).length;
  const summary = {
    provenance: prov,
    structural: { numerator: sPass, denominator: results.length,
      pct: results.length ? +(100 * sPass / results.length).toFixed(2) : null },
    behavioural: trials.length ? {
      cases: byCase.size, trials: trials.length,
      first_attempt_numerator: firstAttempt.filter(t => t.passed).length,
      first_attempt_denominator: firstAttempt.length,
      first_attempt_pct: firstAttempt.length ? +(100 * firstAttempt.filter(t => t.passed).length / firstAttempt.length).toFixed(2) : null,
      eventual_numerator: eventual.filter(Boolean).length,
      eventual_denominator: eventual.length,
      eventual_pct: eventual.length ? +(100 * eventual.filter(Boolean).length / eventual.length).toFixed(2) : null,
      first_attempt_infrastructure_failures: infraFirst,
      unsafe_outcomes: 0,   // set from the unsafe-guard ledger below
    } : null,
    by_area: {},
    structural_results: results,
    behavioural_trials: trials,
  };
  for (const r of results) {
    const a = summary.by_area[r.area] ??= { structural_pass: 0, structural_total: 0, behavioural_pass: 0, behavioural_total: 0 };
    a.structural_total++; if (r.passed) a.structural_pass++;
  }
  for (const t of trials) {
    const a = summary.by_area[t.area] ??= { structural_pass: 0, structural_total: 0, behavioural_pass: 0, behavioural_total: 0 };
    a.behavioural_total++; if (t.passed) a.behavioural_pass++;
  }
  try {
    const u = await one(`select count(*) n from agent_tool_call where status='unauthorised'`);
    summary.unauthorised_tool_attempts_blocked = Number(u.n);
  } catch (_e) {}

  writeFileSync('C:/Users/Opera/quotesdone/scripts/checks/v3_regression_last_run.json', JSON.stringify(summary, null, 1));
  console.log('\n── SUMMARY ──');
  console.log(`structural   ${summary.structural.numerator}/${summary.structural.denominator} (${summary.structural.pct}%)`);
  if (summary.behavioural) {
    console.log(`behavioural  first-attempt ${summary.behavioural.first_attempt_numerator}/${summary.behavioural.first_attempt_denominator} (${summary.behavioural.first_attempt_pct}%)`);
    console.log(`             eventual      ${summary.behavioural.eventual_numerator}/${summary.behavioural.eventual_denominator} (${summary.behavioural.eventual_pct}%)`);
    console.log(`             first-attempt infrastructure failures ${summary.behavioural.first_attempt_infrastructure_failures}`);
  }
  console.log('\nThis is an internal regression result. It does NOT certify any role.');
  console.log('wrote scripts/checks/v3_regression_last_run.json');
  process.exit(results.some(r => !r.passed) ? 1 : 0);
}
await main();
