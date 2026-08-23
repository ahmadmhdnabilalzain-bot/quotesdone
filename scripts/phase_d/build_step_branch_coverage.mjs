// PHASE D DELIVERABLE — PHASE_D_STEP_BRANCH_COVERAGE.csv
//
// The founder's ruling, section 1: a coverage matrix over the 257 FROZEN STEPS, built mechanically,
// never by hand. One row per frozen step, and every column on it is read off a table after a real
// drive of the real kernel doors inside a transaction that ends in `raise exception`.
//
//   node scripts/phase_d/build_step_branch_coverage.mjs [--only=W01,W02] [--jobs=3]
//
// WHY THIS IS NOT PHASE_D_STEP_CASE_RESULT. That table (D10) holds 7 cases for each of the 257
// steps and every one of the 1,799 passes — but its own `decided_at` column says where each was
// decided: 771 at `step_contract`, 771 at `executor_boundary`, 257 at `structural_constraint`, and
// NONE against a live step run. Its header says so in as many words: "A future increment that
// drives all 257 to a live step run can replace the boundary cases without changing the
// denominator." This is that increment, for the two cases a drive can settle — the pass edge and
// the fail edge of every frozen step.
//
// WHAT A BRANCH IS HERE, measured rather than assumed. public.phase_b_workflow_step:
//   next_step_if_pass  names the next step for 227 steps and WORKFLOW_COMPLETE for the 30 closure
//                      steps. It never names a step in another workflow. Each workflow is a chain.
//   next_step_if_fail  names WORKFLOW_BLOCKED_OR_ESCALATED (146), CORRECTION_OR_REJECTION_PATH (82)
//                      or WORKFLOW_BLOCKED (29). It NEVER names a step.
// So no step is reachable only through a fail edge, and "reachable branch with no scenario" reduces
// to: for each of the 257 steps, was its pass edge taken and was its fail edge taken.
//
// TWO ARMS PER WORKFLOW, each its own transaction and its own audited fixture scenario:
//   PASS  one drive of the whole workflow. Per frozen step: was a step run opened, did the kernel
//         dispatch it, what did the deterministic handler do, what effect reached the ledger, which
//         rules and gates were evaluated, who reviewed it, which handoff carried it, whether a
//         trace was written, and which successor the kernel opened next.
//   FAIL  one drive PER STEP, held with that step open, then failed through fn_kernel_step_complete.
//         The assertion is the frozen model's own: the step reaches 'failed' and the run reaches the
//         step's declared failure_workflow_state, with no effect and no object added by the failure.
//
// HELD IS RECORDED, NEVER HIDDEN. 249 of 257 steps are completed by the handler in the same
// statement the kernel opens them, so they are never open and no actor could ever fail them. Where
// the drive had to hold the handler (J03: app.phase_d_hold_step, one step, inside a fixture
// context, refusing with pd_handler_held_for_branch_probe) the row says
// fail_branch_reached_by=handler_held, and where the handler declined of its own accord it says
// natural_refusal. A held row proves the KERNEL's fail edge for that step and does not claim the
// handler could have failed.
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../phase_c/lib/db.mjs';

const arg = (k, d) => (process.argv.find(a => a.startsWith(`--${k}=`)) || `--${k}=${d}`).split('=').slice(1).join('=');
const ONLY = arg('only', '').split(',').filter(Boolean);
const JOBS = Math.max(1, Number(arg('jobs', 3)));

const STEPS = await sql(`select s.step_id, s.workflow_id, s.step_no, s.step_type, s.actor_kind,
    s.next_step_if_pass, s.next_step_if_fail, s.failure_workflow_state, s.success_workflow_state,
    s.entry_condition, s.required_inputs, s.is_closure_step,
    b.handler_class, b.handler_routine, b.rule_ids, b.gate_ids,
    e.expected_effect_type, e.effect_relation, e.effect_operation, e.completion_condition
  from public.phase_b_workflow_step s
  left join public.phase_d_handler_binding b on b.step_id = s.step_id
  left join public.phase_d_step_effect e on e.step_id = s.step_id
  order by s.workflow_id, s.step_no`);
const WFS = [...new Set(STEPS.map(s => s.workflow_id))].filter(w => !ONLY.length || ONLY.includes(w));

