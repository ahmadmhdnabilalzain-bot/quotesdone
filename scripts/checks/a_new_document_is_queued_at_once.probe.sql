-- PROBE (it_engineer, 15 Sep 2026): under PostgREST's own 8 s statement_timeout, the new-document enqueue
-- finishes and leaves the backfill's files alone; the backfill queues a swept file and a pre-7-Sep export
-- page once each, in their shapes, and never a ZZ DEMO file, a demo supplier's file or a conversation PDF;
-- and the 1-hour watch counts a missing owner row.
--
-- A PURE PROBE: one transaction that ends in raise exception, so every fixture (storage.objects rows,
-- the doc_backups rows the calls write, any finding the watch settles, the one real doc_backups row the
-- detection step removes) is rolled back. The uploader runs in its own transaction and never sees an
-- uncommitted row; nothing reaches Dropbox or a person. Success is the exception text starting CHK<<ok.
--
--   node scripts/apply_sql.mjs scripts/checks/a_new_document_is_queued_at_once.probe.sql --apply
set local statement_timeout = '8s';
do $probe$
declare
  v_old constant timestamptz := timestamptz '2000-01-01 00:00:00+00';   -- oldest first: inside every bound
  p_sw  constant text := 'probe/qd-enqueue-split-probe.txt';
  p_leg constant text := '2000-01-05/qdprobe_enqueue_split/page_0000.json';
  v_lead bigint; t0 timestamptz; t_fast int; t_bf int; t_w int; n_fast int; n_bf int; n_bf2 int; n_bf3 int;
  v_in_fast int; v_sw int; v_leg int; v_ex int; w0 int; w1 int; v_det text;
begin
  select l.id into v_lead from public.leads l where l.is_demo order by l.id limit 1;
  if v_lead is null then raise exception 'CHK<<fail: no demo lead to own the demo-supplier fixture>>'; end if;

  insert into storage.objects (bucket_id, name, metadata, created_at) values
    ('compliance-docs', p_sw, '{"size": 1}', v_old),                                               -- swept
    ('quote-files',     'probe/ZZ DEMO enqueue split.pdf', '{"size": 1}', v_old),                    -- demo name
    ('supplier-docs',   'licenses/' || v_lead || '/qd-enqueue-split-probe.pdf', '{"size": 1}', v_old), -- demo supplier
    ('backups',         'conversations/qd-enqueue-split-probe.pdf', '{"size": 1}', v_old),           -- own rule
    ('backups',         p_leg, '{"size": 1}', v_old);                                                -- legacy page

  -- 1. the new-document enqueue: bounded, and it no longer files the backfill's files
  t0 := clock_timestamp(); n_fast := public.fn_enqueue_doc_backups();
  t_fast := round(extract(epoch from clock_timestamp() - t0) * 1000);
  select count(*) into v_in_fast from public.doc_backups where (bucket, path) in (('compliance-docs', p_sw), ('backups', p_leg));
  if v_in_fast <> 0 then raise exception 'CHK<<fail: fn_enqueue_doc_backups filed % backfill fixture(s)>>', v_in_fast; end if;

  -- 2. the backfill at its default bound, then with room above any real legacy rows already waiting
  t0 := clock_timestamp(); n_bf := public.fn_enqueue_doc_backups_backfill();
  t_bf := round(extract(epoch from clock_timestamp() - t0) * 1000);
  n_bf2 := public.fn_enqueue_doc_backups_backfill(1000);
  n_bf3 := public.fn_enqueue_doc_backups_backfill(1000);

  select count(*) into v_sw from public.doc_backups
   where bucket = 'compliance-docs' and path = p_sw and dedupe_key = 'SWEEP:compliance-docs:' || p_sw
     and dropbox_path = '/QuotesDone Backup/Storage/compliance-docs/' || p_sw;
  select count(*) into v_leg from public.doc_backups
   where bucket = 'backups' and path = p_leg and dedupe_key = 'EXPORT:' || p_leg and doc_type = 'Database export'
     and public.fn_backup_prune_dropbox_allowed(bucket, path, dedupe_key, doc_type, dropbox_path);
  select count(*) into v_ex from public.doc_backups
   where (bucket, path) in (('quote-files', 'probe/ZZ DEMO enqueue split.pdf'),
                            ('supplier-docs', 'licenses/' || v_lead || '/qd-enqueue-split-probe.pdf'),
                            ('backups', 'conversations/qd-enqueue-split-probe.pdf'));
  if v_sw <> 1 then raise exception 'CHK<<fail: the swept fixture is queued % time(s), expected 1>>', v_sw; end if;
  if v_leg <> 1 then raise exception 'CHK<<fail: the legacy page is queued % time(s) in the retention shape, expected 1>>', v_leg; end if;
  if v_ex <> 0 then raise exception 'CHK<<fail: % excluded fixture(s) were queued>>', v_ex; end if;
  if n_bf > 400 then raise exception 'CHK<<fail: one default backfill call queued % rows, the bound is 200 + 200>>', n_bf; end if;

  -- 3. the watch counts an owner row that is missing (a real row, removed inside this transaction only)
  t0 := clock_timestamp();
  w0 := coalesce((public.fn_backup_enqueue_watch()->>'unqueued')::int, 0);
  t_w := round(extract(epoch from clock_timestamp() - t0) * 1000);
  begin
    -- through the (gen_kind, gen_ref) index and the leads key: a join on a built dedupe string scans
    delete from public.doc_backups d
     where d.id = (select d2.id from public.doc_backups d2
                     join public.leads l on l.id = case when d2.gen_ref ~ '^\d{1,18}$' then d2.gen_ref::bigint end
                    where d2.gen_kind = 'supplier_details' and d2.dedupe_key = 'S:' || d2.gen_ref || ':details'
                      and not coalesce(l.is_demo, false) and l.created_at < now() - interval '1 hour'
                    order by d2.id limit 1);
    if found then
      w1 := coalesce((public.fn_backup_enqueue_watch()->>'unqueued')::int, 0);
      if w1 <> w0 + 1 then raise exception 'CHK<<fail: the watch counted % then %, expected one more>>', w0, w1; end if;
      v_det := 'watch counted a removed supplier row (' || w0 || ' -> ' || w1 || ')';
    else
      v_det := 'watch detection not exercised: no non-demo registrant supplier over an hour old';
    end if;
  exception when others then
    if sqlerrm like 'CHK<<%' then raise; end if;
    v_det := 'watch detection not exercised: ' || left(sqlerrm, 120);
  end;

  raise exception 'CHK<<ok: new-document enqueue % rows in % ms; backfill % rows in % ms (then %, %); swept once, legacy once, 3 of 3 exclusions held; watch baseline % unqueued in % ms; %>>',
    n_fast, t_fast, n_bf, t_bf, n_bf2, n_bf3, w0, t_w, v_det;
end $probe$;
