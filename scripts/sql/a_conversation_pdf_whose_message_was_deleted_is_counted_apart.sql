-- A CONVERSATION PDF WHOSE MESSAGE WAS DELETED IS COUNTED APART FROM ONE THE BACKUP FORGOT (10 Nov 2026).
-- Seat: it_engineer (the backup). The routine's owner: every_conversation_is_kept_backed_up_twice_and_readable_by_the_sales_
-- engineer.sql (MANIFEST 1373).
--
-- MEASURED 10 Nov 2026 on production (read-only; aborted DO for the view, which the read-only role cannot execute):
-- fn_conversation_retention_breaches('2 hours') reported total 191, all pdfs_without_dropbox_row: 186 wa_messages archived
-- 2, 3 and 10 Nov and 5 assistant_logs archived 10 Nov 01:01Z. Not one of the 191 source rows exists any more (0 of 186
-- wa_messages, 0 of 5 assistant_logs), so none is in v_conversation_message, and fn_enqueue_doc_backups -- which reads the
-- message through that view to file it on the entity tree and to drop demo rows -- can never queue them. Every archive row
-- whose message still exists IS queued (2,455 CONV rows, all done; notifications, inbound_messages, assistant_logs,
-- wa_messages and social_message). One deleter is known: scripts/e2e/wa_exchange_real.mjs tears down its ZZ DEMO WhatsApp
-- rows and left their archive rows behind (fixed in the same commit). The 5 assistant_logs have no deleter found here.
--
-- WHAT THIS CHANGES: pdfs_without_dropbox_row (and so total) counts only an archive row whose message still exists and is
-- not demo, i.e. exactly what the backup can and must queue. An archive row whose message is gone is reported apart, as
-- archived_source_gone with a sample, so it stays visible and is not called a backup failure. Nothing is deleted: whether
-- those 191 PDFs are test traffic to remove is a decision for the IT engineer with the founder, not this file.
-- CREATE OR REPLACE keeps the routine's grants (service role only). Idempotent.
-- Prevented by: every_conversation_is_kept_and_the_sales_engineer_can_read_it.test.mjs (replays this file while pending).
create or replace function public.fn_conversation_retention_breaches(p_grace interval default '02:00:00'::interval)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with unarchived as (
    select v.source_table, v.source_id, v.channel from public.v_conversation_message v
     where not v.is_demo and v.occurred_at < now() - p_grace
       and not exists (select 1 from public.conversation_archive a where a.source_table = v.source_table and a.source_id = v.source_id)),
  waiting as (
    select a.source_table, a.source_id, v.source_id is not null as source_exists, coalesce(v.is_demo, false) as demo
      from public.conversation_archive a
      left join public.v_conversation_message v on v.source_table = a.source_table and v.source_id = a.source_id
     where a.archived_at < now() - p_grace
       and not exists (select 1 from public.doc_backups b where b.dedupe_key = 'CONV:' || a.source_table || ':' || a.source_id)),
  unqueued as (select source_table, source_id from waiting where source_exists and not demo),
  gone as (select source_table, source_id from waiting where not source_exists)
  select jsonb_build_object(
    'grace', p_grace::text,
    'emails_without_pdf', (select count(*) from unarchived where channel = 'email'),
    'conversations_without_pdf', (select count(*) from unarchived),
    'pdfs_without_dropbox_row', (select count(*) from unqueued),
    'total', (select count(*) from unarchived) + (select count(*) from unqueued),
    'sample', (select coalesce(jsonb_agg(u.source_table || ':' || u.source_id), '[]'::jsonb)
                 from (select source_table, source_id from unarchived union all select * from unqueued limit 10) u),
    'archived_source_gone', (select count(*) from gone),
    'archived_source_gone_sample', (select coalesce(jsonb_agg(g.source_table || ':' || g.source_id), '[]'::jsonb)
                                      from (select * from gone limit 10) g));
$fn$;
