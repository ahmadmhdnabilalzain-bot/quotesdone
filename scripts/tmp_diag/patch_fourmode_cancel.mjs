import { readFileSync, writeFileSync } from 'node:fs';
const p = 'scripts/phase_d/build_four_mode_result.mjs';
let s = readFileSync(p, 'utf8');
const rep = (o, n) => { const c = s.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 70)}`); s = s.replace(o, n); };

// 1. cut the cancellation arm out of the main probe.
const START = `  -- ---- CANCELLATION ---------------------------------------------------------------------------`;
const END = `  v_out := v_out
    || 'steps=' || (v->>'steps_in_workflow') || '~|~'`;
const a = s.indexOf(START), b = s.indexOf(END);
if (a < 0 || b < 0 || b < a) throw new Error('cancellation block not found');
s = s.slice(0, a) + `  -- ---- CANCELLATION IS ITS OWN TRANSACTION ----------------------------------------------------
  -- 23 Aug 2026. It used to run here, on its own run inside this same transaction, and it measured
  -- the FAILURE arm as much as itself: both runs hang off one founder command, the failure arm
  -- moves that command to 'failed', and fn_kernel_cancel then reports
  --   {"ok": false, "from": "failed", "to": "cancelled", "error": "transition_not_permitted"}
  -- and leaves the run active -- for a run in 'active', from which phase_b_workflow_transition
  -- declares active -> cancelled. Measured on W01, W04 and W24 after the hold landed.
  --
  -- fn_kernel_cancel deriving the command from the run, and refusing the run on the command's
  -- state model, is a real defect and it is written up as PCCR-004: fn_kernel_cancel is a FROZEN
  -- Phase C subject (canonical_cancellation_service) and changing it needs the founder's approval
  -- through the same door PCCR-001 to PCCR-003 used. It is not changed here.
  --
  -- What is changed is this harness, which had no business coupling two modes through one command.
  -- The cancellation arm is a separate transaction with its own audited fixture scenario, below.

` + s.slice(b);

// 2. add the separate probe and merge its result.
rep(`  let out;
  try { await sql(q); out = '(no marker)'; }`,
`  // ---- CANCELLATION, ITS OWN TRANSACTION AND ITS OWN SCENARIO ---------------------------------
  const qc = (\`do $emit$
declare
  v4 jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_state text; v_out text := '';
  v_can_by text; v_first_step text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','fourmode-cancel-__WF__'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','fmcan-__WFL__','execution_context','test',
    'for_workflow', case when '__WF__' = 'W12' then '__WF__' else null end));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='__WF__' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;

  v_can_by := 'first_open_step';
  v4 := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','__WF__','label','fmcan-__WFL__',
    'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
    'hold_at_first_open_step', true));
  if nullif(v4->>'held_step_run_id','') is null then
    v_can_by := 'handler_held_on_step_1';
    v_first_step := (select ws.step_id from public.phase_b_workflow_step ws
                      where ws.workflow_id = '__WF__' order by ws.step_no limit 1);
    perform set_config('app.phase_d_hold_step', v_first_step, true);
    v4 := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','__WF__','label','fmcan2-__WFL__',
      'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
      'hold_at_step_id', v_first_step));
    perform set_config('app.phase_d_hold_step', '', true);
  end if;
  begin
    perform public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind','workflow_run', 'subject_ref', (v4->>'run_id'), 'op','cancel',
      'reason', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — Phase D cancellation path, inside a transaction that is aborted',
      'actor', 'risk_and_governance_manager'));
    select state into v_state from public.phase_c_workflow_run where run_id = (v4->>'run_id')::bigint;
    v_out := 'cancellation=' || coalesce(v_state,'(null)') || '~|~';
  exception when others then
    v_out := 'cancellation=REFUSED:' ||
      coalesce((regexp_match(SQLERRM,'\\\\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\\\\)'))[1], SQLSTATE) || '~|~';
  end;
  v_out := v_out || 'cancellation_reached_by=' || coalesce(v_can_by,'-') || '~|~'
        || 'cancellation_held_at=' || coalesce(v4->>'held_step_id','-') || '~|~';
  raise exception 'FOURMODECAN<<%>>', v_out;
end $emit$;\`).split('__WFL__').join(wf.toLowerCase()).split('__WF__').join(wf);

  let out;
  try { await sql(q); out = '(no marker)'; }`);

rep(`  const parts = out.split('~|~');`,
`  let outc;
  try { await sql(qc); outc = '(no marker)'; }
  catch (e) {
    const m = String(e.message); const a2 = m.indexOf('FOURMODECAN<<');
    outc = a2 < 0 ? 'ERROR:' + m.slice(0, 300).replace(/[\\r\\n]+/g, ' ') : m.slice(a2 + 13, m.indexOf('>>', a2));
  }
  const parts = (out + outc).split('~|~');`);

writeFileSync(p, s);
console.log('patched');
