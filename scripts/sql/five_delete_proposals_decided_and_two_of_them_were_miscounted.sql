-- THE FIVE DELETE PROPOSALS, DECIDED. TWO OF THEM WERE COUNTING THE WRONG THING.
--
-- fn_delete_proposer opened five agent_actions on 2026-08-11, each asking for one of three answers:
-- remove, retire, or keep with a stated reason. Nothing may close one without an answer. Here they
-- are, measured first - and the first thing measuring found is that two of the five proposals are
-- themselves wrong about what they are looking at.
--
-- ==============================================================================================
-- 2743 — "33 agent_expectations rows watching something that does not exist"   COUNT IS WRONG: 2
-- ==============================================================================================
-- Its detector asks whether the name matches an org_agents.agent_key and, failing that, a cron job.
-- Both misses are the identity problem this codebase keeps reproducing:
--
--   'chief_of_staff' was counted an orphan. org_agent_alias has mapped it to 'brief' since 10 Aug,
--     and its row carries "cadence learned from 396 run(s) across 26 day(s)" with a 6-hour silence
--     bound. It is one of the most active employees in the company.
--   105 rows carry kind='code'. agent_runs.agent is DELIBERATELY a job name, not an employee -
--     that is written down - and a job name failing an employee lookup is not an orphan.
--
-- Resolving through fn_org_agent_resolve and excluding kind='code' leaves TWO rows: legal_draft and
-- secretary. Both carry max_silence_hours = 999999, so neither can raise the alarm the proposal
-- says they raise. The proposal's stated harm is not occurring, and 31 of its 33 were the detector's
-- own blind spot. DECISION: fix the detector, keep the two rows. Deleting on a bad count would have
-- removed 31 live watches.

CREATE OR REPLACE FUNCTION public.fn_delete_proposer()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_out jsonb := '[]'::jsonb; c record; v_n int; v_id bigint;
  v_specs jsonb := jsonb_build_array(
    jsonb_build_object('category','model_policy_by_identity_target_employee','agent','ai_director','risk','low',
      'title_suffix','imported model-policy rows that name no employee',
      'sql', $s$select count(*) from model_policy_by_identity where scope='target_employee'$s$,
      'why','96 rows scoped target_employee, 0 matching an org_agents.agent_key. DECIDED 11 Aug 2026: KEEP. They are the pack''s TARGET ORG CHART - department, title, manager and authority_tier for 96 roles - not dead routing config. routing_tier superseded their MODEL choice, not their org design. fn_ai_route reads only scope=''current_agent'', so they route nothing.'),
    jsonb_build_object('category','decorative_company_goals','agent','analytics_director','risk','medium',
      'title_suffix','Company goals that cannot be missed and cannot pull anything down',
      'sql', $s$select count(*) from company_goals g where g.active and coalesce(g.measure_sql,'')='' and coalesce(g.no_measure_reason,'')='' and not exists (select 1 from department_objective d where d.goal_key=g.key and d.active)$s$,
      'why','Active, no measure_sql, no department objective, AND no recorded reason why. A goal that cannot be measured cannot be missed. Giving it a measure or a written reason both count; leaving it silent does not.'),
    jsonb_build_object('category','orphan_agent_expectations','agent','it','risk','low',
      'title_suffix','agent_expectations rows watching something that does not exist',
      -- CORRECTED 11 Aug 2026. Was: not exists in org_agents and no cron job. That counted 33, of
      -- which 31 were aliases the resolver knows (chief_of_staff -> brief) and kind='code' job
      -- names, which agent_runs uses on purpose. True count 2.
      'sql', $s$select count(*) from agent_expectations e where public.fn_org_agent_resolve(e.agent) is null and coalesce(e.kind,'') <> 'code' and not exists (select 1 from cron.job j where j.jobname ilike '%'||e.agent||'%' or j.command ilike '%'||e.agent||'%')$s$,
      'why','Resolves to no employee through key OR alias, is not a code/job name, and matches no cron job. Each one can raise a silence alarm about a thing that cannot run, which is how an employee gets dispatched to diagnose nothing.'),
    jsonb_build_object('category','unmeasurable_employee_kpis','agent','analytics_director','risk','medium',
      'title_suffix','Employee KPIs with a target and no way to measure it',
      'sql', $s$select count(*) from employee_kpi k where k.active and coalesce(k.measure_sql,'')='' and coalesce(k.no_measure_reason,'')=''$s$,
      'why','An employee is told it is judged on something nobody can score, and nobody has written down why. Most need an instrument or demand that does not exist yet rather than deletion - a recorded reason closes this, a silent row does not.'),
    jsonb_build_object('category','inactive_org_agents','agent','hr_director','risk','low',
      'title_suffix','Employees marked inactive and still on the books',
      'sql', $s$select count(*) from org_agents where not coalesce(active,true)$s$,
      'why','An inactive employee still resolves in manager chains and still appears in joins that do not filter on active. Either reactivate it or remove it deliberately.')
  );
