-- comp-03-objectives-measured — "Objectives carry a computable measure, not prose".
--
-- os_objective held 50 rows across ten OSes and five horizons. Every one carried a `measure` that
-- was a LABEL: 'gl_journal', 'os_review health', 'qualified pipeline', 'KPI instrumentation'.
-- A label cannot produce a value, so no objective in this company could ever be said to be met or
-- missed. measure_sql / actual_value / measured_at were added to the table and left empty on all
-- 50 rows, which is a column definition, not a measure.
--
-- Each statement below was EXECUTED against production before being stored (see
-- scripts/staging/verify_os_objective_measures.mjs, which re-executes all 50 and fails on any that
-- errors or returns a non-numeric). Several read 0 today because production is an unlaunched
-- marketplace with 0 inquiries, 0 quotes and 0 transactions — that is the correct reading, not a
-- broken measure. The precedent and the warning are company_goal_measures.sql: a measure that
-- returns the right number for the wrong reason cannot be caught by looking at its output.
--
-- WHERE THE OBJECTIVE'S OWN SENTENCE IS NOT COMPUTABLE FROM ANY TABLE THAT EXISTS, the measure is
-- the nearest thing that IS true, and it is named as such in the comment above it rather than
-- dressed up as the original. Three of the fifty are in that position: marketing attribution
-- (no channel is recorded on inquiries), SLA ownership (there is no sla table), and forecast error
-- (simulations stores the run, never the error against outturn).
--
-- Keyed by (os_key, horizon), never by id: staging and production do not share the sequence.

-- ── leadership ──────────────────────────────────────────────────────────────────────────────────
-- 'revenue_annual' and 'supplier_coverage_10x86' are literally company_goals KEYS. The company
-- already measures both, daily, into goal_period. Re-deriving them here would create a second
-- number for the same fact and guarantee the two drift; the objective reads the company's own.
update public.os_objective set measure_sql =
$m$select p.actual_value from goal_period p where p.goal_key = 'revenue_annual'
    order by p.updated_at desc nulls last limit 1$m$
where os_key='leadership' and horizon='strategic';

update public.os_objective set measure_sql =
$m$select p.actual_value from goal_period p where p.goal_key = 'supplier_coverage_10x86'
    order by p.updated_at desc nulls last limit 1$m$
where os_key='leadership' and horizon='quarterly';

-- "Every operating system green for four consecutive weeks" — OSes with no non-green review in 28d.
update public.os_objective set measure_sql =
$m$select count(*)::numeric from (
       select os_key from os_review where created_at > now() - interval '28 days'
        group by os_key having count(*) filter (where health = 'green') = count(*)) z$m$
where os_key='leadership' and horizon='annual';

update public.os_objective set measure_sql =
$m$select count(distinct os_key)::numeric from os_review
    where created_at > now() - interval '7 days'$m$
where os_key='leadership' and horizon='weekly';

-- The daily rhythm has eight stages; this is how many completed today.
update public.os_objective set measure_sql =
$m$select count(*) filter (where ok)::numeric from day_cadence
    where business_day = current_date$m$
where os_key='leadership' and horizon='daily';

-- ── commercial ──────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select count(*)::numeric from inquiries
    where coalesce(rfq_ready,false) and created_at > now() - interval '90 days'$m$
where os_key='commercial' and horizon='strategic';

-- NOT the objective's own sentence. "60 qualified inquiries per month FROM MARKETING" needs a
-- channel on the inquiry and no column records one; brief_source is the only provenance field that
-- exists. This counts inquiries in the last 30 days that carry ANY attribution at all, which is the
-- precondition for ever measuring the real thing.
update public.os_objective set measure_sql =
$m$select count(*)::numeric from inquiries
    where created_at > now() - interval '30 days' and coalesce(brief_source,'') <> ''$m$
where os_key='commercial' and horizon='annual';

update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where decision='approve') / nullif(count(*),0), 2)
     from review_chain
    where dept_key='marketing' and created_at > now() - interval '90 days'$m$
where os_key='commercial' and horizon='quarterly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from social_posts
    where coalesce(status,'') = 'published' and created_at > now() - interval '7 days'$m$
where os_key='commercial' and horizon='weekly';

-- Drafts raised in the last day that no reviewer has touched. Target 0.
update public.os_objective set measure_sql =
$m$select count(*)::numeric from social_posts
    where created_at > now() - interval '1 day'
      and coalesce(status,'') in ('draft','pending','queued')$m$
where os_key='commercial' and horizon='daily';

-- ── marketplace ─────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (
         where exists (select 1 from quotes q where q.inquiry_id = i.id)) / nullif(count(*),0), 2)
     from inquiries i where i.created_at > now() - interval '90 days'$m$
where os_key='marketplace' and horizon='strategic';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from leads where approval_status = 'approved'$m$
where os_key='marketplace' and horizon='annual';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from v_category_coverage where coalesce(supplier_supply,0) >= 10$m$
where os_key='marketplace' and horizon='quarterly';

