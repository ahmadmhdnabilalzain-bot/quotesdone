# Runbook: rewrite `public.kb_chunks` to give its dead space back to the disk

Seat: it_engineer. Written 5 Oct 2026 (ledger 1085, stage 4). **This runbook needs the founder's go, given to the
operator directly, before step 3.** A table rewrite locks a live table; it is the one step of the trim that is not
paged.

## Why

Measured on production, 5 Oct 2026 (read-only):

| | |
|---|---|
| `pg_total_relation_size('kb_chunks')` | 8,482 MB (8,482,365,440 B) |
| heap (`pg_relation_size`) / TOAST / indexes (`pg_indexes_size`) | 4,324 MB / ~3,337 MB / 821 MB |
| live rows | 148,326 |
| full read of every row's content (`md5(content)` over the table, one pass) | 29 s |

The ~7 GB of dead space is the 21 Sep purge's deletes (2.6 M rows to 150 k). A plain `VACUUM` marks it reusable inside
the table but never returns it to the disk; only a rewrite does. After the trim
(`scripts/kb/trim_kb_chunks.mjs --run`: 90,488 qd_kb_pack + 3,478 exact-duplicate rows, measured 5 Oct) about
54,360 rows stay.

## Preconditions (all must hold; stop if any does not)

1. The trim PR is merged and applied, and `node scripts/kb/trim_kb_chunks.mjs --run` finished with
   "every duplicate text keeps its surviving copy" and 0 planned rows left.
2. A restorable copy exists: the newest `table_export_run` with `kind = 'full'` and `status = 'done'` (2026-10-02 on
   5 Oct, finished 2026-10-01 23:53 UTC, 159 kb_chunks pages all done + verified), finished after the newest
   `kb_chunks.created_at` (31 Aug). The trim driver resolves and checks this itself; re-run its plan-only mode
   (`node scripts/kb/trim_kb_chunks.mjs`) and read the "restorable copy" line.
3. Window: **02:00-05:00 Asia/Dubai** (22:00-01:00 UTC), but not 02:50-03:10 Dubai, when the daily export opens.
4. Nothing else running. In one read, all must be zero / false:
   ```sql
   select public.fn_kb_purge_load();                       -- purge_running 0, export_running false, active_others small
   select count(*) from pg_stat_activity
    where state <> 'idle' and pid <> pg_backend_pid()
      and (query ilike '%kb_chunks%' or query ilike '%vacuum%' or query ilike '%reindex%');
   ```
   and on GitHub: no `post-deploy smoke` / E2E run in progress, no release-train apply in progress, no campaign hour
   (an apply can lock sign-in; post-deploy smokes overlap manual runs).
5. Disk: a rewrite writes a full new copy before dropping the old: free disk must exceed **2x the live size plus the
   indexes** (after the trim about 1.5 GB); check `/v1/projects/htdblwldjkcgjvmqkbeh/config/disk/util` fs_avail_bytes.

## Lock estimate

`VACUUM FULL` holds ACCESS EXCLUSIVE on `kb_chunks` for the whole rewrite: every read of the table waits, which means
`fn_reason_retrieve` / `fn_reason_retrieve_ml` (think()) and the export wait too.

The rewrite reads the **whole** relation, dead tuples included, not just the live rows: 4,324 MB of heap plus
~3,337 MB of TOAST, about **7.7 GB**, and the trim does not shrink that (a delete leaves the pages in place).

- Read: the one measured full pass over heap + content TOAST took 29 s (~260 MB/s, partly cached). Cold, allow 3x:
  **~90 s**.
- Write: the surviving ~54 k rows, about 0.2 GB of heap + TOAST plus WAL: **~10-20 s**.
- Index rebuilds inside the rewrite: btree indexes (seconds), `kb_chunks_fts` GIN, `kb_chunks_emb_hnsw` over ~54 k
  vectors. On 21 Sep, HNSW over 150 k rows did not finish in 85 s, so over 54 k allow **~60-90 s**.
