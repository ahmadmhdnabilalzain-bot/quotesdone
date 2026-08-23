import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_step_cases_live.mjs';
let s = readFileSync(f, 'utf8');

// ---- 1. the positive is the ordinary drive, not a held-then-dispatched step run ----------------
// Holding a step and then dispatching it by hand is not the canonical path: W03-S06 answered
// pd_evidence_absent that way and EXECUTED on an ordinary drive. The positive now drives the
// workflow exactly as the coverage matrix does and reads the outcome the kernel recorded.
const a = s.indexOf('function queryPositive(step, wf) {');
const b = s.indexOf('const results = [];');
if (a < 0 || b < 0) throw new Error('queryPositive bounds not found');
const NEW = `function queryPositive(step, wf) {
  return \`do $pos$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_srid bigint; v_actor text; v_out text := '';
        v_e0 bigint; v_e bigint; v_neg text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','pos-\${step.toLowerCase()}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','pos-\${step.toLowerCase()}','execution_context','test',
    'for_workflow', case when '\${wf}' = 'W12' then '\${wf}' else null end));
  select count(*) into v_e0 from public.phase_d_effect_ledger;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','\${wf}','label','pos-\${step.toLowerCase()}','execution_context','production',
    'reviewer_role_id', coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
      where x.workflow_id='\${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
      order by x.step_id limit 1),'risk_and_governance_manager'),
    'reviewer_candidates', v_cands));
  select sr.step_run_id, sr.accountable_role_id into v_srid, v_actor
    from public.phase_c_workflow_step_run sr
   where sr.run_id = (v->>'run_id')::bigint and sr.step_id = '\${step}'
   order by sr.step_run_id limit 1;
  if v_srid is null then
    raise exception 'CASE<<NO_OPEN_STEP|the drive never opened this step>>';
  end if;
  select coalesce(nullif(d.refusal_code,''), d.outcome) into v_neg
    from public.phase_d_dispatch d where d.step_run_id = v_srid order by d.dispatch_id desc limit 1;
  v_neg := coalesce(v_neg, 'NO_DISPATCH_ROW');
  select count(*) into v_e from public.phase_d_effect_ledger
   where step_run_id = v_srid;
  v_out := 'positive|' || v_neg || '|'
        || case when v_neg = 'EXECUTED' and v_e = 1 then 'true' else 'false' end
        || '|0|the canonical drive answered ' || v_neg || ' and the ledger holds '
        || v_e::text || ' effect(s) for this step run~';

  -- THE REPLAY: the same step run, the same door, the same idempotency key the kernel used.
  begin
    perform public.fn_phase_d_dispatch_step(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id', v_actor,
      'opened_by_kind','step_case_probe','opened_by_ref','duplicate',
      'idempotency_key','case-dup-\${step}'));
    v_neg := 'REPLAYED';
  exception when others then v_neg := \${CODE}; end;
  v_out := v_out || 'duplicate|' || v_neg || '|'
        || case when (select count(*) from public.phase_d_effect_ledger where step_run_id = v_srid) <= 1
                then 'true' else 'false' end
        || '|0|a replay of the same step run left '
        || (select count(*) from public.phase_d_effect_ledger where step_run_id = v_srid)::text
        || ' effect(s) on it~';
  raise exception 'CASE<<%>>', v_out;
end $pos$;\`;
}

`;
s = s.slice(0, a) + NEW + s.slice(b);

// ---- 2. the load-bearing key is found by PURE evaluation before the handler is invoked ----------
const la = s.indexOf(`  v_hit := null; v_gk := null;
  for v_cand in`);
const lb = s.indexOf(`  v_e1 := v_e;

  -- ---- malformed_output`);
if (la < 0 || lb < 0) throw new Error('failed_rule_or_gate bounds not found');
const NEWFG = `  -- THE LOAD-BEARING KEY IS FOUND BY PURE EVALUATION FIRST. Invoking the handler with a key that is
  -- NOT load-bearing does not refuse -- it EXECUTES the step, which both spends the case and
  -- contaminates every measurement after it. So each candidate is first tested against the step's
  -- APPLICABLE gates and rules, which are pure functions of the evidence and write nothing, and only
  -- the key that actually flips one of them is then removed from a real handler call.
  v_hit := null; v_gk := null;
  for v_cand in
    select k from (
      select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
       where gc.gate_id = any (coalesce((select b2.gate_ids from public.phase_d_handler_binding b2
                                          where b2.step_id = '\${step}'),'{}'))
         and (select ga.applies from public.fn_phase_d_gate_applies(gc.gate_id, '\${step}') ga)
      union
      select unnest(re.required_context) k from public.phase_d_rule_enforcement re
       where re.rule_id = any (coalesce((select b3.rule_ids from public.phase_d_handler_binding b3
                                          where b3.step_id = '\${step}'),'{}'))
         and (select ra.applies from public.fn_phase_d_rule_applies(re.rule_id, '\${step}') ra)) q
     where k <> 'step_id' and v_ctx ? k order by k
  loop
    if exists (
      select 1 from public.phase_d_gate_contract gc
       where gc.gate_id = any (coalesce((select b4.gate_ids from public.phase_d_handler_binding b4
                                          where b4.step_id = '\${step}'),'{}'))
         and (select ga.applies from public.fn_phase_d_gate_applies(gc.gate_id, '\${step}') ga)
         and coalesce((select ge.passed from public.fn_phase_d_gate_evaluate(gc.gate_id, v_ctx) ge), false)
         and not coalesce((select ge2.passed from public.fn_phase_d_gate_evaluate(gc.gate_id, v_ctx - v_cand) ge2), false))
       or exists (
      select 1 from public.phase_d_rule_enforcement re
       where re.rule_id = any (coalesce((select b5.rule_ids from public.phase_d_handler_binding b5
                                          where b5.step_id = '\${step}'),'{}'))
         and (select ra.applies from public.fn_phase_d_rule_applies(re.rule_id, '\${step}') ra)
         and coalesce((select rc.ok from public.fn_phase_d_rule_check(re.rule_id, v_ctx) rc), false)
         and not coalesce((select rc2.ok from public.fn_phase_d_rule_check(re.rule_id, v_ctx - v_cand) rc2), false))
    then
      v_gk := v_cand; exit;
    end if;
  end loop;

  if v_gk is null then
    v_out := v_out || 'failed_rule_or_gate|no_load_bearing_evidence|false|0'
          || '|every applicable gate and rule of this step answers the same with and without each '
          || 'key the live context resolved, so removing one proves nothing~';
  else
    begin
      perform public.fn_phase_d_handler_execute(jsonb_build_object(
        'step_run_id', v_srid, 'actor_role_id', v_actor,
        'idempotency_key','case-fg-\${step}',
        'inputs', v_full, 'context', v_ctx - v_gk, 'gate_evidence', v_ctx - v_gk,
        'execution_context','production'));
      v_hit := 'ACCEPTED';
    exception when others then v_hit := \${CODE}; end;
    select count(*) into v_e from public.phase_d_effect_ledger;
    v_out := v_out || 'failed_rule_or_gate|' || v_hit || '|'
          || case when v_hit in ('pd_rule_refused','pd_gate_refused','pd_evidence_absent')
                  then 'true' else 'false' end
          || '|' || (v_e - v_e1)::text
          || '|removing ' || v_gk || ' from the live evidence flips an applicable predicate, and the '
          || 'real handler then answers ' || v_hit || '~';
  end if;
  select count(*) into v_e from public.phase_d_effect_ledger;
`;
s = s.slice(0, la) + NEWFG + s.slice(lb);

writeFileSync(f, s);
console.log('patched');
