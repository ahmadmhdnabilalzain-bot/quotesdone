-- EVERY EMPLOYEE HAS A CURRENT THOUGHT, EVERY DAY (3 Sep 2026).
--
-- employee-current-thoughts: "an employee's current thoughts are visible in their workspace". The
-- drawer renders agent_memory and five reachable routines deliver it; the DB leg failed because 51
-- of 71 active employees had no agent_memory row in 30 days — 671 rows over 30 employees, written
-- only when a chat turn, a handoff or the OS health brief happened to touch them. An employee that
-- has not been spoken to has no thoughts, which is not how a real member of staff starts a day.
--
-- fn_agent_daily_thought writes one thought per active employee per UTC day, composed entirely
-- from what is measured about them: tasks assigned to them and open in their department, their
-- recommendations awaiting a decision, their worst-attained active KPI, their last run, the size
-- and staleness of their knowledge — and the next thing they will do, derived from the same
-- numbers in that order of precedence. No model. Idempotent per day (source + date), so a second
-- tick is a no-op. importance 4 keeps it below fn_agent_context's LAYER 4 threshold (>= 5): the
-- thought is for the workspace and the record, not for crowding the prompt.
--
-- Scheduled daily at 04:15 UTC (08:15 Dubai, the start of the working day) as
-- agent_daily_thought, wrapped through the kernel under the workforce director like the other
-- people_ops measurements.

create or replace function public.fn_agent_daily_thought()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  a record; n_written int := 0; n_skipped int := 0;
  v_mine int; v_mine_title text; v_dept_open int; v_queue int; v_queue_title text;
  v_kpi text; v_kpi_actual numeric; v_kpi_target numeric; v_kpi_unit text; v_kpi_pct numeric;
  v_last_status text; v_last_at timestamptz; v_kn int; v_kn_stale int;
  v_next text; v_txt text; v_imp int;
