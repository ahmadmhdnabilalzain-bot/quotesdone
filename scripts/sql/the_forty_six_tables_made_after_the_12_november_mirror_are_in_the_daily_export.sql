-- THE FORTY-SIX TABLES MADE AFTER THE 12 NOVEMBER MIRROR ARE IN THE DAILY EXPORT (it_engineer, 17 Nov 2026; for the owning
-- seats named per row).
--
-- MEASURED 17 Nov 2026 (SELECT on production, pg_class against public.table_export_registry): 46 public tables have NO
-- registry row, so fn_table_export_list() - what backup/index.ts exports to the bucket and Dropbox every day - neither
-- backs them up nor says why not. All 46 were created by files applied between 12 and 17 Nov (all in MANIFEST); none of
-- those files inserted a row. The offline check every_table_is_exported_or_explicitly_excluded did not see them because
-- it read tables from the schema mirror alone, captured 12 Nov 11:19 UTC, and the gate runs with --skip=npm-test so it
-- did not run at all. Since 17 Nov the check reads the mirror plus every file applied after it (publicTablesNow in
-- scripts/lib/schema_mirror.mjs) and fails on exactly these 46.
--
-- WHY ONE FILE AND NOT TWENTY EDITS: as the_twelve_tables_made_on_10_november_are_in_the_daily_export.sql, the creating
-- files are applied and hold other seats' routines; this file holds only rows, so applying it can move nothing else.
--
-- THE DECISIONS, from each table's comment and its file's header. 43 are EXPORTED: they are records a later run cannot
-- rebuild (plans, decisions, orders and their turns, referrals, members, ownership, reveals, bill-to companies,
-- confirmations, limits and commitments, Search Console days). Three are EXCLUDED, each for a true reason:
--   pool_event_class   cache    each digest event classed demo or real once; the table keeps two days and re-classes
--   seat_pool_digest   cache    the company-today block, rebuilt by the ceo.company_pool duty every 15 minutes
--   demo_shadow_trace  fixture  what a Stripe TEST-mode or demo payment would have done, kept apart from the real books
-- subject_link is exported, not called a cache: fn_pool_link_backfill re-derives only the last 30 days.
--
-- NOT CHANGED: fn_table_export_list(), any other registry row, the creating files, any table.
-- prevented by: scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs and
-- every_marketing_table_is_in_the_daily_export.test.mjs (both fail on main for these and pass with this file), and this
-- file's _probe.sql after the apply.
-- Pending: scripts/sql/pending/the_forty_six_tables_made_after_the_12_november_mirror_are_in_the_daily_export.txt

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('accountant_cost_driver', true, 'accountant', 'What each model function and vendor costs per request, supplier, fixed, test or stopped: the accountant''s classification.', 'accountant'),
  ('accountant_request_economics', true, 'accountant', 'Cost and margin per request, break-even and cost cuts per month, as the accountant computed them each day.', 'accountant'),
  ('accountant_reveal_payment_check', true, 'payment', 'One row per paid reveal: the accountant''s reconcile of our invoice, the PaymentIntent and the balance transaction.', 'accountant'),
  ('ceo_grant_once', true, 'ceo', 'A single-use, time-limited permission the CEO gave a seat for one action on one subject.', 'ceo'),
  ('ceo_growth_channel', true, 'ceo', 'The CEO''s channel register: each channel''s safety verdict with its rule and rulings (ledger 1705/1706).', 'ceo'),
  ('ceo_own_decision', true, 'decision', 'A decision the CEO takes himself where the estate used to ask the founder (ledger 1696), with its reason.', 'ceo'),
  ('ceo_plan_bet', true, 'ceo', 'Each bet of a CEO plan: filed as an order with a measure, target and due date, or refused with reasons; scored.', 'ceo'),
  ('ceo_plan_week', true, 'ceo', 'Each CEO plan (seeded, weekly or daily review): what it read and what it proposed.', 'ceo'),
  ('ceo_supply_decision', true, 'decision', 'Every decision of the CEO''s supply loop, with its reason and the reading it was taken on (ledger 1696).', 'ceo'),
  ('company_limit_change', true, 'company', 'The company''s spending limits, append-only, each change in force 24 hours after it is written (ledger 1696).', 'ceo'),
  ('company_spend_commitment', true, 'accounting', 'Every AED a seat commits through the subject-aware authority check, by Dubai day.', 'accountant'),
  ('customer_referral', true, 'customer', 'A customer''s words on who referred him, the referrer, and when the referrer was thanked.', 'customer_support'),
  ('engineer_session_request', true, 'it_engineer', 'Work only the engineer session can do, asked from an order conversation, and what became of it.', 'it_engineer'),
  ('escalation_clock', true, 'customer_support', 'Every escalation as a case with a clock: what was promised, on which channel, and when word is next owed.', 'customer_support'),
  ('expense_awaiting_document', true, 'accounting', 'An expense booked on the founder''s word that waits for its statement line or receipt.', 'accountant'),
  ('founder_funding_commitment', true, 'accounting', 'The founder''s monthly funding commitment, each from a founder ledger entry.', 'accountant'),
  ('inquiry_decision_reason', true, 'inquiry', 'Why a customer did not choose a quotation, as he gave it, for the suppliers'' learning.', 'sales_engineer'),
  ('inquiry_revision', true, 'inquiry', 'Each revision of a posted request: every changed field with its old and new value, and who made it.', 'sales_engineer'),
  ('marketing_search_day', true, 'marketing', 'Google Search Console search analytics per day: the site total, each query and each page.', 'marketing'),
  ('marketing_search_sitemap', true, 'marketing', 'Google Search Console sitemaps: URLs submitted and indexed per sitemap.', 'marketing'),
  ('quote_figure_confirmation', true, 'quote', 'A supplier''s confirmation that a quoted total far from its peers is the figure he means.', 'sales_engineer'),
  ('request_reveal_outcome', true, 'sales_engineer', 'One row per paid reveal: the request''s reveal period and what the other suppliers were told.', 'sales_engineer'),
  ('reveal_bill_to', true, 'payment', 'The company a customer asked to be billed as when he revealed a quote (company, UAE TRN, PO reference).', 'accountant'),
  ('seat_capability', true, 'company', 'What each seat can do with its own tools today, and what it cannot (why, and who can).', 'ceo'),
  ('seat_order_thread', true, 'ceo', 'An order as a conversation until its outcome: one row per order hand-over, root or sub-order (16 Nov 2026).', 'ceo'),
  ('seat_order_turn', true, 'ceo', 'Every turn of an order conversation in order: plans, answers, check-ins, statuses and responses.', 'ceo'),
  ('subject_link', true, 'company', 'Which subjects each hand-over, event and judgement is about; the backfill re-derives only the last 30 days.', 'ceo'),
  ('supplier_account_closure', true, 'supplier', 'A supplier company''s request to close its account (quotes withdrawn or kept), and its outcome or reopening.', 'sales_engineer'),
  ('supplier_contact_removal_notice', true, 'supplier', 'A supplier told that contact details were removed from his quotation, and when.', 'sales_engineer'),
  ('supplier_coverage_target', true, 'ceo', 'Verified active suppliers wanted per trade per emirate, proposed and confirmed by the CEO (ledger 1701).', 'ceo'),
  ('supplier_customer_silence', true, 'supplier', 'A supplier''s report after a reveal that the customer is not answering, and the follow-up.', 'sales_engineer'),
  ('supplier_demand_signal', true, 'supplier', 'A supplier''s offer to pay for leads or exclusivity, recorded as a demand signal for the CEO.', 'sales_engineer'),
  ('supplier_loss_reason', true, 'supplier', 'Why a supplier lost a request: the text he was given and its basis.', 'sales_engineer'),
  ('supplier_member', true, 'supplier', 'The members of a supplier company and their roles.', 'sales_engineer'),
  ('supplier_ownership_claim', true, 'supplier', 'A claim to own a supplier company whose owner left, and the sales engineer''s decision.', 'sales_engineer'),
  ('supplier_ownership_transfer', true, 'supplier', 'A transfer of a supplier company''s ownership between members, with its codes and outcome.', 'sales_engineer'),
  ('supplier_referral', true, 'supplier', 'A registration that came through a supplier''s referral link.', 'sales_engineer'),
  ('supplier_referral_code', true, 'supplier', 'Each supplier''s referral link code.', 'sales_engineer'),
  ('supplier_strike_warning_retry', true, 'supplier', 'An undelivered strike warning sent again another way, and the result.', 'customer_support'),
  ('supplier_trade_correction', true, 'supplier', 'A proposed correction of a supplier''s trades or services, its source and its outcome.', 'sales_engineer'),
  ('supplier_whatsapp_offer_declined', true, 'supplier', 'A model-read no to the WhatsApp offer: recorded so the offer is not shown to him again.', 'sales_engineer'),
  ('supplier_whatsapp_optin_code_miss', true, 'supplier', 'Wrong WhatsApp opt-in codes per number, the brake on guessing.', 'sales_engineer'),
  ('supplier_whatsapp_optin_pending', true, 'supplier', 'A yes to WhatsApp by e-mail that waits for its number.', 'sales_engineer'),
  ('pool_event_class', false, 'cache', 'Each digest event classed demo or real once; the table keeps two days and the duty re-classes from the source.', 'ceo'),
  ('seat_pool_digest', false, 'cache', 'The company-today block each seat reads, rebuilt by the ceo.company_pool duty every 15 minutes.', 'ceo'),
  ('demo_shadow_trace', false, 'fixture', 'What a Stripe TEST-mode or demo payment would have done, kept apart from the real books on purpose.', 'accountant')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;
