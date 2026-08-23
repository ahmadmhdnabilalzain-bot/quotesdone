// Diagnostic: drive each frozen workflow through the kernel doors in an aborted transaction and
// dump EVERY phase_d_dispatch row it produced, so the refusal work-list is measured, not guessed.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const RS = '';
const US = '';

const DRIVE = `
do $emit$
declare
  v_fx jsonb; v jsonb; v_rev text; v_cands jsonb; v_out text := '';
  v_ref_key text; v_boid text; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_deliverable_build', 'label','census-__WF__'));

  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';

  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label', 'census-__WF__', 'execution_context','test',
    'for_workflow', case when '__WF__' = 'W12' then '__WF__' else null end));

  select coalesce(
    (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
      where s.workflow_id = '__WF__' and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
      order by s.step_id limit 1),
    'risk_and_governance_manager') into v_rev;

  select st.contributes_ref into v_ref_key
    from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id = '__WF__')
   limit 1;
  v_boid := case
    when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id = '__WF__')
         || ':' || (v_fx->'parent_refs'->>v_ref_key)
    else null end;

  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id', '__WF__', 'label','census-__WF__',
    'execution_context','production',
    'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands)
    || case when v_boid is null then '{}'::jsonb
            else jsonb_build_object('business_object_id', v_boid) end);

  for r in
    select d.step_id, d.outcome, coalesce(d.refusal_code,'') as code, coalesce((select string_agg(distinct m[1], ' ') from regexp_matches(coalesce(d.reason,''), '(BR-[0-9]+|GATE-[0-9]+|k[0-9]_[a-z_]+)', 'g') m), '') as ids,
           replace(replace(left(coalesce(d.reason,''),70), chr(10),' '), chr(13),' ') as reason
      from public.phase_d_dispatch d
     where d.workflow_id = '__WF__'
     order by d.dispatch_id
  loop
    v_out := v_out || chr(30) || concat_ws(chr(31), '__WF__', r.step_id, r.outcome, r.code, r.ids, r.reason);
  end loop;

  raise exception 'CENSUS%', v_out;
end $emit$;
`;

const ids = (await sql('select workflow_id from public.phase_b_workflow order by workflow_id')).map((r) => r.workflow_id);
const out = [];
for (const id of ids) {
  let got = null;
  try {
    await sql(DRIVE.replaceAll('__WF__', id));
    console.error(`${id}: the probe did not raise`);
    process.exit(1);
  } catch (err) {
    const msg = String(err?.message ?? err);
    const at = msg.indexOf('CENSUS');
    if (at < 0) { console.error(`${id} failed before reporting:\n${msg.slice(0, 1200)}`); continue; }
    got = msg.slice(at + 'CENSUS'.length)
      .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
      .replace(/\\"/g, '"').replace(/\\n/g, '\n');
    const ctx = got.indexOf('\nCONTEXT:'); if (ctx >= 0) got = got.slice(0, ctx);
  }
  const rows = got.split(RS).filter((r) => r.trim() !== '').map((r) => r.split(US));
  out.push(...rows);
  process.stdout.write(`  ${id}: ${rows.length} dispatch rows\n`);
}
const cell = (v) => { const s = v == null ? '' : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
writeFileSync(process.argv[2] || 'dispatch_census.csv',
  ['workflow_id,step_id,outcome,refusal_code,ids,reason'].concat(out.map((r) => r.map(cell).join(','))).join('\n') + '\n');
console.log(`rows ${out.length}`);
