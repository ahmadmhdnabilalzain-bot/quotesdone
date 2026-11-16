-- THE EXPORT PAGES NEVER WRITTEN ON 12-15 NOVEMBER CLOSE AS ABANDONED, WITH THEIR REASON.
--
-- Seat: it_engineer (wave 3 OPS builder, 16 Nov 2026). Step 3 of the reviewer's backfill (REVIEW_ops_backup_backfill.sql),
-- written once today's export finished. A one-off: rows only, no routine.
-- Measured on production 16 Nov 2026 ~09:35 UTC (SELECT):
--   * table_export_run: 2026-11-16 'done' (full, 2 attempts). 12, 14, 15 Nov 'failed' and 13 Nov 'running', each after 6
--     attempts, each stopped at public.ceo_year_plan_archive ("has no primary key to page on"). Nothing re-runs a past day:
--     fn_table_export_due claims only today's stamp.
--   * doc_backups: 1,029 rows entity 'company', entity_id 'table_export', status 'waiting_source', error "waiting: storage
--     holds no object at backups/<day>/<table>/page_0000.json": 343 for each of 12, 13 and 14 Nov. They are the backup
--     recheck's refile of the pages fn_it_backup_expected expects for a day with no finished run, one day after the day's
--     grace; the 343 of 15 Nov are refiled at about 22:31 UTC on 16 Nov. These pages never existed: they did not fail to
--     reach Dropbox, and they never can. fn_backup_coverage counts every one as not done after 48 h.
--   * fn_backup_coverage, fn_it_backup_alerts_settle and fn_seat_duty_results_measure all exclude status 'abandoned' with an
--     error starting 'abandoned:' (the form fn_it_backup_recheck already uses), and fn_sales_engineer_refiles_backup never
--     re-queues an abandoned row; the row stays, so the refile does not create it again.
-- APPLY AFTER 16 Nov 2026 22:45 UTC so the 15 Nov rows exist; it is idempotent, and a second apply closes any row that
-- arrived after the first. Only a page of a day whose run gave up (not 'done', 6 attempts) that storage does not hold, and
-- only when a later FULL export finished, is closed.
-- Rollback: update public.doc_backups set status = 'waiting_source', error = 'waiting: storage holds no object at backups/' || path
--   where entity_id = 'table_export' and status = 'abandoned' and error like 'abandoned: the 2026-11-1_ export stopped at%';
set local lock_timeout = '3s';

update public.doc_backups d
   set status = 'abandoned',
       error = left('abandoned: the ' || r.stamp || ' export stopped at public.ceo_year_plan_archive (no primary key to page on) after '
                    || r.attempts || ' attempts, before writing this page; a past day cannot be re-exported, and the full export of '
                    || (select min(f.stamp) from public.table_export_run f where f.status = 'done' and f.kind = 'full' and f.stamp > r.stamp)
                    || ' holds every row (16 Nov 2026, it_engineer)', 300)
  from public.table_export_run r
 where d.entity = 'company' and d.entity_id = 'table_export' and d.status = 'waiting_source' and d.bucket = 'backups'
   and to_char(r.stamp, 'YYYY-MM-DD') = split_part(d.path, '/', 1)
   and r.stamp between date '2026-11-12' and date '2026-11-15'
   and r.status <> 'done' and r.attempts >= 6
   and coalesce(d.error, '') like 'waiting: storage holds no object at backups/' || r.stamp || '/%'
   and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = d.path)
   and exists (select 1 from public.table_export_run f where f.status = 'done' and f.kind = 'full' and f.stamp > r.stamp);

select case
  when exists (select 1 from public.doc_backups d where d.entity_id = 'table_export' and d.status = 'waiting_source'
                  and split_part(d.path, '/', 1) between '2026-11-12' and '2026-11-15'
                  and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = d.path))
    then 'PROBE FAILED: a never-written 12-15 Nov export page is still waiting'
  when exists (select 1 from public.doc_backups d where d.entity_id = 'table_export' and d.status = 'abandoned'
                  and split_part(d.path, '/', 1) between '2026-11-12' and '2026-11-15'
                  and exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = d.path))
    then 'PROBE FAILED: a page that storage holds was closed as abandoned'
  -- the coverage measure (fn_backup_coverage's own predicate) no longer counts them
  when exists (select 1 from public.doc_backups d where d.entity_id = 'table_export' and split_part(d.path, '/', 1) between '2026-11-12' and '2026-11-15'
                  and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = d.path)
                  and d.status <> 'done' and not (d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%'))
    then 'PROBE FAILED: fn_backup_coverage would still count a 12-15 Nov export page as not done'
  else 'PROBE OK: ' || (select count(*) from public.doc_backups d where d.entity_id = 'table_export' and d.status = 'abandoned'
                          and d.error like 'abandoned: the 2026-11-1_ export stopped at%')
       || ' never-written 12-15 Nov export pages closed with their reason' end as verdict;
