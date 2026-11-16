-- THE FOUR WATCHERS NOTHING RUNS ARE RETIRED, AND THE CODE NAMES fn_it_detect AS THE READER OF A FAILED RUN.
--
-- Seat: it_engineer. Founder ledgers 1714 and 1715 (16 Nov 2026): remove what is unnecessary and prove each removal with
-- evidence, and prove everything is still fine.
--
-- WHAT WAS WRONG. Eight edge-function comments said fn_watch_failed_runs "pages on status='error'" and fn_agents_board
-- "LEFT JOINs agent_runs" for seat liveness. Nothing runs either of them, nor fn_runner_silence_watch or
-- fn_agent_silence_watch: no cron job, no seat duty, no body, no edge call (measured below). The reader that does exist is
-- public.fn_it_detect, run by supabase/functions/resilience_ping/ticks/it_engineer/detect.ts and fn_it_engineer_alert_tick:
-- its D1 reads seven days of agent_runs and counts any status outside its ok list ('ok','success','completed','skipped','warn',
-- 'held','noop'), 'error' included, as a failure; its D2 is the silence watch, from each subject's own rhythm; D9 the refusals.
-- The same commit rewrites the comments to name it. fn_agents_board's one body caller, fn_ws_exec_home, is retired by
-- the_july_os_console_backend_and_the_old_agent_context_are_retired.sql, which is applied BEFORE this file.
-- fn_rehearsal_window_covers (whose only body caller was fn_watch_failed_runs) stays in public: a check runs it.
--
-- HOW "NO CALLER" WAS MEASURED (16 Nov 2026, it_engineer, production read with light SELECTs only):
--   * every live routine body in every schema, read with pg_get_functiondef (2,667 in public), comments stripped;
--   * every cron.job command (active or not), trigger, event trigger, view, RLS policy, column default and check constraint;
--   * every table that names a routine for dispatch: seat_duty.routine, seat_handoff_kind.handler, org_task_kind_handler.handler,
--     org_departments.health_fn, agent_tool.impl_target, it_playbook.remedy_routine, it_rerunnable_job.routine,
--     it_safe_fix_family.routine, org_action_executor, fn_task_class, llm_seat_binding, quality_standard.criteria, decision_policy
--     and every *_sql column; and the run-time name builders ('fn_reason_apply_' ||, 'fn_it_game_day_' ||, format('%I') over those
--     tables) - none of which can produce these names;
--   * origin/main supabase/functions and src, comments stripped (no rpc name in either is built from a template);
--   * pg_stat_statements (reset 2 Nov 07:12 UTC, track = top): no top-level statement by any role calls them.
--   A routine whose only body callers are themselves retired here is retired with them (the closure is checked by the probe).
--   The per-object evidence is in the hand-back's EVIDENCE_C.md; the names below carry what still MENTIONS them.
--
-- REVERSIBLE (phase 1 of 2). Nothing is dropped: each object only changes schema, so a caller nobody found fails loudly
-- with "function public.<name> does not exist" instead of silently, and one line brings it back (listed per object below).
-- Phase 2 (DROP, after the tables are archived to the evidence bucket with row counts and checksums) is owed after 7 clean
-- days: scripts/sql/pending/the_retired_schema_is_dropped_only_after_seven_clean_days_probe.txt says how clean is measured.

-- THE OBJECTS (public signature, then who still mentions the name - a scripts/sql definition, a check, an archived file):
--   fn_watch_failed_runs()                                                 mentioned only by: sqlfile:6 archive:1 test:1
--   fn_runner_silence_watch()                                              mentioned only by: sqlfile:7
--   fn_agent_silence_watch()                                               mentioned only by: sqlfile:6 test:1
--   fn_agents_board()                                                      mentioned only by: sqlfile:11 archive:1 script:2 body of fn_ws_exec_home
--
-- REVERSAL, one line per object (run as postgres): back to public, with the EXECUTE grants it had on 16 Nov:
--   alter function retired.fn_watch_failed_runs() set schema public; grant execute on function public.fn_watch_failed_runs() to service_role;
--   alter function retired.fn_runner_silence_watch() set schema public; grant execute on function public.fn_runner_silence_watch() to service_role;
--   alter function retired.fn_agent_silence_watch() set schema public; grant execute on function public.fn_agent_silence_watch() to service_role;
--   alter function retired.fn_agents_board() set schema public; grant execute on function public.fn_agents_board() to service_role;

-- The schema that holds what is retired: owned by postgres, no USAGE for anyone else (PUBLIC, anon, authenticated and
-- service_role cannot even name an object in it), so a retired routine cannot be called and a retired table cannot be read
-- from the API. postgres keeps full access for the phase-2 archive. Idempotent: every cluster file repeats these lines.
create schema if not exists retired;
revoke all on schema retired from public, anon, authenticated, service_role;