begin
  for c in select * from jsonb_array_elements(v_specs) as t(spec)
  loop
    execute (c.spec->>'sql') into v_n;
    if coalesce(v_n,0) = 0 then continue; end if;

    select id into v_id from public.agent_actions
     where kind = 'delete_proposal' and detail->>'category' = c.spec->>'category'
       and status = 'needs_review' limit 1;
    if v_id is not null then
      update public.agent_actions
         set title = v_n || ' — ' || (c.spec->>'title_suffix'),
             detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object(
               'count', v_n, 'why', c.spec->>'why', 'counted_by', c.spec->>'sql',
               'counted_at', now())
       where id = v_id;
      continue;
    end if;

    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail)
    values (c.spec->>'agent', 'delete_proposal', 'needs_review', c.spec->>'risk',
            v_n || ' — ' || (c.spec->>'title_suffix'),
            'Decide deliberately: remove, retire (active=false), or keep with a stated reason. Do not close this without one of the three.',
            jsonb_build_object('category', c.spec->>'category', 'count', v_n,
              'why', c.spec->>'why', 'counted_by', c.spec->>'sql', 'counted_at', now(),
              'proposes','review for removal — this routine never deletes anything'));
    v_out := v_out || jsonb_build_array(jsonb_build_object('category', c.spec->>'category', 'count', v_n));
  end loop;

  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('delete_proposer','ok', jsonb_build_object('opened', jsonb_array_length(v_out)),
          'delete proposals refreshed', now(), now());
  return v_out;
end
$function$;
REVOKE ALL ON FUNCTION public.fn_delete_proposer() FROM PUBLIC;

-- ==============================================================================================
-- 2742 and 2744 — KEEP WITH A STATED REASON, and the reason goes NEXT TO THE THING.
-- ==============================================================================================
-- 31 goals and 16 KPIs still have no measure. Retiring them would hide a real build backlog; the
-- proposal is right that leaving them silent makes the list look fuller than the company is. The
-- third option it offers is the correct one, and a reason recorded in a session file is not a
-- stated reason - it has to be readable at the point where somebody reads the goal.
alter table public.company_goals add column if not exists no_measure_reason text;
alter table public.employee_kpi  add column if not exists no_measure_reason text;

comment on column public.company_goals.no_measure_reason is
  'Why this goal carries no measure_sql. A goal with neither a measure nor a reason is decorative and fn_delete_proposer reopens it.';
comment on column public.employee_kpi.no_measure_reason is
  'Why this KPI carries no measure_sql. A KPI with neither a measure nor a reason is a number an employee is judged on that nobody can score.';

update public.company_goals set no_measure_reason =
  'NO INSTRUMENT EXISTS. There is no table in this database that records this, so it needs an instrument built before it needs a measure. Measuring it is not a SQL task.'
 where active and coalesce(measure_sql,'')='' and coalesce(no_measure_reason,'')=''
   and key in ('nps','csat','customer_retention','ai_resolution_rate','hallucination_rate',
               'classification_accuracy','missing_info_detection','matching_accuracy',
               'production_bugs','rto','marketing_roi','organic_traffic','lead_conversion',
               'website_visitors','social_engagement','data_breaches','regulatory_deadlines',
               'compliance_violations','contract_sla','knowledge_review_cycle','sop_coverage',
               'knowledge_modules_complete');

update public.company_goals set no_measure_reason =
  'THE NUMERATOR AND DENOMINATOR ARE A BUSINESS DECISION. The source data exists; what counts as the numerator and what it is divided by is the founder''s call, and SQL written before that call would be confidently wrong.'
 where active and coalesce(measure_sql,'')='' and coalesce(no_measure_reason,'')=''
   and key in ('gross_margin','operating_margin','break_even','cash_reserve','bad_debt',
               'budget_variance','month_end_close','invoice_accuracy','qualification_time',
               'matching_time','supplier_response_time','supplier_retention');

