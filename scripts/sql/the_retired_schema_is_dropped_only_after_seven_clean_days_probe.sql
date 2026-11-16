-- THE RETIRED SCHEMA IS DROPPED ONLY AFTER SEVEN CLEAN DAYS (the measurement phase 2 waits on; a pure read, no DDL).
--
-- Seat: it_engineer, 16 Nov 2026 (founder ledgers 1714 and 1715). Phase 1 moved routines and tables nobody calls into schema
-- `retired` instead of dropping them (the five files whose names end in "are_retired", "stop_firing_every_five_minutes" and
-- "move_to_the_retired_schema"), so a caller nobody found fails loudly with "does not exist" and one line brings the object
-- back. Phase 2 is the DROP. It is owed when this probe has read CLEAN on a day at least 7 days after the last phase-1 apply.
--
-- CLEAN means all three are zero over the 7 days before the run:
--   1. agent_runs: a run whose status is not ok and whose note or counts names a retired object (read below);
--   2. cron.job_run_details: a failed run whose return_message names a retired object (read below);
--   3. the platform logs, which SQL cannot read, read by the session through the Supabase logs (postgres logs and edge
--      function logs) for the same 7 days: an error naming schema retired or a retired object, or a "function public.<name>
--      does not exist" / "relation public.<name> does not exist" for one of them. The count goes in the PR that drops.
-- Then phase 2, in one new file: copy every retired table to the private `evidence` bucket (JSON, one object per table, with
-- its count(*) and the md5 of its ordered rows recorded beside it, ledger 1278), drop the retired routines and tables, record
-- each name in scripts/sql/DROPPED.txt, and `drop schema retired` once it is empty.
--
-- A non-clean result is not a failure of this probe: it names the object and where it was called, so that object goes back
-- to public with its reversal line (in its phase-1 file) instead of being dropped.
with obj as (
  select p.proname nm from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'retired'
  union select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'retired' and c.relkind in ('r', 'p', 'v', 'm')),
re as (select '\m(' || string_agg(nm, '|') || ')\M' rx, count(*) n from obj),
v as (select
  (select n from re) retired_objects,
  (select count(*) from public.agent_runs a, re
    where re.n > 0 and a.started_at > now() - interval '7 days'
      and coalesce(a.status, '') not in ('ok', 'success', 'completed', 'skipped', 'warn', 'held', 'noop')
      and (coalesce(a.note, '') || ' ' || coalesce(a.counts::text, '')) ~ re.rx) runs_naming_one,
  (select count(*) from cron.job_run_details d, re
    where re.n > 0 and d.start_time > now() - interval '7 days' and d.status = 'failed' and coalesce(d.return_message, '') ~ re.rx) cron_failures_naming_one)
select case when retired_objects = 0 then 'PROBE OK: schema retired holds nothing; phase 2 is done or was never needed'
            when runs_naming_one = 0 and cron_failures_naming_one = 0
            then 'PROBE OK: CLEAN in SQL over 7 days for ' || retired_objects || ' retired objects (0 agent_runs failures, 0 cron failures name one); read the postgres and edge logs for the same 7 days before phase 2'
            else 'PROBE FAILED: NOT CLEAN: ' || runs_naming_one || ' agent_runs failures and ' || cron_failures_naming_one || ' cron failures name a retired object in 7 days' end as verdict
  from v;
