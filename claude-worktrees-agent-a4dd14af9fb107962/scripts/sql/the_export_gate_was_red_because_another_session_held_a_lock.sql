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

-- THE PROBE. Read the setting back rather than trusting the ALTER, and confirm the ACL and the
-- pinned search_path both survived it. This file carries DDL, so the probe must NOT raise an
-- exception — the raise would roll the ALTER back inside its own file
-- (quotesdone-apply-discipline §4). It writes nothing, reads only catalogs, can touch no real
-- person's data, and leaves nothing behind.
--
-- IT IS A SELECT AND NOT A `raise notice`, because a notice prints NOWHERE. MEASURED 18 Sep 2026
-- against this project, asking the management API directly and reading the raw body:
--     do $$ begin raise notice 'a verdict'; end $$;                  -> []
--     do $$ begin raise notice 'a verdict'; end $$; select 1 as a;   -> [{"a":1}]
--     raise warning instead of notice                                -> [{"a":1}]
--     set client_min_messages to notice; … same DO block …           -> [{"a":1}]
-- NOTICE and WARNING are both discarded, log_min_messages is 'warning' so a notice is not even in
-- the Postgres log, psql is not installed and there is no direct connection string. The applier has
-- two channels: a RESULT SET and an ERROR. §4 forbids the error. So the verdict is a result set.
--
-- The contract, read by scripts/apply_sql.mjs and enforced by
-- scripts/checks/a_probe_that_cannot_report_is_not_a_probe.test.mjs: the LAST statement of the file
-- is a SELECT of one row whose value begins `PROBE OK` or `PROBE FAILED`. A FAILED verdict makes
-- the apply exit non-zero while leaving the applied DDL alone, which is the honest outcome — the
-- change is live and its verification did not pass.
--
-- MEASURED in a rolled-back transaction before this file was committed: proconfig
-- {search_path=public,lock_timeout=15s}, anon_can_execute false, and
-- proacl = postgres=X/postgres service_role=X/postgres.
--
-- TWO NULL-SHAPED WAYS TO ACCIDENTALLY PASS, both closed here, because the one outcome a probe may
-- never produce is a false OK.
--
-- 1. `coalesce(proconfig, '{}')` is not decoration. `= any (null)` is NULL, `not NULL` is NULL, and
--    a CASE arm evaluating to NULL is NOT TAKEN — so a routine that had lost every SET clause would
--    fall straight through to the OK arm. Verified by forcing it: `alter function … reset all` in a
--    rolled-back transaction gives `PROBE FAILED: … proconfig is (null)`.
-- 2. ZERO ROWS. This file is an ALTER, so it defines no routine, so apply_sql.mjs's read-back has
--    nothing to read back — this probe is the file's ONLY verification. A plain
--    `select … from pg_proc where proname = 'fn_schema_export'` returns no row at all if the
--    routine is absent or renamed, no row means no verdict, and no verdict used to read as success.
--    The scalar subquery with a coalesce makes one row unconditional: absent is a FAILURE, stated.
--    (apply_sql.mjs now also refuses an apply whose file carries a verdict marker and gets none
--    back, so a probe that goes missing is caught for every file, not just this one.)
select coalesce((
  select case
    when not ('lock_timeout=15s' = any (coalesce(p.proconfig, '{}'::text[])))
      then 'PROBE FAILED: fn_schema_export proconfig is '
           || coalesce(array_to_string(p.proconfig, ','), '(null)')
           || ' — expected it to carry lock_timeout=15s'
    when not ('search_path=public' = any (coalesce(p.proconfig, '{}'::text[])))
      then 'PROBE FAILED: fn_schema_export lost its pinned search_path; proconfig is '
           || coalesce(array_to_string(p.proconfig, ','), '(null)')
    when has_function_privilege('anon', p.oid, 'EXECUTE')
      then 'PROBE FAILED: anon can execute fn_schema_export — the revoke did not survive the ALTER'
    when has_function_privilege('authenticated', p.oid, 'EXECUTE')
      then 'PROBE FAILED: authenticated can execute fn_schema_export — the revoke did not survive'
    else 'PROBE OK: fn_schema_export proconfig = {' || array_to_string(p.proconfig, ',')
         || '}, acl = ' || coalesce(array_to_string(p.proacl, ' '), '(owner only)')
         || ', neither anon nor authenticated can execute it'
  end
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'fn_schema_export'
), 'PROBE FAILED: public.fn_schema_export is not in pg_proc at all — the ALTER above named an object '
   || 'that does not exist, so nothing was verified') as probe;
