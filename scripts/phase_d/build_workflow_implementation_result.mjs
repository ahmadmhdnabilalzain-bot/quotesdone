// PHASE D DELIVERABLE — PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv
//
// One row per frozen Phase B workflow, produced BY DRIVING IT, not by reading a registry. Each
// workflow gets its own scenario built through the canonical object services, is driven through
// the real executor and the frozen kernel, and the row records what actually happened: how many
// steps completed, how many handoffs were accepted through the D9 contract path, how many business
// effects were produced, the run's final state, whether that state is terminal in the frozen model,
// and — where it stopped — the machine refusal code and the reason verbatim.
//
//   node scripts/phase_d/build_workflow_implementation_result.mjs
//
// EVERY DRIVE RUNS INSIDE A TRANSACTION THAT IS ABORTED. The whole batch is one `do` block ending
// in `raise exception`, so the result is carried out in the error message and not one row survives.
// The script asserts that afterwards by re-reading the run table.
//
// The script exits 1 rather than writing fewer rows than there are frozen workflows, so a partial
// export cannot be mistaken for a complete one.
import { writeFileSync, mkdirSync } from 'node:fs';
import { mgmtRead, mgmtWriteData, PROD_REF } from '../staging/qd_guard.mjs';

const DRIVE = `
do $emit$
declare
  v_fx jsonb; v jsonb; wf record; v_rev text; v_cands jsonb; v_out text := '';
begin
  perform set_config('app.phase_d_test_context','on', true);

  -- The candidate reviewers are the roles the FROZEN registry already names as independent
  -- reviewers somewhere in the 257 steps. The driver only ever consults this list for a step whose
  -- own frozen row names nobody, and only accepts a candidate the kernel's own independence test
  -- allows against that step's owner.
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';

  for wf in select workflow_id from public.phase_b_workflow order by workflow_id loop
    v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label', 'wfresult-' || lower(wf.workflow_id), 'execution_context','test'));

    select coalesce(
      (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
        where s.workflow_id = wf.workflow_id
          and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
        order by s.step_id limit 1),
      'risk_and_governance_manager') into v_rev;

    v := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id', wf.workflow_id, 'label','wfresult-' || lower(wf.workflow_id),
      'execution_context','test', 'verdict','approved',
      'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands,
      'parent_refs', v_fx->'rule_context'));

    v_out := v_out || chr(30) || concat_ws(chr(31),
      wf.workflow_id,
      v->>'steps_in_workflow',
      v->>'steps_driven',
      v->>'handoffs_accepted',
      v->>'open_handoffs_left',
      v->>'effects_for_this_run',
      v->>'run_state',
      v->>'terminal',
      case when coalesce((v->>'terminal')::boolean,false)
                and (v->>'steps_driven') = (v->>'steps_in_workflow')
           then 'DETERMINISTIC_CLOSURE'
           when coalesce((v->>'terminal')::boolean,false) then 'TERMINAL_PARTIAL_DRIVE'
           else 'STOPPED' end,
      coalesce((select x->>'step_id' from jsonb_array_elements(v->'steps') x
                 where coalesce((x->>'ok')::boolean,false)=false limit 1), ''),
      coalesce((select x->>'refused_with' from jsonb_array_elements(v->'steps') x
                 where coalesce((x->>'ok')::boolean,false)=false limit 1),
               (select x->>'refused_with' from jsonb_array_elements(v->'handoffs') x
                 where coalesce((x->>'ok')::boolean,false)=false limit 1), ''),
      replace(replace(left(coalesce(
        (select x->>'reason' from jsonb_array_elements(v->'steps') x
          where coalesce((x->>'ok')::boolean,false)=false limit 1),
        (select x->>'reason' from jsonb_array_elements(v->'handoffs') x
          where coalesce((x->>'ok')::boolean,false)=false limit 1), ''), 400), chr(10), ' '), chr(13), ' '),
      v_fx->>'stages_created',
      v_fx->>'notifications_written_by_this_scenario');
  end loop;

  raise exception 'PHASE_D_WORKFLOW_RESULT%', v_out;
end $emit$;
`;

