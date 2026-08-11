-- STAGING ONLY. DO NOT PROMOTE THIS FILE. Applying it to production disables production monitoring.
--
-- FOUR ACTIVE CRON JOBS ON STAGING POSTED TO PRODUCTION URLS.
--
-- Measured 2026-08-11:
--
--   ai_health_15min      7,22,37,52 * * * *   -> https://<production-ref>.supabase.co/functions/v1/ai_health
--   uptime_check_15min   */15 * * * *         -> https://<production-ref>.supabase.co/functions/v1/uptime_check
--   money_tests_daily    30 3 * * *           -> https://<production-ref>.supabase.co/functions/v1/money_tests
--   qa_suite_daily       37 3 * * *           -> https://<production-ref>.supabase.co/functions/v1/qa_suite
--
-- PRODUCTION ALREADY RUNS ALL FOUR ITSELF, ON IDENTICAL SCHEDULES. So these are not a second
-- monitoring vantage point; they are the same job fired twice at the same minute, with the results
-- landing in production's own tables where nothing records which invoker produced them.
--
-- WHAT THE DUPLICATION IS NOT DOING, measured before removing anything:
--   - It is not doubling data. health_checks receives exactly 5 rows per hour across 5 targets,
--     while the uptime cron fires 8 times in two hours from each project. uptime_check does not
--     write per invocation.
--   - It is not costing model spend. ai_health, qa_suite, money_tests and uptime_check have made
--     ZERO ai_cost_log entries in 7 days.
--
-- WHAT IT IS DOING is letting a staging schedule drive production behaviour. uptime_check_15min has
-- succeeded 97 times from staging and ai_health_15min 96 times, all HTTP 200 - production accepted
-- every one. That is the part worth removing: a change to a staging cron should not be able to
-- invoke a production edge function with internal authority.
--
-- THE UNDERLYING CAUSE IS NOT FIXED HERE AND IS ESCALATED, NOT GUESSED AT. The reason production
-- accepts these calls is that the two projects hold BYTE-IDENTICAL internal credentials -
-- app_secrets.cred_cron_monitoring, cred_cron_agents and inbound_secret have the same md5 and the
-- same length on both. Rotating them is a destructive production change touching every one of 172
-- active jobs, and whether the sharing is deliberate is a fact the founder holds. Removing the four
-- schedules removes the behaviour without touching a credential, and is reversible with one
-- cron.schedule call each.

select cron.unschedule('ai_health_15min')    where exists (select 1 from cron.job where jobname='ai_health_15min');
select cron.unschedule('uptime_check_15min') where exists (select 1 from cron.job where jobname='uptime_check_15min');
select cron.unschedule('money_tests_daily')  where exists (select 1 from cron.job where jobname='money_tests_daily');
select cron.unschedule('qa_suite_daily')     where exists (select 1 from cron.job where jobname='qa_suite_daily');
