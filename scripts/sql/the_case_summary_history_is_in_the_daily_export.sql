-- THE CASE SUMMARY HISTORY IS IN THE DAILY EXPORT (it_engineer, 11 Nov 2026; for customer_support).
--
-- MEASURED 11 Nov 2026 on origin/main b6585d489: every_table_is_exported_or_explicitly_excluded failed on one table.
-- every_support_case_keeps_a_summary_and_the_reply_reads_it.sql (#1938, applied 11 Nov ~11:20 UTC) created
-- public.support_case_summary_version, the append-only history of each case summary (founder ruling 1635), and inserted
-- no public.table_export_registry row, so the daily export (fn_table_export_list(), read by backup/index.ts) neither
-- backed it up nor said why not.
--
-- THE DECISION: EXPORTED. Founder ruling 1634 (11 Nov 2026): keep everything in history, for the learning loop and for
-- investor negotiations. A summary version is what the agent knew about a case at that moment; no later run rebuilds it.
--
-- WHY A SEPARATE FILE. The creating file is applied and holds routines; re-applying it to add one statement puts more on
-- production than the change needs (the same choice as the_twelve_tables_made_on_10_november_are_in_the_daily_export.sql).
--
-- NOT CHANGED: fn_table_export_list(), the registry's other rows, any table.
-- prevented by: scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs (it failed on main for this table
-- and passes with this file).
--
--   node scripts/apply_sql.mjs scripts/sql/the_case_summary_history_is_in_the_daily_export.sql --apply --ddl --seat it_engineer

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('support_case_summary_version', true, 'customer', 'Each version of a support case summary: what the agent knew about the case at that moment (founder rulings 1634, 1635).', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- VERDICT (this file sets one row and reads it back).
select case when exists (select 1 from public.table_export_registry where table_name = 'support_case_summary_version' and exported)
            then 'OK support_case_summary_version is exported' else 'FAILED: support_case_summary_version not registered' end as verdict;
