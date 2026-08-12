-- The document controller states what it took on trust — 12 Aug 2026
--
-- Fourth in the s36 sequence. Four rules, four sets of assumptions, each naming how THAT rule is
-- wrong when it is wrong. The retention rule matters most: it is the only one on this board whose
-- recommended action destroys evidence, and its own comment already says the Controller never
-- deletes on its own. Now it says why that restraint exists.
--
-- Health score, snapshot upsert and return shape unchanged.

create or replace function public.fn_document_controller()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare k record; v_health numeric; v_ret numeric; v_backup numeric; n int;
begin
  select * into k from document_kpis;
  v_ret := round(100.0*(k.total_documents - coalesce(k.past_retention,0))/nullif(k.total_documents,0),1);
  v_backup := case when coalesce(k.days_since_backup,999) <= 10 then 100 when coalesce(k.days_since_backup,999) <= 20 then 60 else 20 end;
  v_health := round(coalesce(k.ocr_coverage_pct,100)*0.30 + coalesce(v_ret,100)*0.35 + v_backup*0.20 + greatest(0,100-coalesce(k.oversized,0)*5)*0.15,1);

  insert into document_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('doc_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  -- recommendations (founder-visible; the Controller NEVER deletes a document on its own)
  perform doc_rec('past_retention', coalesce(k.past_retention,0) > 0, 'medium', 'Documents past retention period',
    k.past_retention||' document(s) are older than their retention class. Review for archival or deletion — the Controller flags only and never deletes on its own.',
    jsonb_build_array(
      'The retention class on each document is right. A document filed under the wrong class ages out early and appears here as safe to delete when it is not.',
      'Past retention means MAY be deleted, never MUST. A document under an open dispute, refund claim or regulatory query outlives its class, and this rule cannot see any of those.',
      'Nothing else depends on these files: a quote PDF, a signed T&C or a redacted drawing still referenced by a live RFQ would read identically here.'),
    'Reviewing '||coalesce(k.past_retention,0)||' document(s) keeps the retention promise made to customers in the T&C, which is a commitment and not housekeeping. It also lifts the retention component of doc_health, currently weighted 0.35.',
    'No spend; storage saved is negligible at this size. The real cost is asymmetric and one-way: deleting a document that was still needed cannot be undone, which is why this routine only ever flags.');

  perform doc_rec('ocr_backlog', coalesce(k.ocr_backlog,0) > 0, 'low', 'Documents pending OCR/processing',
    k.ocr_backlog||' registered document(s) are not fully processed/extracted. Re-run the doc processing pipeline.',
    jsonb_build_array(
      'These are processable. A scanned photograph, a CAD original or a password-protected PDF will never extract, and re-running the pipeline on them produces the same backlog tomorrow.',
      'The backlog is pipeline lag, not a pipeline that has stopped — this rule counts unprocessed documents and cannot tell a queue from an outage.'),
    'Extracted text is what makes a document findable and quotable; until then '||coalesce(k.ocr_backlog,0)||' document(s) are stored but effectively invisible to every search and every agent that reads them.',
    'Model spend, small and per document. Re-running on files that can never extract is the wasteful case, which is what the first assumption is there to catch.');

  perform doc_rec('backup_stale', coalesce(k.days_since_backup,999) > 10, 'high', 'Backup may be stale',
    'The last backup to the backups bucket was '||coalesce(k.days_since_backup::text,'never')||' day(s) ago. Confirm the weekly Dropbox backup job is running.',
    jsonb_build_array(
      'An object in the backups bucket means a GOOD backup. This rule reads the newest object''s age and never opens it, so a job writing a truncated or empty archive on schedule looks perfectly healthy.',
      'coalesce(days_since_backup, 999) treats "never backed up" as 999 days rather than as unknown — deliberately, because for a backup the safe reading of no evidence is the alarming one.',
      'The Dropbox side is reachable. A backup written locally but never mirrored still ages this counter correctly and still leaves nothing off-site.'),
    'This is the only rule here that protects against total loss. Everything else on this board is tidiness; a stale backup means a bad day becomes an unrecoverable one.',
    'No spend — the backup job and the Dropbox quota are already paid for. The cost of being wrong is the entire company''s records.');

  perform doc_rec('oversized', coalesce(k.oversized,0) > 0, 'low', 'Oversized files',
    k.oversized||' file(s) exceed 30MB. Consider compressing or archiving to control storage cost.',
    jsonb_build_array(
      'Size is a proxy for waste. A 40MB drawing set is large because it is a drawing set, and compressing it can destroy exactly the detail a supplier needs to price the job.',
      '30MB is a chosen threshold, not a limit anything enforces — nothing breaks at 31MB.'),
    'Marginal. At this volume the storage saving is pennies; the honest value is spotting an upload path that is storing something it should not, such as an unresized original.',
    'No spend. Compressing costs engineering time and risks degrading a customer''s drawing, which is why this is the lowest-risk item on the board and stays a suggestion.');

  select count(*) into n from agent_actions where agent='document_controller' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'doc_health',v_health,'kpis',to_jsonb(k),'open_tasks',n);
end $function$;
