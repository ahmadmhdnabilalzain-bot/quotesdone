// rehearse_change_deployment_loop.mjs — ONE deploy.completed, ONE change_deployment run, START TO
// DONE WITH THE PAID MODEL HELD (MASTER_PLAN A1 / §4.2).
//
// The 26 runs parked on 4 Sep proved the workflow could not turn. This proves it can: a single
// deploy.completed event, emitted inside a declared rehearsal window, becomes a workflow_run that
// walks all nine steps and finishes — every step closed with used_llm=false, the deterministic ones
// citing the change_deployment playbook they applied with a sealed decision_trace and a review row.
//
// WHAT IS REAL AND WHAT IS A FIXTURE, said plainly:
//   * The event is a FIXTURE. Its payload carries rehearsal:true and the run tag, so nobody can read
//     it as a record of a deploy that happened. Everything downstream of it is the live machinery:
//     fn_workflow_start_due, fn_workflow_step_claim, fn_apply_playbook, the real edge executors
//     (qa_suite, resilience_ping, knowledge_exam) and fn_workflow_step_sweep.
//   * withRun declares a rehearsal_window first, so fn_watch_failed_runs does not page the founder
//     about rows this run puts in agent_runs.
//   * No paid provider is reached: the founder's hold is in force and every step must report
//     used_llm=false. A step that reports otherwise fails this rehearsal.
//   * The workflow_run and its event are NOT torn down. They are the evidence, and the payload says
//     what they are.
//
//   QD_FIXTURES=1 node scripts/staging/rehearse_change_deployment_loop.mjs
import { withRun, REF, q, jb } from './demo_factory.mjs';
import { mgmtRead, mgmtFixture } from './qd_guard.mjs';

const BUDGET_ROUNDS = Number(process.env.QD_ROUNDS || 40);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const checks = [];
const ok = (name, pass, detail = '') => { checks.push(pass); console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(58)} ${detail}`); };

const secret = (await mgmtRead(REF, `select value from public.app_secrets where key = 'cred_cron_agents'`))[0]?.value;
if (!secret) { console.error('no cred_cron_agents in app_secrets'); process.exit(2); }

// The real dispatcher, at the endpoint and with the credential cron 255 uses.
async function dispatch(limit = 3) {
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/workflow_dispatch`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, limit }) });
  try { return await r.json(); } catch { return { http: r.status }; }
}

await withRun(async (run) => {
  const held = (await mgmtRead(REF,
    `select (public.fn_kernel_paid_provider_gate('anthropic/claude-sonnet-5')->>'allowed')::boolean a`))[0]?.a;
  ok('the paid provider is held before the rehearsal starts', held === false, `allowed=${held}`);

  // 1. THE FIXTURE EVENT, shaped exactly like the one scripts/deploy_functions.mjs emits.
  const payload = {
    ref: REF, functions: ['workflow_dispatch'], count: 1, at: new Date().toISOString(),
    rehearsal: true, run_tag: `qd_run:${run.tag}`,
    note: 'rehearsal of the change_deployment loop; no deploy happened',
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

  // 3. TURN THE LOOP with the three real routines, until the run finishes or the budget is spent.
  let status = 'running', doneSteps = 0;
  for (let i = 1; i <= BUDGET_ROUNDS && status === 'running'; i++) {
    await dispatch(3);
    try { await mgmtFixture(REF, `select public.fn_workflow_step_sweep(5)`, 'sweep'); } catch { /* rate limit */ }
    try { await mgmtFixture(REF, `select public.fn_action_invoke_dispatch(5)`, 'invoke'); } catch { /* rate limit */ }
    await sleep(4000);
    const s = (await mgmtRead(REF,
      `select r.status, (select count(*) from public.workflow_step_run x
                          where x.workflow_run_id = r.id and x.finished_at is not null) fin
         from public.workflow_run r where r.id = ${q(runId)}`))[0];
    status = s?.status; doneSteps = Number(s?.fin ?? 0);
    console.log(`  round ${String(i).padStart(2)}  run ${status}  ${doneSteps}/9 steps finished`);
  }
  ok('the run reached done', status === 'done', `status=${status}, ${doneSteps}/9 steps finished`);

  // 4. WHAT THE RUN ACTUALLY RECORDED.
  const steps = await mgmtRead(REF,
    `select step_no, status, output->>'used_llm' used_llm, output->>'worked_by' worked_by,
            output->>'playbook_record_id' pb, output->>'similarity' sim,
            output->>'decision_trace_id' trace, output->>'review_queue_id' review
       from public.workflow_step_run where workflow_run_id = ${q(runId)} order by step_no`);
  for (const s of steps) {
    console.log(`     step ${s.step_no} ${String(s.status).padEnd(8)} used_llm=${s.used_llm} ${s.worked_by ?? ''} ${s.pb ?? ''} ${s.sim ?? ''}`);
  }
  ok('all nine steps are finished', steps.length === 9 && steps.every((s) => s.status !== 'ready' && s.status !== 'queued'),
     steps.map((s) => s.status).join(','));
  ok('no step used the paid model', steps.every((s) => s.used_llm === 'false'),
     steps.map((s) => s.used_llm).join(','));

  const det = steps.filter((s) => s.pb);
  ok('every deterministic close cites a change_deployment playbook',
     det.length > 0 && det.every((s) => String(s.pb).startsWith('ops-change-deployment-step-')),
     `${det.length} deterministic close(s)`);
  ok('every deterministic close sealed a trace and queued a review',
     det.every((s) => s.trace && s.review), det.map((s) => `${s.step_no}:${s.trace ? 'T' : '-'}${s.review ? 'R' : '-'}`).join(' '));

  const cost = (await mgmtRead(REF,
    `select count(*)::int c from public.ai_cost_log
      where created_at >= now() - interval '30 minutes' and coalesce(estimated_cost_aed,0) > 0`))[0]?.c;
  ok('no paid model call was billed during the rehearsal', Number(cost) === 0, `billed calls in the last 30m=${cost}`);
}, { keep: true });

const failed = checks.filter((c) => !c).length;
console.log(`\n${checks.length - failed}/${checks.length} checks passed`);
process.exit(failed ? 1 : 0);
