# Runbook: rewrite `public.kb_chunks` to give its dead space back to the disk

Seat: it_engineer. Written 5 Oct 2026 (ledger 1085, stage 4). **This runbook needs the founder's go, given to the
operator directly, before step 3.** A table rewrite locks a live table; it is the one step of the trim that is not
paged.

## Why

Measured on production, 5 Oct 2026 (read-only):

| | |
|---|---|
| `pg_total_relation_size('kb_chunks')` | 8,089 MB |
| heap / TOAST / indexes | 4,124 MB / 3,124 MB / 783 MB |
| live rows / sum of `pg_column_size` of live rows | 148,326 / 468 MB |
| database size | 11 GB |

The ~7.3 GB gap is the 21 Sep purge's deletes (2.6 M rows to 150 k). A plain `VACUUM` marks that space reusable
inside the table but never returns it to the disk; only a rewrite does. After the trim
(`scripts/kb/trim_kb_chunks.mjs --run`: 90,488 qd_kb_pack + 8,465 duplicate rows planned) about 49,400 rows stay.

## Preconditions (all must hold; stop if any does not)

1. The trim PR is merged and applied, and `node scripts/kb/trim_kb_chunks.mjs --run` finished with
   "every duplicate text keeps its surviving copy" and 0 planned rows left.
2. A restorable copy exists: `table_export_run` for `2026-09-18` is `full`/`done` and every `kb_chunks` row is older
   than it (the trim driver's preflight checks both). If a newer full export has finished, prefer it.
3. Window: **02:00-05:00 Asia/Dubai** (22:00-01:00 UTC), but not 02:50-03:10 Dubai, when the daily export opens.
4. Nothing else running. In one read, all must be zero / false:
   ```sql
   select public.fn_kb_purge_load();                       -- purge_running 0, export_running false, active_others small
   select count(*) from pg_stat_activity
    where state <> 'idle' and pid <> pg_backend_pid()
      and (query ilike '%kb_chunks%' or query ilike '%vacuum%' or query ilike '%reindex%');
   ```
   and on GitHub: no `post-deploy smoke` / E2E run in progress, no release-train apply in progress, no campaign hour
   (memory: an apply can lock sign-in; post-deploy smokes overlap manual runs).
5. Disk: a rewrite writes a full new copy before dropping the old: free disk must exceed **2x the live size plus the
   indexes** - after the trim about 1 GB; check `/v1/projects/htdblwldjkcgjvmqkbeh/config/disk/util` fs_avail_bytes.

## Lock estimate

`VACUUM FULL` holds ACCESS EXCLUSIVE on `kb_chunks` for the whole rewrite: every read of the table waits, which
means `fn_reason_retrieve` / `fn_reason_retrieve_ml` (think()) and the export wait too.

- Heap + TOAST copy of the live rows: ~160 MB after the trim (468 MB x 49.4k / 148.3k). At the ~12,500 rows/s the
  purge census measured for a full read, ~4 s; with TOAST writes allow 30 s.
- Index rebuilds inside the rewrite: btree indexes (seconds); `kb_chunks_fts` GIN; `kb_chunks_emb_hnsw` over ~49 k
  vectors. On 21 Sep, HNSW over 150 k rows did not finish in 85 s, so over 49 k allow ~60-90 s.
- **Estimate: 1-3 minutes of exclusive lock. Budget 5.** Anything longer is a stop.

`pg_repack` (extension available on the project, `pg_available_extensions` = 1) holds the exclusive lock only for
the final swap (seconds), but needs the `pg_repack` client on a host with a **direct** database connection and the
database password, which this estate's tooling (management API only) does not have. Use it if that operator has
both; otherwise `VACUUM FULL` as below.

## Steps

1. Read and record the before state (paste into the PR / ledger):
   ```sql
   select count(*) live, pg_total_relation_size('public.kb_chunks') total_b,
          pg_relation_size('public.kb_chunks') heap_b, pg_indexes_size('public.kb_chunks') idx_b,
          pg_database_size(current_database()) db_b, now() at time zone 'Asia/Dubai' dubai
     from public.kb_chunks;
   ```
2. Record the retrieval baseline: one `fn_reason_retrieve_ml` call per seat (any exam question's vectors), count of
   rows returned, and the latest `seat_knowledge_recall` row per seat.
3. Rewrite. From a **direct** session (psql on the pooler's session port or the db host; the management API's
   2-minute cap would cancel it part-way and roll back):
   ```sql
   set lock_timeout = '5s';            -- if a reader holds the table, give up instead of queueing everyone behind us
   set statement_timeout = '10min';    -- a hard stop well past the 1-3 min estimate
   \timing on
   vacuum (full, analyze, verbose) public.kb_chunks;
   ```
   or, with pg_repack: `pg_repack --no-order --table=public.kb_chunks --wait-timeout=5 "<direct connection uri>"`.
   Record the wall time printed by `\timing`: that is the measured lock duration.
4. Read back (all must hold):
   - `count(*)` equals step 1's `live`;
   - `pg_total_relation_size` far below step 1 (expected under 0.5 GB) and `pg_database_size` down by the difference;
   - every index valid: `select indexrelid::regclass from pg_index where indrelid = 'public.kb_chunks'::regclass and not indisvalid` returns nothing;
   - each seat's `fn_reason_retrieve_ml` call from step 2 returns the same number of rows;
   - `insert into public.kb_purge_ledger (verdict, clause, source_kind, category, bytes, note) values ('SIZE', 0, 'kb_chunks', 'pg_total_relation_size', <after>, 'after the rewrite, lock <measured> s');`

## Rollback

- **Before it finishes** (lock_timeout, statement_timeout, cancel, connection loss): `VACUUM FULL` is transactional;
  the old files stay and nothing changed. Check `pg_stat_activity` that no rewrite backend is still running before a
  second try, and do not retry in the same window.
- **After it finishes**: no rows changed, so there is nothing to undo. If an index came back invalid,
  `drop index concurrently <name>` and recreate it concurrently (statements in `scripts/kb/purge_kb_bulk.mjs` step 4).
- **If rows are missing** (count differs - not expected; a rewrite copies every live row): restore those ids from the
  full export named in precondition 2 through the export's restore path, then stop and report.

## Stop conditions

Stop and report rather than force: any precondition false; the lock wait times out twice; the rewrite exceeds 5
minutes; disk free under 2x the live size; any read-back failing.
