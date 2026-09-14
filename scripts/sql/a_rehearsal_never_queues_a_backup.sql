-- A REHEARSAL NEVER QUEUES A BACKUP.
--
-- Assigned: sales_engineer (owner of the document-backup enqueue and upload path). 15 Sep 2026.
--
-- MEASURED BEFORE WRITING (15 Sep 2026, production, read-only):
--   doc_backups held 634 'pending' + 28 'waiting_source' rows, every one with entity 'zz_demo', and
--   0 real rows pending. The count grows with every rehearsal (609 at 21:59Z, 613 at 22:09Z, 634 at
--   22:17Z on 14 Sep). Every one carries an enqueue dedupe key (S:/C:/I:), i.e. fn_enqueue_doc_backups
--   queued it as a supplier, customer or inquiry and trg_doc_backups_admit RELABELLED it 'zz_demo'.
--   fn_doc_backups_next leaves zz_demo rows out unless p_demo is passed, and the uploader never
--   passes it, so these rows can never drain; their fixtures are torn down minutes after they land.
--   14 earlier rows were closed as status 'abandoned' with the error text reused below, touching
--   status and error only.
--
-- WHAT CHANGES:
--   1. trg_doc_backups_admit: a row it would RELABEL 'zz_demo' is not inserted (return null). A row
--      inserted with entity 'zz_demo' on purpose is still admitted: that is the probe contract
--      (backup_retention_cancels_both_halves.probe.sql, it_engineer_duties_9_to_18.test.mjs, the
--      probe in a_document_reaches_dropbox_when_it_lands_and_only_once_it_exists.sql all insert
--      entity 'zz_demo' themselves, claim through fn_doc_backups_next(..., p_demo => true) and delete
--      their own rows). fn_enqueue_doc_backups never writes 'zz_demo', so no rehearsal reaches it.
--   2. One-off: every zz_demo row still 'pending' or 'waiting_source' becomes 'abandoned', exactly as
--      the 14 were. No row whose entity is not 'zz_demo' is touched (asserted on the returned rows).
--   3. Probe, rolled back in its own sub-transaction so it cannot take the DDL above with it.
--
--   node scripts/apply_sql.mjs scripts/sql/a_rehearsal_never_queues_a_backup.sql --apply --ddl

-- No writer inserts into doc_backups while the gate changes and the backlog is closed: the count
-- taken before the update is then the count the update must close.
lock table public.doc_backups in share row exclusive mode;

-- ── 1. ADMISSION ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.trg_doc_backups_admit()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  new.dropbox_path := public.fn_dbx_path(new.dropbox_path);
  -- A rehearsal's documents are never queued: its fixtures are torn down minutes later, and a queued
  -- row could never drain (fn_doc_backups_next leaves zz_demo rows to the probes). Measured: 662 such
  -- rows piled up in one day (a_rehearsal_never_queues_a_backup.sql). A row a probe inserts as
  -- 'zz_demo' itself is not caught here and is still admitted.
  if new.entity is distinct from 'zz_demo' and (
       coalesce(new.dropbox_path, '') ~* 'zz[ _-]?demo' or coalesce(new.path, '') ~* 'zz[ _-]?demo'
       or (new.entity = 'supplier' and exists (select 1 from public.leads l where l.id::text = new.entity_id and l.is_demo))
       or (new.entity = 'customer' and exists (select 1 from public.customers c where c.id::text = new.entity_id and c.is_demo))) then
    return null;
  end if;
  if new.source = 'storage' and new.status = 'pending'
     and not exists (select 1 from storage.objects o where o.bucket_id = new.bucket and o.name = new.path) then
    new.status := 'waiting_source';
    new.error := left('waiting: storage holds no object at ' || coalesce(new.bucket, '?') || '/' || coalesce(new.path, '?'), 300);
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_doc_backups_admit() from public, anon, authenticated;

-- ── 2. THE BACKLOG, CLOSED THE WAY THE 14 WERE ─────────────────────────────────────────────────────
do $close$
declare
  v_before int; v_after int; v_n int; v_bad int;
  v_err constant text := 'abandoned: ZZ DEMO fixture of a rehearsal, torn down; never uploaded (14 Sep 2026)';
