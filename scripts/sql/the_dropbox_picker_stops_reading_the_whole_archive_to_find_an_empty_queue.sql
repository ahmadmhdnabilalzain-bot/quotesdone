-- THE DROPBOX PICKER STOPS READING THE WHOLE ARCHIVE TO FIND AN EMPTY QUEUE.
--
-- Assigned: it_engineer. 18 Sep 2026.
--
-- WHAT HAPPENED. dropbox_backup failed at 2026-09-17 23:50:57 UTC with
--   {"error":"fn_doc_backups_next: canceling statement due to statement timeout"}
-- (agent_runs 121346/121347, 13.2 s, HTTP 500). The authenticator role carries
-- statement_timeout=8s and lock_timeout=8s, so the rpc had eight seconds. The run that followed at
-- 23:51:10 succeeded in 1.8 s, and watch:run_failure:dropbox_backup opened at 22% of nine attempts
-- against a measured 1.9% baseline over 2,421 runs.
--
-- WHAT THE PICKERS ACTUALLY COST, measured on production, 18 Sep, EXPLAIN (ANALYZE, BUFFERS) inside
-- a rolled-back block. FOUR statements, not three -- fn_doc_backups_prune_next requeues an expired
-- 'pruning' claim as well as claiming 'prune_pending', and the first draft of this file missed it:
--
--   fn_doc_backups_next, the two maintenance UPDATEs it runs before it picks anything
--     1 requeue a claim older than 10 min    Seq Scan, Rows Removed by Filter: 10570, 628 buffers, 4.72 ms
--     2 promote a parked row whose object    Seq Scan, Rows Removed by Filter: 10570, 628 buffers, 2.47 ms
--         has arrived in storage
--   fn_doc_backups_prune_next
--     3 requeue an expired 'pruning' claim   Seq Scan, Rows Removed by Filter: 10570, 628 buffers, 6.47 ms
--     4 claim 'prune_pending'                Seq Scan, Rows Removed by Filter: 10570, 628 buffers, 3.29 ms
--                                            ------------------------------------------------------
--                                            2,512 buffers, 16.95 ms to find nothing
--
--   The CLAIM of fn_doc_backups_next is already indexed: ix_doc_backups_status covers
--   status in ('pending','error'). Nothing covers the other four statuses, so each of the four
--   statements above reads all 10,570 rows -- the 9,846 'done' rows most of all, and that number
--   only ever grows -- to discover there is nothing to do.
--
-- MEASURED AFTER, same block, with the index below created inside the transaction:
--     1 requeue      Index Scan using ix_doc_backups_live_status, 2 buffers, 0.125 ms
--     2 promote      Index Scan using ix_doc_backups_live_status, 2 buffers, 0.043 ms
--     3 requeue      Index Scan using ix_doc_backups_live_status, 2 buffers, 0.047 ms
--     4 prune claim  Index Scan using ix_doc_backups_live_status, 2 buffers, 0.081 ms
--                    -----------------------------------------------------------------
--                    8 buffers, 0.296 ms -- 314x fewer buffers, 57x faster, and flat as the archive
--                    grows. The claim still uses ix_doc_backups_status, unchanged.
--   Index size: 8 kB while the predicate matches nothing (the metapage alone) and 16 kB with one
--   live row (metapage plus root). The "2 buffers" above are metapage plus root at the moment of
--   the scan, not the empty form.
--
-- HONESTLY: 16.95 ms is not eight seconds, AND THE MEASUREMENT WAS TAKEN IN A STATE THE INCIDENT
-- WAS NOT IN -- an empty queue on 18 Sep, where the incident was a queue the backfill was filling on
-- 17 Sep. This index is not offered as the cause of the cancellation. What it is: the only part of
-- the picker's cost that scales with the archive, and 100% waste on an empty queue. What the
-- evidence says about the cancellation, ranked, and what would settle it:
--   1 INSTANCE SATURATION. In the same request, immediately before the picker, dropbox_backup calls
--     fn_enqueue_doc_backups and fn_enqueue_doc_backups_backfill. From pg_stat_statements on 18 Sep
--     the two PostgREST entries for fn_enqueue_doc_backups are 5,664 calls at a mean of 104.6 ms
--     (max 7,878.6 ms) and 623 calls at a mean of 1,389.5 ms (max 4,135.1 ms) -- together 1,458
--     seconds of execution and 143.9 million shared buffer hits, about 23,000 buffers a call. The
--     two fn_doc_backups_next entries are 966 calls at a mean of 8.1 ms (max 1,534.2 ms) and 156
--     calls at a mean of 53.1 ms (max 7,489.4 ms). A subject whose plan costs 17 ms reaching 7.5 s
--     is what an 8 s budget spent on a saturated instance looks like. SETTLED BY: the instance CPU
--     and IO metrics for 23:50:45-23:51:00, or pg_stat_activity sampling wait_event_type.
--   2 LOCK WAITS on the two unbounded maintenance UPDATEs. Real exposure -- the edge function
--     updates 'processing' rows one by one and the prune tick bulk-updates to 'prune_pending' --
--     but ARGUED AGAINST by the evidence: the role carries lock_timeout=8s, which does cover row
--     waits, and the message was statement timeout, not lock timeout. SETTLED BY: log_lock_waits.
--   3 The 'waiting_source' promote probing storage.objects once per parked row. MEASURED AND
--     LARGELY RULED OUT: storage.objects holds 10,906 rows and one probe is an Index Scan on
--     name_prefix_search costing 2 buffers and 0.019 ms, so even a thousand parked rows is about
--     2,000 buffers and 20 ms. A LIMIT on that UPDATE was considered and NOT taken: it would cap a
--     cost that measurement says is not there, and `order by id limit n` would hand the same oldest
--     rows to every call, so a parked row whose object never arrives would starve every row behind
--     it. Bounding it is the right change only once a number says it needs bounding.
--   4 BUFFER EVICTION. Not supported: every figure above is shared_blks_hit.
--   5 AUTOVACUUM on doc_backups. Effectively ruled out: 5 MB, and it blocks neither readers nor
--     writers.
-- The enqueue pass that dominates candidate 1 is the sales_engineer's routine and a separate
-- subject; it is named here with its measurement rather than changed in passing. The reading that
-- would have answered this outright is pg_stat_statements.track = 'all', which would attribute the
-- statements INSIDE these security definer bodies instead of only the PostgREST wrapper.
--
-- WHY A PARTIAL INDEX AND NOT A PLAIN ONE ON status. The four statuses named below are the LIVE
-- ones. 'done' (9,846) and 'abandoned' (724) are terminal and no picker ever asks for them, so
-- indexing them would pay btree maintenance on every upload to store rows nothing reads. The
-- dominant insert path, fn_enqueue_doc_backups, inserts status 'pending' -- outside this predicate,
-- so it writes no index tuple at all. And status is ALREADY a key column of ix_doc_backups_status,
-- so no status transition loses a HOT update that it had before. The predicate is written as an IN
-- list so the planner can match it against each picker's own status = '...' qual; (status, id)
-- rather than (status) so fn_doc_backups_prune_next's `order by d.id` is served by the same index
-- with no Sort. A row of that set is read by a caller and rewritten within minutes -- EXCEPT
-- 'waiting_source', which has no expiry: trg_doc_backups_admit parks a row whose storage object has
-- not arrived and nothing ever times it out, so a file that never arrives is parked for ever. Giving
-- that status an expiry belongs to the sales_engineer, who owns the queue; it is not done here.
--
-- ALSO LOOKED AT, AND DELIBERATELY LEFT ALONE. fn_enqueue_doc_backups dedupes with
-- `on conflict do nothing`, and doc_backups additionally carries UNIQUE (bucket, path)
-- (doc_backups_bucket_path_key). Between them, a storage path that already has a row is never
-- queued again WHATEVER that row's status -- so a path whose row was abandoned could not be
-- re-queued if the path were re-used. MEASURED 18 Sep: rows with status 'abandoned' and source
-- 'storage' whose object still exists in storage.objects = 0. The hole is latent, not live, and it
-- is NOT closed here, for two reasons. It is a UNIQUE CONSTRAINT rather than a forgotten predicate,
-- so relaxing it means allowing two rows for one path and giving the uploader two identities for
-- one file. And the 724 abandoned rows carry reasons somebody chose ('abandoned: ZZ DEMO fixture of
-- a rehearsal, torn down', retired quote comparisons, seed files never in storage); reviving them
-- automatically would re-queue exactly what was deliberately stopped. When a path is genuinely
-- re-used the correct act is to put that row back to 'pending', and whose act that is belongs to
-- the sales_engineer. Recorded here so it has a home rather than being rediscovered.
--
--   node scripts/apply_sql.mjs scripts/sql/the_dropbox_picker_stops_reading_the_whole_archive_to_find_an_empty_queue.sql --apply --ddl

-- -- 1. THE INDEX ------------------------------------------------------------------------------------
-- Not CONCURRENTLY: apply_sql.mjs runs a file as one transaction, and CREATE INDEX CONCURRENTLY
-- cannot run inside one. The build itself is milliseconds on 10,570 rows of which 0 match the
-- predicate. Said precisely, because the point of not using CONCURRENTLY rests on it: CREATE INDEX
-- takes SHARE, which lets reads through and blocks WRITES, and it holds that lock until the
-- transaction COMMITS -- so writes to doc_backups wait for the whole apply, not for the build. The
-- apply is one file of DDL plus the probe below.
create index if not exists ix_doc_backups_live_status
  on public.doc_backups (status, id)
  where status in ('processing', 'waiting_source', 'prune_pending', 'pruning');

comment on index public.ix_doc_backups_live_status is
  'The four LIVE statuses of the Dropbox queue. fn_doc_backups_next requeues an expired claim (processing) and promotes a parked row whose object arrived (waiting_source); fn_doc_backups_prune_next requeues an expired pruning claim and claims prune_pending. Without it each of those four read all 10,570 rows -- 2,512 buffers and 17 ms to find an empty queue, growing with the archive. ix_doc_backups_status covers the other half (pending, error) and is unchanged. The indexed set turns over completely, so if this index is ever megabytes rather than tens of kilobytes that is an autovacuum signal, not an index problem.';

-- -- 2. PROBE ----------------------------------------------------------------------------------------
-- This file carries DDL, so the probe CLEANS UP AFTER ITSELF (quotesdone-apply-discipline section 4).
-- Its SUCCESS path ends in a notice. Its failure paths raise deliberately, which takes the index with
-- them: an index the planner cannot reach is worse than no index, because it looks like a fix.
--
-- The row it inserts is a ZZ DEMO row in the convention this table already uses: entity 'zz_demo',
-- which fn_doc_backups_next excludes from every real claim (it claims zz_demo rows only when p_demo
-- is true, and the edge function never passes it), pointing at a bucket and path no storage object
-- holds. It is deleted before the block ends.
--
-- It does NOT assert a before/after count(*) of doc_backups. doc_backups takes thousands of enqueue
-- writes a day, so a concurrent commit between two counts would abort an apply that was correct.
-- What it asserts instead is keyed on the probe's own dedupe_key, which no concurrent writer can
-- touch, and is therefore exact rather than merely lucky.
do $probe$
declare v_id bigint; v_status text; v_plan text; v_seq boolean := false; v_used boolean := false;
begin
  insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key, status)
  values ('zz_demo', 'zz-demo-probe', 'ZZ DEMO probe', 'supplier-docs',
          'zz-demo/the-picker-index-probe-2026-09-18.pdf', 'ZZ DEMO probe.pdf',
          '/QuotesDone Backup/ZZ DEMO/the-picker-index-probe-2026-09-18.pdf',
          'storage', 'ZZDEMO:picker-index-probe:2026-09-18', 'pending')
  returning id into v_id;
  -- trg_doc_backups_admit parks it as 'waiting_source' (storage holds no such object), which is one
  -- of the statuses this index exists for. Say so rather than assume it.
  if not exists (select 1 from public.doc_backups d where d.id = v_id and d.status = 'waiting_source') then
    delete from public.doc_backups where id = v_id;
    raise exception 'PROBE FAILED: the probe row was not parked as waiting_source, so the index was never posed the question.';
  end if;

  -- the planner must reach that row through the index, not by reading the archive, for EVERY status
  -- in the predicate: the implication only holds for the literals in the IN list, so all four are
  -- asserted rather than one being taken as evidence for the rest.
  foreach v_status in array array['processing', 'waiting_source', 'prune_pending', 'pruning'] loop
    v_seq := false; v_used := false;
    for v_plan in execute
      'explain (buffers, format text) select d.id from public.doc_backups d where d.status = ' || quote_literal(v_status)
    loop
      if v_plan like '%ix_doc_backups_live_status%' then v_used := true; end if;
      if v_plan like '%Seq Scan%' then v_seq := true; end if;
    end loop;
    if v_seq or not v_used then
      delete from public.doc_backups where id = v_id;
      raise exception 'PROBE FAILED: a lookup on status % did not use ix_doc_backups_live_status (seq_scan=%, used_index=%). The index is present but not reachable for that status, which buys nothing.', v_status, v_seq, v_used;
    end if;
  end loop;

  delete from public.doc_backups where id = v_id;
  if exists (select 1 from public.doc_backups where dedupe_key = 'ZZDEMO:picker-index-probe:2026-09-18') then
    raise exception 'PROBE FAILED: the ZZ DEMO probe row is still in the queue.';
  end if;

  raise notice 'PROBE OK: a lookup on each of the four live statuses is served by ix_doc_backups_live_status with no sequential scan, and no ZZ DEMO row is left in the queue.';
end $probe$;