update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (
         where exists (select 1 from quotes q where q.inquiry_id = i.id)) / nullif(count(*),0), 2)
     from inquiries i where i.created_at > now() - interval '7 days'$m$
where os_key='marketplace' and horizon='weekly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from inquiries
    where routing is null and created_at > now() - interval '2 days'$m$
where os_key='marketplace' and horizon='daily';

-- ── operations ──────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where not needs_founder) / nullif(count(*),0), 2)
     from org_tasks where created_at > now() - interval '90 days'$m$
where os_key='operations' and horizon='strategic';

-- qa_results.passed is a BOOLEAN verdict on the run, not a count of passing assertions —
-- sum(passed) throws, and this was caught by executing the measure rather than by reading it.
-- total and failed are the integers, so the assertion-level pass rate is (total - failed) / total.
update public.os_objective set measure_sql =
$m$select round(100.0 * sum(coalesce(total,0) - coalesce(failed,0)) / nullif(sum(total),0), 2)
     from qa_results where run_at > now() - interval '365 days'$m$
where os_key='operations' and horizon='annual';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from org_tasks
    where status in ('proposed','assigned','in_progress')
      and created_at < now() - interval '14 days'$m$
where os_key='operations' and horizon='quarterly';

-- NOT the objective's own sentence. There is no sla table anywhere in the schema, so "every SLA
-- breach has an owner" cannot be read. Open work with nobody recorded against it is the same
-- failure one level up, and it IS computable. Target 0.
update public.os_objective set measure_sql =
$m$select count(*)::numeric from org_tasks
    where status in ('proposed','assigned','in_progress') and decided_by is null$m$
where os_key='operations' and horizon='weekly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from org_tasks
    where status = 'in_progress' and updated_at < now() - interval '1 day'$m$
where os_key='operations' and horizon='daily';

-- ── technology ──────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where ok) / nullif(count(*),0), 2)
     from health_checks where created_at > now() - interval '90 days'$m$
where os_key='technology' and horizon='strategic';

update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where ok) / nullif(count(*),0), 2)
     from health_checks where created_at > now() - interval '365 days'$m$
where os_key='technology' and horizon='annual';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from continuity_plan
    where last_tested is null or last_tested < now() - interval '90 days'$m$
where os_key='technology' and horizon='quarterly';

update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where status='ok') / nullif(count(*),0), 2)
     from agent_runs where started_at > now() - interval '7 days'$m$
where os_key='technology' and horizon='weekly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from health_checks
    where not ok and created_at > now() - interval '1 day'$m$
where os_key='technology' and horizon='daily';

-- ── finance ─────────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select count(*)::numeric from finance_snapshots where created_at > now() - interval '35 days'$m$
where os_key='finance' and horizon='strategic';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from finance_reports where created_at > now() - interval '365 days'$m$
where os_key='finance' and horizon='annual';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from department_budget
    where coalesce(monthly_aed,0) > 0
      and 100.0 * coalesce(spent_aed,0) / nullif(monthly_aed,0) >= coalesce(halt_at_pct,100)$m$
where os_key='finance' and horizon='quarterly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from supplier_dues
    where coalesce(status,'') <> 'paid' and due_date < current_date and last_reminder_at is null$m$
where os_key='finance' and horizon='weekly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from gl_journal where coalesce(status,'') <> 'posted'$m$
where os_key='finance' and horizon='daily';

-- ── legal_gov ───────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where coalesce(reasons::text,'') <> '')
                / nullif(count(*),0), 2)
     from decision_log where created_at > now() - interval '90 days'$m$
where os_key='legal_gov' and horizon='strategic';

update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where present) / nullif(count(*),0), 2)
     from legal_checklist$m$
where os_key='legal_gov' and horizon='annual';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from risk_register
    where status = 'open' and (review_due is null or review_due < current_date)$m$
where os_key='legal_gov' and horizon='quarterly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from legal_reviews where reviewed_at > now() - interval '7 days'$m$
where os_key='legal_gov' and horizon='weekly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from compliance_sources
    where coalesce(active,true)
      and (last_checked_at is null or last_checked_at < now() - interval '7 days')$m$
where os_key='legal_gov' and horizon='daily';

-- ── knowledge ───────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where coalesce(validation_status,'unvalidated') <> 'unvalidated')
                / nullif(count(*),0), 2)
     from agent_knowledge$m$
where os_key='knowledge' and horizon='strategic';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from v_category_coverage where coalesce(standard_modules,0) >= 14$m$
where os_key='knowledge' and horizon='annual';

-- The objective's own second clause: "under 5% quarantined".
update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where validation_status = 'quarantined')
                / nullif(count(*),0), 2)
     from agent_knowledge$m$