- **Estimate: 2.5-3.5 minutes of exclusive lock. Budget 5 (statement_timeout 5 min).** If it is cancelled at the
  budget, nothing changed (see Rollback) and the next attempt uses pg_repack.

`pg_repack` is available on the project (`pg_available_extensions`: `pg_repack`, not installed). It holds the
exclusive lock only for the final swap (seconds) and is the better tool for a 7.7 GB relation, but it needs
`create extension pg_repack` (a change: the founder's go covers it only if he says so) and the `pg_repack` client on a
host with a **direct** database connection and the database password, which this estate's tooling (management API
only) does not have. Use it when that operator has both; otherwise `VACUUM FULL` as below.

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
   set statement_timeout = '5min';     -- the budget: past it, the rewrite is cancelled and nothing has changed
   \timing on
   vacuum (full, analyze, verbose) public.kb_chunks;
   ```
   or, with pg_repack: `pg_repack --no-order --table=public.kb_chunks --wait-timeout=5 "<direct connection uri>"`.
   Record the wall time printed by `\timing`: that is the measured lock duration.
4. Read back (all must hold):
   - `count(*)` equals step 1's `live`;
   - `pg_total_relation_size` far below step 1 (expected under 1 GB) and `pg_database_size` down by the difference;
   - every index valid: `select indexrelid::regclass from pg_index where indrelid = 'public.kb_chunks'::regclass and not indisvalid` returns nothing;
   - each seat's `fn_reason_retrieve_ml` call from step 2 returns the same number of rows;
   - `insert into public.kb_purge_ledger (verdict, clause, source_kind, category, bytes, note) values ('SIZE', 0, 'kb_chunks', 'pg_total_relation_size', <after>, 'after the rewrite, lock <measured> s');`

## Restore path (a trimmed row has to come back)

The trimmed ids are recorded twice: `kb_trim_hash` (`clause is not null`; clause 7 rows also name their `keeper_id`)
and the `kb_purge_ledger` batch rows (`verdict = 'TRIM'`, `id_from..id_to` per batch). The rows themselves are in the
full export the driver named in its preflight line (2026-10-02 on 5 Oct):

1. Find the pages: `select path, dropbox_path from public.doc_backups where dropbox_path like '%/<stamp>/kb_chunks/%'
   and status = 'done' order by dropbox_path;` — Supabase storage bucket `backups` at `path`, mirrored to Dropbox at
   `/QuotesDone Backup/Company/Database Exports/<YYYY-MM>/<stamp>/kb_chunks/page_NNNN.json`.
2. Each page is a JSON list of rows (or `{rows|data|records: [...]}`; `rowsOf` in
   `supabase/functions/_shared/it_restore_drill.ts`, the monthly restore drill's reader, which proves the pages open).
3. Re-insert only the ids being restored, never overwriting a live row:
   ```sql
   insert into public.kb_chunks
   select * from jsonb_populate_recordset(null::public.kb_chunks, '<page json list>'::jsonb) r
    where r.id in (<ids>)
   on conflict (id) do nothing;
   ```
   then confirm the count and that `embedding_gte` is present (a restored row with a null vector is re-embedded by the
   normal embed claim).

## Rollback of the rewrite

- **Before it finishes** (lock_timeout, statement_timeout, cancel, connection loss): `VACUUM FULL` is transactional;
  the old files stay and nothing changed. Check `pg_stat_activity` that no rewrite backend is still running before a
  second try, and do not retry in the same window.
- **After it finishes**: no rows changed, so there is nothing to undo. If an index came back invalid,
  `drop index concurrently <name>` and recreate it concurrently (statements in `scripts/kb/purge_kb_bulk.mjs` step 4).
- **If rows are missing** (count differs - not expected; a rewrite copies every live row): restore those ids by the
  restore path above, then stop and report.

## Stop conditions

Stop and report rather than force: any precondition false; the lock wait times out twice; the rewrite reaches the
5-minute statement_timeout; disk free under 2x the live size; any read-back failing.
