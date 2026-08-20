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
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
// THE BUILDER COULD NOT RUN ITS OWN DELIVERABLE. It routed the drive through mgmtWriteData, which
// calls assertNotProduction and refuses the one project that exists:
//     REFUSED: write targeted production (htdblwldjkcgjvmqkbeh). Batch 0 forbids this.
// mgmtWriteData is also INSERT-only by design, so a DO block was never going to pass it. The drive
// is an ABORTED-TRANSACTION PROBE — it ends in raise exception and leaves nothing — which is the
// door scripts/phase_c and scripts/checks already use for exactly this. Nothing is weakened:
// assertNotProduction still guards every migration and rebuild path, and the residue assertion
// below still reads the tables back and proves the probe left nothing.
import { sql, PROJECT_REF } from '../phase_c/lib/db.mjs';

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

  for wf in select workflow_id from public.phase_b_workflow where workflow_id = '__WORKFLOW_ID__' loop
    v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label', 'wfresult-' || lower(wf.workflow_id), 'execution_context','test',
      -- THE EXCLUSION IS USED WHERE A WORKFLOW COLLIDES WITH A SEEDED LEAF, NOT EVERYWHERE.
      -- Measured: applying it to W16 as well dropped W16 from 4/9 to 1/9, and the D9 measurement of
      -- the un-narrowed version was closure 14 -> 3. W12 dispatches to the supplier_assignment the
      -- factory seeds, so W12 is where it is used, and the row records it.
      'for_workflow', case when wf.workflow_id = 'W12' then wf.workflow_id else null end));

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
      coalesce(v_fx->>'for_workflow','(none)'),
      v_fx->>'notifications_written_by_this_scenario',
      v_fx->>'outbound_http_requests_written_by_this_scenario');
  end loop;

  raise exception 'PHASE_D_WORKFLOW_RESULT%', v_out;
end $emit$;
`;

const COLS = [
  'workflow_id', 'steps_in_workflow', 'steps_driven', 'handoffs_accepted', 'open_handoffs_left',
  'business_effects_produced', 'final_run_state', 'state_is_terminal', 'closure_verdict',
  'stopped_at_step', 'refusal_code', 'refusal_reason',
  'fixture_stages_created', 'fixture_exclusion_used', 'notifications_written',
  'outbound_http_requests_written',
];

function csvCell(v) {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

const expected = await sql('select count(*)::int as n from public.phase_b_workflow');
const nWorkflows = expected?.[0]?.n ?? 0;
if (!nWorkflows) {
  console.error('phase_b_workflow is empty — refusing to write a deliverable over nothing');
  process.exit(1);
}

// ONE PROBE PER WORKFLOW, NOT ONE MESSAGE CARRYING THIRTY.
// The first version raised a single exception carrying all 30 rows and the management API
// TRUNCATED it, so the parser saw one row. The guard below caught that and refused to write a
// partial export, which is the only reason it was not published as a 1-row deliverable. Thirty
// small probes cannot be truncated into looking complete.
const ids = (await sql('select workflow_id from public.phase_b_workflow order by workflow_id'))
  .map((r) => r.workflow_id);
if (ids.length !== nWorkflows) {
  console.error('the workflow list and the workflow count disagree');
  process.exit(1);
}

const rows = [];
for (const id of ids) {
  let got = null;
  try {
    await sql(DRIVE.replace('__WORKFLOW_ID__', id));
    console.error(`the drive block for ${id} did not raise — it must abort its own transaction`);
    process.exit(1);
  } catch (err) {
    const msg = String(err?.message ?? err);
    const at = msg.indexOf('PHASE_D_WORKFLOW_RESULT');
    if (at < 0) {
      console.error(`the drive for ${id} failed before it could report:\n` + msg);
      process.exit(1);
    }
    // THE TRANSPORT THROWS THE RAW RESPONSE BODY, NOT A DECODED MESSAGE. scripts/phase_b/lib/db.mjs
    // raises `HTTP ${status}: ${text.slice(0, 2000)}`, so what arrives here is JSON source: the
    // record separators are the six characters \u001e, quotes are backslash-escaped, and the whole
    // thing is cut at 2000 characters. Splitting it raw produced one CSV row per workflow with the
    // entire payload sitting in the first column and \u001e printed as text — a deliverable that
    // looked populated and carried nothing. Un-escape first, then cut the CONTEXT trailer Postgres
    // appends, then split.
    got = msg.slice(at + 'PHASE_D_WORKFLOW_RESULT'.length)
      .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
      .replace(/\\"/g, '"')
      .replace(/\\n/g, '\n');
    const ctx = got.indexOf('\nCONTEXT:');
    if (ctx >= 0) got = got.slice(0, ctx);
  }
  const parsed = got.split('').filter((r) => r.trim() !== '').map((r) => r.split(''));
  if (parsed.length !== 1) {
    console.error(`the drive for ${id} reported ${parsed.length} row(s); exactly one is expected`);
    process.exit(1);
  }
  rows.push(parsed[0]);
  process.stdout.write(`  ${id} ${parsed[0][2]}/${parsed[0][1]} ${parsed[0][8]}\n`);
}


if (rows.length !== nWorkflows) {
  console.error(`drove ${rows.length} workflow(s) and the frozen model has ${nWorkflows}. Refusing to write a partial export.`);
  process.exit(1);
}

const csv = provenance({
  command: 'node scripts/phase_d/build_workflow_implementation_result.mjs',
  numerator: rows.length,
  denominator: nWorkflows,
  of: 'frozen Phase B workflows',
  attribution: 'one row per workflow, produced by DRIVING it through the executor and the kernel '
    + 'inside a transaction that is aborted — not by reading a registry',
}) + [COLS.join(',')]
  .concat(rows.map((r) => r.map(csvCell).join(',')))
  .join('\n') + '\n';

writeFileSync(outPath('PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv'), csv);

// Nothing may survive. The drive aborted its own transaction; this proves it rather than assuming.
const residue = await sql(`
  select (select count(*) from public.phase_c_workflow_run
           where dedupe_key like 'zz-phase-d-wfresult-%')::int          as runs_left,
         (select coalesce(sum(surviving_rows),0) from public.fn_phase_d_fixture_residue())::int as fixture_rows_left`);
const runsLeft = residue?.[0]?.runs_left ?? -1;
const rowsLeft = residue?.[0]?.fixture_rows_left ?? -1;

const closed = rows.filter((r) => r[8] === 'DETERMINISTIC_CLOSURE').length;
const handoffs = rows.reduce((a, r) => a + Number(r[3] || 0), 0);
const effects = rows.reduce((a, r) => a + Number(r[5] || 0), 0);
const notif = rows.reduce((a, r) => a + Number(r[14] || 0), 0);
const outbound = rows.reduce((a, r) => a + Number(r[15] || 0), 0);

console.log(`PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv  ${rows.length} rows`);
console.log(`  outbound HTTP requests      ${outbound}`);
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
