-- THE HOLDOUT RUNNER IS EXECUTABLE BY NO CLIENT ROLE (it_engineer, 17 Nov 2026).
--
-- Security audit of 17 Nov 2026 (docs/reports/2026-11-17-security-audit.md, finding 4). holdout_v2.fn_run_pending(integer,
-- integer) is SECURITY DEFINER (owner postgres), inserts into and deletes from public, and its ACL is the default
-- (NULL), so PUBLIC -- hence anon and authenticated -- may execute it. Only the missing USAGE on schema holdout_v2 stops
-- them. The gate's anon_cannot_execute_security_definer check looked at public only, so it could not see this.
--
-- MEASURED (SELECT on the catalogue, 17 Nov 2026): it is the ONLY SECURITY DEFINER routine outside public that anon or
-- authenticated may execute, in any schema; it has one overload; no cron job, no routine body and no file in the
-- repository calls it (the two mentions are comments). Its search_path is 'public' alone, so pg_temp was searched first.
-- pg_get_functiondef md5 22ecd2294d7b03f06c99c74aaeeaed7f; the body is NOT redefined here.
--
-- WHAT THIS CHANGES: EXECUTE is revoked from PUBLIC, anon and authenticated (PUBLIC first: a revoke from anon against a
-- PUBLIC grant is a silent no-op), and search_path is pinned to public, pg_temp with ALTER, so no body is retyped.
-- service_role also loses EXECUTE (it held it only through PUBLIC); nothing calls the routine, and the owner keeps it.
-- The gate's check now covers every schema this project owns, not only public (same branch).
--
-- ROLLBACK: grant execute on function holdout_v2.fn_run_pending(integer, integer) to public;
--           alter function holdout_v2.fn_run_pending(integer, integer) set search_path to public;
--
--   node scripts/apply_sql.mjs scripts/sql/the_holdout_runner_is_executable_by_no_client_role.sql --apply --ddl

revoke execute on function holdout_v2.fn_run_pending(integer, integer) from public, anon, authenticated;
alter function holdout_v2.fn_run_pending(integer, integer) set search_path to 'public', 'pg_temp';

-- verdict row: every overload is closed, the path is pinned, and no definer routine outside the platform schemas is
-- executable by a client role.
select case
  when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'holdout_v2' and p.proname = 'fn_run_pending') <> 1
    then 'PROBE FAILED: fn_run_pending no longer has exactly one overload; revoke each one'
  when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'holdout_v2' and p.proname = 'fn_run_pending'
                  and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE')))
    then 'PROBE FAILED: anon or authenticated can still execute holdout_v2.fn_run_pending'
  when (select proconfig from pg_proc where oid = 'holdout_v2.fn_run_pending(integer,integer)'::regprocedure)
       is distinct from array['search_path=public, pg_temp']
    then 'PROBE FAILED: holdout_v2.fn_run_pending search_path is not public, pg_temp'
  when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.prosecdef and n.nspname <> 'public'
                  and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
                  and pg_get_userbyid(n.nspowner) not in ('supabase_admin', 'pgbouncer')
                  and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE')))
    then 'PROBE FAILED: another SECURITY DEFINER routine outside public is executable by a client role'
  else 'PROBE OK' end as verdict;
