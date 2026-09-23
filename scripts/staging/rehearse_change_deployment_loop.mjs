// rehearse_change_deployment_loop.mjs — ONE deploy.completed, ONE change_deployment run, START TO
// DONE WITH THE PAID MODEL HELD, EVERY STEP PERFORMED BY AN EXECUTOR (MASTER_PLAN A1 / §4.2).
//
// 4 Sep: the 26 parked runs proved the workflow could not turn; the same evening 28 runs reached done
// with steps 1 and 9 closed by the dispatcher applying a playbook — 1 distinct deliverable across 28
// different deploys, no baseline read, no grade. 5 Sep: steps 1, 8 and 9 have a deterministic executor
// (fn_change_deployment_execute, kind rpc) that reads THIS run's payload, captures a baseline, records
// the promotion and its parity verdict, defers until the monitoring window has elapsed, and grades.
// This proves that chain end to end on production with no model call.
//
// WHAT IS REAL AND WHAT IS A FIXTURE, said plainly:
//   * The event is a FIXTURE. Its payload carries rehearsal:true and the run tag, so nobody can read
//     it as a record of a deploy that happened, and it deliberately carries NO `verified` block — no
//     deploy was verified — so step 8 must report parity 'not_in_payload', never a verdict it invented.
//     Everything downstream is the live machinery: fn_workflow_start_due, fn_workflow_step_sweep,
//     fn_action_invoke_rpc / fn_action_invoke_dispatch / fn_action_invoke_collect, the real edge
//     executors (qa_suite, resilience_ping, knowledge_exam), and the dispatcher (workflow_dispatch),
//     which is called every round to prove it no longer takes a step an rpc executor owns.
//   * The baseline and the grade are read from production's own agent_runs / kernel traces for the
//     slug in the payload (workflow_dispatch) — real numbers over real windows.
//   * Step 9 waits: the executor defers until 60 minutes after the payload's `at`. The loop sleeps
//     until the deferral's not_before instead of hammering the API, so a full run takes ~65-75 minutes.
//   * withRun declares a rehearsal_window first, so fn_watch_failed_runs does not page the founder
//     about rows this run puts in agent_runs.
//   * No paid provider is reached: the founder's hold is in force and every step must report used_llm=false.
//   * The workflow_run and its event are NOT torn down. They are the evidence, and the payload says
//     what they are.
//
//   QD_FIXTURES=1 node scripts/staging/rehearse_change_deployment_loop.mjs
import { withRun, REF, q, jb } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';

const BUDGET_MS = Number(process.env.QD_BUDGET_MINUTES || 110) * 60000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const checks = [];
const ok = (name, pass, detail = '') => { checks.push(pass); console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(62)} ${detail}`); };

const secret = (await mgmtRead(REF, `select value from public.app_secrets where key = 'cred_cron_agents'`))[0]?.value;
if (!secret) { console.error('no cred_cron_agents in app_secrets'); process.exit(2); }

// The real dispatcher, at the endpoint and with the credential cron 255 uses.
async function dispatch(limit = 3) {
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/workflow_dispatch`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, limit }) });
  try { return await r.json(); } catch { return { http: r.status }; }
}
const kernel = async (stmt, where) => { try { await mgmtFixture(REF, stmt, where); } catch { /* 429: next round */ } };

