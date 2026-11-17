-- THE 13 NOVEMBER EXPORT PAGES THE REFILE PICKED UP CLOSE AS ABANDONED TOO.
--
-- Seat: it_engineer (17 Nov 2026). The follow-up of
-- the_export_pages_never_written_on_12_to_15_november_close_as_abandoned_with_their_reason.sql, which was applied
-- 17 Nov 2026 04:33 UTC and closed every 12, 14 and 15 Nov page (364/364/361) but only 21 of 13 Nov: its probe said
-- "fn_backup_coverage would still count a 12-15 Nov export page as not done". A one-off: rows only, no routine.
-- Measured on production 17 Nov 2026 (SELECT; live bodies read with pg_get_functiondef):
--   * At 04:30:22 UTC, three minutes before that apply, fn_it_backup_recheck found refile handoff 404345 (the
--     13 Nov pages, opened 14 Nov 22:31) 48 hours old and escalated it as support_ceo_report 27361;
--     fn_ceo_backup_escalation_decide read no Dropbox refusal ("cause internal") and at once handed backup.remediate
--     407910 to sales_engineer, whose handler fn_sales_engineer_acts_on_handoff -> fn_sales_engineer_refiles_backup
--     set the 343 still-'waiting_source' 13 Nov rows to 'pending', attempts 0, requeued_at now(), error
--     'refile 1: never_queued (handoff 407910)'. The first file's update reads only 'waiting_source', so it missed them.
--     (12 Nov's report 27338 was read the day before as a Dropbox plan/billing cause, so no remediation requeued 12 Nov.)
--   * By 04:33 the uploader had tried 25 of them: status 'error', attempts 1, 'download Object not found'. The other
--     318 are 'pending'. None has a storage object; 2026-11-13's run is 'running' after 6 attempts; 16 Nov's full
--     export is 'done'.
--   * Left alone they loop for ever: the uploader retries an 'error' row while attempts < 5; at 5, fn_it_backup_check
--     hands it over again as 'upload_failed' under the key 'db:<id>', which the open remediation (keys 'exp:obj:...')
--     does not shadow; the refile requeues it, the recheck refiles a second time and escalates to the CEO again, and
--     remediation 407910 counts as 'refile_not_verified_in_48h' from 19 Nov 04:30 UTC.
--   * It does NOT re-open an abandoned row, so no routine changes here: fn_sales_engineer_refiles_backup updates
--     only "status <> 'abandoned'" (answers 'cannot_refile: row missing or abandoned'); fn_it_backup_check's
--     never-queued finding joins any doc_backups row by bucket and path, abandoned included, and its upload-failed
--     finding reads only 'error' and 'skipped_large'; fn_it_backup_recheck reads an 'abandoned:' row as settled.
--     So once these 343 are closed, handoffs 404345 and 407910 (and 404024, 406598, 407826) close at the next recheck
--     and the sweep completes report 27361.
--   * Not fixed here: the refile still requeues a backups/ export page that storage has never held, which can only
--     fail. That is the refiler's own rule for a source that does not exist, and wants its own file.
-- Only a 12-15 Nov table_export page in 'pending' or 'error' whose error is the refile's note or the uploader's
-- 'download Object not found', that storage does not hold, of a day whose run gave up (not 'done', 6 attempts), and
-- only when a later FULL export finished, is closed, with the first file's reason text. Idempotent.
-- Rollback (back to the state before the refile picked them up):
--   update public.doc_backups set status = 'waiting_source', error = 'waiting: storage holds no object at backups/' || path
--    where entity_id = 'table_export' and status = 'abandoned' and error like 'abandoned: the 2026-11-1_ export stopped at%(17 Nov 2026, it_engineer)';
set local lock_timeout = '3s';

update public.doc_backups d
   set status = 'abandoned',
       error = left('abandoned: the ' || r.stamp || ' export stopped at public.ceo_year_plan_archive (no primary key to page on) after '
                    || r.attempts || ' attempts, before writing this page; a past day cannot be re-exported, and the full export of '
                    || (select min(f.stamp) from public.table_export_run f where f.status = 'done' and f.kind = 'full' and f.stamp > r.stamp)
                    || ' holds every row (17 Nov 2026, it_engineer)', 300)
  from public.table_export_run r
 where d.entity = 'company' and d.entity_id = 'table_export' and d.status in ('pending', 'error') and d.bucket = 'backups'
   and to_char(r.stamp, 'YYYY-MM-DD') = split_part(d.path, '/', 1)
   and r.stamp between date '2026-11-12' and date '2026-11-15'
   and r.status <> 'done' and r.attempts >= 6
   and (coalesce(d.error, '') ~ '^refile [0-9]+: [a-z_]+ \(handoff [0-9]+\)$'
        or coalesce(d.error, '') ~ '^(requeued: )?download Object not found')
   and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = d.path)
   and exists (select 1 from public.table_export_run f where f.status = 'done' and f.kind = 'full' and f.stamp > r.stamp);

select case
  when exists (select 1 from public.doc_backups d where d.entity_id = 'table_export' and d.status in ('waiting_source', 'pending', 'error')
                  and split_part(d.path, '/', 1) between '2026-11-12' and '2026-11-15'
                  and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = d.path))
    then 'PROBE FAILED: a never-written 12-15 Nov export page is still waiting, pending or in error'
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
       || ' never-written 12-15 Nov export pages closed with their reason, '
       || (select count(*) from public.doc_backups d where d.entity_id = 'table_export' and d.status = 'abandoned'
             and d.error like 'abandoned: the 2026-11-1_ export stopped at%(17 Nov 2026, it_engineer)')
       || ' of them by this file' end as verdict;
