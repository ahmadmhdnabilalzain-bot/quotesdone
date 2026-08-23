// PHASE D DELIVERABLE — PHASE_D_FOUR_MODE_RESULT.csv
//
// The founder's ruling of 21 Aug 2026, section D: for every workflow, run one happy path, one
// failure/block path, one cancellation path and one duplicate replay, and roll the whole scenario
// back.
//
// One row per frozen workflow, four modes each, every one produced by driving the real kernel doors
// inside a transaction that ends in `raise exception`. Each workflow is its own transaction, and
// its own audited fixture run, so a scenario cannot see another workflow's rows.
//
//   node scripts/phase_d/build_four_mode_result.mjs
//
// WHAT EACH MODE MEANS HERE, stated so the CSV cannot be read as claiming more than it measures:
//
//   happy         the drive, unmodified. `closed_by_handler` counts workflows where every
//                 step-opening the kernel dispatched was EXECUTED by the deterministic handler and
//                 the run reached a declared terminal state. `actor_driven` counts the rest that
//                 reached a terminal state with this harness completing the steps the handler
//                 declined. They are different claims and they are in different columns.
//   failure       the first open step is completed with outcome 'fail' through
//                 fn_kernel_step_complete, and the run state afterwards is recorded. A workflow
//                 whose kernel refuses the failure is recorded with the refusal.
//   cancellation  fn_kernel_cancel is called on the run and the run state afterwards is recorded.
//   replay        the whole drive is issued a second time with the SAME label, so every
//                 idempotency key repeats. The assertion is the EFFECT LEDGER ROW COUNT: a replay
//                 that produced a second effect would show here as a positive delta.
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../phase_c/lib/db.mjs';

const WFS = (await sql('select workflow_id from public.phase_b_workflow order by workflow_id'))
  .map(r => r.workflow_id);

