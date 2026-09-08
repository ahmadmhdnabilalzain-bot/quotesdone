// Build F34 by splicing the LIVE fn_phase_d_handler_execute definition, so nothing else in a
// 23 KB routine moves. Two branches change; every anchor is an exact, complete substring of the
// live body and the script refuses if any of them is not found exactly once.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_functiondef('public.fn_phase_d_handler_execute(jsonb)'::regprocedure) as def`);

const MEASURE_OLD = `         when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'metric', coalesce(s.required_output,''),
           'denominator', p_input->'denominator',
           'numerator', p_input->'numerator',
           'formula', nullif(btrim(coalesce(p_input->>'formula','')),''),
           'window', nullif(btrim(coalesce(p_input->>'window','')),'')))`;

const MEASURE_NEW = `         -- F34. THE FOUR VALUES CAME FROM p_input, AND NOTHING PASSES p_input HERE.
         -- E32 stopped the harness supplying handler inputs, correctly, and the kernel dispatch
         -- passes no measurement keys, so denominator, numerator, formula and window were null on
         -- every call, jsonb_strip_nulls removed them, and the step's own output contract refused
         -- the output the handler had just built. They now come from the committed catalogue
         -- through fn_phase_d_fixture_output, which returns NULL when no row exists -- so a step
         -- with no committed measurement is still refused by its contract, and the denominator-of-0
         -- guard below is untouched.
         when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'metric', coalesce(public.fn_phase_d_fixture_output(sr.step_id,'metric'),
                              to_jsonb(nullif(btrim(coalesce(s.required_output,'')),''))),
           'denominator', public.fn_phase_d_fixture_output(sr.step_id,'denominator'),
           'numerator', public.fn_phase_d_fixture_output(sr.step_id,'numerator'),
           'formula', public.fn_phase_d_fixture_output(sr.step_id,'formula'),
           'window', public.fn_phase_d_fixture_output(sr.step_id,'window')))`;

const REVIEW_OLD = `         when 'REVIEW_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'verdict', nullif(btrim(coalesce(p_input->>'verdict','')),''),
           'reviewer_role_id', nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'')))`;

const REVIEW_NEW = `         -- F34. A REVIEW READ OFF THE CALLER'S OWN STRING.
         -- Both keys came from p_input, so the kernel dispatch -- which passes neither -- produced
         -- an output naming no reviewer, and BR-002 then refused the step for "names (none) as
         -- reviewer". That refusal was true and it was about this harness, not about the business.
         -- The founder's section 4 names CANONICAL_INTERNAL_REVIEW as an allowed execution input
         -- when it travels through its real interface, and that interface is fn_kernel_review_decide:
         -- it checks independence itself, seals a TRACE-ROLE-ACTION carrying the decision, and
         -- stamps phase_c_task.reviewer_role_id. Both values are therefore READ FROM THOSE ROWS.
         -- A caller can no longer assert either one.
         when 'REVIEW_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'verdict', v_review->'verdict',
           'reviewer_role_id', v_review->'reviewer_role_id'))`;

// The BR-002 raise stays. What changes is that it now judges a RECORDED review, and a step with no
// recorded review at all gets its own refusal instead of being reported as a failed independence
// test — E19's lesson, applied to the pair this file creates.
const BR002_OLD = `  if b.handler_class = 'REVIEW_HANDLER'
     and not public.fn_kernel_reviewer_independent(
               sr.accountable_role_id, v_output->>'reviewer_role_id') then`;

const BR002_NEW = `  -- F34. TWO REFUSALS THAT WORE ONE NAME. "no review has been recorded for this step" and "the
  -- recorded review names the creator" are different facts with different remedies, and both came
  -- out as pd_rule_refused/BR-002. The first is now its own code, so a driver can answer it by
  -- recording the review through the kernel's own door and asking for the step again.
  if b.handler_class = 'REVIEW_HANDLER'
     and coalesce(btrim(coalesce(v_output->>'reviewer_role_id','')),'') = '' then
    raise exception 'fn_phase_d_handler_execute: step % is a review step and no internal review has been recorded for it. fn_kernel_review_decide seals the verdict and stamps the reviewer on the task; until it has run there is no reviewer to name and no verdict to carry. (pd_review_not_recorded)',
      sr.step_id using errcode = '23514';
  end if;

  if b.handler_class = 'REVIEW_HANDLER'
     and not public.fn_kernel_reviewer_independent(
               sr.accountable_role_id, v_output->>'reviewer_role_id') then`;

// One declaration, and one assignment placed immediately before the output object is built.
const DECL_OLD = `  v_assert := (`;
const DECL_NEW = `  -- F34. The recorded canonical review for this step run, read once.
  v_review := public.fn_phase_d_recorded_review(v_step_run);

  v_assert := (`;

const parts = [
  ['MEASUREMENT branch', MEASURE_OLD, MEASURE_NEW],
  ['REVIEW branch', REVIEW_OLD, REVIEW_NEW],
  ['BR-002 guard', BR002_OLD, BR002_NEW],
  ['v_review assignment', DECL_OLD, DECL_NEW],
];

