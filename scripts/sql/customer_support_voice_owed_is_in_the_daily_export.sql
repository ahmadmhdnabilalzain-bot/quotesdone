-- customer_support_voice_owed IS IN THE DAILY EXPORT (customer_support; registered by it_engineer, 1 Nov 2026).
--
-- Assigned: customer_support (the table is its outbox of duty messages owed to a customer or supplier).
--
-- MEASURED 1 Nov 2026: scripts/sql/customer_support_writes_its_duty_updates_through_the_model.sql (MANIFEST line 2169)
-- created public.customer_support_voice_owed and inserted no row into public.table_export_registry, so the table was
-- in neither the daily export nor its exclusions. Production read the same day: no registry row, 0 rows in the table.
-- scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs failed on main for it.
--
-- Exported, as a conversation record: each row is a message the company owed a named customer or supplier (to_email,
-- the draft, the situation and facts it was written from) and what the model finally wrote and when. That is the same
-- subject as public.notifications, which is exported as 'conversation'.
--
-- Prevented by: scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs (a table with no row fails it).
--   node scripts/apply_sql.mjs scripts/sql/customer_support_voice_owed_is_in_the_daily_export.sql --apply

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('customer_support_voice_owed', true, 'conversation', 'A duty message customer_support owed a customer or supplier: the recipient, the draft and facts it was written from, and what the model wrote and when (founder_instruction 1339).', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

select case when exists (select 1 from public.table_export_registry
                          where table_name = 'customer_support_voice_owed' and exported and category = 'conversation')
            then 'PROBE OK' else 'PROBE FAILED: customer_support_voice_owed has no exported registry row' end as verdict;
