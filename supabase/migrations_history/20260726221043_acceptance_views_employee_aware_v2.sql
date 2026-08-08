-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726221043   name: acceptance_views_employee_aware_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

drop view if exists public.v_org_chart;
create view public.v_org_chart as
select d.sort, d.dept_key, d.name as department, d.lead_agent as head_agent,
       a.agent_key, a.title, a.seniority, a.manager_key, a.role, a.responsibilities, a.active,
       (a.agent_key = d.lead_agent) as is_head,
       (select count(*) from org_agents r where r.manager_key = a.agent_key) as direct_reports,
       (select count(*) from org_agents x where x.department = d.dept_key) as dept_headcount
from org_departments d
left join org_agents a on a.department = d.dept_key
where d.active;

drop view if exists public.v_capability_matrix;
create view public.v_capability_matrix as
select a.agent_key, a.title, a.seniority, a.department, a.manager_key,
       (select count(*) from org_agents r where r.manager_key = a.agent_key) as direct_reports,
       (select count(*) from employee_kpi k where k.agent_key = a.agent_key and k.active) as owned_kpis,
       (select count(*) from employee_authority ea where ea.agent_key = a.agent_key) as personal_authorities,
       (select count(*) from org_authority au where au.dept_key = a.department) as dept_authorities,
       (select count(*) from org_action_executor e where e.department = a.department and e.active) as executable_actions,
       (select count(*) from agent_knowledge k where k.agent_key = a.agent_key) as knowledge_topics,
       (select count(*) from agent_memory m where m.agent_key = a.agent_key) as memories,
       case when (select count(*) from employee_kpi k where k.agent_key = a.agent_key and k.active) = 0 then 'NO KPI'
            when (select count(*) from org_action_executor e where e.department = a.department and e.active) = 0 then 'CANNOT ACT'
            else 'ok' end as employee_status
from org_agents a;

create or replace view public.v_approval_trace as
select rc.subject_type, rc.subject_id, rc.dept_key,
       rc.id as step, rc.stage, rc.author_agent, rc.reviewer_agent,
       rc.decision, rc.reason, rc.violated_rule, rc.confidence, rc.created_at
from review_chain rc;

comment on view public.v_approval_trace is 'Acceptance test target: every approval step assembled from rows, never narrated.';
