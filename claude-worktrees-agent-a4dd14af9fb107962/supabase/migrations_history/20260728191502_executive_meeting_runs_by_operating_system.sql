-- The executive meeting was an ad-hoc checklist of company metrics. It now runs the way an
-- executive-led company runs: ten operating systems, each with an owner who answers for it,
-- reviewed against one standard, plus the company-level numbers the CEO owns directly.
create or replace function public.fn_exec_meeting()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare m jsonb; findings jsonb := '[]'::jsonb; actions int := 0; recs jsonb;
  v_period text := to_char(now(),'IYYY-"W"IW');
  v_rev numeric; v_spend numeric; v_sup int; v_open int; v_avail numeric;
  v_red int; v_amber int; v_green int; r record;
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

  -- AGENDA ITEM 1..10: every operating system that is not green, named with its owner
  for r in
    select o.num, o.name, r2.health, r2.owner_agent, r2.findings
    from os_review r2 join operating_system o on o.os_key = r2.os_key
    where r2.period = v_period and r2.health <> 'green' order by
      case r2.health when 'red' then 1 else 2 end, o.num
  loop
    findings := findings || jsonb_build_array(jsonb_build_object(
      'item', r.num||'. '||r.name, 'owner', coalesce(r.owner_agent,'unassigned'),
      'health', r.health, 'finding', r.findings::text));
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
end $fn$;
revoke execute on function public.fn_exec_meeting() from public, anon, authenticated;