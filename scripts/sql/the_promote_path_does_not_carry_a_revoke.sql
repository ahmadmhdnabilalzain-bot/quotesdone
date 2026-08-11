-- THE PROMOTE PATH CANNOT CARRY A REVOKE, AND THAT IS HOW A FUNCTION REACHES anon.
--
-- Caught by measurement on production 2026-08-11 18:35 UTC, minutes after creating it:
--
--   has_function_privilege('anon','public.fn_employee_scorecard(text,integer)','execute')  ->  TRUE
--
-- apply_sql.mjs --promote deliberately promotes a routine by reading pg_get_functiondef() back out
-- of staging and posting THAT verbatim, so the two projects cannot drift. pg_get_functiondef emits
-- the CREATE FUNCTION statement and NOTHING ELSE - no GRANT, no REVOKE. So the revoke in the source
-- file runs on staging and is silently absent on production, where a brand-new signature is a fresh
-- CREATE and Postgres grants EXECUTE to PUBLIC by default.
--
-- The same session proves the contrast: fn_dept_objective_measure, fn_employee_kpi_measure and
-- fn_goal_decompose all came back FALSE for anon, because those files were applied with --ddl,
-- which posts the identical file text - revoke included - to both projects.
--
-- This is the fourth instance of the documented trap ("a new signature is a new CREATE"). Applied
-- with --ddl so that the revoke itself reaches production.

revoke all on function public.fn_employee_scorecard(text, integer) from public;
revoke all on function public.fn_employee_scorecard(text, integer) from anon;
