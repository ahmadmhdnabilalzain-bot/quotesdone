-- Unattended-growth self-audit: is every department loop alive (plan/execute/learn) or stalled? green/amber/red per dept.
create or replace function public.fn_autonomy_audit()
returns jsonb language sql stable security definer set search_path to 'public','pg_temp' as $$
  with per as (
    select d.dept_key, d.name,
      (select max(created_at) from org_memory m where m.scope=d.dept_key and m.kind='plan')   as last_plan,
      (select max(created_at) from org_memory m where m.scope=d.dept_key and m.kind='lesson') as last_lesson,
      (select count(*) from org_tasks t where t.dept_key=d.dept_key and t.status in ('assigned','proposed','in_progress')) as open_tasks,
      (select count(*) from org_tasks t where t.dept_key=d.dept_key and t.status='done' and t.updated_at > now()-interval '7 days') as done_7d
    from org_departments d where d.active )
  select jsonb_build_object('as_of', now(),
    'departments', (select jsonb_agg(jsonb_build_object('dept',dept_key,'name',name,'last_plan',last_plan,'last_lesson',last_lesson,'open_tasks',open_tasks,'done_7d',done_7d,
      'status', case when (last_plan is null or last_plan < now()-interval '4 days') and open_tasks=0 and done_7d=0 then 'red'
                     when (last_plan is null or last_plan < now()-interval '3 days') then 'amber' else 'green' end) order by dept_key) from per),
    'summary', (select jsonb_build_object('green', count(*) filter (where (last_plan is not null and last_plan >= now()-interval '3 days')),
        'stalled', count(*) filter (where (last_plan is null or last_plan < now()-interval '4 days') and open_tasks=0 and done_7d=0)) from per));
$$;
create or replace function public.fn_autonomy_audit_run()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare a jsonb; stalled int;
begin
  a := fn_autonomy_audit(); stalled := coalesce((a->'summary'->>'stalled')::int,0);
  insert into org_memory(scope,kind,content,source) values ('exec','audit','Autonomy self-audit: '||(a->'summary')::text||' — '||stalled||' loop(s) stalled.','autonomy_audit');
  if stalled>0 then insert into agent_actions(agent,kind,status,risk,title,recommendation,detail)
    values ('brief','autonomy_stall','pending','medium',stalled||' department loop(s) have stalled','Check fn_autonomy_audit().',a); end if;
  return a;
end $$;
-- cron: select cron.schedule('autonomy_audit_weekly','0 6 * * 1', $$select public.fn_autonomy_audit_run()$$);