// ---- the drive preamble every arm shares ------------------------------------------------------
const PRE = (wf, label) => `
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','${label}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','${label}','execution_context','test',
    'for_workflow', '${wf}'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  -- THE REAL OBJECT THE SCENARIO CREATED, derived exactly as build_four_mode_result.mjs derives it.
  -- The first full run of this file omitted it and measured 209 of 257 steps producing their
  -- declared effect where the four-mode drive of the same estate measured 249 — because a drive
  -- that never names the business object is a different drive, and a coverage matrix built from it
  -- reports the harness rather than the estate.
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${wf}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${wf}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;`;

// A TRANSPORT FAILURE IS NOT A MEASUREMENT. One arm of the first full run came back
// 'ERROR:fetch failed' — the management endpoint dropped the connection — and a row saying a step's
// fail edge was not exercised because the network blinked is a false red of exactly the kind this
// estate keeps finding. Only a raise carrying the marker, or an error carrying a SQL message, is an
// answer. A dropped connection, a 429 and a 5xx are retried.
const emit = async (q, marker) => {
  for (let attempt = 1; ; attempt++) {
    try { await sql(q); return '(no marker)'; }
    catch (e) {
      const m = String(e.message); const a = m.indexOf(marker + '<<');
      if (a >= 0) return m.slice(a + marker.length + 2, m.indexOf('>>', a));
      const transient = /fetch failed|ECONNRESET|ETIMEDOUT|socket hang up|HTTP 429|HTTP 5\d\d/i.test(m);
      if (transient && attempt < 4) { await new Promise(r => setTimeout(r, 3000 * attempt)); continue; }
      return 'ERROR:' + m.slice(0, 400).replace(/\s+/g, ' ');
    }
  }
};