let body = def;
for (const [name, oldText, newText] of parts) {
  const n = body.split(oldText).length - 1;
  if (n !== 1) {
    console.error(`ANCHOR "${name}" matched ${n} time(s); exactly one is required. Refusing to write.`);
    process.exit(1);
  }
  body = body.replace(oldText, newText);
}

// The declaration block: add v_review next to the other locals.
const DECLARE_ANCHOR = `\ndeclare\n`;
if (body.split(DECLARE_ANCHOR).length - 1 !== 1) {
  console.error('the declare block did not match exactly once'); process.exit(1);
}
body = body.replace(DECLARE_ANCHOR, `\ndeclare\n  v_review jsonb;   -- F34: the recorded canonical internal review for this step run\n`);

const HEADER = `-- F34 - the handler asked the caller for two things only the estate can answer
--
-- The founder's ruling of 22 Aug 2026, sections 4 and 8A. Two branches of fn_phase_d_handler_execute
-- built their step-specific output keys out of p_input, and nothing passes p_input on the kernel
-- path: E32 removed the harness's ability to supply handler inputs, deliberately, and
-- fn_phase_d_dispatch_step passes only the identifiers of the step run. So both branches produced
-- an output missing the keys their own contract requires.
--
--   MEASUREMENT_HANDLER  denominator, numerator, formula, window   -> from p_input, always null
--   REVIEW_HANDLER       verdict, reviewer_role_id                 -> from p_input, always null
--
-- MEASURED. Of the 30 frozen workflows, W02, W27 and W30 have their FIRST handler refusal at a
-- review step reported as "the review names (none) as reviewer" (BR-002), and W11-S01 refuses with
-- pd_output_schema_invalid even after its capability fixture is accepted. Both are this defect.
--
-- WHERE EACH VALUE COMES FROM NOW, and neither is invented:
--
--   * the four measurement values come from public.phase_d_fixture_catalogue at scope
--     HANDLER_OUTPUT, through fn_phase_d_fixture_output (F33). Committed, versioned, checksummed,
--     and NULL when the catalogue holds nothing -- so the contract still refuses a step nobody has
--     supplied, and the denominator-of-0 guard is untouched.
--
--   * the verdict and the reviewer come from the review the estate actually recorded:
--     fn_kernel_review_decide seals a TRACE-ROLE-ACTION carrying the decision and stamps
--     phase_c_task.reviewer_role_id, having checked independence itself. fn_phase_d_recorded_review
--     reads those two rows. A caller cannot assert either one any more.
--
-- AND ONE REFUSAL BECOMES TWO. "no review has been recorded" and "the recorded review names the
-- creator" both came out as BR-002, which is E19's finding in a new place: a reader cannot tell a
-- missing input from a judged failure. The first is now pd_review_not_recorded, which is what lets
-- fn_phase_d_drive_workflow answer it through the kernel's own review door and ask for the step
-- again -- the same shape F17 established for the capability boundary. BR-002 keeps its teeth: a
-- recorded review that names the creator is still refused, and fn_kernel_review_decide refuses to
-- record one in the first place.
--
-- THE REST OF THE ROUTINE IS BYTE-IDENTICAL. This file was produced by reading the live definition
-- with pg_get_functiondef and replacing four anchors, each of which had to match exactly once or
-- the generator refused to write.

`;

const RECORDED_REVIEW_FN = `-- The recorded canonical internal review for one step run, read from the two rows
-- fn_kernel_review_decide writes: the reviewer it stamped on the task, and the decision it sealed
-- into the task's TRACE-ROLE-ACTION. Nothing here decides anything; a step run with no recorded
-- review returns an empty object and the handler refuses.
CREATE OR REPLACE FUNCTION public.fn_phase_d_recorded_review(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
  select jsonb_strip_nulls(jsonb_build_object(
           'task_id', t.task_id,
           'reviewer_role_id', nullif(btrim(coalesce(t.reviewer_role_id,'')),''),
           'verdict', (select ev->>'review_decision'
                         from public.phase_c_trace tr,
                              lateral jsonb_array_elements(
                                case when jsonb_typeof(coalesce(tr.evidence_refs,'[]'::jsonb)) = 'array'
                                     then tr.evidence_refs else '[]'::jsonb end) ev
                        where tr.task_id = t.task_id
                          and ev ? 'review_decision'
                        order by tr.trace_id desc
                        limit 1)))
    from public.phase_c_workflow_step_run sr
    join public.phase_c_task t
      on t.run_id = sr.run_id and t.step_id = sr.step_id
   where sr.step_run_id = p_step_run_id
   order by t.task_id desc
   limit 1;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_phase_d_recorded_review(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_recorded_review(bigint) TO service_role;

COMMENT ON FUNCTION public.fn_phase_d_recorded_review(bigint) IS
  'The internal review the estate recorded for this step run: the reviewer fn_kernel_review_decide '
  'stamped on the task and the decision it sealed into that task''s trace. Empty when no review has '
  'been recorded, so the handler refuses rather than naming a reviewer nobody appointed. F34.';
`;

writeFileSync('scripts/sql/phase_d_f34_the_handler_asked_the_caller_for_what_only_the_estate_knows.sql',
  HEADER + RECORDED_REVIEW_FN + '\n\n' + body + ';\n');
console.log('written');
