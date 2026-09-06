import { readFileSync, writeFileSync } from 'node:fs';

const SP = 'C:/Users/Opera/AppData/Local/Temp/claude/C--Users-Opera-quotesdone/'
  + '051dbf76-3315-4c3b-9c5c-69c40409fdcc/scratchpad';
const body = readFileSync(SP + '/o08_body.sql', 'utf8');

const head = `-- O08. THE NINE THAT REMAINED, EXECUTED.
--
-- Every one of the nine was recorded NOT_RUN with classification REAL_PRODUCT_GAP and a stated
-- build order in public.phase_d_injected_defect_disposition.what_would_make_it_executable. O01-O07
-- built each of them; this file replaces the nine NOT_RUN emissions in
-- public.fn_phase_d_run_injected_defects with branches that drive an injection AND its control.
--
-- TWO OF THE NINE BLOCKERS WERE WRONG, AND WRONG ABOUT SOMETHING ALWAYS PRESENT. PD-AUTH-005 and
-- PD-LEGAL-005 both said closing them needs public.fn_phase_c_task_create, a
-- KERNEL_INTERNAL_PRIMITIVE, and that a probe calling it is the bypass
-- fn_kernel_retired_path_state exists to catch. public.fn_kernel_open_step IS a kernel entry point
-- that accepts a caller-supplied owner and routes to that primitive -- the exact thing the blocker
-- said had to be built -- and it is an fn_kernel_* routine, so the board's own exclusion covers it
-- and no exclusion list is lengthened. That is the fourth time in this Phase D that a recorded
-- reason for not running a case turned out to be a claim nobody had re-measured.
--
-- EVERY BRANCH THAT WRITES ROLLS ITSELF BACK. fn_phase_d_injected_defect_report has callers other
-- than the deliverable builder and not all of them abort. Each writing branch does its work inside
-- a plpgsql exception block -- a subtransaction -- and raises at the end of it, so the rows are
-- discarded in every caller and the findings travel out in the raise message, which is memory
-- rather than data. Nothing here depends on somebody else remembering to abort.
--
-- NOTHING HERE FORGES A FOUNDER. PD-FIN-004 binds the founder's own verified auth subject through
-- public.fn_phase_c_founder_subject_bind -- the estate's own server door, which refuses any subject
-- that does not resolve to an active founder identity -- inside a block that always rolls back, on
-- the founder's written instruction for this session. The decision it creates never commits, and
-- public.fn_kernel_refund_decision_record writes decided_by from the VERIFIED identity in every
-- case, so the service could not record a decision in his name even if a caller asked it to.
--
-- THE SIGNATURE IS UNCHANGED, INCLUDING prosecdef. This routine is SECURITY INVOKER and stays so:
-- making it a definer to let a branch reach further would be the "a SECURITY DEFINER guard reads
-- its own identity" shape, and every door these branches use carries its own lock.

CREATE OR REPLACE FUNCTION public.fn_phase_d_run_injected_defects()
 RETURNS TABLE(defect_id text, category text, status text, observed text, blocker text)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$`;

writeFileSync('scripts/sql/phase_d_o08_the_nine_that_remained_executed.sql',
  head + body + '$function$;\n');
console.log('written', head.length + body.length, 'chars');