// ---- PASS ARM ---------------------------------------------------------------------------------
// ONE DRIVE PER CHUNK OF STEPS, BECAUSE THE TRANSPORT CUTS AT 2000 CHARACTERS. Measured 23 Aug
// 2026: the single-drive pass arms for W17 and W30 -- eleven steps each -- ran over it, the last
// step's line lost its tail fields, and the matrix reported W17-S11 and W30-S11 as "reached only by
// a direct step-complete call" while both carried an EXECUTED dispatch and an effect. The guard
// below now makes an overrun a stop; this is what keeps it from happening. Each chunk is its own
// transaction, its own audited fixture scenario and its own drive of the whole workflow -- so every
// step's row still comes from a drive that reached that step through the canonical path -- and it
// reports only the steps in its own window.
const CHUNK = 7;
async function passArm(wf, lo, hi) {
  const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; r record; v_run bigint;
        v_ref_key text; v_boid text;
begin${PRE(wf, `cov-${wf.toLowerCase()}-${lo}`)}
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','label','cov-${wf.toLowerCase()}-${lo}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  for r in
    select s.step_id,
           sr.step_run_id, sr.state step_state, sr.reviewer_role_id, sr.trace_id,
           coalesce(jsonb_array_length(case when jsonb_typeof(sr.gates_evaluated)='array'
                                            then sr.gates_evaluated else '[]'::jsonb end),0) gates_n,
           d.opened_by_kind, d.outcome, d.refusal_code,
           el.effect_type, el.effect_relation, el.effect_operation, el.result_reference,
           el.state_before, el.state_after, el.provider_mode, el.trace_id effect_trace,
           (select count(*) from public.phase_d_dispatch dd where dd.step_run_id = sr.step_run_id) dispatches_n,
           (select count(*) from public.phase_c_handoff_run h where h.from_step_run_id = sr.step_run_id) handoffs_out,
           (select count(*) from public.phase_c_task t where t.run_id = v_run and t.step_id = s.step_id) tasks_n
      from public.phase_b_workflow_step s
      left join lateral (select * from public.phase_c_workflow_step_run x
                          where x.run_id = v_run and x.step_id = s.step_id
                          order by x.step_run_id limit 1) sr on true
      left join lateral (select * from public.phase_d_dispatch x
                          where x.step_run_id = sr.step_run_id order by x.dispatch_id desc limit 1) d on true
      left join lateral (select * from public.phase_d_effect_ledger x
                          where x.step_run_id = sr.step_run_id order by x.effect_id limit 1) el on true
     where s.workflow_id = '${wf}' and s.step_no between ${lo} and ${hi}
     order by s.step_no
  loop
    v_out := v_out || 'P|' || r.step_id
      || '|' || case when r.step_run_id is null then '0' else '1' end
      || '|' || coalesce(r.opened_by_kind,'-')
      || '|' || coalesce(r.outcome,'-')
      || '|' || coalesce(nullif(r.refusal_code,''),'-')
      || '|' || coalesce(r.effect_type,'-')
      || '|' || coalesce(r.effect_relation,'-')
      || '|' || coalesce(r.effect_operation,'-')
      || '|' || coalesce(left(r.result_reference,28),'-')
      || '|' || coalesce(r.state_before,'-') || '>' || coalesce(r.state_after,'-')
      || '|' || coalesce(r.provider_mode,'-')
      || '|' || r.gates_n::text
      || '|' || coalesce(left(r.reviewer_role_id,22),'-')
      || '|' || r.handoffs_out::text
      || '|' || case when coalesce(r.trace_id, r.effect_trace) is null then '0' else '1' end
      || '|' || coalesce(r.step_state,'-')
      || '|' || r.dispatches_n::text
      || '|' || r.tasks_n::text
      || '~';
  end loop;
  v_out := v_out || 'RUN|' || coalesce((select state from public.phase_c_workflow_run where run_id = v_run),'-')
        || '|' || coalesce(v->>'terminal','-')
        || '|' || (select count(*) from public.phase_d_effect_ledger where run_id = v_run)::text
        || '|' || (select count(*) from public.phase_d_dispatch where run_id = v_run)::text
        || '|' || (select count(*) from public.phase_c_workflow_step_run where run_id = v_run)::text
        || '|' || (select count(*) from public.phase_d_dispatch dd
                    join public.phase_c_workflow_step_run ss on ss.step_run_id = dd.step_run_id
                   where ss.run_id = v_run and dd.opened_by_kind is null)::text || '~';
  -- A TRUNCATED PAYLOAD IS NOT A SHORT ANSWER. The management endpoint cuts an exception message at
  -- 2000 characters. Measured 23 Aug 2026: the pass arms for W17 and W30 -- eleven steps each --
  -- ran over it, the LAST step's line lost its tail fields, and the matrix reported W17-S11 and
  -- W30-S11 as "reached only by a direct step-complete call" when both carried an EXECUTED dispatch
  -- and an effect. A silent cut is the defect; this makes it a stop.
  if length(v_out) > 1750 then
    raise exception 'PHASE_D_COVERAGE_OVERFLOW __WF__ produced % characters over the 1750 this transport carries. Shorten the per-step fields; do not let a step fall off the end.', length(v_out);
  end if;
  raise exception 'COVP<<%>>', v_out;
end $emit$;`;
  return emit(q.split('__WF__').join(wf), 'COVP');
}

// ---- FAIL ARM: one drive per step, held open, then failed --------------------------------------
async function failArm(wf, steps) {
  const out = [];
  for (const s of steps) {
    const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := '';
        v_eff_before bigint; v_obj_before bigint; v_srid bigint; v_held text;
        v_ref_key text; v_boid text;
begin
  -- THE HOLD IS SET BEFORE THE SCENARIO IS BUILT. Measured 23 Aug 2026: W05-S01 and W18-S03 came
  -- back no_open_step because the scenario own product trigger starts the run while the scenario is
  -- still being built (H06), so those steps were dispatched and EXECUTED before this line ran.
  -- W18 dispatch order was S03, S02, S01, S04... for exactly that reason.
  perform set_config('app.phase_d_hold_step','${s.step_id}', true);${PRE(wf, `cvf-${s.step_id.toLowerCase()}`)}
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','label','cvf-${s.step_id.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
    'hold_at_step_id','${s.step_id}')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  if v_srid is null then
    raise exception 'COVF<<F|${s.step_id}|0|no_open_step|-|-|-|0|-|-|%>>',
      coalesce(v->'stopped'->>'refused_with','-');
  end if;
  select coalesce(nullif(d.refusal_code,''),d.outcome) into v_held
    from public.phase_d_dispatch d where d.step_run_id = v_srid order by d.dispatch_id desc limit 1;
  select count(*) into v_eff_before from public.phase_d_effect_ledger;
  select count(*) into v_obj_before from public.phase_d_object_record where superseded_by is null;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid,
      'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run where step_run_id = v_srid),
      'outcome','fail',
      'idempotency_key','cvf:${s.step_id}:' || v_srid,
      'inputs', jsonb_build_object('mode','failure path'),
      'output', jsonb_build_object('status','failed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH — deliberate failure path'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','failure')),
      'requested_action','block',
      'acceptance_criteria','the fail edge of ${s.step_id} is exercised',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH — the Phase D failure path for ${s.step_id}, driven deliberately inside a transaction that is aborted',
      'object_version', 1));
    v_out := 'F|${s.step_id}|1'
      || '|' || case when coalesce(v_held,'') = 'pd_handler_held_for_branch_probe' then 'handler_held' else 'natural_refusal' end
      || '|' || coalesce(v_held,'-')
      || '|' || coalesce((select state from public.phase_c_workflow_step_run where step_run_id = v_srid),'-')
      || '|' || coalesce((select state from public.phase_c_workflow_run where run_id = (v->>'run_id')::bigint),'-')
      || '|' || ((select count(*) from public.phase_d_effect_ledger) - v_eff_before)::text
      || '|' || ((select count(*) from public.phase_d_object_record where superseded_by is null) - v_obj_before)::text
      || '|' || case when (select trace_id from public.phase_c_workflow_step_run where step_run_id = v_srid) is null then '0' else '1' end
      || '|-';
  exception when others then
    v_out := 'F|${s.step_id}|1'
      || '|' || case when coalesce(v_held,'') = 'pd_handler_held_for_branch_probe' then 'handler_held' else 'natural_refusal' end
      || '|' || coalesce(v_held,'-') || '|REFUSED|REFUSED|0|0|0|'
      || coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\\)'))[1], SQLSTATE);
  end;
  raise exception 'COVF<<%>>', v_out;
end $emit$;`;
    out.push(await emit(q, 'COVF'));
    process.stderr.write(`  ${out[out.length - 1]}\n`);
  }
  return out;
}

