-- N02. A REJECTED REVIEW STOPPED NOTHING ON THE 229 STEPS THAT NAME NO REVIEWER.
--
-- public.fn_kernel_review_decide is the canonical door for an internal review verdict. It accepts
-- approved, rejected and changes_requested, seals the decision into a TRACE-ROLE-ACTION trace row,
-- and stamps phase_c_task.reviewer_role_id.
--
-- Who then READS the verdict? Exactly one predicate, in two places that say the same thing:
--
--   fn_kernel_step_complete 3g          -- k3_reviewer_verdict_missing
--   fn_phase_d_handler_execute 4b       -- pd_review_not_recorded
--
-- and both are guarded by
--
--   coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
--
-- 28 of the 257 frozen steps name an independent reviewer. On the other 229 nothing reads the
-- verdict at all. Worse, even on the 28 the predicate tests for the PRESENCE OF AN APPROVAL, never
-- for the presence of a REJECTION -- it is right by accident there, and silent everywhere else.
--
-- PROVED BY EXECUTION, 24 Aug 2026, in transactions that end in raise exception
-- (scripts/tmp_diag/rev_gap.mjs):
--
--   W04-S03  declared_reviewer=(none)
--            fn_kernel_review_decide(decision 'rejected') -> ok=true
--            fn_phase_d_recorded_review               -> verdict 'rejected'
--            fn_kernel_step_complete(outcome 'pass')  -> COMPLETED, state=completed
--
--   W04-S04  declared_reviewer=compliance_and_privacy_officer
--            same rejected verdict                    -> REFUSED k3_reviewer_verdict_missing
--
-- A reviewer rejected the work, the rejection was recorded through the canonical door, and the step
-- completed anyway. That is a review that records the reviewer and not the review.
--
-- WHERE THE GUARD GOES, AND WHY NOT IN THE HANDLER. The Phase D dispatch fires at step OPEN, so a
-- verdict sealed after the open is not a fact the handler had when it ran; a check there would be
-- asked before the answer exists. Every completion, from every caller, passes through the UPDATE of
-- public.phase_c_workflow_step_run.state, so that is where the question can always be answered.
-- The table already carries a sibling BEFORE UPDATE guard of exactly this shape --
-- a00_phase_c_step_run_trace_guard -- so this is the established place for it, not a new mechanism.
--
-- WHY NOT AMEND fn_kernel_review_decide INSTEAD. That routine is the FROZEN Phase C subject
-- internal_review_service. Making it refuse a verdict for a step that names no reviewer is one
-- coherent resolution of the same contract, and it needs the founder's word; it is raised as
-- PCCR-005, disclosed and not applied. THIS resolution needs no frozen change and closes the hole
-- in the safer direction: a verdict recorded against any step is now HONOURED rather than ignored,
-- so a rejection can no longer be recorded and then walked past. The two resolutions do not
-- conflict -- if PCCR-005 is ever approved, fewer verdicts exist and this guard simply has less to
-- find.
--
-- WHAT IT DOES NOT DO, said out loud:
--   * it does not fire on a move to 'failed' -- a rejected review SHOULD let a step fail;
--   * it does not fire when a later approved verdict supersedes the rejection, because it reads the
--     LATEST sealed verdict by trace_id, which is the correction path Phase D requires;
--   * it does not read, invent or require a reviewer on steps that name none. It reads a verdict
--     that a reviewer chose to record, and refuses to let it be ignored.
--
-- THE REFUSAL CODE IS pd_review_verdict_rejected. It is a Phase C table guard, but the only
-- extractor that reads refusal codes out of a drive matches (pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+),
-- and a stable code the harness can actually parse is worth more here than a purer prefix nothing
-- reads. Stated rather than left to be discovered from a regex.

CREATE OR REPLACE FUNCTION public.fn_phase_c_step_run_review_verdict_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_verdict text; v_reviewer text; v_task bigint;
begin
  -- Only a move INTO completed is judged. A state that did not change, and any other target
  -- state -- failed, cancelled, blocked -- is none of this guard's business.
  if NEW.state is not distinct from OLD.state then return NEW; end if;
  if NEW.state <> 'completed' then return NEW; end if;

  -- The LATEST sealed review verdict for this run and step, across every task the step has had.
  -- Latest, so a correction that was subsequently approved is not held against the step.
  select t.task_id, tr.reviewer_role_id, ev->>'review_decision'
    into v_task, v_reviewer, v_verdict
    from public.phase_c_task t
    join public.phase_c_trace tr on tr.task_id = t.task_id
   cross join lateral jsonb_array_elements(
           case when jsonb_typeof(coalesce(tr.evidence_refs,'[]'::jsonb)) = 'array'
                then tr.evidence_refs else '[]'::jsonb end) ev
   where t.run_id = NEW.run_id
     and t.step_id = NEW.step_id
     and tr.trace_policy_id = 'TRACE-ROLE-ACTION'
     and ev ? 'review_decision'
   order by tr.trace_id desc
   limit 1;

  if coalesce(v_verdict,'') in ('rejected','changes_requested') then
    raise exception 'step % cannot complete: the latest internal review verdict on task % is %, recorded by %. A verdict that is recorded and then walked past is not a review. Record an approved verdict through fn_kernel_review_decide, or fail the step. (pd_review_verdict_rejected)',
      NEW.step_id, v_task, v_verdict, coalesce(v_reviewer,'(unstamped)')
      using errcode = '23514';
  end if;

  return NEW;
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_step_run_review_verdict_guard() FROM PUBLIC;

DROP TRIGGER IF EXISTS a01_phase_c_step_run_review_verdict ON public.phase_c_workflow_step_run;
CREATE TRIGGER a01_phase_c_step_run_review_verdict
  BEFORE UPDATE ON public.phase_c_workflow_step_run
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_step_run_review_verdict_guard();
