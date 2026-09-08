// Diagnostic: drive one workflow exactly as the deliverable builder does, and dump the FIRST
// refused dispatch together with the step context the handler was given. Aborted transaction.
//   node scripts/tmp_diag/first_refusal.mjs W03
import { sql } from '../lib/db.mjs';

const WF = process.argv[2] || 'W03';
const US = String.fromCharCode(31);

const q = `
do $emit$
declare
  v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_ref_key text; v_boid text;
  r record; v_out text := '';
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build','label','diag-first-refusal'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';

  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','diagfr-${WF.toLowerCase()}','execution_context','test',
    'for_workflow', case when '${WF}' = 'W12' then '${WF}' else null end));

  select coalesce(
    (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
      where s.workflow_id = '${WF}' and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
      order by s.step_id limit 1), 'risk_and_governance_manager') into v_rev;

  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id = '${WF}')
   limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id='${WF}')
         || ':' || (v_fx->'parent_refs'->>v_ref_key) else null end;

  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${WF}','label','diagfr-${WF.toLowerCase()}','execution_context','production',
    'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);

  v_out := 'parent_refs=' || coalesce(v_fx->>'parent_refs','?') || chr(31)
        || 'stages_created=' || coalesce(v_fx->>'stages_created','?')
        || ' not_created=' || coalesce(v_fx->>'stages_not_created','?') || chr(31)
        || 'business_object_id=' || coalesce(v_boid,'(null)') || chr(31);

  for r in
    select d.step_id, d.outcome, d.refusal_code, left(d.reason, 700) as reason,
           d.unresolved_keys::text as unres, d.step_run_id
      from public.phase_d_dispatch d where d.workflow_id = '${WF}' order by d.dispatch_id limit 12
  loop
    v_out := v_out || r.step_id || ' ' || coalesce(r.outcome,'?') || ' '
          || coalesce(r.refusal_code,'-') || ' unresolved=' || coalesce(r.unres,'{}')
          || ' :: ' || coalesce(r.reason,'') || chr(31);
  end loop;

  raise exception 'DIAG%', v_out;
end $emit$;`;

try { await sql(q); console.error('no raise'); }
catch (err) {
  const m = String(err?.message ?? err);
  const at = m.indexOf('DIAG');
  let got = m.slice(at + 4).replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\"/g, '"').replace(/\\n/g, '\n');
  const c = got.indexOf('\nCONTEXT:'); if (c >= 0) got = got.slice(0, c);
  for (const line of got.split(US)) if (line.trim()) console.log(line);
}
