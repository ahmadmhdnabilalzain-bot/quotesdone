-- The schedule that makes fn_index_slowdown_watch a mechanism rather than a routine nobody calls.
--
-- 04:15 UTC daily, deliberately between the 03:50 opportunity scan and the 04:30 founder brief: a
-- fall raised at 04:15 is on the record before the brief that morning is written, rather than a day
-- behind it. Daily because the check's own window is 7 days and the indices are measured daily —
-- a weekly watcher would let six of seven falls sit unexamined inside the window it is judged on.
--
-- cron.schedule() UPSERTS on the job name. The guard is a pg_proc lookup rather than
-- to_regproc('cron.schedule'), which returns NULL on an overloaded name — see
-- cron_improvement_handover.sql for the version of this that was silently always-false.
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'cron' and p.proname = 'schedule') then
    raise notice 'pg_cron not installed; index_slowdown_watch_daily not scheduled';
    return;
  end if;
  perform cron.schedule('index_slowdown_watch_daily', '15 4 * * *',
                        'select public.fn_index_slowdown_watch();');
end $$;
