-- KERNEL-COMPLIANT CRON RE-ENABLE. Founder, 2 Sep 2026: re-open the automation the stand-down closed,
-- so every loop has its consumer/handler back — but do it RIGHT: a state-changing cron must run as a
-- TRACED phase_c kernel component (fn_kernel_cron_exec), or it reddens active_state_changing_cron_components_not_wrapped.
-- This helper registers a cron as a component + wrapper, rewrites its command to the kernel wrapper, and
-- activates it — atomically and idempotently. Deterministic; needs no inference.
--
--   node scripts/apply_sql.mjs scripts/sql/kernel_wrap_and_enable_cron.sql --apply --ddl

begin;

create or replace function public.fn_kernel_wrap_and_enable_cron(
  p_jobid bigint, p_role text, p_dept text, p_authority text default 'routine_operational_decision')
 returns jsonb language plpgsql security definer set search_path to 'public','cron','pg_temp'
as $fn$
declare v_name text; v_cmd text; v_sched text; v_src text;
begin
  select jobname, command, schedule into v_name, v_cmd, v_sched from cron.job where jobid = p_jobid;
  if v_name is null then return jsonb_build_object('ok',false,'error','no such cron job '||p_jobid); end if;
  if v_cmd ilike '%fn_kernel_cron_exec%' then
    -- already wrapped: just make sure it is active
    perform cron.alter_job(p_jobid, active := true);
    return jsonb_build_object('ok',true,'jobid',p_jobid,'jobname',v_name,'action','already_wrapped_activated');
  end if;
  -- the routine/target the original command runs (best-effort, for the component source)
  v_src := coalesce((select 'public.'||p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                      where n.nspname='public' and p.prokind='f' and position(p.proname in v_cmd) > 0
                      order by length(p.proname) desc limit 1), 'cron.job:'||p_jobid);

  insert into public.phase_c_component(
    component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
    schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id,
    department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy,
    activation_state, classification, gap, repair_or_keep_action, evidence, measured_at)
  values (
    'cron:'||v_name, 'cron_job', 'cron.job/'||p_jobid, 'pg_cron schedule', 'pg_cron', 'no',
    v_sched, true, 'system.scheduler', 'system.scheduler', p_role,
    p_dept, 'SYSTEM_SCOPE', '', p_authority, 'TRACE-SYSTEM-EXECUTION', 'schedule_tick:jobname:scheduled_at', 'next_scheduled_tick',
    'active', 'WIRE_TO_CANONICAL', '', 'kept; re-enabled as a traced kernel component 2 Sep 2026 (stand-down lifted)',
    'wrapped + re-enabled 2 Sep 2026', now()::date)
  on conflict (component_id) do update set
    accountable_role_id = excluded.accountable_role_id, department_id = excluded.department_id,
    authority_class = excluded.authority_class, activation_state = 'active',
    canonical_system_actor = 'system.scheduler', trace_policy_id = 'TRACE-SYSTEM-EXECUTION';

  insert into public.phase_c_system_execution_wrapper(jobid, component_id, original_command, wrapped_at, note)
  values (p_jobid, 'cron:'||v_name, v_cmd, now(), 're-enabled 2 Sep 2026 after the stand-down')
  on conflict (jobid) do update set component_id = excluded.component_id, original_command = excluded.original_command, wrapped_at = now();

  perform cron.alter_job(p_jobid, command := format('select public.fn_kernel_cron_exec(%s);', p_jobid), active := true);
  return jsonb_build_object('ok',true,'jobid',p_jobid,'jobname',v_name,'action','wrapped_and_enabled','owner',p_role,'dept',p_dept);
end $fn$;
revoke execute on function public.fn_kernel_wrap_and_enable_cron(bigint,text,text,text) from public;
grant execute on function public.fn_kernel_wrap_and_enable_cron(bigint,text,text,text) to service_role;

commit;
