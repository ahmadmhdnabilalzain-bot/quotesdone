-- THE KPI HISTORY HAD A WRITER AND NO SCHEDULE.
--
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   digital-twin-live-kpis   MISSING  14 of 14 active metric(s) have no snapshot inside 24h;
--                                     metric_snapshot holds 42 rows, newest 2026-08-06 09:09:26
--   s33-replay-six-tracks    MISSING  4 of 6 tracks have rows on 2026-08-08 (missing: KPIs, outcomes)
--
--   metric_snapshot has rows on exactly two days ever: 2026-07-27 and 2026-08-06.
--
-- ── THE CAUSE ───────────────────────────────────────────────────────────────────────────────────
-- fn_bi_snapshot walks metric_definition, executes each active metric's own measure_sql and writes
-- the result to metric_snapshot. It works. It has NO CRON. The only thing that ever calls it is
-- fn_emit_metric_alerts, scheduled `0 3 * * 1` — once a week, on a Monday, as a side effect of an
-- alerting job. So the company defines fourteen KPIs, computes them once a week by accident, and
-- calls the result a live digital twin.
--
-- Every other leg of digital-twin-live-kpis already passes: fn_report_drilldown is a
-- browser-reachable reader of metric_snapshot and emits it, and eighteen places in the shell
-- refresh without a reload. The schedule is the whole remaining distance.
--
-- ── WHY SIX-HOURLY AND NOT DAILY ────────────────────────────────────────────────────────────────
-- The staleness window that matters is 24 hours. A job whose PERIOD equals the window fails on any
-- jitter — one late or skipped run and every KPI is stale. Six-hourly is the coarsest cadence that
-- keeps a 4x margin, and the cost is fourteen scalar measurements four times a day.
--
-- :35 past the hour, away from the :00, :05, :10, :20, :25 and :40 jobs already on the clock.
--
-- cron.schedule() UPSERTS on the job name, so re-applying this file cannot create a second job.
-- The guard is a pg_proc lookup rather than to_regproc('cron.schedule'), which returns NULL on an
-- overloaded name and would make the guard silently always-false — see cron_improvement_handover.sql.
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'cron' and p.proname = 'schedule') then
    raise notice 'pg_cron not installed; bi_snapshot_6h not scheduled';
    return;
  end if;
  perform cron.schedule('bi_snapshot_6h', '35 */6 * * *', 'select public.fn_bi_snapshot();');
end $$;
