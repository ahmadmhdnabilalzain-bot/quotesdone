-- The registry row for capability_verify_daily. STAGING ONLY — apply_sql --ddl forbids carrying row
-- data to production; this row reaches production through promote_rows_to_production.mjs.
-- s38-manual-always-current reads 0 undocumented and 0 ghosts; an unregistered job puts it back to 1.
insert into public.cron_registry (jobname, human_name, category, purpose)
values ('capability_verify_daily', 'Critical capability verification (daily)', 'governance',
        'Writes v_critical_capability_tests back onto critical_capability.last_verdict and last_checked, and raises a founder alert for any capability whose real test verdict is failing. Before this the sixteen capabilities were graded by a view that nothing read, so matching had been failing at 33% for days with no surface saying so.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
