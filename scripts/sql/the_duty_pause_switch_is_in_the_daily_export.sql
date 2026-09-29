-- THE DUTY PAUSE SWITCH IS IN THE DAILY EXPORT (30 Sep 2026; seat: it_engineer).
--
-- every_duty_runner_honours_one_pause_switch.sql (on main, applied) created public.duty_pause, and
-- the_daily_export_reads_a_registry_every_pull_request_adds_rows_to.sql landed beside it without a row for it, so
-- scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs is red on main (measured 30 Sep 2026,
-- origin/main 64795c0: "duty_pause" is the one unregistered table). A pause row is a decision someone took
-- (reason, paused_by), so it is exported with the company's records.
--   node scripts/apply_sql.mjs scripts/sql/the_duty_pause_switch_is_in_the_daily_export.sql --apply

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('duty_pause', true, 'company', 'one row pauses one duty wherever it runs, with the reason and who paused it', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;
