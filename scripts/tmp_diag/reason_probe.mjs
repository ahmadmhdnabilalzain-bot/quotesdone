// Full refusal reasons for one workflow, one refusal code. Aborted transaction.
import { sql } from '../phase_c/lib/db.mjs';

const CODE = process.argv[2];
const DRIVE = `
do $emit$
declare
  v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_ref_key text; v_boid text; v_out text := '';
  r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build', 'label','rp-__WF__'));
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','rp-__WF__', 'execution_context','test',
    'for_workflow', case when '__WF__' = 'W12' then '__WF__' else null end));
  select coalesce(
    (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
      where s.workflow_id = '__WF__' and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
      order by s.step_id limit 1),
    'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='__WF__') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id='__WF__')
         || ':' || (v_fx->'parent_refs'->>v_ref_key) else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','__WF__','label','rp-__WF__','execution_context','production',
    'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);
  for r in
    select d.step_id, replace(replace(left(coalesce(d.reason,''),700), chr(10),' '), chr(13),' ') as reason
      from public.phase_d_dispatch d
     where d.workflow_id = '__WF__' and d.refusal_code = '__CODE__'
     order by d.dispatch_id limit 2
  loop
    v_out := v_out || chr(30) || r.step_id || ' :: ' || r.reason;
  end loop;
  raise exception 'REASONS%', left(v_out, 1500);
end $emit$;
`;

for (const id of process.argv.slice(3)) {
  try { await sql(DRIVE.replaceAll('__WF__', id).replaceAll('__CODE__', CODE)); }
  catch (err) {
    const msg = String(err?.message ?? err);
    const at = msg.indexOf('REASONS');
    if (at < 0) { console.log(`${id}: FAILED\n${msg.slice(0, 600)}\n`); continue; }
    let got = msg.slice(at + 'REASONS'.length)
      .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
      .replace(/\\"/g, '"').replace(/\\n/g, '\n');
    const ctx = got.indexOf('\nCONTEXT:'); if (ctx >= 0) got = got.slice(0, ctx);
    console.log(`=== ${id} [${CODE}] ===`);
    got.split('').filter((x) => x.trim()).forEach((x) => console.log('  ' + x));
    console.log('');
  }
}