begin
  select count(*) into v_before from public.doc_backups
   where entity = 'zz_demo' and status in ('pending', 'waiting_source');
  raise notice 'before: % zz_demo rows pending/waiting_source; queue %', v_before,
    (select jsonb_object_agg(k, c) from (select entity || '/' || status k, count(*) c from public.doc_backups group by 1) z);

  with u as (
    update public.doc_backups d set status = 'abandoned', error = v_err
     where d.entity = 'zz_demo' and d.status in ('pending', 'waiting_source')
    returning d.entity)
  select count(*), count(*) filter (where entity is distinct from 'zz_demo') into v_n, v_bad from u;

  select count(*) into v_after from public.doc_backups
   where entity = 'zz_demo' and status in ('pending', 'waiting_source');
  assert v_bad = 0, format('%s rows outside zz_demo were touched', v_bad);
  assert v_n = v_before, format('closed %s of %s', v_n, v_before);
  assert v_after = 0, format('%s zz_demo rows still open', v_after);
  raise notice 'closed: %; after: % open; queue %', v_n, v_after,
    (select jsonb_object_agg(k, c) from (select entity || '/' || status k, count(*) c from public.doc_backups group by 1) z);
end $close$;

-- ── 3. PROBE: a ZZ DEMO document inserts 0 rows, a real-shaped one 1; rolled back ──────────────────
do $probe$
declare n int; v_cust text := (select c.id::text from public.customers c where c.is_demo limit 1);
begin
  begin
    -- shaped exactly as fn_enqueue_doc_backups writes a demo supplier's generated row
    insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
    values ('supplier', 'probe-rehearsal', 'Company Details', 'generated', 'supplier_details', 'probe-rehearsal',
            '/QuotesDone Backup/Suppliers/Fit-out/ZZ DEMO Supplier (probe-rehearsal)/Company Details.pdf', 'PROBE:rehearsal:path');
    get diagnostics n = row_count;
    assert n = 0, 'a ZZ DEMO path must insert 0 rows, inserted ' || n;
    if v_cust is not null then     -- a demo customer whose name carries no ZZ DEMO marker: the is_demo branch
      insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
      values ('customer', v_cust, 'Customer Details', 'generated', 'customer_details', v_cust,
              '/QuotesDone Backup/Customers/Probe Customer (' || left(v_cust, 8) || ')/Customer Details.pdf', 'PROBE:rehearsal:cust');
      get diagnostics n = row_count;
      assert n = 0, 'an is_demo customer must insert 0 rows, inserted ' || n;
    end if;
    insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
    values ('supplier', 'probe-real-shaped', 'Company Details', 'generated', 'supplier_details', 'probe-real-shaped',
            '/QuotesDone Backup/Suppliers/Fit-out/Al Noor Contracting (probe-real-shaped)/Company Details.pdf', 'PROBE:rehearsal:real');
    get diagnostics n = row_count;
    assert n = 1, 'a real-shaped row must insert 1 row, inserted ' || n;
    assert (select entity = 'supplier' and status = 'pending' from public.doc_backups where dedupe_key = 'PROBE:rehearsal:real'),
      'the real-shaped row must keep its entity and be pending';
    -- the probe contract: a row inserted as zz_demo on purpose is still admitted
    insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
    values ('zz_demo', 'zz_demo', 'ZZ DEMO', 'generated', 'zz_demo', 'probe', '/QuotesDone Backup/_zz_demo/probe.pdf', 'PROBE:rehearsal:zz');
    get diagnostics n = row_count;
    assert n = 1, 'an explicit zz_demo probe row must still be admitted';
    raise sqlstate 'QDPRB' using message = 'probe rolled back';
  exception when sqlstate 'QDPRB' then
    null;   -- everything inside the inner block is undone; assertion failures are not caught
  end;
  select count(*) into n from public.doc_backups where dedupe_key like 'PROBE:rehearsal:%';
  assert n = 0, 'probe rows left behind: ' || n;
  raise notice 'probe: ZZ DEMO path 0 rows, is_demo customer 0 rows (%), real-shaped 1 row, explicit zz_demo 1 row; rolled back',
    coalesce(left(v_cust, 8), 'no demo customer to try');
end $probe$;
