-- A POLLED CAD JOB IS DISPATCHED AT MOST ONCE A MINUTE.
--
-- Assigned: sales_engineer. 3 Nov 2026. Independent review of #1837.
--
-- MEASURED: #1837 restored customer_api's dispatch of .github/workflows/cad-read-worker.yml and re-dispatched a job
-- while the customer's screen polled it. The rule (cadJobNeedsRedispatch) let a dispatch through on every poll in the
-- first 15 s of each minute of the job's age, with no state and no age cap: a page polling once a second sent ~15
-- dispatches a minute (150 in ten minutes in cad_dispatch.test.ts before this change), for as long as it stayed open.
--
-- WHAT THIS CHANGES: one nullable column, cad_read_jobs.last_dispatch_at. A poll claims the job's slot with ONE
-- update whose WHERE holds the window - set last_dispatch_at = now where id = $1 and (last_dispatch_at is null or
-- last_dispatch_at < now - 1 minute) returning id - and dispatches only when a row comes back
-- (supabase/functions/customer_api/cad_dispatch.ts claimCadDispatch). Two polls at once: the second waits on the row
-- lock, re-reads the WHERE against the first's write, and gets no row. Past one hour the poll stops dispatching and
-- raises the hour's held finding (cadReadHeld).
--
-- WHAT IT DOES NOT CHANGE: the first dispatch at queue time does not read or write this column (a job queued before
-- this file is applied is still dispatched); fn_cad_read_claim, the worker, RLS and grants are untouched.
--
-- COST: ADD COLUMN with no default is a catalogue change, no table rewrite and no scan; lock_timeout bounds the wait
-- for the ACCESS EXCLUSIVE lock so a busy queue makes this file fail rather than queue behind a reader.
-- RUN AS ONE TRANSACTION (apply_sql.mjs does): the probe's temp tables are ON COMMIT DROP, so statement-by-statement
-- autocommit would commit the column and then fail the probe.
-- AFTER THE APPLY: regenerate the schema mirror (export_from_either_source_is_identical.mjs --write), as #1847 did.

set local lock_timeout = '3s';
alter table public.cad_read_jobs add column if not exists last_dispatch_at timestamptz;
comment on column public.cad_read_jobs.last_dispatch_at is
  'When a polled job last claimed a re-dispatch of the CAD worker (customer_api cad_dispatch.ts): at most once a minute.';

-- PROBE (this file has DDL, so it cleans up and returns a verdict row; it never raises). Its own ZZ DEMO row, never
-- committed: inserted, claimed twice inside the window and once outside it, deleted, and asserted gone.
create temp table zz_cad_dispatch_probe (probe_id uuid) on commit drop;
create temp table zz_cad_dispatch_claims (n int, won boolean) on commit drop;
with ins as (
  insert into public.cad_read_jobs (owner_email, source_path, file_name, why)
  values ('zz.probe@example.invalid', 'zz-demo/probe/never-read.dwg', 'ZZ DEMO probe.dwg', 'over_edge_ceiling')
  returning id
) insert into zz_cad_dispatch_probe select id from ins;
with c as (update public.cad_read_jobs set last_dispatch_at = now()
  where id = (select probe_id from zz_cad_dispatch_probe) and (last_dispatch_at is null or last_dispatch_at < now() - interval '1 minute') returning id)
insert into zz_cad_dispatch_claims select 1, exists (select 1 from c);
with c as (update public.cad_read_jobs set last_dispatch_at = now()
  where id = (select probe_id from zz_cad_dispatch_probe) and (last_dispatch_at is null or last_dispatch_at < now() - interval '1 minute') returning id)
insert into zz_cad_dispatch_claims select 2, exists (select 1 from c);
update public.cad_read_jobs set last_dispatch_at = now() - interval '61 seconds' where id = (select probe_id from zz_cad_dispatch_probe);
with c as (update public.cad_read_jobs set last_dispatch_at = now()
  where id = (select probe_id from zz_cad_dispatch_probe) and (last_dispatch_at is null or last_dispatch_at < now() - interval '1 minute') returning id)
insert into zz_cad_dispatch_claims select 3, exists (select 1 from c);

delete from public.cad_read_jobs where id = (select probe_id from zz_cad_dispatch_probe);

select case
  when (select count(*) from zz_cad_dispatch_probe) <> 1 then 'PROBE FAILED: the probe row was not written'
  when exists (select 1 from public.cad_read_jobs where id = (select probe_id from zz_cad_dispatch_probe)) then 'PROBE FAILED: the probe row was left behind'
  when (select array_agg(won order by n) from zz_cad_dispatch_claims) is distinct from array[true, false, true]
    then 'PROBE FAILED: claims inside/outside the minute were ' || (select array_agg(won order by n)::text from zz_cad_dispatch_claims) || ', expected {t,f,t}'
  else 'PROBE OK' end as verdict;
