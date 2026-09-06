-- THE SCENARIO WATERMARK IGNORES THE SCHEDULER'S OWN TRACES (6 Sep 2026). Follows the_boost_embeds_three_at_a_time.sql.
--
-- MEASURED twice in CI (PR #525, 21:2xZ and 21:47Z) and never on the operator machine: the positive
-- control for fn_phase_d_committed_scenario_close raised "a survivor is a hard stop. watermark drift ..."
-- while the same open+close in one aborted transaction answered ok locally, three times. The
-- committed-scenario watermark is count(*) per watched relation, and public.phase_c_trace is watched.
-- Since 13:55Z the embedding boost ticks every six seconds through fn_kernel_cron_exec, and every tick
-- writes one phase_c_trace row (subject_kind system_execution, system_actor_id system.scheduler,
-- component cron:kb_embed_backfill_boost — 100 rows in the last ten minutes). A scenario that takes
-- longer than a tick — as it does from a CI runner — sees the trace count above its watermark by
-- rows it never wrote, and the door refuses, correctly by its rule and wrongly about the world.
--
-- The scheduler's traces are not a scenario's residue. Each watched relation can now carry a
-- count_filter; phase_c_trace counts only rows that are not the scheduler's own executions
-- (subject_kind <> 'system_execution'), which keeps every kind a scenario writes (workflow_run, task,
-- step_run, command) inside the watermark and the Q04 "exactly v_ao above" rule intact.
--
--   node scripts/apply_sql.mjs scripts/sql/the_scenario_watermark_ignores_the_schedulers_own_traces.sql --apply --ddl

begin;

alter table public.phase_d_committed_scenario_watch add column if not exists count_filter text;
comment on column public.phase_d_committed_scenario_watch.count_filter is
  'optional SQL predicate applied to count(*) for the watermark; rows the running company writes on a schedule (not a scenario''s residue) are excluded here';

update public.phase_d_committed_scenario_watch
   set count_filter = 'subject_kind <> ''system_execution'''
 where relation = 'public.phase_c_trace';

CREATE OR REPLACE FUNCTION public.fn_phase_d_committed_scenario_watermarks()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_n bigint; v_out jsonb := '{}'::jsonb;
begin
  for r in select relation, count_filter from public.phase_d_committed_scenario_watch order by relation loop
    if coalesce(r.count_filter, '') <> '' then
      execute format('select count(*) from %s where %s', r.relation, r.count_filter) into v_n;
    else
      execute format('select count(*) from %s', r.relation) into v_n;
    end if;
    v_out := v_out || jsonb_build_object(r.relation, v_n);
  end loop;
  select coalesce(max(id),0) into v_n from net.http_request_queue;
  v_out := v_out || jsonb_build_object('net.http_request_queue_max_id', v_n);
  select count(*) into v_n from public.kernel_maintenance_write;
  v_out := v_out || jsonb_build_object('public.kernel_maintenance_write', v_n);
  return v_out;
end $function$;

do $$
declare v jsonb; n_all bigint; n_wm bigint;
begin
  v := public.fn_phase_d_committed_scenario_watermarks();
  select count(*) into n_all from public.phase_c_trace;
  n_wm := (v->>'public.phase_c_trace')::bigint;
  if n_wm is null then raise exception 'the watermark no longer reports public.phase_c_trace'; end if;
  if n_wm >= n_all then raise exception 'the phase_c_trace watermark (%) still counts the scheduler''s traces (table holds %)', n_wm, n_all; end if;
end $$;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_scenario_watermark_ignores_the_schedulers_own_traces.sql',
       evidence = 'watched relations may carry a count_filter; phase_c_trace excludes system_execution (6 Sep 2026)'
 where schema_name = 'public' and routine_name = 'fn_phase_d_committed_scenario_watermarks';

commit;