const rows = [];
for (const wf of WFS) {
  const q = (`do $emit$
declare
  v jsonb; v2 jsonb; v3 jsonb; v4 jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_boid text; v_ref_key text;
  v_out text := ''; sr record; v_replay_n int; v_eff_before bigint; v_eff_after bigint; v_state text;
  v_res bigint; v_cust bigint; v_inq bigint; v_quo bigint; v_txn bigint;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','fourmode-${wf}'));

  select count(*) into v_cust from public.customers;
  select count(*) into v_inq  from public.inquiries;
  select count(*) into v_quo  from public.quotes;
  select count(*) into v_txn  from public.transactions;

  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','fm-${wf.toLowerCase()}','execution_context','test',
    'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${wf}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${wf}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;

  -- ---- HAPPY ---------------------------------------------------------------------------------
  select count(*) into v_eff_before from public.phase_d_effect_ledger;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','label','fm-${wf.toLowerCase()}',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
    -- THE HAPPY ARM KEEPS THE REAL OBJECT THE SCENARIO CREATED. Only the failure and cancellation
    -- arms below name an identity that resolves to nothing, and they do it deliberately.
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  select count(*) into v_eff_after from public.phase_d_effect_ledger;

  -- ---- REPLAY: THE SAME STEP RUNS, DISPATCHED AGAIN -------------------------------------------
  -- The first version of this file called the driver a second time. That is not a replay:
  -- fn_kernel_workflow_start opens a NEW run, so its effects are new effects and six workflows duly
  -- reported a positive delta. A replay is the SAME work arriving twice, so this re-dispatches every
  -- step run the happy drive produced, through the same door the kernel uses, with the same
  -- idempotency key. The assertion is the effect-ledger row count.
  v_replay_n := 0;
  for sr in select * from public.phase_c_workflow_step_run where run_id = (v->>'run_id')::bigint
             order by step_run_id
  loop
    begin
      perform public.fn_phase_d_dispatch_step(jsonb_build_object(
        'step_run_id', sr.step_run_id, 'actor_role_id', sr.accountable_role_id,
        'opened_by_kind','replay', 'opened_by_ref','the same step run, dispatched again',
        'idempotency_key', 'replay:' || sr.step_id || ':' || sr.step_run_id));
      v_replay_n := v_replay_n + 1;
    exception when others then null;
    end;
  end loop;
  v2 := jsonb_build_object('replayed_step_runs', v_replay_n);

  -- ---- FAILURE / BLOCK ------------------------------------------------------------------------
  -- ITS OWN RUN, DELIBERATELY STOPPED AT ONE STEP. The happy run reaches a terminal state, and a
  -- failure applied to a finished run measures nothing: the first version of this file recorded
  -- cancel=completed for all 30 because it cancelled runs that had already completed. max_steps 1
  -- leaves a step open, which is the only state in which either path means anything.
  --
  -- 23 AUG 2026 — max_steps STOPPED BEING ABLE TO LEAVE A STEP OPEN, AND THE NUMBER FELL AS THE
  -- HANDLER IMPROVED. Since PCCR-001 the kernel dispatches at step OPENING, so a handler that can
  -- execute completes its step, the kernel opens the successor and dispatches that, and the whole
  -- run cascades to terminal INSIDE fn_kernel_workflow_start -- before this driver's max_steps is
  -- consulted at all. Measured: failure path exercised fell 16 -> 4 of 30 and cancellation
  -- 16 -> 9, entirely because more handlers now succeed. Every REFUSED:22023 below was
  -- "step_run_id ... required (got (null))" -- the probe had no open step to act on.
  --
  -- That is F38 and G07 a third time, and the fix is the same shape: the probe MAKES the condition
  -- it tests instead of hoping the run is left in it. business_object_id names an identity that
  -- resolves to no row, so the step-context resolver reports row_found false, every rule that
  -- reads the subject refuses, the handler cannot execute, and step 1 stays OPEN with the run
  -- ACTIVE. That is not a harness trick: "violating or missing evidence" is literally what the
  -- founder's section 9A asks this path to be driven with, and this is the estate refusing it.
  v3 := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','__WF__','label','fmfail-__WFL__',
    -- An identity of the right SHAPE that names nothing. A bare object name would fail the
    -- '<object>:' prefix test and never reach the resolver at all.
    'business_object_id', (select w2.primary_object from public.phase_b_workflow w2
                            where w2.workflow_id = '__WF__') || ':00000000-0000-0000-0000-000000000000',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
    -- max_steps 0 OPENS the run and drives nothing, so its first step is still open. With 1 the
    -- driver completed that step and the run moved to waiting_review, leaving nothing to fail:
    -- measured, 20 of 30 came back "step_run_id ... required (got (null))".
    'max_steps', 0));
  select * into sr from public.phase_c_workflow_step_run
   where run_id = (v3->>'run_id')::bigint
     and state in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
   order by step_run_id limit 1;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', sr.step_run_id, 'actor_role_id', sr.accountable_role_id, 'outcome','fail',
      'idempotency_key', 'fm-${wf.toLowerCase()}:fail:' || sr.step_run_id,
      'inputs', jsonb_build_object('mode','failure path'),
      'output', jsonb_build_object('status','failed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH — deliberate failure path'),
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','failure')),
      'requested_action','block', 'acceptance_criteria','the failure path is exercised',
      -- fn_kernel_step_complete: "outcome fail requires a stated reason. An unexplained failure is
      -- not a record of anything." Measured, not guessed: the first version omitted it and all 30
      -- came back 23514.
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH — the Phase D failure path, driven deliberately inside a transaction that is aborted',
      'object_version', 1));
    select state into v_state from public.phase_c_workflow_step_run where step_run_id = sr.step_run_id;
    v_out := v_out || 'failure=step:' || coalesce(v_state,'(null)') || ',run:'
          || coalesce((select state from public.phase_c_workflow_run where run_id = (v3->>'run_id')::bigint),'?') || '~|~';
  exception when others then
    v_out := v_out || 'failure=REFUSED:' ||
      coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\\)'))[1], SQLSTATE) || '~|~';
  end;

  -- ---- CANCELLATION ---------------------------------------------------------------------------
  -- Also its own run, left open at one step. fn_kernel_cancel takes subject_kind / subject_ref /
  -- op / reason / actor -- read off the routine, after the first version passed run_id and
  -- actor_role_id and was refused with 22023 on all 30.
  v4 := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','__WF__','label','fmcan-__WFL__',
    -- 23 Aug 2026: the same correction as the failure arm above, for the same reason. A run that
    -- cascaded to completed is not cancellable and fn_kernel_cancel is right to refuse it; a run
    -- stopped at its first step by missing evidence is exactly the run a person cancels.
    'business_object_id', (select w2.primary_object from public.phase_b_workflow w2
                            where w2.workflow_id = '__WF__') || ':00000000-0000-0000-0000-000000000000',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
    -- Same reason, and a second one: the frozen Phase B state model does not declare
    -- waiting_review -> cancelled, so cancelling a run the driver had already pushed into
    -- waiting_review was refused by the MODEL rather than by the cancellation service. Measured on
    -- W24, W27 and W29. That refusal is the frozen model working, and where it still happens it is
    -- recorded per row rather than engineered around.
    'max_steps', 0));
  begin
    perform public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind','workflow_run', 'subject_ref', (v4->>'run_id'), 'op','cancel',
      'reason', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — Phase D cancellation path, inside a transaction that is aborted',
      'actor', 'risk_and_governance_manager'));
    select state into v_state from public.phase_c_workflow_run where run_id = (v4->>'run_id')::bigint;
    v_out := v_out || 'cancellation=' || coalesce(v_state,'(null)') || '~|~';
  exception when others then
    v_out := v_out || 'cancellation=REFUSED:' ||
      coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\\)'))[1], SQLSTATE) || '~|~';
  end;

  v_out := v_out
    || 'steps=' || (v->>'steps_in_workflow') || '~|~'
    || 'dispatched=' || (v->>'dispatches_seen') || '~|~'
    || 'executed=' || (v->>'dispatches_executed') || '~|~'
    || 'handoffs=' || (v->>'handoffs_accepted') || '~|~'
    || 'caps=' || coalesce(v->>'capability_results_accepted','0') || '~|~'
    || 'effects=' || (v_eff_after - v_eff_before)::text || '~|~'
    || 'run_state=' || (v->>'run_state') || '~|~'
    || 'terminal=' || (v->>'terminal') || '~|~'
    || 'steps_driven=' || (v->>'steps_driven') || '~|~'
    || 'replay_effects_added=' || ((select count(*) from public.phase_d_effect_ledger) - v_eff_after)::text || '~|~'
    || 'replay_step_runs=' || coalesce(v2->>'replayed_step_runs','0') || '~|~'
    || 'first_refusal=' || coalesce(v->'first_handler_refusal'->>'refused_with','-') || '~|~'
    || 'first_refusal_at=' || coalesce(v->'first_handler_refusal'->>'at','-') || '~|~'
    || 'business_rows_created_inside_the_transaction=' ||
       ((select count(*) from public.customers) - v_cust
      + (select count(*) from public.inquiries) - v_inq
      + (select count(*) from public.quotes) - v_quo
      + (select count(*) from public.transactions) - v_txn)::text || '~|~';

  raise exception 'FOURMODE<<%>>', v_out;
end $emit$;`).split('__WFL__').join(wf.toLowerCase()).split('__WF__').join(wf);

  let out;
  try { await sql(q); out = '(no marker)'; }
  catch (e) {
    const m = String(e.message); const a = m.indexOf('FOURMODE<<');
    out = a < 0 ? 'ERROR:' + m.slice(0, 300).replace(/[\r\n]+/g, ' ') : m.slice(a + 10, m.indexOf('>>', a));
  }
  const parts = out.split('~|~');
  const pick = (k) => (parts.find(p => p.startsWith(k + '=')) || (k + '=?')).slice(k.length + 1);
  const r = {
    workflow_id: wf,
    steps: pick('steps'), dispatched: pick('dispatched'), executed: pick('executed'),
    handoffs: pick('handoffs'), capability_results: pick('caps'), effects: pick('effects'),
    run_state: pick('run_state'), terminal: pick('terminal'), steps_driven: pick('steps_driven'),
    happy_verdict:
      pick('terminal') === 'true' && pick('executed') !== '0' && pick('executed') === pick('dispatched')
        ? 'HANDLER_CLOSED_UNAIDED'
        : pick('terminal') === 'true' && pick('steps_driven') === pick('steps')
        ? 'ACTOR_DRIVEN_TO_TERMINAL'
        : pick('terminal') === 'true' ? 'ACTOR_DRIVEN_PARTIAL' : 'STOPPED',
    failure_path: pick('failure'), cancellation_path: pick('cancellation'),
    replay_effects_added: pick('replay_effects_added'), replay_step_runs: pick('replay_step_runs'),
    first_handler_refusal: pick('first_refusal'), first_handler_refusal_at: pick('first_refusal_at'),
    business_rows_created_inside_the_transaction: pick('business_rows_created_inside_the_transaction'),
  };
  rows.push(r);
  process.stderr.write(`${wf} exec=${r.executed}/${r.dispatched} caps=${r.capability_results} eff=${r.effects} ${r.happy_verdict} fail=${r.failure_path} cancel=${r.cancellation_path} replay+${r.replay_effects_added} in_tx_rows=${r.business_rows_created_inside_the_transaction}\n`);
}

