-- FIVE COMPANY GOALS AND THREE EMPLOYEE KPIs THE COMPANY COULD ALREADY ANSWER.
--
-- 39 of 63 active goals and 19 of 124 active KPIs still carried a target and no measure. This file
-- adds the eight whose source I verified EXISTS and then EXECUTED on production before storing.
-- Values at 2026-08-11 22:05 UTC:
--
--   knowledge_accuracy      55.80  against 98    MISSED, badly
--   api_response              316  against 400   met
--   backup_success          85.56  against 100   MISSED
--   critical_incidents         16  against 0     MISSED
--   workflow_automation     96.32  against 98    MISSED, narrowly
--   kpi 112 variance-explained  62.12  against 90    MISSED
--   kpi 122 demand with no supply  0  against 0     met, and see the note
--   kpi 123 supplier response   66.67  against 60    met
--
-- Six of the eight report a MISS on their first measurement. That is the point: a goal with no
-- measure cannot be missed, so no department can be told it is failing, and until tonight these
-- six were silent. fn_goal_decompose can only hand a goal down to a department if it carries a
-- measure, so each of these also becomes decomposable.

-- ---------------------------------------------------------------------------------------------
-- knowledge_accuracy — "AI knowledge accuracy above 98%", metric "Knowledge exam pass rate".
-- knowledge_exam_results has 558 graded answers: 308 correct, 120 not_covered, 80 wrong,
-- 44 partial, 6 unverifiable. 'unverifiable' is excluded from the denominator because it records
-- the GRADER failing to decide, not the examinee failing to know — counting it as a miss would
-- charge the employee for the examiner's problem. 'not_covered' IS counted: the exam asked
-- something the knowledge base should have held and did not, which is exactly the gap this goal
-- exists to close.
update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where verdict='correct')/nullif(count(*) filter (where verdict <> 'unverifiable'),0),2) from knowledge_exam_results$q$
 where key='knowledge_accuracy' and measure_sql is null;

-- api_response — "Average API response under 400ms".
-- health_checks holds two kinds and only 'http' carries a latency; 'agent_runs' rows have
-- latency_ms NULL. avg() ignores nulls, so leaving the filter out would have produced the right
-- number by accident and the wrong number the day a third kind with a latency is added.
update public.company_goals set measure_sql = $q$select round(avg(latency_ms)) from health_checks where check_kind='http' and latency_ms is not null and created_at > now() - interval '30 days'$q$
 where key='api_response' and measure_sql is null;

-- backup_success — "100% backup success". doc_backups over 90 days: 154 done, 26 error.
update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where status='done')/nullif(count(*),0),2) from doc_backups where created_at > now() - interval '90 days'$q$
 where key='backup_success' and measure_sql is null;

-- critical_incidents — "Zero critical incidents".
-- THE SEVERITY VOCABULARY DOES NOT CONTAIN THE WORD 'critical'. os_incidents uses high/low, and
-- 'high' is the worst class this company has ever recorded (16 rows: 15 silent_failure, 2 ai_spend,
-- 1 other). Measuring severity='critical' literally would return 0 forever for a VOCABULARY reason
-- and read as "we have had no critical incidents" — the decorative number this whole exercise
-- exists to stop. 'critical' is accepted too so the measure keeps working if the vocabulary grows.
update public.company_goals set measure_sql = $q$select count(*)::numeric from os_incidents where severity in ('critical','high') and opened_at > now() - interval '365 days'$q$
 where key='critical_incidents' and measure_sql is null;

-- workflow_automation — "Workflow automation above 98%", metric "Automated workflow share".
-- Measurable only as of tonight, and only because of the resolver: a step is machine-performable
-- when it is not behind the founder gate AND its actor_role names somebody the company can reach —
-- either a run-relative position (owner/Director, resolved per run) or an employee the global
-- resolver can find. Before the title arm this would have read 96 of 163; the six that remain are
-- the four founder gates plus two steps addressed to "domain specialist", which is nobody.
update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where coalesce(gate,'') <> 'founder' and (lower(btrim(actor_role)) in ('owner','director','dept_head') or public.fn_org_agent_resolve(actor_role) is not null))/nullif(count(*),0),2) from workflow_step$q$
 where key='workflow_automation' and measure_sql is null;

-- ---------------------------------------------------------------------------------------------
-- EMPLOYEE KPIs
-- ---------------------------------------------------------------------------------------------

-- 112 bi_analyst — "Variance explained with a root cause", share of missed KPIs with a named cause.
-- fn_kpi_review writes one org_task per missed KPI titled 'KPI missed: …', and
-- fn_org_task_root_cause_guard is what puts a cause on it. 66 such tasks, 41 with a root_cause.
-- Deliberately NOT measured over all org_tasks: 41 of 450 done tasks carry a cause, but most of
-- those 450 are not variances and were never supposed to have one. A denominator that inflates the
-- miss is the same defect as one that hides it.
update public.employee_kpi set measure_sql = $q$select round(100.0*count(*) filter (where root_cause is not null)/nullif(count(*),0),2) from org_tasks where title like 'KPI missed:%'$q$
 where id=112 and measure_sql is null;

-- 122 supplier_coverage — "Demand with no supply": categories carrying inquiry demand and no
-- matchable supplier. Returns 0 TODAY, and the honest reading is "there is no demand yet", not
-- "coverage is perfect". It is stored anyway because it is the correct question and it starts
-- answering the moment the first inquiry lands — unlike its sibling 121, which needs suppliers to
-- have RESPONDED to something and so cannot be answered at all yet.
update public.employee_kpi set measure_sql = $q$select count(*)::numeric from v_category_coverage where coalesce(supplier_supply,0)=0 and name in (select distinct category from inquiries where created_at > now() - interval '90 days')$q$
 where id=122 and measure_sql is null;

-- 123 supplier_retention — "Supplier response rate". Same source and the same x100 as the
-- company goal supplier_response_rate: leads.rv_response_rate is a 0..1 FRACTION and the KPI
-- target is 60 PERCENT. Stored raw, a healthy 66.67% would have been filed as a catastrophic miss.
update public.employee_kpi set measure_sql = $q$select round(100.0*avg(rv_response_rate),2) from leads where rv_reveals > 0$q$
 where id=123 and measure_sql is null;

-- ---------------------------------------------------------------------------------------------
-- THE ONES I LOOKED AT AND DID NOT WRITE, so the next session does not re-derive it:
--
--   data_breaches, regulatory_deadlines — os_incidents.kind holds silent_failure, ai_spend and
--     other. Nothing has ever written a breach or a deadline kind, so any measure returns 0 for a
--     VOCABULARY reason and would read as a clean record. That is a decorative number.
--   sop_coverage — os_runbooks (106 rows) is keyed to os_key; workflow (19 processes) is not.
--     There is no link between a runbook and a process, and inventing the join is a content
--     decision about which runbook documents which process, not a SQL one.
--   knowledge_review_cycle — "days since last review" needs a review date. kb_revisions.decided_at
--     is NULL on all 9,416 rows, so the column that would answer it has never been written.
--   production_bugs — would be the same expression as critical_incidents against the same 16 rows.
--     Two goals sharing one number is not two measures.
--   121 supplier_coverage, 96/97 inquiry_router/inquiry_scoring, 104/106 trust_safety and
--     moderation, 119 payments_manager — all need demand that does not exist. Their zeros would
--     describe an empty marketplace, not performance.
--   103/114 boq_analyst, ai_qa_specialist — need a fixture or holdout set that does not exist.
--     Building the fixture is the work, and it is a real build, not a measure.
