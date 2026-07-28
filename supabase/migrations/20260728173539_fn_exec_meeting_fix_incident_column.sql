create or replace function public.fn_exec_meeting()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  m jsonb; findings jsonb := '[]'::jsonb; actions int := 0;
  v_rev numeric; v_spend numeric; v_kpi numeric; v_sup int; v_open int; v_risk int; v_inc int; v_avail numeric;
begin
  select coalesce(sum(coalesce(reveal_fee, app_fee, 0)),0) into v_rev from transactions where revealed_at > now()-interval '7 days';
  select coalesce(sum(cost_aed),0) into v_spend from ai_cost_log where occurred_at > now()-interval '7 days';
  select round(100.0*count(*) filter (where verdict in ('MET','NEAR'))/nullif(count(*) filter (where verdict<>'NO DATA'),0),1)
    into v_kpi from fn_kpi_scoreboard();
  select count(*) into v_sup from leads where claimed and approval_status='approved';
  select count(*) into v_open from org_tasks where status<>'done';
  select count(*) into v_risk from risk_register;
  select count(*) into v_inc from os_incidents where opened_at > now()-interval '7 days';
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into v_avail
    from health_checks where created_at > now()-interval '7 days';

  m := jsonb_build_object('revenue_7d_aed',v_rev,'ai_spend_7d_aed',round(coalesce(v_spend,0),2),
    'kpi_attainment_pct',v_kpi,'onboarded_suppliers',v_sup,'open_tasks',v_open,
    'open_risks',v_risk,'incidents_7d',v_inc,'platform_availability_pct',v_avail);

  if coalesce(v_rev,0)=0 then findings := findings || jsonb_build_array(jsonb_build_object('item','Revenue','owner','cfo','finding','No revenue recognised in the last 7 days.')); end if;
  if coalesce(v_kpi,0)<70 then findings := findings || jsonb_build_array(jsonb_build_object('item','KPIs','owner','cpo','finding','KPI attainment at '||coalesce(v_kpi,0)||'%, below the 70% floor.')); end if;
  if coalesce(v_sup,0)=0 then findings := findings || jsonb_build_array(jsonb_build_object('item','Supplier Success','owner','onboarding','finding','Zero onboarded suppliers. Every downstream marketplace metric is gated on this.')); end if;
  if coalesce(v_avail,100)<99.5 then findings := findings || jsonb_build_array(jsonb_build_object('item','Technology','owner','it','finding','Platform availability '||coalesce(v_avail,0)||'% against a 99.5% target.')); end if;
  if v_inc>0 then findings := findings || jsonb_build_array(jsonb_build_object('item','Operations','owner','ops_director','finding',v_inc||' incident(s) opened this week.')); end if;
  if v_open>60 then findings := findings || jsonb_build_array(jsonb_build_object('item','Chief of Staff','owner','brief','finding',v_open||' open tasks. Work is accumulating faster than it closes.')); end if;

  insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
  select coalesce((select department from org_agents where agent_key=f->>'owner'),'exec'),
         'Exec meeting action: '||(f->>'item'),
         (f->>'finding')||' Owner: '||(f->>'owner')||'. Raised at the weekly executive meeting on '||to_char(now(),'DD Mon YYYY')||'. Diagnose the cause and close it, or bring evidence that the target is wrong.',
         'proposed','advisory', false, 'coordinate'
  from jsonb_array_elements(findings) f
  where not exists (select 1 from org_tasks t where t.title='Exec meeting action: '||(f->>'item') and t.status<>'done');
  get diagnostics actions = row_count;

  insert into exec_reports (officer, period, summary, findings, recommendations, metrics, status)
  values ('ceo', to_char(now(),'IYYY-"W"IW'),
          'Weekly executive meeting. '||jsonb_array_length(findings)||' finding(s), '||actions||' action(s) assigned.',
          findings::text,
          case when jsonb_array_length(findings)=0 then 'All agenda items within tolerance. Hold current priorities.'
               else 'Close the assigned actions before next Monday; each is owned and tracked.' end,
          m::text,'open');

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('exec_meeting', now(), now(), 'ok', jsonb_build_object('findings',jsonb_array_length(findings),'actions',actions),
          'Weekly executive meeting held: '||jsonb_array_length(findings)||' findings, '||actions||' actions assigned.');

  return jsonb_build_object('findings',jsonb_array_length(findings),'actions',actions,'metrics',m);
end $fn$;
revoke execute on function public.fn_exec_meeting() from public, anon, authenticated;