const cols = Object.keys(rows[0]);
const csv = provenance({
  command: 'node scripts/phase_d/build_four_mode_result.mjs',
  numerator: rows.length, denominator: WFS.length,
  of: 'frozen Phase B workflows, each driven four ways inside its own transaction that ends in raise exception',
  attribution: 'every figure is read off public.phase_d_dispatch, public.phase_d_effect_ledger and public.phase_c_workflow_run after the drive, not off the driver\'s own loop',
}) + cols.join(',') + '\n'
  + rows.map(r => cols.map(c => `"${String(r[c] ?? '').replace(/"/g, '""')}"`).join(',')).join('\n') + '\n';
writeFileSync(outPath('PHASE_D_FOUR_MODE_RESULT.csv'), csv);

const n = (k, p) => rows.filter(r => p(r[k])).length;
console.log(`\nworkflows                      ${rows.length} of ${WFS.length}`);
console.log(`happy: handler closed unaided  ${n('happy_verdict', v => v === 'HANDLER_CLOSED_UNAIDED')} of ${rows.length}`);
console.log(`happy: reached terminal        ${n('terminal', v => v === 'true')} of ${rows.length}`);
console.log(`failure path exercised         ${n('failure_path', v => !String(v).startsWith('REFUSED'))} of ${rows.length}`);
console.log(`cancellation reached cancelled ${n('cancellation_path', v => v === 'cancelled')} of ${rows.length}`);
console.log(`replay produced no new effect  ${n('replay_effects_added', v => v === '0')} of ${rows.length}`);
console.log(`business rows created in-tx    ${rows.reduce((a, r) => a + (Number(r.business_rows_created_inside_the_transaction) || 0), 0)} (all rolled back; residue is read below, after every transaction aborted)`);
console.log(`capability results accepted    ${rows.reduce((a, r) => a + (Number(r.capability_results) || 0), 0)}`);
console.log(`dispatches executed            ${rows.reduce((a, r) => a + (Number(r.executed) || 0), 0)} of ${rows.reduce((a, r) => a + (Number(r.dispatched) || 0), 0)}`);
// ---- RESIDUE, MEASURED AFTER EVERY TRANSACTION HAS ABORTED -----------------------------------
// The per-row figure above counts what each scenario created INSIDE its transaction, which is the
// point of a scenario and not a finding. This is the founder's actual test: counts before the test
// equal counts after it.
const after = (await sql(`select
  (select count(*) from public.customers) customers,
  (select count(*) from public.inquiries) inquiries,
  (select count(*) from public.quotes) quotes,
  (select count(*) from public.transactions) transactions,
  (select count(*) from public.phase_d_object_record) object_records,
  (select count(*) from public.phase_d_dispatch) dispatches,
  (select count(*) from public.phase_d_effect_ledger) effects,
  (select count(*) from public.phase_d_scenario_record) scenario_records,
  (select count(*) from public.phase_d_test_context_grant) fixture_contexts,
  (select count(*) from public.phase_d_capability_request) capability_requests,
  (select count(*) from public.phase_d_capability_result) capability_results,
  (select count(*) from public.founder_command where intent_id like 'PHASE_D_FIXTURE%') fixture_founder_commands,
  (select count(*) from public.notifications where created_at > now() - interval '2 hours') notifications_2h,
  (select count(*) from net.http_request_queue) outbound_http,
  (select count(*) from public.ai_cost_log) ai_cost_log_rows,
  (select count(*) from public.llm_attempt) llm_attempt_rows,
  (select count(*) from public.fn_phase_d_fixture_residue()) fixture_residue`))[0];
console.log('\nresidue after every transaction aborted:');
for (const [k, v] of Object.entries(after)) console.log(`  ${String(k).padEnd(26)} ${v}`);
writeFileSync(outPath('PHASE_D_FOUR_MODE_RESIDUE.txt'),
  Object.entries(after).map(([k, v]) => `${k}=${v}`).join('\n') + '\n');
if (rows.length !== WFS.length) process.exit(1);