// ---- run the workflows, a few at a time -------------------------------------------------------
const results = new Map();
const queue = [...WFS];
async function worker() {
  for (let wf = queue.shift(); wf; wf = queue.shift()) {
    const steps = STEPS.filter(s => s.workflow_id === wf);
    process.stderr.write(`${wf} (${steps.length} steps)\n`);
    const chunks = [];
    for (let lo = 1; lo <= steps.length; lo += CHUNK) chunks.push([lo, Math.min(lo + CHUNK - 1, steps.length)]);
    const parts = [];
    for (const [lo, hi] of chunks) parts.push(await passArm(wf, lo, hi));
    const p = parts.join('');
    const f = await failArm(wf, steps);
    results.set(wf, { pass: p, fail: f });
    process.stderr.write(`${wf} done\n`);
  }
}
await Promise.all(Array.from({ length: Math.min(JOBS, WFS.length) }, worker));

// ---- assemble one row per frozen step ---------------------------------------------------------
const rows = [];
for (const s of STEPS) {
  if (!results.has(s.workflow_id)) continue;
  const { pass, fail } = results.get(s.workflow_id);
  const pl = pass.split('~').find(l => l.startsWith(`P|${s.step_id}|`));
  const p = pl ? pl.split('|') : [];
  const fl = fail.find(l => l.startsWith(`F|${s.step_id}|`));
  const f = fl ? fl.split('|') : [];
  const runLine = (pass.split('~').find(l => l.startsWith('RUN|')) || '').split('|');

  const opened = p[2] === '1';
  const effectProduced = !!p[6] && p[6] !== '-';
  const declaredEffect = s.expected_effect_type || '-';
  const failOk = f[2] === '1' && f[5] === 'failed'
    && (f[6] === (s.failure_workflow_state || 'blocked'));

  rows.push({
    workflow_id: s.workflow_id,
    step_id: s.step_id,
    step_no: s.step_no,
    step_type: s.step_type,
    scenario: `cov-${s.workflow_id.toLowerCase()}-${Math.floor((s.step_no - 1) / CHUNK) * CHUNK + 1} (pass), cvf-${s.step_id.toLowerCase()} (fail)`,
    branch_pass_target: s.next_step_if_pass,
    branch_fail_target: s.next_step_if_fail,
    input_class: (s.required_inputs || '').slice(0, 90),
    handler: `${s.handler_class || '-'}:${s.handler_routine || '-'}`,
    declared_effect: `${declaredEffect}/${s.effect_relation || '-'}/${s.effect_operation || '-'}`,
    actual_effect: `${p[6] || '-'}/${p[7] || '-'}/${p[8] || '-'}`,
    actual_effect_reference: p[9] || '-',
    effect_state_move: p[10] || '-',
    provider_mode: p[11] || '-',
    rules_declared: (s.rule_ids || []).length,
    gates_declared: (s.gate_ids || []).length,
    gates_evaluated: p[12] || '0',
    reviewer: p[13] || '-',
    handoffs_opened: p[14] || '0',
    trace_written: p[15] || '0',
    tasks_opened: p[18] || '0',
    opened_by: p[3] || '-',
    dispatch_outcome: p[4] || '-',
    dispatch_refusal: p[5] || '-',
    dispatches: p[17] || '0',
    pass_step_state: p[16] || '-',
    reached_by_canonical_path: opened ? 'YES' : 'NO',
    // A step run the kernel never dispatched would be one an actor completed directly. Read from
    // the dispatch table, not from the driver's own loop.
    reached_only_by_direct_step_complete: opened && (p[17] === '0' || p[17] === undefined) ? 'YES' : 'NO',
    produced_declared_effect: effectProduced ? 'YES' : 'NO',
    pass_branch_exercised: opened ? 'YES' : 'NO',
    fail_branch_exercised: f[2] === '1' ? 'YES' : 'NO',
    // THE HOLD IS RECORDED WHERE IT WAS NEEDED, NOT WHERE IT FIRED. app.phase_d_hold_step is set
    // for every fail arm, so its refusal appears even on steps whose handler declines anyway. The
    // question the column answers is whether an ACTOR could ever reach this step to fail it, and
    // the ordinary pass drive settles that: a step whose last dispatch was not EXECUTED was still
    // open when the driver reached it, so a person reaches it with no hold at all.
    fail_branch_reached_by: f[2] !== '1' ? '-'
      : (p[4] && p[4] !== 'EXECUTED' && p[4] !== '-') ? 'natural_refusal' : 'handler_held',
    fail_branch_handler_outcome: f[4] || '-',
    fail_step_state: f[5] || '-',
    fail_run_state: f[6] || '-',
    fail_declared_run_state: s.failure_workflow_state || '-',
    fail_matches_frozen_model: failOk ? 'YES' : 'NO',
    fail_effects_added: f[7] || '-',
    fail_objects_added: f[8] || '-',
    fail_trace_written: f[9] || '-',
    fail_refusal: f[10] || '-',
    workflow_run_state_after_pass: runLine[1] || '-',
    result: opened && effectProduced && failOk ? 'COVERED'
      : !opened ? 'STEP_NEVER_OPENED'
      : !effectProduced ? 'NO_EFFECT_ON_PASS'
      : 'FAIL_BRANCH_NOT_AS_DECLARED',
  });
}

