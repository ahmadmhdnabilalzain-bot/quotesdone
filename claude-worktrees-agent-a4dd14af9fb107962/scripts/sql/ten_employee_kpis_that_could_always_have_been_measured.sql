-- 29 EMPLOYEE KPIs HAD A TARGET AND NO MEASURE. TEN OF THEM WERE ALWAYS MEASURABLE.
--
-- os_objective #44 "Every KPI measurable and measured" reports these honestly since this session:
-- it read 0 this morning because it was measured at 03:20 and the 29 were written at 08:00, and it
-- reads 29 now. A KPI with a target and no measure cannot be missed, so its owner cannot be told
-- they are failing - the same defect as the 55 decorative company goals, one level down.
--
-- EVERY MEASURE BELOW WAS EXECUTED ON PRODUCTION BEFORE BEING STORED. Values at 2026-08-12:
--
--   ai_director            cost per agent_reasoning call     0.1408 AED   target 0.15      MET
--   prompt_engineer        avg prompt tokens, reasoning      11,882       target 18,000    MET
--   analytics_director     goals carrying a measured actual  23.81%       target 100%      MISSED
--   channel_specialist     hard bounce rate                  8.06%        target 2%        MISSED
--   notification_ops       notifications >24h unsent         36           target 0         MISSED
--   billing_specialist     reveals with no payment record    0            target 0         MET
--   supplier_retention     approved suppliers gone quiet     0            target 0         MET
--   supplier_intel_analyst suppliers with capability data    99.92%       target 80%       MET
--   category_curator       categories missing modules        2            target 0         MISSED
--   taxonomy_manager       categories off the specification  2            target 0         MISSED
--
-- TWO OF THESE ARE FINDINGS IN THEMSELVES, not just instrumentation:
--
--   36 notifications are older than 24 hours and still unsent. That is the exact gap named in the
--   email_delivery_stops scenario written earlier tonight - "nothing escalates when the queue stops
--   draining, so a multi-hour outage looks identical to a quiet day". It now has an owner and a
--   number, and fn_kpi_review will open a task on it at the next Monday sweep.
--
--   The hard bounce rate is 8.06% against a 2% target. That is the number that paused the supplier
--   invite campaign and put AED 1M out of reach through that channel. It was nobody's KPI until now.
--
-- suppliers_quiet = 0 and reveals_unpaid = 0 are MET only because there are no approved suppliers
-- and no transactions. They are honest measures of an empty business, not achievements, and they
-- will start reporting truthfully the moment either exists.

update public.employee_kpi set measure_sql = $q$select round(sum(cost_aed)/nullif(count(*),0),4) from ai_cost_log where task_class='agent_reasoning' and occurred_at > now()-interval '7 days'$q$
 where agent_key='ai_director' and kpi='Cost per reasoning call' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select round(avg(prompt_tokens)) from ai_cost_log where task_class='agent_reasoning' and occurred_at > now()-interval '7 days'$q$
 where agent_key='prompt_engineer' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select round(100.0*count(*) filter (where exists (select 1 from goal_period p where p.goal_key=g.key and p.actual_value is not null))/nullif(count(*),0),2) from company_goals g where g.active$q$
 where agent_key='analytics_director' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select round(100.0*count(*) filter (where invite_status='bounced')/nullif(count(*) filter (where invited_at is not null),0),2) from leads$q$
 where agent_key='channel_specialist' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select count(*)::numeric from notifications where coalesce(status,'')<>'sent' and created_at < now()-interval '24 hours'$q$
 where agent_key='notification_ops' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select count(*)::numeric from transactions where coalesce(fee_status,'')<>'paid'$q$
 where agent_key='billing_specialist' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select count(*)::numeric from leads where approval_status='approved' and coalesce(rv_responded,0)=0$q$
 where agent_key='supplier_retention' and kpi='Suppliers gone quiet' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select round(100.0*count(*) filter (where coalesce(capability_summary,'')<>'')/nullif(count(*),0),2) from leads$q$
 where agent_key='supplier_intel_analyst' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select count(*)::numeric from v_category_coverage where coalesce(standard_modules,0) < 8$q$
 where agent_key='category_curator' and coalesce(measure_sql,'')='';

update public.employee_kpi set measure_sql = $q$select count(*)::numeric from v_category_coverage where coalesce(agent_is_canonical,false)=false$q$
 where agent_key='taxonomy_manager' and coalesce(measure_sql,'')='';

-- THE 19 LEFT ALONE, AND WHY - so the next session does not re-derive it:
--   Needs a fixture or holdout set that does not exist: boq_analyst (BOQ extraction accuracy),
--     ai_qa_specialist (qualification accuracy vs holdout), test_automation_eng (regressions caught),
--     model_evaluator (task classes benchmarked), eng_manager (changes behind a failing-first check).
--     Building the fixture is the work; the SQL is trivial afterwards.
--   Needs demand that does not exist yet - 0 inquiries, 0 quotes: doc_intel_manager,
--     drawing_analyst, inquiry_router, inquiry_scoring, supplier_coverage (both KPIs),
--     supplier_retention (response rate), moderation_specialist, trust_safety_mgr, fraud_analyst.
--     These would return NULL or a meaningless 0 today; writing them now would put a decorative
--     number in front of an employee, which is the defect being removed.
--   Needs an instrument that does not exist: comms_manager ("alerts that reach the founder") -
--     founder_alerts has NO delivery state at all, only id/level/event/detail/channel/created_at,
--     so whether an alert reached him is genuinely unknowable today. Measured this session.
--   Business definition required: gov_relations_mgr, bi_analyst, payments_manager.
