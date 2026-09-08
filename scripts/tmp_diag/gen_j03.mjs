import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_phase_d_handler_execute'`);

const A = `  select * into b from public.phase_d_handler_binding where step_id = sr.step_id;`;
if ((prosrc.match(/  select \* into b from public\.phase_d_handler_binding where step_id = sr\.step_id;/g) || []).length !== 1)
  throw new Error('anchor not unique');

const body = prosrc.replace(A, `  -- ---- 0b. THE BRANCH PROBE'S HOLD --------------------------------------------------------
  -- Section 1 of the founder's ruling asks for BRANCH coverage of all 257 frozen steps. The frozen
  -- model is a linear chain: next_step_if_pass names the next step (or WORKFLOW_COMPLETE), and
  -- next_step_if_fail names one of three symbolic outcomes and never a step. So a step's fail edge
  -- is exercised by an ACTOR reporting failure on it, which requires the step to be OPEN.
  --
  -- MEASURED 23 Aug 2026: 249 of 257 steps are completed by this handler in the same statement the
  -- kernel opens them, so they are never open and no actor can ever take them. W18 is the extreme
  -- case -- all seven steps EXECUTED unaided, the run reaching completed inside
  -- fn_kernel_workflow_start, nothing left to fail or cancel. A handler that succeeds is the
  -- system working; it also means the fail edge of the frozen model is unreachable through the
  -- actor door, and an unexercised branch cannot be reported as covered.
  --
  -- This is the hold, and every part of it is deliberately narrow:
  --   * it acts only inside an open Phase D fixture context, which fn_phase_d_test_context_open
  --     grants for one operation inside one transaction that ends in raise exception;
  --   * it names ONE step, set by the caller at transaction level, and never a workflow or a class;
  --   * it refuses with its own code, pd_handler_held_for_branch_probe, which appears in
  --     phase_d_dispatch.refusal_code -- so no reader, and no deliverable, can mistake a held step
  --     for a handler that could not do its work;
  --   * it changes nothing else. The kernel then does exactly what it does for any refused
  --     dispatch: the step stays open and owned.
  --
  -- What the fail-branch case then proves is the KERNEL's edge for that step -- outcome fail moves
  -- the step to failed and the run to the step's declared failure_workflow_state, with no partial
  -- effect and no residue -- and NOT that the handler could have failed. Those are different
  -- claims and the coverage matrix records which one it has, per step.
  if nullif(btrim(coalesce(current_setting('app.phase_d_hold_step', true), '')), '') = sr.step_id
     and public.fn_phase_d_fixture_context() is not null then
    raise exception 'fn_phase_d_handler_execute: step % is held open by an audited Phase D branch probe; the handler declined so an actor can take the step (pd_handler_held_for_branch_probe)',
      sr.step_id using errcode = '23505';
  end if;

` + A);

const header = `-- J03 — a step the handler always completes has a fail edge nobody can reach
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. Driving all 30 frozen workflows: 250 of 350
-- dispatches EXECUTED, and the great majority of the 257 frozen steps are closed by
-- fn_phase_d_handler_execute in the same statement fn_kernel_open_step opens them. W18 is the
-- clearest case -- all seven steps EXECUTED unaided and the run reached completed inside
-- fn_kernel_workflow_start, so hold_at_first_open_step found nothing to hold, the failure probe had
-- no step_run_id and fn_kernel_cancel had a completed run and correctly refused to cancel it.
-- A phantom business_object_id does not change that: none of W18's steps reads the business object,
-- and all seven still EXECUTED. Measured, not assumed.
--
-- The frozen Phase B model gives every one of the 257 steps a fail edge -- next_step_if_fail is
-- WORKFLOW_BLOCKED_OR_ESCALATED for 146, CORRECTION_OR_REJECTION_PATH for 82 and WORKFLOW_BLOCKED
-- for 29, and never another step -- together with a declared failure_workflow_state. Exercising
-- that edge needs the step OPEN so an actor can report the failure.
--
-- This adds a hold with one name, one transaction and one refusal code. See the routine comment
-- for the full boundary; in short, it acts only inside an open Phase D fixture context, refuses
-- exactly the one step named in app.phase_d_hold_step, and records
-- pd_handler_held_for_branch_probe in phase_d_dispatch so a held step can never be read as a
-- handler that failed. The step-branch coverage deliverable records, per step, whether its fail
-- edge was reached because the handler refused of its own accord or because it was held.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_handler_execute. No DDL, no grants:
-- CREATE OR REPLACE preserves the ACL.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_j03.mjs; one anchor, required to match
-- exactly once.
CREATE OR REPLACE FUNCTION public.fn_phase_d_handler_execute(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$`;

writeFileSync('scripts/sql/phase_d_j03_a_step_the_handler_always_completes_has_a_fail_edge_nobody_can_reach.sql',
  header + body + '$function$;\n');
console.log('written', body.length, 'was', prosrc.length);
