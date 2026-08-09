-- The schedule that makes fn_capability_verify a mechanism rather than a one-off.
--
-- 02:15 UTC daily, away from the 03:30 money suite, the 03:37 QA suite, the 03:50 DR drill, the
-- 04:30 founder brief and the 00:35 KPI snapshot. Daily rather than weekly because the verdict it
-- writes carries a THIRTY-day staleness window: a weekly job that misses four Mondays would let a
-- capability go quietly unverified, and the whole point of the table is that nothing goes quietly.
--
-- cron.schedule() UPSERTS on the job name, so re-applying this file cannot create a second job.
-- The guard is a pg_proc lookup rather than to_regproc('cron.schedule'), which returns NULL on an
-- overloaded name and would make the guard silently always-false — see cron_improvement_handover.sql.
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'cron' and p.proname = 'schedule') then
    raise notice 'pg_cron not installed; capability_verify_daily not scheduled';
    return;
  end if;
  perform cron.schedule('capability_verify_daily', '15 2 * * *', 'select public.fn_capability_verify();');
end $$;
