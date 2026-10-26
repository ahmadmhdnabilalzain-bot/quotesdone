-- STAGING'S MANUAL DESCRIBED FOUR JOBS THAT ONLY EXIST ON PRODUCTION.
--
-- 13 Aug 2026, found while fixing an s38 regression on production. The same drift check run against
-- staging:
--
--   undocumented active jobs        0
--   documented jobs that do not run 4   <- ai_health_15min, money_tests_daily,
--                                          qa_suite_daily, uptime_check_15min
--
-- These four ARE scheduled on production, and their cron commands are
-- `net.http_post(url := 'https://<production ref>.supabase.co/functions/v1/...')` with the ref
-- hardcoded. They were correctly never scheduled on staging: copying them across would have
-- pointed staging's scheduler at production's endpoints. What crossed over was the REGISTRY ROW,
-- which is seeded per project, so staging's manual claims four jobs staging does not run.
--
-- (The ref is written as a placeholder above because scripts/staging/qd_guard.mjs refuses any file
-- containing the production ref literal - it cannot tell a comment from a connection string, and
-- that is the right way round for a guard whose job is stopping branch code reaching production.
-- It refused this file on the first attempt.)
--
-- public.cron_registry is a per-project record of what that project actually runs. A row describing
-- somebody else's scheduler is not documentation, it is an inherited claim, and s38 is right to
-- count it as drift. Removing it makes staging's manual true.
--
-- WHAT THIS DELIBERATELY DOES NOT DO: schedule staging equivalents pointing at
-- pglpqrhvozwepymcuunn. That is the better long-term answer - staging is exactly where a money or
-- health regression should surface first, and money_tests now runs meaningfully there (it asserts
-- the Stripe key is NOT live off production, and needs no pricing_config row to complete). It is
-- left out because ai_health_15min and uptime_check_15min fire 96 times a day each and I have not
-- measured what ai_health costs per call. Adding ~194 daily invocations on a hunch is a spend
-- decision, and spend is the founder's to make. The rows are removed so the manual stops lying;
-- the scheduling question is stated here rather than silently answered.

delete from public.cron_registry r
 where r.jobname in ('ai_health_15min', 'money_tests_daily', 'qa_suite_daily', 'uptime_check_15min')
   and not exists (select 1 from cron.job j where j.jobname = r.jobname);
