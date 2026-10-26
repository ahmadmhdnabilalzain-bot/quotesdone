-- 55 COMPANY GOALS CARRIED A TARGET AND NO MEASURE. TWELVE OF THEM ALWAYS COULD.
--
-- "A goal with no measure_sql cannot be missed, so it cannot pull anything down, so no department
-- can be told it is failing. Either give each one a measure or retire it."
--
-- fn_goal_decompose can only hand a goal down to its department if the goal carries a measure, so
-- these 55 were the ceiling on the whole chain: 8 of 63 goals decomposable. This file measures the
-- twelve whose source columns were verified to exist first, and states plainly which of the
-- remaining 43 cannot be measured and why - rather than inventing SQL that returns a confident
-- wrong number. A measure that runs and returns the wrong value is worse than no measure at all,
-- because fn_dept_objective_measure and fn_os_objective_measure only trap ERRORS; they cannot
-- detect a query that succeeds and lies.
--
-- EVERY MEASURE BELOW WAS EXECUTED ON PRODUCTION BEFORE BEING STORED. Values at 2026-08-11 18:55 UTC:
--
--   customers_registered      0        suppliers_verified        0        rfqs_processed        0
--   customers_active          0        suppliers_active          0        revenue_monthly_m12   0
--   rfqs_successful         NULL       quotes_per_rfq          NULL       collection_rate     NULL
--   supplier_response_rate   67.00     uptime                90.53       categories_covered   20
--
-- The zeros are correct and are the point: this company has no customers, no inquiries and no
-- transactions, and until now the 55 goals could not say so. NULL means "no denominator yet" and is
-- deliberately not 0 - least(100.0, NULL) returning 100.0 is what put 97.7% attainment in the
-- founder's email on a zero-revenue day.
--
-- ONE SCALE TRAP CAUGHT BY MEASURING, NOT BY READING. leads.rv_response_rate is a 0..1 FRACTION
-- (max 1.000, min 0.000 over 3 rows with reveals), while the goal supplier_response_rate targets
-- 85 PERCENT. Stored raw it would have reported 0.67 against a target of 85 and marked a healthy
-- 67% response rate as a catastrophic miss. It is multiplied by 100 below.

update public.company_goals set measure_sql = $q$select count(*)::numeric from customers$q$
 where key='customers_registered' and measure_sql is null;

update public.company_goals set measure_sql = $q$select count(distinct customer_id)::numeric from inquiries where created_at > now() - interval '30 days'$q$
 where key='customers_active' and measure_sql is null;

update public.company_goals set measure_sql = $q$select count(*)::numeric from leads where approval_status='approved'$q$
 where key='suppliers_verified' and measure_sql is null;

update public.company_goals set measure_sql = $q$select count(*)::numeric from leads where approval_status='approved' and coalesce(matching_blocked,false)=false$q$
 where key='suppliers_active' and measure_sql is null;

update public.company_goals set measure_sql = $q$select count(*)::numeric from inquiries where created_at > now() - interval '365 days'$q$
 where key='rfqs_processed' and measure_sql is null;

update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where completed_at is not null)/nullif(count(*),0),2) from inquiries where created_at > now() - interval '90 days'$q$
 where key='rfqs_successful' and measure_sql is null;

update public.company_goals set measure_sql = $q$select round(avg(c),2) from (select count(q.id) c from inquiries i left join quotes q on q.inquiry_id=i.id where i.created_at > now() - interval '90 days' group by i.id) x$q$
 where key='quotes_per_rfq' and measure_sql is null;

-- x100: the column is a fraction, the goal is a percentage. See the trap noted above.
update public.company_goals set measure_sql = $q$select round(100.0*avg(rv_response_rate),2) from leads where rv_reveals > 0$q$
 where key='supplier_response_rate' and measure_sql is null;

update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where ok)/nullif(count(*),0),2) from health_checks where created_at > now() - interval '30 days'$q$
 where key='uptime' and measure_sql is null;

update public.company_goals set measure_sql = $q$select count(*)::numeric from v_category_coverage where coalesce(supplier_supply,0) > 0$q$
 where key='categories_covered' and measure_sql is null;

update public.company_goals set measure_sql = $q$select coalesce(sum(revenue_aed),0)::numeric from finance_snapshots where period_start > now() - interval '31 days'$q$
 where key='revenue_monthly_m12' and measure_sql is null;

update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where fee_status='paid')/nullif(count(*),0),2) from transactions$q$
 where key='collection_rate' and measure_sql is null;

-- THE 43 NOT MEASURED HERE, AND WHY - so the next session does not re-derive it:
--   No source table exists in this database at all: nps, csat, customer_retention, ai_resolution_rate,
--     hallucination_rate, classification_accuracy, missing_info_detection, matching_accuracy,
--     knowledge_accuracy, production_bugs, critical_incidents, rto, backup_success, api_response,
--     ai_availability, marketing_roi, organic_traffic, lead_conversion, website_visitors,
--     social_engagement, data_breaches, regulatory_deadlines, compliance_violations, contract_sla.
--     These need an instrument built before they need a measure. Measuring them is not a SQL task.
--   Source exists but the definition is a business decision the founder holds: gross_margin,
--     operating_margin, break_even, cash_reserve, bad_debt, budget_variance, month_end_close,
--     invoice_accuracy, autonomous_decision_rate, human_intervention, workflow_automation,
--     failed_workflows, sop_coverage, knowledge_modules_complete, knowledge_review_cycle,
--     qualification_time, matching_time, supplier_response_time, supplier_retention.
--     Each needs its numerator and denominator agreed before SQL can be honest about it.
