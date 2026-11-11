-- THE TWELVE TABLES MADE ON 10 NOVEMBER ARE IN THE DAILY EXPORT (it_engineer, 11 Nov 2026; for the owning seats below).
--
-- MEASURED 11 Nov 2026 on origin/main 033ee03bc: every_table_is_exported_or_explicitly_excluded failed. Five files
-- applied on 10 Nov (all in MANIFEST) created twelve public tables and inserted no public.table_export_registry row for
-- any of them, so the daily export (fn_table_export_list(), read by backup/index.ts) neither backed them up nor said
-- why not. The check's rule: exported with its subject, or excluded as secret/cache/log/measurement/fixture/no_writer
-- only if that is truly what it is.
--
-- WHY ONE FILE AND NOT FIVE EDITS. The check accepts a row from any file in apply order. The five creating files are
-- applied and hold other seats' routines and seeds; re-applying all five to add one statement each puts more on
-- production than the change needs. This file holds only the twelve rows, so applying it can move nothing else.
--
-- THE DECISIONS, from each table's columns and its file's header (production could not be read for row counts: the
-- session's token answered 401). Every one is EXPORTED; none is a cache, a log or a measurement that a later run
-- rebuilds without loss:
--   the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql (ceo, with accountant)
--     break_even_basis         the founder's spend and target dates (ledger 1609) and the plan's assumed rates
--     break_even_cost_line     the vendor lines and their 'excluded' reasons; refreshed from the books, but the kind and
--                              basis of each line are the accountant's decision, which no refresh rebuilds
--     ceo_break_even_month     the ledger as the CEO computed it each month, with its verdict
--     ceo_break_even_replan    each re-plan: what was behind and the lever the CEO chose
--     ceo_seat_month_target    the CEO's monthly target per seat, and the measured status
--     ceo_year_plan_archive    the founder's 24 Sep plan, kept on purpose ("nothing the founder set is deleted")
--   the_ceo_approves_the_january_launch_plan_and_the_founder_reads_it_in_his_brief.sql (ceo)
--     ceo_brief_line           each CEO decision line the founder reads in his brief, once per subject
--   a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql (ceo, with customer_support)
--     trade_opening_rule       the CEO's opening threshold (5 to 25) and why it was set
--     trade_customer_opening   per trade: open or not, and when it opened or closed (the hourly tick re-counts the
--                              suppliers, but opened_at and closed_at are history it cannot rebuild)
--     customer_trade_waitlist  a customer or WhatsApp number waiting for a trade, and whether they were told
--   the_founder_gets_one_weekly_email_and_the_it_session_list_goes_to_the_session.sql (it_engineer)
--     it_session_fix_day       the day's IT list for the session and when a session read it
--   an_unanswered_request_is_a_strike_and_a_quote_clears_the_run.sql (customer_support, for the sales engineer)
--     supplier_strike_event    each strike and clearing on a supplier's matchability
--
-- NOT CHANGED: fn_table_export_list(), the registry's other rows, the five creating files, any table.
-- prevented by: scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs (it failed on main for these twelve
-- and passes with this file), and this file's _probe.sql after the apply.
-- Pending: scripts/sql/pending/the_twelve_tables_made_on_10_november_are_in_the_daily_export.txt

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('break_even_basis', true, 'ceo', 'The founder''s spend and target dates for break-even by 30 Jun 2027 and the plan''s assumed rates (ledger 1609).', 'ceo'),
  ('break_even_cost_line', true, 'accounting', 'The break-even ledger''s vendor cost lines, and the reason each excluded line is not counted (ledger 1609).', 'accountant'),
  ('ceo_break_even_month', true, 'decision', 'The break-even ledger as the CEO computed it each month, with its verdict (ledger 1609).', 'ceo'),
  ('ceo_break_even_replan', true, 'decision', 'Each CEO re-plan of the break-even ledger: what was behind and the lever chosen (ledger 1609).', 'ceo'),
  ('ceo_seat_month_target', true, 'ceo', 'The CEO''s monthly target per seat and its measured status (ledger 1609).', 'ceo'),
  ('ceo_year_plan_archive', true, 'ceo', 'The founder''s 24 Sep 2026 year plan, kept when ledger 1609 replaced it as the operating plan.', 'ceo'),
  ('ceo_brief_line', true, 'decision', 'Each CEO decision line the founder reads in his daily brief, once per subject.', 'ceo'),
  ('trade_opening_rule', true, 'decision', 'The CEO''s threshold for opening a trade to customers (5 to 25 verified suppliers) and why (ledger 1614).', 'ceo'),
  ('trade_customer_opening', true, 'decision', 'Per trade: open to customers or not, and when it opened or closed (ledger 1614).', 'ceo'),
  ('customer_trade_waitlist', true, 'customer', 'A customer or WhatsApp number waiting for a trade to open, and whether they were told (ledger 1614).', 'customer_support'),
  ('it_session_fix_day', true, 'it_engineer', 'The day''s IT fix list handed to the session, and when a session read it (ledger 1616).', 'it_engineer'),
  ('supplier_strike_event', true, 'supplier', 'Each strike and clearing on a supplier''s matchability: an unanswered request, or a quote.', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;
