import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_step_cases_live.mjs';
let s = readFileSync(f, 'utf8');

// 1. THE LOOP MUST STOP THE MOMENT A CANDIDATE EXECUTES THE STEP. A key whose removal does not
//    refuse lets the handler run to completion and write an effect, and every case after it is then
//    measured against a step run that is finished.
const OLD_LOOP_TAIL = `    if v_neg in ('pd_rule_refused','pd_gate_refused','pd_evidence_absent') then
      v_hit := v_neg; v_gk := v_cand; exit;
    end if;
  end loop;`;
const NEW_LOOP_TAIL = `    if v_neg in ('pd_rule_refused','pd_gate_refused','pd_evidence_absent') then
      v_hit := v_neg; v_gk := v_cand; exit;
    end if;
    -- A CANDIDATE THAT DID NOT REFUSE RAN THE STEP. Removing that key was not load-bearing, and the
    -- handler completed: there is nothing left to remove a key from, so the loop stops here rather
    -- than measuring the remaining candidates against a finished step run.
    if v_neg = 'ACCEPTED' then v_gk := v_cand; exit; end if;
  end loop;`;
if (!s.includes(OLD_LOOP_TAIL)) throw new Error('loop tail anchor not found');
s = s.split(OLD_LOOP_TAIL).join(NEW_LOOP_TAIL);

const OLD_NOHIT = `    v_out := v_out || 'failed_rule_or_gate|no_load_bearing_evidence|false|' || (v_e - v_e1)::text
          || '|no key of this step''s live evidence is read by a predicate that refuses without it~';`;
const NEW_NOHIT = `    v_out := v_out || 'failed_rule_or_gate|'
          || case when v_neg = 'ACCEPTED' then 'evidence_not_load_bearing' else 'no_candidate_key' end
          || '|false|' || (v_e - v_e1)::text
          || '|no key of this step''s live evidence is read by a predicate that refuses without it'
          || case when v_gk is null then '' else '; the last tried was ' || v_gk end || '~';`;
if (!s.includes(OLD_NOHIT)) throw new Error('no-hit anchor not found');
s = s.split(OLD_NOHIT).join(NEW_NOHIT);

// 2. THE POSITIVE GETS ITS OWN TRANSACTION. Five refused calls against one step run leave the run
//    in the state those refusals put it in -- measured on W03: three steps answered the positive
//    with k3_run_not_active. A positive measured after five deliberate refusals is measuring the
//    refusals. It is now a second probe, its own drive, its own scenario, nothing varied.
const a = s.indexOf(`  -- ---- positive: the kernel's own door, nothing varied`);
const b = s.indexOf(`  raise exception 'CASE<<%>>', v_out;
end $case$;\`;
}`);
if (a < 0 || b < 0) throw new Error('positive block bounds not found');
s = s.slice(0, a) + `  raise exception 'CASE<<%>>', v_out;
end $case$;\`;
}

// THE POSITIVE AND ITS REPLAY, IN THEIR OWN TRANSACTION AND THEIR OWN DRIVE.
function queryPositive(step, wf) {
  return \`do $pos$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_srid bigint; v_actor text; v_out text := '';
        v_e0 bigint; v_e bigint; v_neg text;
begin
  perform set_config('app.phase_d_hold_step','\${step}', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','pos-\${step.toLowerCase()}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','pos-\${step.toLowerCase()}','execution_context','test',
    'for_workflow', case when '\${wf}' = 'W12' then '\${wf}' else null end));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','\${wf}','label','pos-\${step.toLowerCase()}','execution_context','production',
    'reviewer_role_id', coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
      where x.workflow_id='\${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
      order by x.step_id limit 1),'risk_and_governance_manager'),
    'reviewer_candidates', v_cands, 'hold_at_step_id','\${step}'));
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  perform set_config('app.phase_d_hold_step','', true);
  if v_srid is null then
    raise exception 'CASE<<NO_OPEN_STEP|%>>', coalesce(v->'stopped'->>'refused_with','-');
  end if;
  select accountable_role_id into v_actor from public.phase_c_workflow_step_run where step_run_id = v_srid;
  select count(*) into v_e0 from public.phase_d_effect_ledger;

  begin
    perform public.fn_phase_d_dispatch_step(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id', v_actor,
      'opened_by_kind','step_case_probe','opened_by_ref','positive',
      'idempotency_key','case-pos-\${step}'));
    select coalesce(nullif(d.refusal_code,''), d.outcome) into v_neg
      from public.phase_d_dispatch d where d.step_run_id = v_srid
       and d.opened_by_ref = 'positive' order by d.dispatch_id desc limit 1;
    v_neg := coalesce(v_neg, 'NO_DISPATCH_ROW');
  exception when others then v_neg := \${CODE}; end;
  select count(*) into v_e from public.phase_d_effect_ledger;
  v_out := 'positive|' || v_neg || '|'
        || case when v_neg = 'EXECUTED' and (v_e - v_e0) = 1 then 'true' else 'false' end
        || '|' || (v_e - v_e0)::text
        || '|the kernel dispatch answered ' || v_neg || ' and the ledger holds '
        || (v_e - v_e0)::text || ' effect(s) for this step run~';

  begin
    perform public.fn_phase_d_dispatch_step(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id', v_actor,
      'opened_by_kind','step_case_probe','opened_by_ref','duplicate',
      'idempotency_key','case-pos-\${step}'));
    v_neg := 'REPLAYED';
  exception when others then v_neg := \${CODE}; end;
  v_out := v_out || 'duplicate|' || v_neg || '|'
        || case when (select count(*) from public.phase_d_effect_ledger) - v_e0 <= 1 then 'true' else 'false' end
        || '|' || ((select count(*) from public.phase_d_effect_ledger) - v_e0)::text
        || '|a replay of the same step run left '
        || ((select count(*) from public.phase_d_effect_ledger) - v_e0)::text || ' effect(s)~';
  raise exception 'CASE<<%>>', v_out;
end $pos$\`;
}
` + s.slice(b + `  raise exception 'CASE<<%>>', v_out;
end $case$;\`;
}`.length);

// 3. The worker runs both probes per step and concatenates their reports.
const OLDW = `    const raw = await emit(query(s.step_id, s.workflow_id), 'CASE');
    results.push([s.step_id, raw]);`;
const NEWW = `    const neg = await emit(query(s.step_id, s.workflow_id), 'CASE');
    const pos = await emit(queryPositive(s.step_id, s.workflow_id), 'CASE');
    results.push([s.step_id, (neg.startsWith('ERROR:') || neg.startsWith('NO_OPEN_STEP') ? neg : neg)
                             + (pos.startsWith('ERROR:') || pos.startsWith('NO_OPEN_STEP') ? '' : pos)]);`;
if (!s.includes(OLDW)) throw new Error('worker anchor not found');
s = s.split(OLDW).join(NEWW);

writeFileSync(f, s);
console.log('patched');