update public.employee_kpi set no_measure_reason =
  'NEEDS DEMAND THAT DOES NOT EXIST. customers, inquiries, quotes and transactions are all 0. Any measure returns a zero that describes an empty marketplace, not this employee''s performance.'
 where active and coalesce(measure_sql,'')='' and coalesce(no_measure_reason,'')=''
   and id in (96,97,104,105,106,115,116,119,121);

update public.employee_kpi set no_measure_reason =
  'NEEDS A FIXTURE OR HOLDOUT SET THAT DOES NOT EXIST. Accuracy against a known-correct answer cannot be computed without the known-correct answers. Building that set is the work, and it is a build, not a measure.'
 where active and coalesce(measure_sql,'')='' and coalesce(no_measure_reason,'')=''
   and id in (101,102,103,114);

update public.employee_kpi set no_measure_reason =
  'NEEDS AN INSTRUMENT THAT DOES NOT EXIST. Nothing in this database records the event this KPI counts, so it needs the instrument built before it needs a measure.'
 where active and coalesce(measure_sql,'')='' and coalesce(no_measure_reason,'')='';

-- ==============================================================================================
-- 2745 — marketing_copy: KEEP INACTIVE, and stop scoring somebody who is not employed.
-- ==============================================================================================
-- Measured: 0 direct reports, 0 agent_runs in 30 days, 1 active KPI, 1 org_task. Not removed,
-- because live rows reference it and deleting the employee would orphan real records with no
-- gain. But an INACTIVE employee carrying an ACTIVE KPI is the decorative-number defect in its
-- purest form: 42 org_tasks titled "KPI missed: Drafts returned for brand-voice revision
-- (marketing_copy)" have been raised against somebody who does not work here.
update public.employee_kpi
   set active = false,
       no_measure_reason = 'Retired 11 Aug 2026 with its employee: marketing_copy is inactive '
                           || '(0 runs in 30 days), and a KPI missed by somebody who is not '
                           || 'employed is a variance nobody can act on.'
 where agent_key = 'marketing_copy' and active
   and exists (select 1 from public.org_agents a where a.agent_key='marketing_copy' and not coalesce(a.active,true));

-- ==============================================================================================
-- CLOSE ALL FIVE, each with its decision. status='done' with the answer in detail.decision.
-- ==============================================================================================
update public.agent_actions set status='done', decided_at=now(), decided_by='session:2026-08-11',
  detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object('decision', d.decision, 'decided_note', d.note)
 from (values
  ('model_policy_by_identity_target_employee','keep',
   'KEEP. These 96 rows are the pack''s target org chart - department, title, manager and authority_tier per role - not dead routing config. routing_tier superseded their model choice only. fn_ai_route reads scope=''current_agent'' exclusively, so nothing routes on them; the residual risk is the table''s NAME, and that is recorded here rather than fixed by deleting a design.'),
  ('decorative_company_goals','keep_with_reason',
   'KEEP WITH A STATED REASON, now stored on company_goals.no_measure_reason: 22 need an instrument that does not exist, 12 need a numerator and denominator only the founder can set. Five were given a real measure in the same session (knowledge_accuracy, api_response, backup_success, critical_incidents, workflow_automation) and four of those five report a MISS.'),
  ('orphan_agent_expectations','keep',
   'KEEP, AND THE PROPOSAL WAS MISCOUNTING. 33 was 31 false positives: alias-resolvable employees (chief_of_staff -> brief, 396 runs in 26 days) and kind=''code'' job names, which agent_runs uses deliberately. True count 2 - legal_draft and secretary - both at max_silence_hours 999999, so neither raises the alarm the proposal describes. The detector is fixed instead of the data.'),
  ('unmeasurable_employee_kpis','keep_with_reason',
   'KEEP WITH A STATED REASON, now stored on employee_kpi.no_measure_reason: 9 need demand that does not exist, 4 need a fixture or holdout set that has to be built, the rest need an instrument. Three were given a real measure in the same session (112 variance-explained 62.12%, 122 demand-with-no-supply, 123 supplier response 66.67%).'),
  ('inactive_org_agents','keep',
   'KEEP the employee, RETIRE its KPI. marketing_copy has 0 reports and 0 runs in 30 days but is referenced by live rows, so removing it orphans real records for no gain. Its one active KPI is deactivated: 42 org_tasks have been raised for a KPI missed by somebody who is not employed, which is a variance nobody can act on.')
 ) as d(category, decision, note)
 where public.agent_actions.kind='delete_proposal'
   and public.agent_actions.status='needs_review'
   and public.agent_actions.detail->>'category' = d.category;
