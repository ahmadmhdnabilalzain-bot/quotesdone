-- v_os_health computes eight per-OS figures every time it is queried, and the ONLY object in the
-- database that names it is fn_os_review — the function that copies those figures into
-- os_review.metrics. A copier is not a reader: measured 6 Aug 2026, procs naming v_os_health = 1
-- (fn_os_review), views = 0, crons = 0. So the view is the spec file's own defect verbatim: built,
-- correct, per-OS, opened by nobody.
--
-- fn_exec_meeting is the right consumer and needed no new object. It already runs weekly on the
-- active cron exec_meeting_weekly, already opens os_review for the same ISO week, and already
-- writes an agenda item plus an org_tasks row for every OS that is not green. What it did NOT do
-- was say WHY an OS is amber — the agenda carried a RAG letter and a prose finding, and the six
-- numbers that produced that letter stayed in a store nothing opened.
--
-- This change joins v_os_health into the agenda loop and puts the drivers, by name, into the
-- finding, into exec_reports.findings (read by fn_day_conductor, fn_founder_brief, fn_officer_recs
-- and the report_registry view) and into the detail of the task the OS owner is handed. Nothing
-- else about the meeting changes.
create or replace function public.fn_exec_meeting()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare m jsonb; findings jsonb := '[]'::jsonb; actions int := 0; recs jsonb;
  v_period text := to_char(now(),'IYYY-"W"IW');
  v_rev numeric; v_spend numeric; v_sup int; v_open int; v_avail numeric;
  v_red int; v_amber int; v_green int; r record; v_drivers text;
begin
  -- ensure the OS reviews for this week exist before the meeting reads them
  if not exists (select 1 from os_review where period = v_period) then
    perform fn_os_review();
  end if;

  select count(*) filter (where health='red'), count(*) filter (where health='amber'), count(*) filter (where health='green')
    into v_red, v_amber, v_green from os_review where period = v_period;

  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at > now()-interval '7 days';
  select coalesce(sum(cost_aed),0) into v_spend from ai_cost_log where occurred_at > now()-interval '7 days';
  select count(*) into v_sup from leads where approval_status='approved';
  select count(*) into v_open from org_tasks where status<>'done';
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into v_avail
    from health_checks where check_kind='http' and created_at > now()-interval '7 days';

  m := jsonb_build_object('week',v_period,'os_green',v_green,'os_amber',v_amber,'os_red',v_red,
       'revenue_7d_aed',v_rev,'ai_spend_7d_aed',round(coalesce(v_spend,0),2),
       'approved_suppliers',v_sup,'supplier_target',860,
       'open_tasks',v_open,'platform_availability_pct',v_avail);

  -- AGENDA ITEM 1..10: every operating system that is not green, named with its owner AND with the
  -- live per-OS figures out of v_os_health that put it there. LEFT JOIN: an OS the view cannot
  -- resolve still reaches the agenda, it just reaches it without drivers.
  for r in
    select o.num, o.name, r2.health, r2.owner_agent, r2.findings,
           h.open_risks, h.kpi_gaps, h.backlog_per_head, h.stale_tasks,
           h.review_pass_pct, h.budget_pct, h.needs_founder_pct,
           -- CAPACITY IS THE ONE DIMENSION v_os_health DOES NOT COMPUTE (6 Aug 2026). It is
           -- resource_pool committed/capacity and it exists only in os_review.metrics, so it
           -- was the one of the eight figures with no reader outside its own writer. Taken off
           -- the report row the meeting is already reading.
           r2.metrics->>'capacity_pct' capacity_pct
    from os_review r2 join operating_system o on o.os_key = r2.os_key
    left join v_os_health h on h.os_key = r2.os_key
    where r2.period = v_period and r2.health <> 'green' order by
      case r2.health when 'red' then 1 else 2 end, o.num
  loop
    v_drivers := 'open_risks '||coalesce(r.open_risks::text,'?')
      ||', kpi_gaps '||coalesce(r.kpi_gaps::text,'?')
      ||', capacity_pct '||coalesce(r.capacity_pct,'?')
      ||', backlog_per_head '||coalesce(r.backlog_per_head::text,'?')
      ||', stale_tasks '||coalesce(r.stale_tasks::text,'?')
      ||', review_pass_pct '||coalesce(r.review_pass_pct::text,'?')
      ||', budget_pct '||coalesce(r.budget_pct::text,'?')
      ||', needs_founder_pct '||coalesce(r.needs_founder_pct::text,'?');
    findings := findings || jsonb_build_array(jsonb_build_object(
      'item', r.num||'. '||r.name, 'owner', coalesce(r.owner_agent,'unassigned'),
      'health', r.health, 'finding', r.findings::text, 'drivers', v_drivers));
  end loop;

  -- COMPANY-LEVEL ITEMS the CEO owns directly
  if coalesce(v_rev,0)=0 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Revenue','owner','cfo','health','amber','finding','No revenue recognised in the last 7 days.'));
  end if;
  if v_sup < 860 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Supplier coverage','owner','procurement','health',
      case when v_sup=0 then 'red' else 'amber' end,
      'finding', v_sup||' approved suppliers against a target of 860 (10 in each of 86 categories).'));
  end if;
  if coalesce(v_avail,100) < 99.5 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Platform availability','owner','cto','health','amber','finding','Availability '||coalesce(v_avail,0)||'% against 99.5%.'));
  end if;

  insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)
  select coalesce((select department from org_agents where agent_key=f->>'owner'),'exec'),
    'Exec meeting '||v_period||': '||(f->>'item'),
    'Health: '||(f->>'health')||'. Owner: '||(f->>'owner')||'. '||(f->>'finding')
    ||coalesce(' Drivers: '||(f->>'drivers')||'.','')
    ||' Raised at the weekly executive meeting. Close it, or bring evidence the standard is wrong.',
    'proposed','advisory',false,'exec_review'
  from jsonb_array_elements(findings) f
  where not exists (select 1 from org_tasks t where t.title='Exec meeting '||v_period||': '||(f->>'item') and t.status<>'done');
  get diagnostics actions = row_count;

  recs := case when jsonb_array_length(findings)=0
    then jsonb_build_array('All ten operating systems green and company metrics within tolerance. Hold current priorities.')
    else jsonb_build_array(
      v_red||' operating system(s) red, '||v_amber||' amber. Each has a named owner and a tracked action.',
      'Priority order follows the constitution: compliance, then customer trust, then quality, then revenue.') end;

  insert into exec_reports (officer,period,summary,findings,recommendations,metrics,status)
  values ('ceo',v_period,
    'Weekly executive meeting across ten operating systems. '||v_green||' green, '||v_amber||' amber, '||v_red
    ||' red. '||jsonb_array_length(findings)||' agenda finding(s), '||actions||' action(s) assigned.',
    findings, recs, m, 'open')
  on conflict do nothing;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('exec_meeting',now(),now(),'ok',
    jsonb_build_object('os_green',v_green,'os_amber',v_amber,'os_red',v_red,'findings',jsonb_array_length(findings),'actions',actions),
    'Executive meeting '||v_period||': '||v_green||' green / '||v_amber||' amber / '||v_red||' red across ten operating systems, '||actions||' actions assigned.');

  return jsonb_build_object('week',v_period,'green',v_green,'amber',v_amber,'red',v_red,
                            'findings',jsonb_array_length(findings),'actions',actions,'metrics',m);
end $function$;