do $retire_watchers$
begin
  if to_regprocedure('public.fn_watch_failed_runs()') is not null then
    revoke all on function public.fn_watch_failed_runs() from public, anon, authenticated, service_role;
    alter function public.fn_watch_failed_runs() set schema retired;
  end if;
  if to_regprocedure('public.fn_runner_silence_watch()') is not null then
    revoke all on function public.fn_runner_silence_watch() from public, anon, authenticated, service_role;
    alter function public.fn_runner_silence_watch() set schema retired;
  end if;
  if to_regprocedure('public.fn_agent_silence_watch()') is not null then
    revoke all on function public.fn_agent_silence_watch() from public, anon, authenticated, service_role;
    alter function public.fn_agent_silence_watch() set schema retired;
  end if;
  if to_regprocedure('public.fn_agents_board()') is not null then
    revoke all on function public.fn_agents_board() from public, anon, authenticated, service_role;
    alter function public.fn_agents_board() set schema retired;
  end if;
end
$retire_watchers$;

-- PROBE (watchers): a verdict row, never a raise (a raise would roll back the moves above). It reads, live, at apply time:
--   moved      every signature is now in schema retired;  gone  no routine of these names is left in public;
--   callers    no routine outside schema retired names one of them in its body (comments stripped), no cron command,
--              no view, no policy, no column default, and no trigger outside retired runs a retired routine;
--   closed     no role but postgres may execute a retired routine.
with sig(s) as (values
         ('fn_watch_failed_runs()'),
         ('fn_runner_silence_watch()'),
         ('fn_agent_silence_watch()'),
         ('fn_agents_board()')),
nm(n) as (select unnest(array['fn_agent_silence_watch','fn_agents_board','fn_runner_silence_watch','fn_watch_failed_runs'])),
body as (select regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') src, ns.nspname || '.' || p.proname who
           from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
          where ns.nspname not in ('retired', 'pg_catalog', 'information_schema')
            and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
v as (select
  (select count(*) from sig where to_regprocedure('retired.' || s) is not null) moved,
  (select count(*) from sig) wanted,
  (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace join nm on nm.n = p.proname where ns.nspname = 'public') left_in_public,
  (select string_agg(who || ' names ' || substring(src from '\m(fn_agent_silence_watch|fn_agents_board|fn_runner_silence_watch|fn_watch_failed_runs)\M'), '; ') from body where src ~ '\m(fn_agent_silence_watch|fn_agents_board|fn_runner_silence_watch|fn_watch_failed_runs)\M') body_callers,
  (select string_agg(jobname, ', ') from cron.job where command ~ '\m(fn_agent_silence_watch|fn_agents_board|fn_runner_silence_watch|fn_watch_failed_runs)\M') cron_callers,
  (select string_agg(schemaname || '.' || viewname, ', ') from pg_views where schemaname not in ('retired', 'pg_catalog', 'information_schema') and definition ~ '\m(fn_agent_silence_watch|fn_agents_board|fn_runner_silence_watch|fn_watch_failed_runs)\M') view_callers,
  (select string_agg(tablename || '.' || policyname, ', ') from pg_policies where coalesce(qual, '') || ' ' || coalesce(with_check, '') ~ '\m(fn_agent_silence_watch|fn_agents_board|fn_runner_silence_watch|fn_watch_failed_runs)\M') policy_callers,
  (select string_agg(c.relname, ', ') from pg_attrdef ad join pg_class c on c.oid = ad.adrelid where pg_get_expr(ad.adbin, ad.adrelid) ~ '\m(fn_agent_silence_watch|fn_agents_board|fn_runner_silence_watch|fn_watch_failed_runs)\M') default_callers,
  (select string_agg(c.relname || '.' || t.tgname, ', ') from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
     join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace where pn.nspname = 'retired' and cn.nspname <> 'retired') trigger_callers,
  (select count(*) from sig, unnest(array['anon', 'authenticated', 'service_role']) r(role)
     where to_regprocedure('retired.' || s) is not null and has_function_privilege(r.role, to_regprocedure('retired.' || s), 'execute')) still_executable)
select case when moved = wanted and left_in_public = 0 and body_callers is null and cron_callers is null and view_callers is null
             and policy_callers is null and default_callers is null and trigger_callers is null and still_executable = 0
            then 'PROBE OK: watchers: ' || moved || ' of ' || wanted || ' routines in schema retired, none left in public, no caller outside retired, executable by no API role'
            else 'PROBE FAILED: watchers: moved ' || moved || '/' || wanted || ', left in public ' || left_in_public
                 || ', bodies [' || coalesce(body_callers, '') || '], cron [' || coalesce(cron_callers, '') || '], views [' || coalesce(view_callers, '')
                 || '], policies [' || coalesce(policy_callers, '') || '], defaults [' || coalesce(default_callers, '') || '], triggers [' || coalesce(trigger_callers, '')
                 || '], executable by an API role ' || still_executable end as verdict
  from v;
