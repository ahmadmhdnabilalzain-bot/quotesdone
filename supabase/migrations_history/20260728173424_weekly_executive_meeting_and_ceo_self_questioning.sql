-- Individual reports existed; a convened meeting that runs one agenda across departments
-- and assigns tracked actions out of it did not.
create or replace function public.fn_exec_meeting()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  m jsonb; findings jsonb := '[]'::jsonb; actions int := 0; v_id bigint;
  v_rev numeric; v_spend numeric; v_kpi numeric; v_sup int; v_open int; v_risk int; v_inc int; v_avail numeric;
begin
  select coalesce(sum(coalesce(reveal_fee, app_fee, 0)),0) into v_rev from transactions where revealed_at > now()-interval '7 days';
  select coalesce(sum(cost_aed),0) into v_spend from ai_cost_log where occurred_at > now()-interval '7 days';
  select round(100.0*count(*) filter (where verdict in ('MET','NEAR'))/nullif(count(*) filter (where verdict<>'NO DATA'),0),1)
    into v_kpi from fn_kpi_scoreboard();
  select count(*) into v_sup from leads where claimed and approval_status='approved';
  select count(*) into v_open from org_tasks where status<>'done';
  select count(*) into v_risk from risk_register;
  select count(*) into v_inc from os_incidents where created_at > now()-interval '7 days';
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into v_avail
    from health_checks where created_at > now()-interval '7 days';

  m := jsonb_build_object(
    'revenue_7d_aed', v_rev,
    'ai_spend_7d_aed', round(coalesce(v_spend,0),2),
    'kpi_attainment_pct', v_kpi,
    'onboarded_suppliers', v_sup,
    'open_tasks', v_open,
    'open_risks', v_risk,
    'incidents_7d', v_inc,
    'platform_availability_pct', v_avail);

  -- AGENDA: each item either passes or becomes a finding with an owner
  if coalesce(v_rev,0) = 0 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Revenue','owner','cfo','finding','No revenue recognised in the last 7 days.'));
  end if;
  if coalesce(v_kpi,0) < 70 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','KPIs','owner','cpo','finding','KPI attainment at '||coalesce(v_kpi,0)||'%, below the 70% floor.'));
  end if;
  if coalesce(v_sup,0) = 0 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Supplier Success','owner','onboarding','finding','Zero onboarded suppliers. Every downstream marketplace metric is gated on this.'));
  end if;
  if coalesce(v_avail,100) < 99.5 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Technology','owner','it','finding','Platform availability '||coalesce(v_avail,0)||'% against a 99.5% target.'));
  end if;
  if v_inc > 0 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Operations','owner','ops_director','finding',v_inc||' incident(s) opened this week.'));
  end if;
  if v_open > 60 then
    findings := findings || jsonb_build_array(jsonb_build_object('item','Chief of Staff','owner','brief','finding',v_open||' open tasks. Work is accumulating faster than it closes.'));
  end if;

  -- Assign an action per finding, tracked to completion
  for v_id in
    select 1 from jsonb_array_elements(findings)
  loop null; end loop;

  insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
  select coalesce((select department from org_agents where agent_key = f->>'owner'),'exec'),
         'Exec meeting action: '||(f->>'item'),
         (f->>'finding')||' Owner: '||(f->>'owner')||'. Raised at the weekly executive meeting on '||to_char(now(),'DD Mon YYYY')||'. Diagnose the cause and close it, or bring evidence that the target is wrong.',
         'proposed','advisory', false, 'coordinate'
  from jsonb_array_elements(findings) f
  where not exists (
    select 1 from org_tasks t
    where t.title = 'Exec meeting action: '||(f->>'item') and t.status <> 'done');
  get diagnostics actions = row_count;

  insert into exec_reports (officer, period, summary, findings, recommendations, metrics, status)
  values ('ceo', to_char(now(),'IYYY-"W"IW'),
          'Weekly executive meeting. '||jsonb_array_length(findings)||' finding(s), '||actions||' action(s) assigned.',
          findings::text,
          case when jsonb_array_length(findings)=0
               then 'All agenda items within tolerance. Hold current priorities.'
               else 'Close the assigned actions before next Monday; each is owned and tracked.' end,
          m::text, 'open');

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('exec_meeting', now(), now(), 'ok',
          jsonb_build_object('findings',jsonb_array_length(findings),'actions',actions),
          'Weekly executive meeting held: '||jsonb_array_length(findings)||' findings, '||actions||' actions assigned.');

  return jsonb_build_object('findings',jsonb_array_length(findings),'actions',actions,'metrics',m);
end $fn$;

-- Every question in the system was answered; none was asked. The CEO now asks its own.
create or replace function public.fn_ceo_questions()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare qs text[] := '{}'; n int := 0; q text;
  v_rev numeric; v_sup int; v_inq int; v_worst text; v_cost numeric; v_prev numeric;
begin
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at > now()-interval '30 days';
  select count(*) into v_sup from leads where claimed and approval_status='approved';
  select count(*) into v_inq from inquiries where created_at > now()-interval '30 days';
  select department into v_worst from fn_kpi_scoreboard() where verdict='MISSED' and department is not null
    group by department order by count(*) desc limit 1;
  select coalesce(sum(cost_aed),0) into v_cost from ai_cost_log where occurred_at > now()-interval '7 days';
  select coalesce(sum(cost_aed),0) into v_prev from ai_cost_log where occurred_at between now()-interval '14 days' and now()-interval '7 days';

  if v_rev = 0 then qs := qs || ('Why are we not growing? Revenue is zero over 30 days with '||v_sup||' onboarded suppliers and '||v_inq||' inquiries. What is the single binding constraint, and what would remove it?'); end if;
  if v_sup = 0 then qs := qs || 'We have 86 fully briefed category experts and no onboarded suppliers. Are we building capability ahead of demand, and is that still the right sequence?'; end if;
  if v_worst is not null then qs := qs || ('Why is '||v_worst||' missing more targets than any other department this week? Is it capability, capacity, or a target that was never realistic?'); end if;
  if v_prev > 0 and v_cost > v_prev * 1.25 then qs := qs || ('AI cost rose from '||round(v_prev,2)||' to '||round(v_cost,2)||' AED week on week. What drove it and did it buy anything?'); end if;
  qs := qs || 'Which workflow wastes the most employee time, and what would automating it be worth?';
  qs := qs || 'Which department produced the highest return on its AI spend this month, and what are the others not copying?';
  qs := qs || 'What are we doing today only because we have always done it?';

  foreach q in array qs loop
    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    select 'exec', 'CEO question: '||left(q,80), q||E'\n\nAnswer with evidence from company data, not opinion. If the answer implies a change, open it as an initiative with a named metric and a baseline so it can be graded.',
           'proposed','advisory', false, 'recommend'
    where not exists (select 1 from org_tasks where title='CEO question: '||left(q,80) and status<>'done');
    if found then n := n + 1; end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('ceo_questions', now(), now(), 'ok', jsonb_build_object('asked',n),
          'CEO self-questioning: '||n||' strategic question(s) raised from live company data.');
  return jsonb_build_object('asked',n);
end $fn$;

revoke execute on function public.fn_exec_meeting() from public, anon, authenticated;
revoke execute on function public.fn_ceo_questions() from public, anon, authenticated;