where os_key='knowledge' and horizon='quarterly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from knowledge_exam_results
    where verdict = 'wrong' and not coalesce(filled,false)$m$
where os_key='knowledge' and horizon='weekly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from agent_knowledge
    where review_due < current_date and coalesce(confidence,1) >= 0.7$m$
where os_key='knowledge' and horizon='daily';

-- ── intelligence ────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where coalesce(measure_sql,'') <> '')
                / nullif(count(*),0), 2)
     from employee_kpi where active$m$
where os_key='intelligence' and horizon='strategic';

update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (
         where exists (select 1 from goal_period p
                        where p.goal_key = g.key and p.actual_value is not null))
                / nullif(count(*),0), 2)
     from company_goals g where g.active$m$
where os_key='intelligence' and horizon='annual';

-- NOT the objective's own sentence. "Forecast error under 20%" needs the outturn beside the
-- forecast and simulations stores only the run. This counts the runs recorded this quarter — the
-- population the error would be computed over once an outturn column exists.
update public.os_objective set measure_sql =
$m$select count(*)::numeric from simulations where created_at > now() - interval '90 days'$m$
where os_key='intelligence' and horizon='quarterly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from employee_kpi
    where active and coalesce(measure_sql,'') = ''$m$
where os_key='intelligence' and horizon='weekly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from market_intel where created_at > now() - interval '1 day'$m$
where os_key='intelligence' and horizon='daily';

-- ── evolution ───────────────────────────────────────────────────────────────────────────────────
update public.os_objective set measure_sql =
$m$select count(*)::numeric from outcome_record where created_at > now() - interval '90 days'$m$
where os_key='evolution' and horizon='strategic';

update public.os_objective set measure_sql =
$m$select round(100.0 * count(*) filter (where verdict = 'better')
                / nullif(count(*) filter (where coalesce(verdict,'pending') <> 'pending'), 0), 2)
     from outcome_record where created_at > now() - interval '365 days'$m$
where os_key='evolution' and horizon='annual';

update public.os_objective set measure_sql =
$m$select round(sum(cost_aed) / nullif(count(*),0), 4)
     from ai_cost_log where occurred_at > now() - interval '90 days'$m$
where os_key='evolution' and horizon='quarterly';

update public.os_objective set measure_sql =
$m$select count(*)::numeric from self_review where created_at > now() - interval '7 days'$m$
where os_key='evolution' and horizon='weekly';

-- Reads 0 today and that is CORRECT, not empty: fn_outcome_evaluate's first grading window opens
-- 2026-08-11, so nothing is due yet. Manufacturing a graded row to move this number would be
-- falsifying the measure, which is the failure this whole file exists to undo.
update public.os_objective set measure_sql =
$m$select count(*)::numeric from outcome_record
    where due_at < now() and coalesce(verdict,'pending') = 'pending'$m$
where os_key='evolution' and horizon='daily';


-- ── the routine that resolves them ──────────────────────────────────────────────────────────────
-- employee_kpi.measure_sql has had a resolver for weeks; os_objective.measure_sql had none, which
-- is why the columns sat empty. Per-objective exception handling is not defensive padding: one
-- measure that references a table dropped later must not stop the other forty-nine from being
-- measured.
--
-- A THROWN MEASURE AND A MEASURE THAT HONESTLY RETURNS NULL MUST NOT LOOK THE SAME. Several of
-- these divide by nullif(count,0) and legitimately read NULL on an unlaunched marketplace. So
-- measured_at is stamped ONLY on the path that ran: measured_at set means the SQL executed,
-- measured_at null on a row that has measure_sql means it threw. Without that, a broken measure
-- would be indistinguishable from an empty table and this file would rot silently — which is
-- precisely how the labels it replaces survived.
create or replace function public.fn_os_objective_measure()
returns TABLE(measured integer, failed integer)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v numeric; n_ok int := 0; n_bad int := 0;
begin
  for r in select id, measure_sql from os_objective
            where coalesce(active,true) and coalesce(measure_sql,'') <> '' loop
    begin
      execute r.measure_sql into v;
      update os_objective
         set actual_value = v, measured_at = now()
       where id = r.id;
      n_ok := n_ok + 1;
    exception when others then
      update os_objective
         set actual_value = null, measured_at = null
       where id = r.id;
      n_bad := n_bad + 1;
    end;
  end loop;
  return query select n_ok, n_bad;
end $function$;

-- Daily at 03:20, before the 04:45 os_review_weekly reads the OS layer. A measure refreshed once
-- by hand is a screenshot; the objective is only "measured" if the number keeps up with the rows.
select cron.schedule('os_objective_measure_daily', '20 3 * * *',
                     'select public.fn_os_objective_measure();');

-- Seed the first run on BOTH projects. Deploying a resolver and leaving actual_value null would be
-- shipping the same empty column the file opens by describing.
select * from public.fn_os_objective_measure();