begin
  for a in select agent_key, department, coalesce(title, role, agent_key) title
             from public.org_agents where active order by agent_key
  loop
    if exists (select 1 from public.agent_memory m
                where m.agent_key = a.agent_key and m.source = 'fn_agent_daily_thought'
                  and m.created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') then
      n_skipped := n_skipped + 1; continue;
    end if;

    select count(*), min(title) filter (where rn = 1) into v_mine, v_mine_title
      from (select title, row_number() over (order by created_at) rn
              from public.org_tasks where assigned_agent = a.agent_key and coalesce(status,'') <> 'done') t;
    select count(*) into v_dept_open from public.org_tasks
     where dept_key = a.department and coalesce(status,'') <> 'done';
    select count(*), min(title) filter (where rn = 1) into v_queue, v_queue_title
      from (select title, row_number() over (order by created_at) rn
              from public.agent_actions where agent = a.agent_key
               and status in ('pending','held_for_review','proposed','open','needs_review')) q;
    select kpi, actual_value, target_value, unit,
           case when coalesce(target_value,0) <> 0 then round(100.0 * actual_value / target_value, 1) end
      into v_kpi, v_kpi_actual, v_kpi_target, v_kpi_unit, v_kpi_pct
      from public.employee_kpi
     where agent_key = a.agent_key and active and actual_value is not null and coalesce(target_value,0) <> 0
     order by actual_value / target_value asc limit 1;
    select status, started_at into v_last_status, v_last_at
      from public.agent_runs where agent = a.agent_key order by started_at desc limit 1;
    select count(*), count(*) filter (where validation_status in ('stale','quarantined') or review_due < current_date)
      into v_kn, v_kn_stale
      from public.agent_knowledge where agent_key = a.agent_key;

    v_next := case
      when v_mine > 0 then 'work the oldest task assigned to me: ' || left(v_mine_title, 120)
      when v_queue > 0 then 'close my oldest recommendation still awaiting a decision: ' || left(v_queue_title, 120)
      when v_kpi is not null and coalesce(v_kpi_pct, 100) < 100 then 'move "' || v_kpi || '" toward target (' || v_kpi_pct || '% attained)'
      when v_kn_stale > 0 then 'refresh my ' || v_kn_stale || ' stale knowledge item(s) before relying on them'
      when v_dept_open > 0 then 'pick up unassigned work in ' || a.department || ' (' || v_dept_open || ' open)'
      else 'no open work is assigned to me; monitor my department''s KPIs and keep my knowledge current' end;

    v_txt := 'Today (' || to_char(now() at time zone 'UTC', 'DD Mon YYYY') || ') as ' || a.title || ': '
      || v_mine || ' task(s) assigned to me and ' || v_dept_open || ' open in ' || a.department || '; '
      || v_queue || ' recommendation(s) of mine awaiting a decision; '
      || coalesce('weakest KPI "' || v_kpi || '" at ' || v_kpi_actual || coalesce(' ' || v_kpi_unit, '') || ' of ' || v_kpi_target
                  || coalesce(' (' || v_kpi_pct || '%)', '') || '; ', 'no measured KPI yet; ')
      || coalesce('last run ' || v_last_status || ' ' || to_char(v_last_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC; ', 'never run by the scheduler; ')
      || v_kn || ' knowledge item(s), ' || v_kn_stale || ' stale. Next: ' || v_next || '.';

    -- something is waiting on this employee: the thought matters more today
    v_imp := case when v_mine > 0 or v_queue > 0 or v_kn_stale > 0 or coalesce(v_kpi_pct, 100) < 50 then 4 else 3 end;

    insert into public.agent_memory (agent_key, kind, content, source, importance, horizon)
    values (a.agent_key, 'thought', v_txt, 'fn_agent_daily_thought', v_imp, 'short');
    n_written := n_written + 1;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('agent_daily_thought', now(), now(), 'ok',
          jsonb_build_object('written', n_written, 'already_today', n_skipped),
          'Daily thought: ' || n_written || ' employee(s) wrote today''s thought, ' || n_skipped || ' already had one.');
  return jsonb_build_object('written', n_written, 'already_today', n_skipped);
end $function$;

revoke execute on function public.fn_agent_daily_thought() from public, anon, authenticated;

begin;
do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'agent_daily_thought';
  if v_job is null then
    -- CRON REMOVED 7 Sep 2026 (founder: "Remove it from the code. Delete, not archive.").
    -- This scheduled agent_daily_thought, which was deleted from cron.job in the same change.
    -- The notice replaces the call so this routine still runs and still reports, rather
    -- than silently doing nothing or quietly recreating a job nobody asked for.
    raise notice 'cron scheduling removed on 7 Sep 2026: agent_daily_thought is not recreated';
  end if;
  perform public.fn_kernel_wrap_and_enable_cron(v_job, 'agent_workforce_capability_director', 'people_ops', 'routine_operational_decision');
  update public.phase_c_component
     set repair_or_keep_action = 'built 3 Sep 2026: every active employee writes one measured daily thought into agent_memory (scripts/sql/fn_agent_daily_thought.sql)',
         evidence = 'scheduled and wrapped 3 Sep 2026 as the daily employee thought; pure SQL, no model'
   where component_id = 'cron:agent_daily_thought';
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
  values (v_job, 'agent_daily_thought',
          'Pure SQL: INSERTs one agent_memory row (kind thought) per active org_agents row per UTC day, and one agent_runs row. No HTTP, no model.',
          'Daily 04:15 UTC; own transaction on a scheduled tick; reads org_tasks, agent_actions, employee_kpi, agent_runs and agent_knowledge by the employee''s own agent_key and writes only agent_memory about real employees; a scenario''s fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them; close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
  insert into public.cron_registry (jobname, human_name, category, purpose)
  values ('agent_daily_thought', 'Daily employee thought', 'people_ops',
          'Daily 04:15 UTC: every active employee writes today''s thought into agent_memory from its measured tasks, queue, KPIs, runs and knowledge, and names the next thing it will do.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
end $$;
commit;

do $ctl$
begin
  if not exists (select 1 from cron.job where jobname = 'agent_daily_thought' and active and command ilike '%fn_kernel_cron_exec%') then
    raise exception 'agent_daily_thought is not active and wrapped';
  end if;
end $ctl$;
