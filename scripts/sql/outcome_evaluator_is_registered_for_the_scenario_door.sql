-- THE OUTCOME EVALUATOR IS REGISTERED FOR THE SCENARIO DOOR, NOT SWITCHED OFF (4 Sep 2026).
--
-- fn_phase_d_committed_scenario_guards condition (4) required cron 143 outcome_evaluate_daily to be
-- INACTIVE — the 16 Aug stand-down written into the door. The founder lifted the stand-down on 2 Sep;
-- the consciousness agent re-enabled 143 on 3 Sep and it graded 25 overdue outcomes. The door then
-- refused every committed scenario (kernel_positive_controls: fn_phase_d_committed_scenario_close
-- red). Condition (4) now requires the evaluator to be REGISTERED in phase_d_committed_scenario_cron
-- like every other cron that reaches a watched relation — the same rule as condition (3) — and the
-- registration below states what it reaches (measured from fn_outcome_evaluate: outcome_record,
-- institutional_memory, org_tasks, agent_runs, company_event via fn_emit) and why a committed
-- fixture is not contaminated. Every other line of the guard routine is the live definition.
--
--   node scripts/apply_sql.mjs scripts/sql/outcome_evaluator_is_registered_for_the_scenario_door.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_phase_d_committed_scenario_guards()
 RETURNS TABLE(check_name text, ok boolean, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_n bigint; v_txt text;
begin
  -- (1) no other scenario is open
  select count(*) into v_n from public.phase_d_committed_scenario where state = 'OPEN';
  check_name := 'no_other_scenario_open'; ok := (v_n = 0);
  detail := format('%s scenario(s) currently OPEN', v_n); return next;

  -- (2) every registered outbound door on a relation this scenario writes is suppressed or
  --     measured unreachable. Read from the register, not asserted.
  select count(*), coalesce(string_agg(d.relation || '/' || d.trigger_name, ', '), '(none)')
    into v_n, v_txt
    from public.phase_d_outbound_door d
   where d.relation in (select relation from public.phase_d_committed_scenario_watch)
     and d.disposition not in ('SUPPRESSED_BY_ITS_OWN_GUARD','NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP');
  check_name := 'every_outbound_door_on_a_written_relation_is_disposed'; ok := (v_n = 0);
  detail := format('%s undisposed: %s', v_n, v_txt); return next;

  -- (3) every ACTIVE cron job whose command can reach a watched relation is registered here with
  --     its quarantine. Derived from cron.job and the routine bodies, so a new job refuses.
  with resolved as (
    select j.jobid, j.jobname,
           coalesce((select w.original_command from public.phase_c_system_execution_wrapper w
                      where j.command like '%fn_kernel_cron_exec(' || w.jobid || ')%' limit 1),
                    j.command) as cmd
      from cron.job j where j.active),
  reach as (
    select r.jobid, r.jobname,
           exists (select 1 from public.phase_d_committed_scenario_watch t
                    where r.cmd like '%' || replace(t.relation,'public.','') || '%')
           or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       join public.phase_d_committed_scenario_watch t
                         on p.prosrc like '%' || replace(t.relation,'public.','') || '%'
                      where n.nspname = 'public' and r.cmd like '%' || p.proname || '(%') as touches
      from resolved r)
  select count(*), coalesce(string_agg(x.jobid || ' ' || x.jobname, ', '), '(none)') into v_n, v_txt
    from reach x
   where x.touches
     and not exists (select 1 from public.phase_d_committed_scenario_cron c where c.jobid = x.jobid);
  check_name := 'every_active_cron_that_reaches_a_watched_relation_is_registered'; ok := (v_n = 0);
  detail := format('%s unregistered: %s', v_n, v_txt); return next;

  -- (4) 4 SEP 2026: outcome_evaluate_daily used to be required INACTIVE ("business automation is not
  -- being reactivated here") — a stand-down condition from 16 Aug 2026. The founder lifted the
  -- stand-down on 2 Sep and the evaluator is back on its clock (it graded 25 overdue outcomes on
  -- 3 Sep). A running evaluator is not a threat to a committed scenario as long as it is REGISTERED
  -- for this door like every other cron that reaches a watched relation (it writes org_tasks,
  -- agent_runs and emits company_event); that is what is required now, and it is the same rule as (3).
  select count(*) into v_n from cron.job j
   where j.jobname = 'outcome_evaluate_daily' and j.active
     and not exists (select 1 from public.phase_d_committed_scenario_cron c where c.jobid = j.jobid);
  check_name := 'outcome_evaluate_daily_registered_for_the_door'; ok := (v_n = 0);
  detail := format('%s active unregistered row(s)', v_n); return next;

  -- (5) the estate has no fixture residue before we start
  select count(*) into v_n from public.fn_phase_d_fixture_residue();
  check_name := 'fixture_residue_zero_before_open'; ok := (v_n = 0);
  detail := format('%s relation(s) carry residue', v_n); return next;

  -- (6) net.http_request_queue watermark is readable
  select coalesce(max(id),0) into v_n from net.http_request_queue;
  check_name := 'outbound_http_queue_watermark_readable'; ok := true;
  detail := format('max(id) = %s', v_n); return next;
end $function$;

insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
values (143, 'outcome_evaluate_daily',
  'Writes public.outcome_record, public.institutional_memory, public.org_tasks (rollback tasks for worsened outcomes) and public.agent_runs (its run log), and emits public.company_event through fn_emit — measured from fn_outcome_evaluate on 4 Sep 2026.',
  'Re-enabled 3 Sep 2026 after the founder lifted the stand-down (2 Sep). Runs in its own transaction on its own schedule and cannot see a committed scenario''s uncommitted ZZ DEMO fixture, so it never grades or writes about a scenario row; every row it writes is about the real estate. close() asserts only the rows this scenario created are gone, by id, so its writes do not move the watermark.')
on conflict (jobid) do update set reaches = excluded.reaches, quarantine = excluded.quarantine;

do $proof$
declare v record; v_bad text;
begin
  select string_agg(check_name || ': ' || detail, '; ') into v_bad
    from public.fn_phase_d_committed_scenario_guards()
   where not ok and check_name in ('outcome_evaluate_daily_registered_for_the_door');
  if v_bad is not null then raise exception 'guard still red: %', v_bad; end if;
  raise notice 'proof: outcome_evaluate_daily is active and registered for the scenario door';
end $proof$;
