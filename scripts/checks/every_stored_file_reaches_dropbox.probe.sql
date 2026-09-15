-- PROBE (it_engineer, 15 Sep 2026): the storage sweep in fn_enqueue_doc_backups files an unclaimed
-- stored file once, and never a ZZ DEMO file, a demo supplier's file, a conversation PDF or a dated
-- table-export page (those two folders have their own rules).
--
-- A PURE PROBE: one transaction that ends in raise exception, so every fixture row, every doc_backups
-- row the enqueue writes and every storage.objects fixture is rolled back. Nothing reaches Dropbox (the
-- uploader runs in its own transaction and never sees uncommitted rows) and nothing reaches a person.
-- Success is the exception text starting CHK<<ok.
--
--   node scripts/apply_sql.mjs scripts/checks/every_stored_file_reaches_dropbox.probe.sql --apply
do $probe$
declare
  v_lead bigint; n1 int; n2 int; v_rows int; v_demo int; v_sweep int;
  v_old constant timestamptz := timestamptz '2000-01-01 00:00:00+00';  -- oldest first: inside the 200 bound
begin
  select l.id into v_lead from public.leads l where l.is_demo order by l.id limit 1;
  if v_lead is null then raise exception 'CHK<<fail: no demo lead to own the demo-supplier fixture>>'; end if;

  insert into storage.objects (bucket_id, name, metadata, created_at) values
    ('compliance-docs', 'probe/qd-storage-sweep-probe.txt', '{"size": 1}', v_old),          -- must be swept
    ('quote-files',     'probe/ZZ DEMO storage sweep.pdf', '{"size": 1}', v_old),           -- demo name
    ('supplier-docs',   'licenses/' || v_lead || '/qd-sweep-probe.pdf', '{"size": 1}', v_old), -- demo supplier
    ('backups',         'conversations/qd-sweep-probe.pdf', '{"size": 1}', v_old),          -- own rule
    ('backups',         '2000-01-01/qd_sweep_probe/page_0000.json', '{"size": 1}', v_old);  -- export page: own rule

  -- 15 Sep 2026: the sweep is fn_enqueue_doc_backups_backfill (a_new_document_is_queued_at_once_and_the_backfill_runs_on_its_own.sql)
  n1 := public.fn_enqueue_doc_backups_backfill();
  select count(*) into v_rows from public.doc_backups
   where bucket = 'compliance-docs' and path = 'probe/qd-storage-sweep-probe.txt'
     and dedupe_key = 'SWEEP:compliance-docs:probe/qd-storage-sweep-probe.txt'
     and dropbox_path like '/QuotesDone Backup/Storage/compliance-docs/%' and status = 'pending';
  select count(*) into v_demo from public.doc_backups
   where (bucket, path) in (('quote-files', 'probe/ZZ DEMO storage sweep.pdf'),
                            ('supplier-docs', 'licenses/' || v_lead || '/qd-sweep-probe.pdf'),
                            ('backups', 'conversations/qd-sweep-probe.pdf'),
                            ('backups', '2000-01-01/qd_sweep_probe/page_0000.json'));
  select count(*) into v_sweep from public.doc_backups where dedupe_key like 'SWEEP:%' and created_at = now();

  n2 := public.fn_enqueue_doc_backups_backfill();

  if v_rows <> 1 then raise exception 'CHK<<fail: the unclaimed fixture was queued % time(s), expected 1>>', v_rows; end if;
  if v_demo <> 0 then raise exception 'CHK<<fail: % excluded fixture(s) were queued>>', v_demo; end if;
  if v_sweep > 200 then raise exception 'CHK<<fail: one call swept % files, the bound is 200>>', v_sweep; end if;
  if (select count(*) from public.doc_backups where bucket = 'compliance-docs' and path = 'probe/qd-storage-sweep-probe.txt') <> 1 then
    raise exception 'CHK<<fail: the second call queued the fixture again>>';
  end if;
  raise exception 'CHK<<ok: swept once (first call % rows, of them % by the sweep; second call % rows), 4 of 4 exclusions held>>', n1, v_sweep, n2;
end $probe$;
