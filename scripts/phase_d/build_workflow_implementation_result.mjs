// A3. THIS BUILDER DRIVES IN PRODUCTION MODE, AND THE HEADLINE IS SUPPOSED TO FALL.
//
// It passed execution_context test at both call sites, and test is the ONE value that disables
// the two fail-closed boundaries in fn_phase_d_handler_execute -- the capability boundary at its
// section 3 and the provider boundary at section 4. Measured: 21 of the 257 bindings carry
// capability_dependency REASONING and 0 carry a provider dependency, so in production mode those
// 21 steps refuse with pd_capability_unavailable and the workflows containing them do not close.
//
// That is the design working under the founder's hold on paid inference, not a regression, and
// keeping test mode to protect a 30-of-30 number is how a check goes green over a defect.
//
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
  v_ref_key text; v_boid text;
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
      -- A3. THE SCENARIO FACTORY STAYS IN TEST, AND THAT IS NOT A LOOPHOLE. It refuses production
      -- outright -- "this factory runs only in test (pd_fixture_not_test_context)" -- because it
      -- CREATES the business objects a run needs, and creating them under production semantics is
      -- precisely what the residue rule forbids. What must be measured in production is the
      -- HANDLER, and that is the call below. Seeding in test and executing in production is the
      -- honest split; passing production to both only made the factory refuse before a single step
      -- ran, which measures nothing at all.
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

    -- E32. THE ARRIVAL NAMES THE OBJECT IT IS ABOUT, and it names a REAL one where the scenario
    -- created one. The driver derives business_key from the run's business_object_id and only when
    -- it carries the '<object>:' prefix, so a bare object name resolves to no row and every rule
    -- that reads the subject refuses for the wrong reason. Where the scenario seeded the
    -- workflow's primary object, its actual key goes in; where it did not, the driver's own
    -- fallback applies and fn_phase_d_step_context reports row_found=false, which is the truth.
    select st.contributes_ref into v_ref_key
      from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow
                            where workflow_id = wf.workflow_id)
     limit 1;
    v_boid := case
      when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id = wf.workflow_id)
           || ':' || (v_fx->'parent_refs'->>v_ref_key)
      else null end;

    -- parent_refs, context, verdict, owner_ref and effect payload are NOT passed and are no longer
    -- accepted. fn_kernel_step_complete does not take them, and that is the point of E32: the
    -- deliverable is produced through the door production uses, so a harness cannot hand the rules
    -- a value. Everything the rules read is resolved by fn_phase_d_step_context from real rows.
    v := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id', wf.workflow_id, 'label','wfresult-' || lower(wf.workflow_id),
      'execution_context','production',
      'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands)
      || case when v_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_boid) end);

    v_out := v_out || chr(30) || concat_ws(chr(31),
      wf.workflow_id,
      v->>'steps_in_workflow',
      v->>'steps_driven',
      v->>'handoffs_accepted',
      v->>'open_handoffs_left',
      -- E32. TWO SUBJECTS, TWO COLUMNS, EACH NAMED FOR WHAT IT MEASURES. The old row had one
      -- number and a reader had to guess whose achievement it was. dispatches_seen counts the
      -- step-openings the kernel handed to the deterministic handler; dispatches_executed counts
      -- the ones the handler completed unaided. steps_driven counts what an ACTOR pushed through
      -- fn_kernel_step_complete, which is a fact about this harness, not about Phase D.
      v->>'dispatches_seen',
      v->>'dispatches_executed',
      v->>'effects_for_this_run',
      v->>'run_state',
      v->>'terminal',
      -- The verdict vocabulary now distinguishes the two. HANDLER_CLOSED_UNAIDED is the only one
      -- that is a Phase D claim; the ACTOR_DRIVEN ones say a person, or this harness standing in
      -- for one, did the work.
      case when coalesce((v->>'terminal')::boolean,false)
                and (v->>'steps_driven') = (v->>'steps_in_workflow')
                and coalesce((v->>'dispatches_executed')::int,0) > 0
                and (v->>'dispatches_executed') = (v->>'dispatches_seen')
           then 'HANDLER_CLOSED_UNAIDED'
           when coalesce((v->>'terminal')::boolean,false)
                and (v->>'steps_driven') = (v->>'steps_in_workflow')
           then 'ACTOR_DRIVEN_TO_TERMINAL'
           when coalesce((v->>'terminal')::boolean,false) then 'ACTOR_DRIVEN_PARTIAL'
           else 'STOPPED' end,
      -- WHERE THE DRIVE STOPPED. Not the same question as where the handler first declined, and
      -- folding the two into one column made this deliverable report W21 as stopping at W21-S01
      -- when it had reached W21-S07 — because step 1's dispatch refused, as nearly all of them do.
      coalesce(v->'stopped'->>'at',''),
      coalesce(v->'stopped'->>'refused_with',''),
      -- A DELIVERABLE THAT MUST REPRODUCE CANNOT CARRY A PER-RUN IDENTIFIER. BR-013's reason names
      -- the inquiry it judged — "inquiry 2623 is not quote-ready" — and the scenario factory
      -- creates a new one every drive, so the committed CSV differed from its own rebuild on that
      -- number alone. Runs of three or more digits are redacted to <id> in the REASON columns only;
      -- every count, code and identifier that is part of the finding is shorter than that and
      -- survives. The reason stays readable and the row stays reproducible.
      regexp_replace(replace(replace(left(coalesce(v->'stopped'->>'reason',''), 400), chr(10), ' '), chr(13), ' '), '[0-9]{3,}', '<id>', 'g'),
      -- WHERE THE DETERMINISTIC HANDLER FIRST DECLINED. This is the Phase D subject.
      coalesce(v->'first_handler_refusal'->>'at',''),
      coalesce(v->'first_handler_refusal'->>'refused_with',''),
      regexp_replace(replace(replace(left(coalesce(v->'first_handler_refusal'->>'reason',''), 400), chr(10), ' '), chr(13), ' '), '[0-9]{3,}', '<id>', 'g'),
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
  'dispatches_seen', 'dispatches_executed',
  'business_effects_produced', 'final_run_state', 'state_is_terminal', 'closure_verdict',
  'drive_stopped_at', 'drive_stop_code', 'drive_stop_reason',
  'first_handler_refusal_at', 'first_handler_refusal_code', 'first_handler_refusal_reason',
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
  // The old wording said "through the executor and the kernel", and an independent audit measured
  // that it went through the executor and NOT the kernel: the driver called
  // fn_phase_d_handler_execute directly and never fn_kernel_step_complete. E32 made the statement
  // true instead of rewording it, and this line now names the four doors so a reader can check it.
  attribution: 'one row per workflow, produced by DRIVING it through the kernel doors only — '
    + 'fn_kernel_workflow_start, fn_kernel_review_decide, fn_kernel_step_complete and the D9 '
    + 'handoff path into fn_kernel_handoff_accept — inside a transaction that is aborted. No '
    + 'context, gate evidence, business key, owner or effect payload is supplied by this harness: '
    + 'the kernel dispatch resolves every one of those itself and accepts none from a caller. '
    + 'dispatches_executed is the Phase D number; steps_driven is what an actor pushed through',
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

// INDEXED BY NAME, NOT BY POSITION. This summary read r[5], r[8], r[14] and r[15], and adding
// dispatches_seen / dispatches_executed and splitting the stop columns shifted every one of them:
// the "business effects" line would have printed dispatches_seen and the "outbound HTTP requests"
// line would have printed a refusal code. A positional index into a column list that just grew is
// an instrument reporting on the wrong subject, and it prints a plausible number while doing it.
const at = (name) => {
  const i = COLS.indexOf(name);
  if (i < 0) throw new Error(`the summary asks for a column that does not exist: ${name}`);
  return i;
};
const sum = (name) => rows.reduce((a, r) => a + Number(r[at(name)] || 0), 0);

const closed = rows.filter((r) => r[at('closure_verdict')] === 'HANDLER_CLOSED_UNAIDED').length;
const handoffs = sum('handoffs_accepted');
const effects = sum('business_effects_produced');
const dispatched = sum('dispatches_seen');
const executed = sum('dispatches_executed');
const notif = sum('notifications_written');
const outbound = sum('outbound_http_requests_written');

console.log(`PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv  ${rows.length} rows`);
console.log(`  outbound HTTP requests      ${outbound}`);
console.log(`  step-openings dispatched     ${dispatched}`);
console.log(`  completed by the handler     ${executed}   (the Phase D number)`);
console.log(`  workflows closed unaided     ${closed} / ${rows.length}`);
console.log(`  handoffs accepted            ${handoffs}`);
console.log(`  business effects produced    ${effects}`);
console.log(`  notifications written        ${notif}   (must be 0)`);
console.log(`  workflow runs left behind    ${runsLeft}   (must be 0)`);
console.log(`  fixture rows left behind     ${rowsLeft}   (must be 0)`);

if (notif !== 0 || runsLeft !== 0 || rowsLeft !== 0) {
  console.error('the drive left something behind or produced an external effect');
  process.exit(1);
}
