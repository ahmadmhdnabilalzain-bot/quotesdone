-- FOUR MORE COMPANY GOALS THE COMPANY COULD ALREADY ANSWER.
--
-- 43 of 63 goals still carried a target and no measure after #205. Four of them turn out to be
-- answerable from instruments that already exist - two of them from the exact pattern os_objective
-- #16 has been using all along. Every measure was EXECUTED on production before being stored:
--
--   autonomous_decision_rate   97.02%   target 90 at_least   MET
--   human_intervention          2.98%   target  2 at_most    MISSED, narrowly
--   ai_availability            98.49%   target 99.95         MISSED
--   failed_workflows           58.33%   target 0.5 at_most   MISSED, badly - see below
--
-- THE DENOMINATOR ON failed_workflows IS THE WHOLE POINT, and the obvious version would have been
-- wrong by two orders of magnitude. workflow_run holds 195 running, 7 failed, 5 done. Measured as
-- failures over ALL runs that is 7/207 = 3.38%; measured over runs that actually REACHED A TERMINAL
-- STATE it is 7/12 = 58.33%. The second is the honest number: a run still in flight has not
-- succeeded, and counting it as a success flatters the rate with work that has not finished.
--
-- STATED BECAUSE IT IS A FINDING, NOT A MEASURE: only 5 workflow_run rows in the whole table have
-- ever reached 'done', against 195 'running'. None of the running ones is older than 7 days and
-- attempts is 0 on every one, so they are not visibly retry-stuck - but a workflow engine that has
-- completed five runs in its lifetime is not executing the company's processes. That is a build
-- order for a session with room to trace the runner, and it is deliberately NOT dressed up as a
-- passing metric here.
--
-- ai_availability, BOUNDARY STATED: this is the share of model calls in ai_cost_log that returned
-- ok. That is AI availability as this company experiences it, which is what the goal is about. It
-- is NOT provider uptime and must not be quoted as such.
--
-- api_response (400ms) and workflow_automation were deliberately NOT given measures. The only
-- available proxies - average LLM latency (13,068 ms) and the org_tasks done-rate - measure
-- something other than what the goal names, and a number that measures the wrong subject is the
-- defect this whole session has been removing.

update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where not needs_founder)/nullif(count(*),0),2) from org_tasks where created_at > now()-interval '30 days'$q$
 where key='autonomous_decision_rate' and coalesce(measure_sql,'')='';

update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where needs_founder)/nullif(count(*),0),2) from org_tasks where created_at > now()-interval '30 days'$q$
 where key='human_intervention' and coalesce(measure_sql,'')='';

update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where ok)/nullif(count(*),0),2) from ai_cost_log where occurred_at > now()-interval '30 days'$q$
 where key='ai_availability' and coalesce(measure_sql,'')='';

-- Terminal runs only. See the note above: counting in-flight runs as successes flatters this.
update public.company_goals set measure_sql = $q$select round(100.0*count(*) filter (where status='failed')/nullif(count(*) filter (where status in ('failed','done')),0),2) from workflow_run$q$
 where key='failed_workflows' and coalesce(measure_sql,'')='';