await withRun(async (run) => {
  const held = (await mgmtRead(REF,
    `select (public.fn_kernel_paid_provider_gate('anthropic/claude-sonnet-5')->>'allowed')::boolean a`))[0]?.a;
  ok('the paid provider is held before the rehearsal starts', held === false, `allowed=${held}`);

  // 1. THE FIXTURE EVENT, shaped like the one scripts/deploy_functions.mjs emits — minus `verified`.
  const payload = {
    ref: REF, functions: ['workflow_dispatch'], count: 1, at: new Date().toISOString(),
    rehearsal: true, run_tag: `qd_run:${run.tag}`,
    note: 'rehearsal of the change_deployment loop; no deploy happened, nothing was verified',
  };
  await mgmtFixture(REF,
    `select public.fn_emit('deploy.completed', 'deploy', ${q(payload.at)}, 'rehearse_change_deployment_loop', ${jb(payload)})`,
    'deploy.completed rehearsal');
  const ev = (await mgmtRead(REF,
    `select id from public.company_event where event_type='deploy.completed'
       and payload->>'run_tag' = 'qd_run:${run.tag}' order by id desc limit 1`))[0]?.id;
  ok('deploy.completed emitted inside the rehearsal window', !!ev, `event_id=${ev}`);

  // 2. THE LIVE BRIDGE turns it into a run. Nothing here names change_deployment; the workflow's own
  //    trigger_event does.
  await mgmtFixture(REF, `select public.fn_workflow_start_due(1440)`, 'workflow_start_due');
  const runId = (await mgmtRead(REF,
    `select id from public.workflow_run
      where workflow_key='change_deployment' and trigger_event_id=${Number(ev)} limit 1`))[0]?.id;
  ok('a change_deployment run started from that event', !!runId, `run_id=${runId}`);
  if (!runId) return;

  // 3. TURN THE LOOP with the real routines until the run finishes or the budget is spent. The
  //    dispatcher is called first every round: the claim must now leave steps 1, 8, 9 alone.
  const t0 = Date.now();
  let status = 'running', doneSteps = 0, round = 0, dispatcherTookOurs = 0;
  while (Date.now() - t0 < BUDGET_MS && status === 'running') {
    round++;
    const d = await dispatch(3);
    for (const w of (d?.detail?.worked || [])) if (String(w.run_id) === String(runId)) dispatcherTookOurs++;
    await kernel(`select public.fn_workflow_step_sweep(5)`, 'sweep');
    await kernel(`select public.fn_action_invoke_dispatch(5)`, 'invoke edge');
    await kernel(`select public.fn_action_invoke_rpc(5)`, 'invoke rpc');
    await kernel(`select public.fn_action_invoke_collect()`, 'collect');
    await sleep(4000);
    const s = (await mgmtRead(REF,
      `select r.status, r.current_step,
              (select count(*) from public.workflow_step_run x where x.workflow_run_id = r.id and x.finished_at is not null) fin,
              (select x.response->>'not_before' from public.action_execution x
                 join public.workflow_step_run sr on sr.id = x.workflow_step_run_id
                where sr.workflow_run_id = r.id and x.status = 'queued' and x.response->>'invoker' = 'deferred'
                order by x.created_at desc limit 1) not_before
         from public.workflow_run r where r.id = ${q(runId)}`))[0];
    status = s?.status; doneSteps = Number(s?.fin ?? 0);
    const nb = s?.not_before ? new Date(s.not_before).getTime() - Date.now() : 0;
    console.log(`  round ${String(round).padStart(3)}  run ${status}  step ${s?.current_step}  ${doneSteps}/9 finished`
      + (nb > 0 ? `  (step 9 deferred; ${Math.ceil(nb / 60000)} min to go)` : ''));
    if (nb > 0) await sleep(Math.min(nb + 2000, 60000));
  }
  ok('the run reached done', status === 'done', `status=${status}, ${doneSteps}/9 steps finished after ${round} rounds`);
  ok('the dispatcher took none of this run\'s executor-owned steps', dispatcherTookOurs === 0, `taken=${dispatcherTookOurs}`);

  // 4. WHAT THE RUN ACTUALLY RECORDED.
  const steps = await mgmtRead(REF,
    `select step_no, status, output->>'used_llm' used_llm, output->>'worked_by' worked_by,
            output->>'playbook_record_id' pb,
            output->'result'->0 as res
       from public.workflow_step_run where workflow_run_id = ${q(runId)} order by step_no`);
  for (const s of steps) {
    const r = s.res || {};
    console.log(`     step ${s.step_no} ${String(s.status).padEnd(8)} used_llm=${s.used_llm} ${s.worked_by ?? ''}`
      + (r.kind ? `  ${r.kind}: ${String(r.outcome || '').slice(0, 140)}` : ''));
  }
  ok('all nine steps are done', steps.length === 9 && steps.every((s) => s.status === 'done'), steps.map((s) => s.status).join(','));
  ok('no step used the paid model', steps.every((s) => s.used_llm === 'false'), steps.map((s) => s.used_llm).join(','));
  ok('no step was closed advisory by a playbook', steps.every((s) => !s.pb), steps.filter((s) => s.pb).map((s) => s.step_no).join(',') || 'none');
  ok('every step was settled from an executor', steps.every((s) => String(s.worked_by || '').startsWith('executor:')),
     steps.map((s) => s.worked_by).join(','));

  const by = (n) => steps.find((s) => Number(s.step_no) === n);
  const s1 = by(1)?.res || {}, s8 = by(8)?.res || {}, s9 = by(9)?.res || {};
  ok('step 1 captured a baseline for the slug in the payload',
     by(1)?.worked_by === 'executor:fn_change_deployment_execute' && s1.kind === 'baseline'
       && Array.isArray(s1.functions) && s1.functions[0] === 'workflow_dispatch' && Number.isInteger(s1.baseline?.failures),
     `baseline failures=${s1.baseline?.failures} over ${s1.window?.hours}h ending ${s1.at}`);
  ok('step 8 recorded the promotion and an honest parity verdict',
     s8.kind === 'promote' && s8.promoted === true && s8.parity?.verdict === 'not_in_payload',
     `parity=${s8.parity?.verdict}`);
  ok('step 9 graded over a window of at least 60 minutes against step 1',
     s9.kind === 'grade' && ['improved', 'no_change', 'worse'].includes(s9.grade)
       && Number(s9.window?.hours) >= 0.99 && s9.baseline?.source === 'step 1 of this run',
     `grade=${s9.grade} window=${s9.window?.hours}h post=${s9.post?.failures} baseline=${s9.baseline?.failures} (${s9.baseline?.source})`);
  ok('step 9 never reversed anything itself', s9.reversal_performed === false,
     `rollback_recommended=${s9.rollback_recommended} task=${s9.rollback_task_id}`);
  const deferred = (await mgmtRead(REF,
    `select coalesce(max((x.response->>'deferrals')::int), 0) d from public.action_execution x
       join public.workflow_step_run sr on sr.id = x.workflow_step_run_id
      where sr.workflow_run_id = ${q(runId)} and sr.step_no = 9`))[0]?.d;
  ok('step 9 was deferred by the invoker before it graded', Number(deferred) >= 1, `deferrals=${deferred}`);

  const cost = (await mgmtRead(REF,
    `select count(*)::int c from public.ai_cost_log
      where occurred_at >= ${q(new Date(t0).toISOString())} and coalesce(cost_aed,0) > 0`))[0]?.c;
  ok('no paid model call was billed during the rehearsal', Number(cost) === 0, `billed calls since start=${cost}`);
}, { keep: true });

const failed = checks.filter((c) => !c).length;
console.log(`\n${checks.length - failed}/${checks.length} checks passed`);
process.exit(failed ? 1 : 0);
