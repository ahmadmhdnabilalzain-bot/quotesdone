-- Declared timeouts that are shorter than the work, found by the invoker dead-lettering them.
--
-- Every one of the 55 executors carries timeout_seconds = 60, which was a default, not a
-- measurement. The first afternoon of real invocations produced two dead letters, both
-- exec_review -> exec_agents, both "Timeout of 60000 ms reached" — while the work SUCCEEDED:
-- exec_reports 49..55 were filed at 13:47:58 through 13:50:08, about 130 seconds for seven
-- officers with a model call each. The HTTP call gave up before the function did.
--
-- That shape is the dangerous one. A timeout recorded as a failure on work that completed is how
-- a retry doubles a spend. It did not here, because exec_review declares max_attempts 1 and
-- idempotency none_read_only, but the declaration was wrong and is now measured.
--
-- Raised only for the executors whose target fans out over the whole company or the whole corpus
-- and whose observed duration exceeds 60 s. Everything else keeps 60: a generous default applied
-- everywhere would hide the next one of these.
update public.org_action_executor
   set timeout_seconds = 180
 where action_class in ('exec_review',            -- exec_agents: 7 officers, ~130 s measured
                        'capability_exam',        -- knowledge_exam: grades several agents per run
                        'knowledge_acquire')      -- kb_deepen: builds a topic map per category
   and coalesce(timeout_seconds, 0) < 180;

update public.dead_letter
   set resolved_at = now(), resolved_by = 'part9_session',
       resolution = 'Not a failed execution: exec_agents completed and filed exec_reports 49..55, but org_action_executor.exec_review declared timeout_seconds = 60 against an observed ~130 s. The declaration was the defect; it is 180 now.'
 where source = 'fn_action_invoke_collect' and kind = 'exec_review' and resolved_at is null;
