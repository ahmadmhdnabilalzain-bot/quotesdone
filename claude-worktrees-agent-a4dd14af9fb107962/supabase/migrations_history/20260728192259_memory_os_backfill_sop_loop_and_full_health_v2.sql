update institutional_memory m set os_key = od.os_key
from os_department od where m.os_key is null and od.dept_key = m.category_slug;

update institutional_memory set os_key = case
  when kind='outcome' then 'evolution'
  when subject_type ilike '%supplier%' or subject_type ilike '%inquiry%' or subject_type ilike '%quote%' then 'marketplace'
  when subject_type ilike '%invoice%'  or subject_type ilike '%bill%'    then 'finance'
  when subject_type ilike '%dispute%'  or subject_type ilike '%contract%' then 'legal_gov'
  else 'operations' end
where os_key is null;

create or replace function public.fn_sop_update()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; n_new int := 0; v_slug text;
begin
  for r in
    select m.id, m.os_key, m.headline, m.detail, m.outcome
    from institutional_memory m
    where m.created_at > now() - interval '7 days'
      and m.outcome in ('worse','improved')
      and not exists (select 1 from os_runbooks b where b.slug = 'lesson-'||m.id)
    limit 25
  loop
    v_slug := 'lesson-'||r.id;
    insert into os_runbooks (slug, title, category, when_to_use, steps, sort)
    values (v_slug, left(coalesce(r.headline,'Lesson '||r.id),120), coalesce(r.os_key,'operations'),
            case r.outcome when 'worse'
              then 'Before repeating this change. It was tried and it made things worse.'
              else 'When this situation recurs. This approach was measured and it worked.' end,
            coalesce(r.detail,''), 100);
    n_new := n_new + 1;
  end loop;
  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('sop_update',now(),now(),'ok',jsonb_build_object('runbooks_written',n_new),
    'SOP update: '||n_new||' graded lesson(s) written into the runbook library so the company cannot repeat them by accident.');
  return jsonb_build_object('written',n_new);
end $fn$;
revoke execute on function public.fn_sop_update() from public, anon, authenticated;

create or replace view public.v_os_health as
select s.num, s.os_key, s.name, s.owner_agent,
  s.employees, s.open_tasks,
  round(s.open_tasks::numeric / nullif(s.employees,0), 2) as backlog_per_head,
  (select count(*) from org_tasks t join os_department od on od.dept_key=t.dept_key
    where od.os_key=s.os_key and t.status<>'done' and t.created_at < now()-interval '14 days') as stale_tasks,
  (select round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1)
     from review_chain rc join os_department od on od.dept_key=rc.dept_key
    where od.os_key=s.os_key) as review_pass_pct,
  (select count(*) from risk_register r
    where exists (select 1 from os_department od join org_agents a on a.department=od.dept_key
                   where od.os_key=s.os_key and a.agent_key=r.owner_agent)) as open_risks,
  (select count(*) from org_tasks t join os_department od on od.dept_key=t.dept_key
    where od.os_key=s.os_key and t.title like 'KPI missed:%' and t.status<>'done') as kpi_gaps,
  s.budget_aed, s.spent_aed,
  round(100.0*s.spent_aed/nullif(s.budget_aed,0),1) as budget_pct,
  (select round(100.0*count(*) filter (where needs_founder)/nullif(count(*),0),1)
     from org_tasks t join os_department od on od.dept_key=t.dept_key
    where od.os_key=s.os_key and t.status<>'done') as needs_founder_pct
from v_os_scoreboard s;

comment on view public.v_os_health is
  'Eight dimensions: performance (kpi_gaps), risk (open_risks), quality (review_pass_pct), capacity (backlog_per_head), backlog (stale_tasks), cost (budget_pct), automation (needs_founder_pct), staffing (employees).';