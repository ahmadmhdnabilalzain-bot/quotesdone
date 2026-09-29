-- THREE DUPLICATE INDEXES ARE DROPPED (platform audit 30 Sep 2026, finding L1).
--
-- Supabase's performance advisor reported duplicate_index x3. Measured the same day from pg_index
-- and pg_stat_user_indexes; each pair has an identical definition, and neither backs a constraint:
--
--   agent_runs (agent, started_at desc)
--     KEEP agent_runs_agent_started_idx   41,345,140 scans
--     DROP idx_agent_runs_agent_started   0 scans, 24 MB   (a_duration_nobody_compares_to_anything...)
--   kb_chunks (category, created_at) where embedding_gte is null
--     KEEP kb_chunks_unembedded_cat_created_idx    0 scans
--     DROP kb_chunks_unembedded_cat_created_idx2   0 scans, 19 MB  (the_library_starts_embedding...)
--   os_audit_log (at desc)
--     KEEP os_audit_log_at_idx   0 scans
--     DROP idx_os_audit_at       0 scans, 12 MB
--
-- The planner loses nothing: the surviving twin serves every query the dropped one could. Every
-- insert into these three tables stops paying for a second copy.
--
-- DROP INDEX takes an ACCESS EXCLUSIVE lock for a moment. agent_runs is written every few seconds, so
-- the lock is bounded: if it cannot be had in 5 s the apply fails cleanly and is simply retried.
set lock_timeout = '5s';   -- plain SET: it holds whether or not the applier wraps the file in a transaction

drop index if exists public.idx_agent_runs_agent_started;
drop index if exists public.kb_chunks_unembedded_cat_created_idx2;
drop index if exists public.idx_os_audit_at;

-- VERDICT: the three are gone and each surviving twin is still there.
select case
  when to_regclass('public.idx_agent_runs_agent_started') is null
   and to_regclass('public.kb_chunks_unembedded_cat_created_idx2') is null
   and to_regclass('public.idx_os_audit_at') is null
   and to_regclass('public.agent_runs_agent_started_idx') is not null
   and to_regclass('public.kb_chunks_unembedded_cat_created_idx') is not null
   and to_regclass('public.os_audit_log_at_idx') is not null
  then 'PROBE OK'
  else 'PROBE FAILED: a duplicate survived or a kept twin is missing' end as verdict;