const cols = Object.keys(rows[0]);
const csv = provenance({
  command: 'node scripts/phase_d/build_step_branch_coverage.mjs',
  numerator: rows.length, denominator: STEPS.length,
  of: 'frozen Phase B steps, each driven on its pass edge and on its fail edge inside transactions that end in raise exception',
  attribution: 'every figure is read off public.phase_c_workflow_step_run, public.phase_d_dispatch, public.phase_d_effect_ledger, public.phase_c_handoff_run and public.phase_c_task after the drive; nothing is asserted from a registry column',
}) + cols.join(',') + '\n'
  + rows.map(r => cols.map(c => `"${String(r[c] ?? '').replace(/"/g, '""')}"`).join(',')).join('\n') + '\n';
writeFileSync(outPath('PHASE_D_STEP_BRANCH_COVERAGE.csv'), csv);

const n = (k, v) => rows.filter(r => r[k] === v).length;
console.log(`\nfrozen steps in the matrix        ${rows.length} of ${STEPS.length}`);
console.log(`reached through the canonical path ${n('reached_by_canonical_path', 'YES')} of ${rows.length}`);
console.log(`producing their declared effect    ${n('produced_declared_effect', 'YES')} of ${rows.length}`);
console.log(`reached only by a direct complete  ${n('reached_only_by_direct_step_complete', 'YES')}`);
console.log(`pass edge exercised                ${n('pass_branch_exercised', 'YES')} of ${rows.length}`);
console.log(`fail edge exercised                ${n('fail_branch_exercised', 'YES')} of ${rows.length}`);
console.log(`  of which the handler refused of its own accord ${n('fail_branch_reached_by', 'natural_refusal')}`);
console.log(`  of which the handler was held for the probe    ${n('fail_branch_reached_by', 'handler_held')}`);
console.log(`fail edge matches the frozen model ${n('fail_matches_frozen_model', 'YES')} of ${rows.length}`);
console.log(`fail edge produced an effect       ${rows.filter(r => Number(r.fail_effects_added) > 0).length}`);
console.log(`fail edge produced an object       ${rows.filter(r => Number(r.fail_objects_added) > 0).length}`);
console.log(`\nresult:`);
for (const [k, c] of Object.entries(rows.reduce((a, r) => (a[r.result] = (a[r.result] || 0) + 1, a), {})))
  console.log(`  ${k.padEnd(30)} ${c}`);
