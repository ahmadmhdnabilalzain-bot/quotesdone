-- THE AUTOMATION PAGE ANSWERS IN UNDER A SECOND (6 Sep 2026).
--
-- Walked in the founder's browser: the OS Automation page showed "Could not load automation:
-- canceling statement due to statement timeout". fn_os_automation_list ran a LATERAL "latest run"
-- per cron job over cron.job_run_details -- 250,408 rows since 19 Jul with no (jobid, start_time)
-- index -- and took 10.9 s against PostgREST's 8 s wall. Two changes, measured:
--   * an index on cron.job_run_details (jobid, start_time desc), the access path the lateral wants;
--   * the "latest run" is read from the last 8 days (the window every other reader of this table
--     uses); a job with no tick in 8 days shows no last run, which is the truth about it.
-- The routine keeps its shape (an array of jobs; os_automation wraps it) -- every other line is the
-- live definition.
--
--   node scripts/apply_sql.mjs scripts/sql/the_automation_page_answers_in_under_a_second.sql --apply --ddl
begin;

-- cron.job_run_details is owned by supabase_admin; postgres may not be allowed to index it. The
-- index is attempted and its refusal recorded, and the routine below no longer depends on it.
do $idx$
begin
  begin
    execute 'create index if not exists job_run_details_jobid_start_idx on cron.job_run_details (jobid, start_time desc)';
    raise notice 'index job_run_details_jobid_start_idx present';
  exception when insufficient_privilege then
    raise notice 'index not created: % (owner is supabase_admin); the one-pass query below does not need it', sqlerrm;
  end;
end $idx$;

CREATE OR REPLACE FUNCTION public.fn_os_automation_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 6 SEP 2026: ONE pass over the last 8 days of run details (distinct on jobid), joined to the jobs,
  -- instead of a per-job LATERAL over the whole 250k-row table. 10.9 s -> well under the 8 s wall.
  with latest as (
    select distinct on (d.jobid) d.jobid, d.status, d.start_time, d.end_time, d.return_message
      from cron.job_run_details d
     where d.start_time > now() - interval '8 days'
     order by d.jobid, d.start_time desc nulls last
  )
  select coalesce(jsonb_agg(x order by x->>'category', x->>'human_name'), '[]'::jsonb) from (
    select jsonb_build_object(
      'jobid', j.jobid, 'jobname', j.jobname,
      'human_name', coalesce(r.human_name, initcap(replace(replace(j.jobname,'_',' '),'-',' '))),
      'category', coalesce(r.category,'Operations'), 'purpose', coalesce(r.purpose,''),
      'schedule', j.schedule, 'active', j.active,
      'last_status', lr.status, 'last_start', lr.start_time, 'last_end', lr.end_time,
      'last_message', left(coalesce(lr.return_message,''), 240)
    ) as x
    from cron.job j
    left join public.cron_registry r on r.jobname = j.jobname
    left join latest lr on lr.jobid = j.jobid
  ) q;
$function$;

do $proof$
declare t0 timestamptz := clock_timestamp(); v_n int; v_ms int;
begin
  select jsonb_array_length(public.fn_os_automation_list()) into v_n;
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_ms > 4000 then raise exception 'fn_os_automation_list still takes % ms for % jobs', v_ms, v_n; end if;
  raise notice 'proof: fn_os_automation_list returned % jobs in % ms', v_n, v_ms;
end $proof$;

commit;
