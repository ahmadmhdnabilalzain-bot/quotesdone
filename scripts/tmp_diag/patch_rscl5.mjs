import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_step_cases_live.mjs';
let s = readFileSync(f, 'utf8');

// THE DRIVE MUST NAME THE OBJECT THE SCENARIO CREATED, or it is a different drive. The coverage
// builder derives business_object_id from the fixture's own parent_refs and records why: without it
// the same estate measured 209 of 257 steps producing an effect where the four-mode drive measured
// 249. The positive arm here omitted it and 25 steps of W04, W05 and W09 answered pd_rule_refused
// while the coverage matrix had them EXECUTED. Same derivation, same source.
const OLD = `  select count(*) into v_e0 from public.phase_d_effect_ledger;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','\${wf}','label','pos-\${step.toLowerCase()}','execution_context','production',
    'reviewer_role_id', coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
      where x.workflow_id='\${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
      order by x.step_id limit 1),'risk_and_governance_manager'),
    'reviewer_candidates', v_cands));`;
const NEW = `  select count(*) into v_e0 from public.phase_d_effect_ledger;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='\${wf}')
   limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id='\${wf}')
         || ':' || (v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','\${wf}','label','pos-\${step.toLowerCase()}','execution_context','production',
    'reviewer_role_id', coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
      where x.workflow_id='\${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
      order by x.step_id limit 1),'risk_and_governance_manager'),
    'reviewer_candidates', v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);`;
if (!s.includes(OLD)) throw new Error('positive drive anchor not found');
s = s.split(OLD).join(NEW);

const OLDD = `declare v jsonb; v_fx jsonb; v_cands jsonb; v_srid bigint; v_actor text; v_out text := '';
        v_e0 bigint; v_e bigint; v_neg text;`;
const NEWD = `declare v jsonb; v_fx jsonb; v_cands jsonb; v_srid bigint; v_actor text; v_out text := '';
        v_e0 bigint; v_e bigint; v_neg text; v_ref_key text; v_boid text;`;
if (!s.includes(OLDD)) throw new Error('positive declare anchor not found');
s = s.split(OLDD).join(NEWD);

// The negative arm drives with a hold and reaches the step either way, but it should name the same
// object for the same reason: a step measured against a different business object is a different
// step.
const OLDN = `    'reviewer_candidates', v_cands, 'hold_at_step_id','\${step}'));`;
const NEWN = `    'reviewer_candidates', v_cands, 'hold_at_step_id','\${step}')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);`;
if (s.includes(OLDN)) {
  s = s.split(OLDN).join(NEWN);
  const OLDN2 = `  v_gbase jsonb; v_rbase jsonb;`;
  s = s.split(OLDN2).join(`  v_gbase jsonb; v_rbase jsonb; v_ref_key text; v_boid text;`);
  const OLDN3 = `  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','\${wf}','label','case-\${step.toLowerCase()}','execution_context','production',`;
  const NEWN3 = `  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='\${wf}')
   limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id='\${wf}')
         || ':' || (v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','\${wf}','label','case-\${step.toLowerCase()}','execution_context','production',`;
  if (!s.includes(OLDN3)) throw new Error('negative drive anchor not found');
  s = s.split(OLDN3).join(NEWN3);
}

writeFileSync(f, s);
console.log('patched');
