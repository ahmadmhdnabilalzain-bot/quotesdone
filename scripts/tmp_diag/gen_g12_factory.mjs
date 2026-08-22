import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const FILE = 'scripts/sql/phase_d_g12_the_three_objects_only_the_kernel_may_create.sql';
const base = readFileSync(FILE, 'utf8');
if (base.includes('fn_phase_d_fixture_scenario')) {
  console.log('already spliced'); process.exit(0);
}

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`);
let def = r[0].def;
const anchor = `  -- F12. THE FOUNDER AUTHORITY FIXTURE, LAST, BECAUSE NOTHING DEPENDS ON IT.`;
const n = def.split(anchor).length - 1;
if (n !== 1) throw new Error(`anchor matched ${n} time(s)`);

def = def.replace(anchor, `  -- G12. THE THREE OBJECTS ONLY THE KERNEL MAY CREATE, asked for through the kernel's own doors.
  -- fn_phase_d_object_write refuses workflow_run, workflow_step_run and handoff_record by name --
  -- "a Phase D handler that wrote it would be a second creator for one object" -- so no stage of
  -- the chain above can create them and the round-trip proof reported all three as
  -- NOT_CREATED_BY_ANY_STAGE, counted as neither pass nor fail. This does not write them either: it
  -- calls fn_kernel_workflow_start and fn_kernel_step_complete and records what the kernel made.
  begin
    v_w := public.fn_phase_d_kernel_object_fixture(jsonb_build_object('label', v_label));
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 998, 'stage_key','kernel_objects', 'object_id','workflow_run/workflow_step_run/handoff_record',
      'status', case when coalesce((v_w->>'objects_recorded')::int,0) > 0 then 'CREATED' else 'REFUSED' end,
      'relation','public.phase_c_workflow_run + _step_run + _handoff_run',
      'result_reference', format('run_id=%s step_run_id=%s handoff_run_id=%s',
        coalesce(v_w->>'run_id','(none)'), coalesce(v_w->>'step_run_id','(none)'),
        coalesce(v_w->>'handoff_run_id','(none)')),
      'state','open', 'contributes', null, 'detail', v_w->>'note'));
    if coalesce((v_w->>'objects_recorded')::int,0) > 0 then v_ok := v_ok + 1;
    else v_blocked := v_blocked + 1; end if;
  exception when others then
    v_man := v_man || jsonb_build_array(jsonb_build_object(
      'stage_no', 998, 'stage_key','kernel_objects', 'object_id','workflow_run/workflow_step_run/handoff_record',
      'status','REFUSED',
      'refused_with', coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+)\\)'))[1],'(none)'),
      'reason', left(SQLERRM, 300)));
    v_blocked := v_blocked + 1;
  end;

` + anchor);

writeFileSync(FILE, base + '\n' + def + '\n');
console.log('G12 factory splice written');