const COLS = [
  'workflow_id', 'steps_in_workflow', 'steps_driven', 'handoffs_accepted', 'open_handoffs_left',
  'business_effects_produced', 'final_run_state', 'state_is_terminal', 'closure_verdict',
  'stopped_at_step', 'refusal_code', 'refusal_reason',
  'fixture_stages_created', 'notifications_written',
];

function csvCell(v) {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

const expected = await mgmtRead(PROD_REF, 'select count(*)::int as n from public.phase_b_workflow');
const nWorkflows = expected?.[0]?.n ?? 0;
if (!nWorkflows) {
  console.error('phase_b_workflow is empty — refusing to write a deliverable over nothing');
  process.exit(1);
}

// The drive is expected to RAISE. Its message carries the result; anything else is a real failure.
let payload = null;
try {
  // The block writes and then aborts ITSELF, so it goes through the data door rather than the
  // read door; mgmtRead is right to refuse a statement that is not read-only. Nothing here
  // survives — the residue assertion below reads the tables back and proves it.
  await mgmtWriteData(PROD_REF, DRIVE, 'phase D workflow drive (aborted transaction)');
  console.error('the drive block did not raise — it is supposed to abort its own transaction');
  process.exit(1);
} catch (err) {
  const msg = String(err?.message ?? err);
  const at = msg.indexOf('PHASE_D_WORKFLOW_RESULT');
  if (at < 0) {
    console.error('the drive failed before it could report:\n' + msg);
    process.exit(1);
  }
  payload = msg.slice(at + 'PHASE_D_WORKFLOW_RESULT'.length);
}

const rows = payload.split('\u001e').filter((r) => r.trim() !== '').map((r) => r.split('\u001f'));
if (rows.length !== nWorkflows) {
  console.error(`drove ${rows.length} workflow(s) and the frozen model has ${nWorkflows}. Refusing to write a partial export.`);
  process.exit(1);
}

const csv = [COLS.join(',')]
  .concat(rows.map((r) => r.map(csvCell).join(',')))
  .join('\n') + '\n';

mkdirSync('docs/phase-d', { recursive: true });
writeFileSync('docs/phase-d/PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv', csv);

// Nothing may survive. The drive aborted its own transaction; this proves it rather than assuming.
const residue = await mgmtRead(PROD_REF, `
  select (select count(*) from public.phase_c_workflow_run
           where source_ref like 'zz-phase-d-wfresult-%')::int          as runs_left,
         (select coalesce(sum(surviving_rows),0) from public.fn_phase_d_fixture_residue())::int as fixture_rows_left`);
const runsLeft = residue?.[0]?.runs_left ?? -1;
const rowsLeft = residue?.[0]?.fixture_rows_left ?? -1;

const closed = rows.filter((r) => r[8] === 'DETERMINISTIC_CLOSURE').length;
const handoffs = rows.reduce((a, r) => a + Number(r[3] || 0), 0);
const effects = rows.reduce((a, r) => a + Number(r[5] || 0), 0);
const notif = rows.reduce((a, r) => a + Number(r[13] || 0), 0);

console.log(`PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv  ${rows.length} rows`);
console.log(`  deterministic closure        ${closed} / ${rows.length}`);
console.log(`  handoffs accepted            ${handoffs}`);
console.log(`  business effects produced    ${effects}`);
console.log(`  notifications written        ${notif}   (must be 0)`);
console.log(`  workflow runs left behind    ${runsLeft}   (must be 0)`);
console.log(`  fixture rows left behind     ${rowsLeft}   (must be 0)`);

if (notif !== 0 || runsLeft !== 0 || rowsLeft !== 0) {
  console.error('the drive left something behind or produced an external effect');
  process.exit(1);
}
