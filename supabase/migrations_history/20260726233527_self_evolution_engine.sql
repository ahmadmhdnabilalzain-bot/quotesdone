-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726233527   name: self_evolution_engine
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Item 15: the company reviews itself. Deterministic detection, no LLM cost.
create or replace function public.fn_self_review()
returns jsonb language plpgsql security definer set search_path = public
as $fn$
declare v_found int := 0;
begin
  -- Stale knowledge: past its review date
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'stale_knowledge', k.agent_key||' / '||k.topic,
         'Knowledge past its review date',
         'review_due '||k.review_due||', owner '||coalesce(k.owner_agent,'none')||', confidence '||coalesce(k.confidence::text,'unset'),
         'Re-research and revalidate, or mark superseded'
  from agent_knowledge k
  where k.review_due < current_date
    and not exists (select 1 from self_review s where s.review_type='stale_knowledge'
                     and s.subject = k.agent_key||' / '||k.topic and s.status='proposed');
  get diagnostics v_found = row_count;

  -- Departments that cannot act
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'overloaded_dept', d.dept_key,
         'Department has authority but no wired executor',
         (select count(*)::text from org_authority a where a.dept_key=d.dept_key)||' authority rules, 0 executors',
         'Wire an executor or remove the authority rule'
  from org_departments d
  where d.active
    and not exists (select 1 from org_action_executor e where e.department=d.dept_key and e.active)
    and not exists (select 1 from self_review s where s.review_type='overloaded_dept' and s.subject=d.dept_key and s.status='proposed');

  -- Employees with no KPI
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'missed_kpi', a.agent_key,
         'Employee has no measurable KPI',
         'title '||coalesce(a.title,'none')||', department '||a.department,
         'Assign a KPI tied to a company goal, or retire the role'
  from org_agents a
  where a.active
    and not exists (select 1 from employee_kpi k where k.agent_key=a.agent_key and k.active)
    and not exists (select 1 from self_review s where s.review_type='missed_kpi' and s.subject=a.agent_key and s.status='proposed');

  -- Recurring failures: any agent failing more than 3 times in 7 days
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'recurring_failure', r.agent,
         'Agent failing repeatedly',
         count(*)||' failures in 7 days; latest: '||left(coalesce(max(r.note),''),160),
         'Diagnose root cause; this is an automation candidate if the fix is mechanical'
  from agent_runs r
  where r.started_at > now() - interval '7 days' and r.status='error'
  group by r.agent having count(*) > 3
    and not exists (select 1 from self_review s where s.review_type='recurring_failure' and s.subject=r.agent and s.status='proposed');

  -- Categories with supply but no standard knowledge
  insert into self_review (review_type, subject, finding, evidence, proposal)
  select 'stale_sop', v.catalog_slug,
         'Category has supplier supply but no standard knowledge base',
         v.supplier_supply||' suppliers in pipeline, coverage '||v.coverage,
         'Build the 14-module knowledge base; supplier supply is already there'
  from v_category_coverage v
  where v.coverage <> 'COMPLIANT' and v.supplier_supply >= 100
    and not exists (select 1 from self_review s where s.review_type='stale_sop' and s.subject=v.catalog_slug and s.status='proposed');

  return jsonb_build_object(
    'stale_knowledge', (select count(*) from self_review where review_type='stale_knowledge' and status='proposed'),
    'depts_cannot_act', (select count(*) from self_review where review_type='overloaded_dept' and status='proposed'),
    'employees_no_kpi', (select count(*) from self_review where review_type='missed_kpi' and status='proposed'),
    'recurring_failures', (select count(*) from self_review where review_type='recurring_failure' and status='proposed'),
    'categories_needing_knowledge', (select count(*) from self_review where review_type='stale_sop' and status='proposed'),
    'total_open', (select count(*) from self_review where status='proposed'));
end;
$fn$;

revoke execute on function public.fn_self_review() from anon, authenticated, public;
grant execute on function public.fn_self_review() to service_role;

comment on function public.fn_self_review is 'Item 15 self-evolution: deterministic detection of stale knowledge, dead departments, KPI-less employees, recurring failures and unbuilt high-supply categories.';
