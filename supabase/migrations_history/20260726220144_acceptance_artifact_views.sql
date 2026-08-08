-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726220144   name: acceptance_artifact_views
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The ten acceptance artifacts, built as LIVE VIEWS rather than static documents,
-- so they cannot drift from reality. Regenerate the acceptance pack by selecting from these.

-- 1. Organization Chart
create or replace view public.v_org_chart as
select d.sort, d.dept_key, d.name as department, d.charter, d.north_star,
       d.lead_agent as head_agent, a.agent_key, a.role, a.kind, a.active,
       (a.agent_key = d.lead_agent) as is_head,
       (select count(*) from org_agents x where x.department = d.dept_key) as dept_headcount
from org_departments d
left join org_agents a on a.department = d.dept_key
where d.active;

-- 2. Capability Matrix: employee vs responsibilities, permissions, executable actions, knowledge
create or replace view public.v_capability_matrix as
select a.agent_key, a.department, a.role,
       (select count(*) from org_authority au where au.dept_key = a.department) as authority_rules,
       (select count(*) from org_action_executor e where e.department = a.department and e.active) as executable_actions,
       (select count(*) from agent_knowledge k where k.agent_key = a.agent_key) as knowledge_topics,
       (select count(*) from agent_memory m where m.agent_key = a.agent_key) as memories,
       (select count(*) from agent_runs r where r.agent = a.agent_key and r.started_at > now() - interval '30 days') as runs_30d,
       case when (select count(*) from org_action_executor e where e.department = a.department and e.active) = 0
            then 'CANNOT ACT - advisory only' else 'can act' end as execution_status
from org_agents a;

-- 3. Decision Matrix: what each department may approve / execute / must escalate
create or replace view public.v_decision_matrix as
select au.dept_key, au.action_class, au.max_tier, au.threshold_aed, au.note,
       exists (select 1 from org_action_executor e
               where e.department = au.dept_key and e.action_class = au.action_class and e.active) as executor_wired,
       (select count(*) from decision_log dl where dl.actor = au.dept_key) as decisions_logged,
       case when au.max_tier = 'gated' then 'founder approval required'
            when au.max_tier = 'advisory' then 'recommend only'
            else 'autonomous' end as effect
from org_authority au;

-- 4. Knowledge Matrix
create or replace view public.v_knowledge_matrix as
select k.agent_key, k.layer, count(*) as topics, round(avg(length(k.content))) as avg_chars,
       count(*) filter (where k.topic in ('Industry Knowledge','Products & Services','Technical Knowledge',
         'Supplier Knowledge','Quotation Knowledge','Documents Knowledge','UAE Regulations & Authorities',
         'Inquiry Qualification Logic')) as spec_modules_present,
       max(k.updated_at) as last_updated
from agent_knowledge k group by k.agent_key, k.layer;

-- 5. Memory Matrix
create or replace view public.v_memory_matrix as
select 'agent' as scope_type, m.agent_key as scope, m.kind, count(*) as rows_held,
       max(m.created_at) as newest, min(m.created_at) as oldest
from agent_memory m group by m.agent_key, m.kind
union all
select 'department', o.scope, o.kind, count(*), max(o.created_at), min(o.created_at)
from org_memory o group by o.scope, o.kind;

-- 6. Test Matrix
create or replace view public.v_test_matrix as
select r.agent as suite,
       count(*) as runs_14d,
       count(*) filter (where r.status = 'ok') as passed,
       count(*) filter (where r.status = 'error') as failed,
       round(100.0 * count(*) filter (where r.status = 'ok') / greatest(count(*),1)) as pass_pct,
       max(r.started_at) as last_run,
       case when count(*) filter (where r.status = 'error') = 0 then 'PASS'
            when count(*) filter (where r.status = 'ok') = 0 then 'FAIL'
            else 'FLAKY' end as verdict
from agent_runs r
where r.started_at > now() - interval '14 days'
  and (r.agent ilike '%test%' or r.agent ilike '%eval%' or r.agent ilike '%qa%'
       or r.agent ilike '%exam%' or r.agent ilike '%smoke%' or r.agent ilike '%drill%'
       or r.agent ilike '%canary%' or r.agent ilike '%health%')
group by r.agent;

-- 7. Gap Report
create or replace view public.v_gap_report as
select priority, source_doc, area, item, status, verdict_at_audit, evidence, notes, updated_at
from spec_backlog where status <> 'done';

-- 8. Workflow Matrix (which departments can participate in each business process)
create or replace view public.v_workflow_matrix as
select e.department, e.action_class, e.active as executor_active, e.note,
       au.max_tier, au.threshold_aed
from org_action_executor e
full outer join org_authority au
  on au.dept_key = e.department and au.action_class = e.action_class;

comment on view public.v_org_chart is 'Acceptance artifact 1: organisation chart';
comment on view public.v_capability_matrix is 'Acceptance artifact 2: employee vs responsibilities, permissions, knowledge';
comment on view public.v_workflow_matrix is 'Acceptance artifact 3: which employees participate in each process';
comment on view public.v_decision_matrix is 'Acceptance artifact 4: approve / reject / escalate / execute';
comment on view public.v_knowledge_matrix is 'Acceptance artifact 5: knowledge bases per employee';
comment on view public.v_memory_matrix is 'Acceptance artifact 6: what each employee remembers';
comment on view public.v_test_matrix is 'Acceptance artifact 9: automated tests proving capabilities';
comment on view public.v_gap_report is 'Acceptance artifact 10: candid list of partial and planned features';
