-- THE SCHEMA-MIRROR GATE WAS RED BECAUSE ANOTHER SESSION HELD A LOCK, NOT BECAUSE PRODUCTION DRIFTED.
--
-- `export_from_either_source_is_identical` failed 11 times out of 29 runs in one 2.5-hour stretch on
-- 18 Sep 2026 — 38%, including on the head of main — always with the same error:
--     ERROR: 57014: canceling statement due to statement timeout
--     CONTEXT: SQL function "fn_schema_export" statement 1
-- The obvious reading is that the export outgrew the budget: the mirror is 62,223 lines and 3.5 MB
-- and every apply makes it bigger. MEASURED 18 Sep 2026, that reading is wrong.
--
-- WHAT THE EXPORT ACTUALLY COSTS (management API, statement_timeout = 2min):
--     select * from public.fn_schema_export()   857, 1042, 1381, 1229, 886 ms   (5 consecutive runs,
--                                                                                3,523,813 chars each)
--     select length(public.fn_schema_export())  636, 487, 1004 ms
--   Per section, `explain (analyze, buffers)`, warm: EXTENSIONS 0.3ms, SEQUENCES 4ms, TABLES 342ms,
--   VIEWS 432ms, FUNCTIONS 314ms. The whole statement is a SECOND. It is nowhere near two minutes,
--   and the sections everybody suspects (FUNCTIONS is 2.8 MB of the 3.5 MB) are not the cost either.
--   The TABLES scan itself — the statement the error names — plans and executes in 14 ms over
--   5,498 attributes; `not exists (… pg_depend …)` is already a Hash Right Anti Join, not a per-row
--   scan. Substituting format_type and pg_get_expr into that projection changed nothing (11-12 ms).
--   THERE IS NO SLOW STATEMENT TO OPTIMISE. Nothing here is paginated, made incremental or
--   rewritten, because a rewrite would risk the one property this export exists to have — that its
--   bytes equal the committed mirror's — to fix a cost that was never there. A server-side hash
--   fast path was considered and rejected for the same reason plus one more: the check's value is
--   the first differing LINE, which needs the full text anyway on any mismatch.
--
--   THE BOUNDARY OF THAT MEASUREMENT, stated rather than implied: the per-section figures above are
--   WARM. Only TABLES was also measured cold (11,568 ms on a first run, and 81,176 ms once while
--   other sessions were applying) — VIEWS and FUNCTIONS were never measured cold, and FUNCTIONS is
--   2.84 MB of the 3.5 MB. So "the export costs about a second" is a claim about a warm database,
--   which is the state every run after the first one is in. What IS measured end to end is the
--   whole statement: 20 consecutive full exports in a quiet window all returned 201.
--
-- WHAT IT REALLY WAITS ON. fn_schema_export deparses every object in `public`
-- (pg_get_expr, pg_get_indexdef, pg_get_constraintdef, pg_get_triggerdef, pg_get_functiondef), and
-- deparsing opens the relation, which takes an ACCESS SHARE lock. Any concurrent DDL — another
-- session's `apply_sql.mjs --apply --ddl` — holds ACCESS EXCLUSIVE and the export simply stops.
-- MEASURED, with an aborted-transaction probe that locked ONE table and rolled back:
--     holder: lock table public.notifications in access exclusive mode; pg_sleep(12); rollback
--     export while that lock was held: 12,374 ms  (a statement that takes ~900 ms unblocked)
-- One table, one lock, and the export waits for all of it. A 2-minute apply therefore does not slow
-- the gate down — it kills it, and the check then reports the same red it reports for real drift.
-- That is the estate's own lens: an instrument measuring the wrong subject. The 38% was never about
-- the schema; it tracked how many other sessions were applying at the time.
--
-- THE FIX IS TO STOP WAITING SILENTLY. With no lock_timeout the export sits blocked until the
-- 2-minute statement_timeout fires, so one contended run costs a full two minutes before anything
-- can be retried — which is why re-running it by hand took five or six attempts over ten minutes.
-- With a lock_timeout it gives up in seconds with a DIFFERENT error, and the caller retries while
-- the other session's DDL is still running instead of after it. MEASURED the same way (the ALTER
-- below issued inside a transaction that was ROLLED BACK, against the same 25s lock holder):
--     blocked export, no lock_timeout : 120,000 ms then 57014 (statement timeout)
--     blocked export, lock_timeout 5s :   5,333 ms then 55P03 (lock_not_available)
-- 15s is the value chosen: long enough to ride out an ordinary single-statement apply without a
-- retry, short enough that eight attempts fit inside the window one attempt used to burn.
--
-- THIS IS A MECHANISM CHANGE, NOT A STRICT IMPROVEMENT, and it is worth saying plainly. A lock held
-- for, say, 18 seconds used to be waited out silently and the export still succeeded on its FIRST
-- attempt; now that attempt fails at 15s and recovery depends on the caller retrying. The trade is
-- deliberate: a wait that could cost 120 seconds per attempt and then report a red
-- indistinguishable from drift now costs at most 15, and the outcome is labelled for what it is.
-- The caller's budget (scripts/lib/db.mjs: 7 attempts, 2s doubling to a 60s cap, with jitter) is
-- roughly three minutes of patience, which is longer than the wait it replaces.
--
-- WHAT THIS DOES NOT CHANGE. Not one byte of the export. lock_timeout governs how long a lock wait
-- may last, never what is emitted, and the body is untouched — that is why this is an ALTER and not
-- a CREATE OR REPLACE. It follows that:
--   * no revoke is restated. ALTER FUNCTION does not touch the ACL (only CREATE grants EXECUTE to
--     PUBLIC), and the revokes in the canonical file are still in force. Read back below.
--   * `search_path` stays pinned to 'public' exactly as it was; SET clauses are additive.
--   * canonical_routine_manifest compares pg_proc.prosrc, which does not move here, so the canonical
--     file for this routine remains scripts/sql/the_mirror_tables_header_ends_its_line.sql.
--   * supabase/schema/full_schema.sql DOES move by one line: the export prints its own
--     pg_get_functiondef, which now carries the SET clause. Regenerate it after applying, as usual.
--
-- The caller's half of this — a bounded retry, and a 55P03/57014 that reports COULD NOT MEASURE
-- instead of implying drift — is in scripts/checks/export_from_either_source_is_identical.mjs.
-- Seat: it_engineer.

