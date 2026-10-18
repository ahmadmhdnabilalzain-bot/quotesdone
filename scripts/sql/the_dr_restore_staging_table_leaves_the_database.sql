-- THE DR_RESTORE STAGING TABLE LEAVES THE DATABASE (it_engineer, 5 Oct 2026, item 24).
--
-- public.dr_restore was the staging table of the dr_drill restore drill (two_drills_in_one_staging_table.sql,
-- 13 Aug 2026). The drill's edge function is gone and its clear routine fn_dr_restore_clear was dropped on 8 Sep 2026
-- (retire_the_routines_no_seat_can_reach.sql, recorded in DROPPED.txt). The table stayed behind.
--
-- MEASURED on production htdblwldjkcgjvmqkbeh, 4 Oct 2026 19:56Z, read-only:
--   * select count(*) from public.dr_restore = 0
--   * pg_proc.prosrc ilike '%dr_restore%': 0 routines.   pg_views.definition: 0 views.   cron.job.command: 0 jobs.
--   * pg_constraint.confrelid (foreign keys into it): 0.   pg_trigger: 0.   pg_policy: 0.
--   * pg_depend: only its own toast table, its id sequence and its one index (the sequence is dropped explicitly below).
--   * every public text column named table_name / relname / target_table / table / subject / component / name /
--     object_name holding 'dr_restore': only table_export_registry (1 row, category log).
--   * 78 deployed edge functions: none named for a drill or restore reads it; supabase/functions, src and scripts
--     name it nowhere except history files and retired checks.
-- The files that still mention it (fn_dr_restore_clear_one_bounded_delete_per_pass.sql, two_drills_in_one_staging_table.sql,
-- retired checks) are history: no live routine or job runs any of them.
--
-- No routine is dropped here: the only routine that served the table already went on 8 Sep.
-- Prevented by: scripts/checks/dr_restore_stays_dropped_and_the_exam_idles_once_scored.test.mjs.

drop table if exists public.dr_restore;
drop sequence if exists public.dr_restore_id_seq;

delete from public.table_export_registry where table_name = 'dr_restore';

select case
  when to_regclass('public.dr_restore') is not null then 'PROBE FAILED: dr_restore is still present'
  when to_regclass('public.dr_restore_id_seq') is not null then 'PROBE FAILED: dr_restore_id_seq is still present'
  when exists (select 1 from public.table_export_registry where table_name = 'dr_restore')
    then 'PROBE FAILED: the export registry still lists dr_restore'
  else 'PROBE OK' end as verdict;
