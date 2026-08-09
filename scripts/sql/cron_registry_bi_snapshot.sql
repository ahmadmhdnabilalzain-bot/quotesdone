-- The registry row for bi_snapshot_6h (scripts/sql/cron_bi_snapshot.sql).
--
-- s38-manual-always-current measures drift in BOTH directions: automation that runs and is not
-- documented, and documentation for automation that no longer exists. It reads 0 and 0 today
-- against 151 active jobs. Scheduling a job without registering it would put it straight back to 1.
--
-- STAGING ONLY. apply_sql --ddl forbids carrying row data to production; this row reaches
-- production through promote_rows_to_production.mjs, which reads the verified value back out.
insert into public.cron_registry (jobname, human_name, category, purpose)
values ('bi_snapshot_6h', 'Business KPI snapshot (6-hourly)', 'analytics',
        'Executes every active metric_definition.measure_sql and writes the result to metric_snapshot, so the fourteen defined KPIs have a history rather than the two days they had when this was only a weekly side effect of fn_emit_metric_alerts.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
