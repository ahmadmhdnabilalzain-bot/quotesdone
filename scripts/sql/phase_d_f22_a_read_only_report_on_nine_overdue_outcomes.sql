-- F22 - a read-only report on nine overdue outcomes, and nothing else
--
-- THE FOUNDER'S RULING, 21 Aug 2026, sections 4 and G:
--
--     Do not reactivate the cron. Create a read-only report for the nine overdue outcome records if
--     needed. Do not: update the records; create corrective tasks; send alerts externally;
--     reactivate learning automation; alter Row #3 because the automation is intentionally held.
--
-- This function is STABLE and LANGUAGE sql. It cannot write: Postgres refuses an INSERT, UPDATE or
-- DELETE inside a STABLE function, so the "read-only" in its name is enforced by the language and
-- not by my restraint. It creates no task, sends nothing, and touches neither cron.job nor the
-- outcome records.
--
-- WHAT IT REPORTS PER RECORD, which is his list: the original due date, the owning workflow, the
-- accountable role, why evaluation is paused, the automation-hold status, and what would happen if
-- the cron were later activated.
--
-- THE LAST COLUMN IS A MEASUREMENT, NOT A GUESS. public.fn_outcome_evaluate walks
-- `where o.verdict = 'pending' and o.due_at <= now()`, so what would happen to a given record on
-- activation is decided by its verdict and by whether its KPI carries a measure_sql. A record whose
-- verdict is not 'pending' would be SKIPPED -- the cron would run and pass it by -- and a record
-- with no measurable KPI would be graded `unmeasurable`. Both are stated per row rather than
-- summarised, because "nine overdue records" and "nine records the cron would grade" are different
-- claims and this estate has been bitten by exactly that difference.
--
-- THE OWNING WORKFLOW is derived, and where it cannot be derived the column says so rather than
-- guessing: outcome_record carries actor, dept_key, subject_type and subject_id, not a workflow id.
-- A subject that names a Phase C workflow run resolves; anything else is reported as the subject it
-- actually is.

CREATE OR REPLACE FUNCTION public.fn_phase_d_outcome_overdue_report()
 RETURNS TABLE(
   outcome_id        bigint,
   actor             text,
   dept_key          text,
   subject           text,
   original_due_at   timestamptz,
   days_overdue      int,
   owning_workflow   text,
   accountable_role  text,
   expected_metric   text,
   verdict_now       text,
   why_evaluation_is_paused text,
   automation_hold   text,
   what_activation_would_do text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select
    o.id,
    o.actor,
    o.dept_key,
    coalesce(nullif(btrim(o.subject_type),'') || ':' || coalesce(o.subject_id::text,'(no id)'),
             '(no subject recorded)'),
    o.due_at,
    greatest(0, (extract(epoch from (now() - o.due_at)) / 86400)::int),
    -- The workflow that owns it, where the subject actually names one.
    coalesce(
      (select r.workflow_id from public.phase_c_workflow_run r
        where o.subject_type in ('workflow_run','phase_c_workflow_run')
          and r.run_id::text = o.subject_id::text),
      (select w.workflow_id from public.phase_b_workflow w
        where w.workflow_id = o.subject_id::text),
      '(the record names ' || coalesce(nullif(btrim(o.subject_type),''),'no subject type')
        || ', which is not a workflow run)'),
    -- The accountable role, from the department that owns the outcome.
    coalesce(
      (select d.lead_agent from public.org_departments d where d.dept_key = o.dept_key),
      (select a.role from public.org_agents a where a.agent_key = o.actor),
      o.actor,
      '(no accountable role resolves from actor or department)'),
    coalesce(o.expected_metric, '(none declared)'),
    coalesce(o.verdict, '(null)'),
    -- WHY IT IS PAUSED. One sentence, and it is about this record rather than about the estate.
    case
      when o.closed_at is not null
        then 'the record is closed; it is overdue only in the sense that its due date has passed'
      when coalesce(o.verdict,'') <> 'pending'
        then format('the record already carries verdict %s, and public.fn_outcome_evaluate only walks records whose verdict is pending', o.verdict)
      else 'the daily evaluation cron outcome_evaluate_daily is inactive by founder instruction, so nothing has graded it'
    end,
    -- THE HOLD, READ FROM cron.job RATHER THAN ASSERTED.
    (select case when j.active then 'ACTIVE — this report is out of date'
                 else format('HELD — cron job %s (%s) is inactive by founder instruction of 21 Aug 2026', j.jobid, j.jobname) end
       from cron.job j where j.jobname = 'outcome_evaluate_daily'),
    -- WHAT ACTIVATION WOULD DO, derived from the evaluator's own selection predicate.
    case
      when coalesce(o.verdict,'') <> 'pending'
        then 'NOTHING — the cron selects verdict = pending and due_at <= now(); this record would be passed by'
      when o.expected_kpi_id is null
        then 'GRADE IT unmeasurable — no KPI is attached, so there is no measure_sql to read a current value from'
      when (select k.measure_sql from public.employee_kpi k where k.id = o.expected_kpi_id) is null
        then 'GRADE IT unmeasurable — the attached KPI carries no measure_sql'
      when o.baseline_value is null
        then 'GRADE IT unmeasurable — no baseline_value was recorded, so no delta can be computed'
      else 'GRADE IT improved, worse or flat by running the attached KPI''s measure_sql and comparing against the recorded baseline'
    end
  from public.outcome_record o
  where o.due_at < now() and o.closed_at is null
  order by o.due_at;
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_outcome_overdue_report() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_outcome_overdue_report() FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_outcome_overdue_report() TO service_role, authenticated;

COMMENT ON FUNCTION public.fn_phase_d_outcome_overdue_report() IS
  'THE OVERDUE OUTCOME RECORDS, READ ONLY. STABLE and LANGUAGE sql, so Postgres itself refuses any '
  'write from inside it. Reports the original due date, the owning workflow where the subject names '
  'one, the accountable role, why evaluation is paused for THAT record, the cron hold read from '
  'cron.job, and what activation would do -- derived from fn_outcome_evaluate''s own selection '
  'predicate rather than assumed. Created under the founder''s instruction of 21 Aug 2026 to report '
  'on the nine records and to change nothing (F22).';
