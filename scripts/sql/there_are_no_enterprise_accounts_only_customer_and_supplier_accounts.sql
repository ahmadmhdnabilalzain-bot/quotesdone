-- THERE ARE NO ENTERPRISE ACCOUNTS: ONLY CUSTOMER ACCOUNTS AND SUPPLIER ACCOUNTS.
-- Seat: sales_engineer. 30 Sep 2026. Founder ruling, 30 Sep 2026: "No enterprise accounts. We have customer accounts
-- and supplier accounts, that's it."
--
-- WHAT IS REMOVED (all created by the_sales_engineer_reviews_the_week_owns_licences_the_ladder_and_enterprise_accounts.sql,
-- 24 Sep 2026; that file is now history for these objects - its other sections, the weekly review, licence validity and
-- the reveal ladder, stay live):
--   * seat_duty sales_engineer.enterprise_pipeline (weekly). No cron job, it_duty_schedule, duty_pause or
--     marketing_duty_run row names it (measured 30 Sep 2026); fn_seat_duties_tick reads seat_duty only.
--   * fn_sales_engineer_enterprise_pipeline() and fn_enterprise_account_report(bigint). No other routine, view, trigger
--     or policy names either (pg_proc.prosrc, pg_views, pg_trigger; measured 30 Sep 2026).
--   * enterprise_account_member (0 rows) and enterprise_account (0 rows), with their policies, grants, sequence and
--     the one foreign key between them. No other table references them and no customer table has an
--     enterprise_account_id column (information_schema, measured 30 Sep 2026).
--   * their two table_export_registry rows.
-- Each routine drop is recorded in routine_change_log by the qd_record_routine_drop event trigger and in DROPPED.txt.
--
-- NOT TOUCHED, on purpose: ceo_year_plan.enterprise and ceo_mandate 'reveal_fees_and_enterprise' are the founder's
-- 24 Sep year-one targets (they set the request, reveal and fee path). Re-deriving his revenue path is his number to
-- set, not an engineering change; this file removes the machinery only.
--
-- Guard: scripts/checks/enterprise_accounts_never_return.test.mjs.

delete from public.seat_duty where duty = 'sales_engineer.enterprise_pipeline';

drop function if exists public.fn_sales_engineer_enterprise_pipeline();
drop function if exists public.fn_enterprise_account_report(bigint);

drop table if exists public.enterprise_account_member;
drop table if exists public.enterprise_account;

delete from public.table_export_registry where table_name = 'enterprise_account_member';
delete from public.table_export_registry where table_name = 'enterprise_account';

-- Knowledge that teaches enterprise accounts as something QuotesDone keeps. The sales_engineer seat's entry
-- sales_engineer:enterprise-account-plan leaves sales_knowledge when knowledge/ is reloaded
-- (node scripts/kb/load_verified_packs.mjs --apply retires every verified_pack row no longer in the repo).
-- The four ops_knowledge records below are the dismantled business_development department's (7 Sep 2026), by exact
-- record_id. knowledge_exam_questions #713 (built from one of them, for the deleted backend_engineer agent) stays:
-- that table is frozen as no_writer in the export registry, and no seat sits that exam.
delete from public.ops_knowledge where record_id in (
  'ops-department-business-development-professional-knowledge-operational-application-enterprise--d603740d31',
  'ops-department-business-development-controls-control-requirements-enterprise-accounts-controls-3fdb5ba956',
  'ops-department-business-development-evidence-data-and-evidence-enterprise-accounts-evidence-an-fb8b5d1eb7',
  'ops-department-business-development-professional-knowledge-knowledge-domain-enterprise-account-b9da3a5356');

-- the seat's playbook is generated from seat_duty; rebuild it so it no longer lists the duty
select public.fn_seat_playbook_build('sales_engineer', 'enterprise accounts removed, founder ruling 30 Sep 2026');

select case
  when to_regclass('public.enterprise_account') is not null or to_regclass('public.enterprise_account_member') is not null
    then 'PROBE FAILED: an enterprise table is still present'
  when exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                 and proname in ('fn_sales_engineer_enterprise_pipeline', 'fn_enterprise_account_report'))
    then 'PROBE FAILED: an enterprise routine is still present'
  when exists (select 1 from public.seat_duty where duty = 'sales_engineer.enterprise_pipeline')
    then 'PROBE FAILED: the enterprise duty is still scheduled'
  when exists (select 1 from public.table_export_registry where table_name like 'enterprise_account%')
    then 'PROBE FAILED: the export registry still lists an enterprise table'
  when exists (select 1 from public.ops_knowledge where record_id like 'ops-department-business-development-%enterprise-account%')
    then 'PROBE FAILED: the department''s enterprise-account knowledge is still present'
  when exists (select 1 from public.seat_playbook where seat = 'sales_engineer' and markdown ilike '%enterprise_pipeline%')
    then 'PROBE FAILED: the sales_engineer playbook still lists the enterprise duty'
  else 'PROBE OK' end as verdict;
