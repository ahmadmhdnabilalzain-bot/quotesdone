-- THE MANUAL STAYS CURRENT BECAUSE THE SOP ROUTINE RE-DERIVES IT FROM WHAT ACTUALLY RUNS.
--
-- Measured 3 Sep 2026: cron_registry documented every active job (0 undocumented, 0 ghosts) — by
-- hand, once. Nothing kept it that way: fn_sop_update wrote graded lessons into the runbook
-- library and never looked at the scheduler, and sop_update_weekly (job 158) had been off since
-- 16 Aug. A manual that is current by coincidence is one job away from being wrong.
--
-- fn_sop_update now does the registry sweep first, in both directions:
--   - every ACTIVE cron job with no registry row gets one, named from the job, categorised by the
--     department that owns its kernel component (or 'operations'), with a purpose that states the
--     command it runs, its schedule and its accountable role — a true sentence, generated from the
--     scheduler, that a person can sharpen later;
--   - every registry row whose job no longer exists in cron.job is removed: documentation for
--     automation that is gone is drift, not history (the job's runs stay in job_run_details).
-- Then the lessons, as before. The run note records both counts, so a week in which the registry
-- moved says so.
--
-- sop_update_weekly is re-enabled as a traced kernel component under the role its component row
-- already carries (knowledge_director / data_intel).
--
--   node scripts/apply_sql.mjs scripts/sql/the_manual_regenerates_from_the_cron_registry.sql --apply --ddl

create or replace function public.fn_sop_update()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; n_new int := 0; v_slug text; n_reg int := 0; n_ghost int := 0;
begin
  -- 1. the registry follows the scheduler: undocumented active jobs are documented
  insert into public.cron_registry (jobname, human_name, category, purpose)
  select j.jobname,
         initcap(replace(j.jobname, '_', ' ')),
         coalesce(c.department_id, 'operations'),
         'Scheduled ' || j.schedule || ' (UTC): runs `' || btrim(coalesce(w.original_command, j.command))
           || '`' || coalesce('; accountable role ' || c.accountable_role_id, '')
           || '. Documented automatically by fn_sop_update on ' || to_char(now(), 'YYYY-MM-DD')
           || ' because the job was active and undocumented.'
    from cron.job j
    left join public.phase_c_system_execution_wrapper w on w.jobid = j.jobid
    left join public.phase_c_component c on c.component_id = w.component_id
   where j.active
     and not exists (select 1 from public.cron_registry g where g.jobname = j.jobname);
  get diagnostics n_reg = row_count;

  -- ...and documentation for jobs that no longer exist is removed
  delete from public.cron_registry g
   where not exists (select 1 from cron.job j where j.jobname = g.jobname);
  get diagnostics n_ghost = row_count;

  -- 2. graded lessons become runbooks, as before
  for r in
    select m.id, m.headline, m.detail, m.outcome,
           coalesce(m.os_key,
                    (select d.os_key from org_tasks o join os_department d on d.dept_key = o.dept_key
                      where m.subject_type = 'org_task' and o.id::text = m.subject_id limit 1),
                    (select d.os_key from os_department d where d.dept_key = m.learned_by limit 1)) as os_key
    from institutional_memory m
    where m.outcome in ('worse', 'improved', 'success', 'success_over_dissent')
      and not exists (select 1 from os_runbooks b where b.slug = 'lesson-' || m.id)
    order by m.created_at desc
    limit 25
  loop
    v_slug := 'lesson-' || r.id;
    insert into os_runbooks (slug, title, category, when_to_use, steps, sort, os_key)
    values (v_slug, left(coalesce(r.headline, 'Lesson ' || r.id), 120),
            coalesce(r.os_key, 'operations'),
            case when r.outcome = 'worse'
              then 'Before repeating this change. It was tried and it made things worse.'
              else 'When this situation recurs. This approach was measured and it worked.' end,
            coalesce(r.detail, ''), 100, r.os_key);
    n_new := n_new + 1;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('sop_update', now(), now(), 'ok',
    jsonb_build_object('runbooks_written', n_new, 'jobs_documented', n_reg, 'ghost_entries_removed', n_ghost),
    'SOP update: registry re-derived from the scheduler (' || n_reg || ' active job(s) newly documented, '
    || n_ghost || ' entr(ies) for vanished jobs removed); ' || n_new
    || ' graded lesson(s) written into the runbook library so the company cannot repeat them by accident.');
  return jsonb_build_object('written', n_new, 'jobs_documented', n_reg, 'ghost_entries_removed', n_ghost);
end
$function$;

-- The weekly SOP update runs again, traced through the kernel.
select public.fn_kernel_wrap_and_enable_cron(158, 'knowledge_director', 'data_intel');
update public.phase_c_component c
   set accountable_role_id = 'knowledge_director', department_id = 'data_intel', activation_state = 'active'
  from public.phase_c_system_execution_wrapper w
 where w.jobid = 158 and c.component_id = w.component_id;

do $$
declare v_bad int;
begin
  select count(*) into v_bad
    from public.phase_c_system_execution_wrapper w
    join public.phase_c_component c on c.component_id = w.component_id
   where w.jobid = 158
     and not exists (select 1 from public.org_role o where o.role_id = c.accountable_role_id);
  if v_bad > 0 then
    raise exception 'sop_update_weekly: accountable role does not resolve in org_role';
  end if;
end $$;
