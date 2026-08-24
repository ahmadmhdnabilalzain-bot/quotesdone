-- ROLLBACK for phase_d_n02_a_rejected_review_stopped_nothing_on_the_229_steps_that_name_no_reviewer.sql
--
-- Removes the guard that refuses a step completion while a rejected review verdict stands, and the
-- routine behind it. Nothing else in N02 wrote a row, so there is no data to restore.
--
-- WHAT COMES BACK WITH IT, stated because a rollback that hides its own cost is the defect: on the
-- 229 frozen steps that declare no independent reviewer, a recorded 'rejected' verdict stops
-- nothing again, and the step completes on its pass edge. That was measured on W04-S03 before N02
-- and is the behaviour this file restores.
drop trigger if exists a01_phase_c_step_run_review_verdict on public.phase_c_workflow_step_run;
drop function if exists public.fn_phase_c_step_run_review_verdict_guard();
