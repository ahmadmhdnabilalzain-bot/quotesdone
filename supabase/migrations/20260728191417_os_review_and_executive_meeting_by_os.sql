-- Governance: every OS is reviewed on the same schedule, by the same standard, and its
-- owner answers for it. The executive meeting stops being an ad-hoc checklist and becomes
-- a review of ten systems, each with a named owner.

create table if not exists public.os_review (
  id           bigserial primary key,
  os_key       text not null references operating_system(os_key),
  period       text not null,
  owner_agent  text,
  health       text not null check (health in ('green','amber','red')),
  metrics      jsonb,
  findings     jsonb,
  actions      int not null default 0,
  created_at   timestamptz not null default now(),
  unique (os_key, period)
);
alter table public.os_review enable row level security;

create or replace function public.fn_os_review()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; v_period text := to_char(now(),'IYYY-"W"IW');
  v_health text; v_find jsonb; v_act int; v_total int := 0; v_red int := 0; v_amber int := 0;
  v_missed int; v_stale int; v_overspend numeric;
begin
  for r in select * from v_os_scoreboard loop
    v_find := '[]'::jsonb; v_act := 0;

    select count(*) into v_missed from org_tasks t
      join os_department od on od.dept_key = t.dept_key
     where od.os_key = r.os_key and t.title like 'KPI missed:%' and t.status <> 'done';

    select count(*) into v_stale from org_tasks t
      join os_department od on od.dept_key = t.dept_key
     where od.os_key = r.os_key and t.status <> 'done' and t.created_at < now() - interval '14 days';

    v_overspend := case when r.budget_aed > 0 then round(100.0*r.spent_aed/r.budget_aed,1) else 0 end;

    if r.employees = 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','no employees','detail','This operating system has no staff.'));
    end if;
    if r.kpis = 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','no KPIs','detail','This operating system cannot be held to account.'));
    end if;
    if r.kpis_unmeasurable > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','unmeasurable KPIs','detail',r.kpis_unmeasurable||' KPI(s) have no measure.'));
    end if;
    if v_missed > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','KPIs missing target','detail',v_missed||' unclosed KPI gap(s).'));
    end if;
    if v_stale > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','stale work','detail',v_stale||' task(s) open more than 14 days.'));
    end if;
    if v_overspend >= 95 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','budget halt','detail',v_overspend||'% of monthly AI budget spent.'));
    elsif v_overspend >= 70 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','budget degrade','detail',v_overspend||'% of monthly AI budget spent.'));
    end if;

    v_health := case
      when r.employees = 0 or r.kpis = 0 or v_overspend >= 95 then 'red'
      when jsonb_array_length(v_find) > 0 then 'amber'
      else 'green' end;

    if v_health <> 'green' then
      insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select coalesce((select department from org_agents where agent_key = r.owner_agent), 'exec'),
             'OS review ['||v_health||']: '||r.name,
             'Owner: '||coalesce(r.owner_agent,'unassigned')||'. Week '||v_period||'. Findings: '||v_find::text
             ||'. Close each finding or bring evidence the standard is wrong.',
             'proposed','advisory', false, 'exec_review'
      where not exists (select 1 from org_tasks t2 where t2.title like 'OS review [%]: '||r.name and t2.status <> 'done');
      get diagnostics v_act = row_count;
    end if;

    insert into os_review (os_key, period, owner_agent, health, metrics, findings, actions)
    values (r.os_key, v_period, r.owner_agent, v_health,
            jsonb_build_object('departments',r.departments,'employees',r.employees,'open_tasks',r.open_tasks,
                               'kpis',r.kpis,'kpis_unmeasurable',r.kpis_unmeasurable,
                               'budget_pct',v_overspend,'kpi_gaps',v_missed,'stale_tasks',v_stale),
            v_find, v_act)
    on conflict (os_key, period) do update
      set health=excluded.health, metrics=excluded.metrics, findings=excluded.findings,
          actions=excluded.actions, created_at=now();

    v_total := v_total + 1;
    if v_health='red' then v_red := v_red+1; elsif v_health='amber' then v_amber := v_amber+1; end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('os_review', now(), now(), case when v_red>0 then 'error' else 'ok' end,
          jsonb_build_object('reviewed',v_total,'red',v_red,'amber',v_amber,'green',v_total-v_red-v_amber),
          'Operating system review, week '||v_period||': '||(v_total-v_red-v_amber)||' green, '||v_amber||' amber, '||v_red||' red.');

  return jsonb_build_object('reviewed',v_total,'red',v_red,'amber',v_amber,'green',v_total-v_red-v_amber);
end $fn$;

revoke execute on function public.fn_os_review() from public, anon, authenticated;

-- the one KPI still without a measure
update employee_kpi
   set measure_sql = $q$select round(avg((kpis->>'engagement_rate')::numeric),2) from marketing_snapshots where created_at > now()-interval '30 days'$q$
 where metric = 'Average engagement across channels' and measure_sql is null;