alter function public.fn_schema_export() set lock_timeout to '15s';

-- Read the setting back rather than trusting the ALTER, and confirm the ACL and the pinned
-- search_path both survived it. This file defines DDL, so the probe must NOT raise an exception:
-- that would roll the ALTER back inside its own file (quotesdone-apply-discipline §4). It leaves
-- nothing behind — it writes nothing and reads only catalogs.
--
-- AND THE NOTICE IS NOT A GATE. Measured 18 Sep 2026: the management API does not return NOTICE
-- text, and scripts/apply_sql.mjs has no handling for it, so `PROBE FAILED` would print nowhere.
-- canonical_routine_manifest compares pg_proc.prosrc and never reads proconfig, so nothing in CI
-- asserts this setting either. Verify it by hand after the apply — one statement:
--     select proconfig, has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute
--       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'fn_schema_export';
--   expected: {search_path=public,lock_timeout=15s} and false.
-- MEASURED in a rolled-back transaction before this file was committed: exactly that, with
-- proacl = postgres=X/postgres service_role=X/postgres.
do $probe$
declare
  v_config text[];
  v_acl    text;
begin
  select p.proconfig, coalesce(array_to_string(p.proacl, ' '), '(default: owner only)')
    into v_config, v_acl
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_schema_export';

  if v_config is null or not ('lock_timeout=15s' = any (v_config)) then
    raise notice 'PROBE FAILED: fn_schema_export proconfig is %, expected it to carry lock_timeout=15s', v_config;
  elsif not ('search_path=public' = any (v_config)) then
    raise notice 'PROBE FAILED: fn_schema_export lost its pinned search_path; proconfig is %', v_config;
  else
    raise notice 'fn_schema_export proconfig = %; acl = %', v_config, v_acl;
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'fn_schema_export'
       and has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise notice 'PROBE FAILED: anon can execute fn_schema_export — the revoke did not survive';
  else
    raise notice 'anon cannot execute fn_schema_export (revoke intact)';
  end if;
end
$probe$;
