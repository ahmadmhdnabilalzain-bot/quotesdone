-- the_two_real_suppliers_are_moved_into_the_ruled_tree.sql
--
-- Seat: it_engineer. Written 13 Nov 2026; HELD: it moves real files of two real companies, so it is applied only on the founder's
-- explicit OK (founder rulings 1680 and 1682: "There is nothing called uncategorized"). It is not in MANIFEST.txt; its note is
-- scripts/sql/pending/the_two_real_suppliers_are_moved_into_the_ruled_tree.txt. NOTHING IS DELETED: every file is MOVED (moved_from;
-- the dropbox_backup worker calls files/move_v2 and confirms size and hash).
-- REQUIRES the_supplier_folder_is_his_main_category_and_his_licensed_name.sql applied and dropbox_backup deployed with move.ts.
--
-- MEASURED 13 Nov 2026 (Dropbox listing, read only): /QuotesDone Backup/Suppliers/ holds 39 files. 11 are the founder's company
-- (uncategorized/<name> (158318)/), 26 are lead 19398 (industrial-equipment-suppliers/<name> (19398)/), and 3 are test acceptances at
-- the top of Suppliers/ (dj zaino, QA Flooring Test Co, QD PATH PROBE - ...). Every other folder there (Uncategorized's other five
-- sub-folders, Other, the 18 other slug folders, the four "QD Demo Claimed Aluminium" folders) is EMPTY: their files were moved to
-- _archive/ownerless-2026-10-12 and _archive/demo-leftovers-2026-10-12 on 12 Oct and the folders were left behind.
--
-- WHAT IT DOES, in one transaction:
--   1. the file the founder put in his licence slot on purpose (his company profile, filed before #1985 as "Trade licence - ..._Company-
--      Profile.pdf") is relabelled as what it is: doc_type 'Company profile (sent as trade licence)'. The rule then files it under
--      Earlier versions/, never as a licence;
--   2. for 158318 and 19398: every doc_backups row under his legacy folder is pointed at his ruled folder
--      Suppliers/<main category>/<company as on his licence>/ (same relative path), moved_from = where the file is now;
--   3. fn_enqueue_doc_backups() then names each document by the rule (Trade licence - <original name>, Earlier versions/..., Signed
--      Supplier Agreement.pdf); moved_from keeps the ORIGINAL place, so each file moves once, straight to its final name;
--   4. the three test acceptances move to _archive/suppliers-test-folders-2026-11-13/<their folder>/.
-- AFTER IT: the empty folders are moved (not deleted) into _archive/suppliers-empty-folders-2026-11-13/ by the release operator with a
-- Dropbox folder move; the plan and the list are in the session report. doc_backups needs nothing more: no row points into them.
-- THE GUARD: replace 0 below with the founder_instruction id in which he approved this move; with 0 the file changes nothing and says so.

do $$
declare v_ok constant bigint := 0;   -- the approving founder_instruction id
        v_n int; v_moved int := 0; r record;
begin
  if not exists (select 1 from public.founder_instruction where id = v_ok) then
    raise exception 'HELD: the_two_real_suppliers_are_moved_into_the_ruled_tree.sql moves real files; set v_ok to the founder''s approving ledger id';
  end if;

  -- 1. his profile in the licence slot is not a licence
  update public.doc_backups
     set doc_type = 'Company profile (sent as trade licence)',
         dedupe_key = replace(dedupe_key, ':Trade licence:', ':Company profile (sent as trade licence):')
   where entity = 'supplier' and entity_id = '158318' and bucket = 'supplier-docs'
     and path like 'licenses/158318/%' and path ilike '%company-profile%' and doc_type = 'Trade licence';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'expected 1 profile in the licence slot of 158318, found %', v_n; end if;

  -- 2. the legacy folder of each, to his ruled folder
  for r in
    select l.id,
           substring(d.dropbox_path from '^(/QuotesDone Backup/Suppliers/[^/]+/[^/]* \(' || l.id || '\)/)') as old_folder,
           '/QuotesDone Backup/Suppliers/' || public.fn_dbx_main_category(l.id) || '/'
             || public.fn_dbx_safe(coalesce(nullif(btrim(l.licence_legal_name), ''), btrim(l.company_name))) || '/' as new_folder
      from public.leads l join public.doc_backups d on d.dedupe_key = 'S:' || l.id || ':details'
     where l.id in (158318, 19398)
  loop
    if r.old_folder is null or r.new_folder is null then raise exception 'supplier %: no legacy folder or no main category', r.id; end if;
    update public.doc_backups d
       set moved_from = case when d.status = 'done' then coalesce(d.moved_from, d.dropbox_path) else d.moved_from end,
           dropbox_path = r.new_folder || substr(d.dropbox_path, length(r.old_folder) + 1),
           status = 'pending', error = null, attempts = 0, upload_state = null, backed_up_at = null, verified_at = null, requeued_at = now()
     where d.entity = 'supplier' and d.entity_id = r.id::text and starts_with(d.dropbox_path, r.old_folder)
       and d.status in ('done', 'error', 'pending', 'waiting_source');
    get diagnostics v_n = row_count; v_moved := v_moved + v_n;
  end loop;

  -- 3. each document gets its ruled name
  perform public.fn_enqueue_doc_backups();

  -- 4. the three test acceptances at the top of Suppliers/
  update public.doc_backups d
     set moved_from = d.dropbox_path,
         dropbox_path = '/QuotesDone Backup/_archive/suppliers-test-folders-2026-11-13/' || substr(d.dropbox_path, length('/QuotesDone Backup/Suppliers/') + 1),
         status = 'pending', error = null, attempts = 0, requeued_at = now(), backed_up_at = null, verified_at = null
   where d.entity = 'company' and d.entity_id = 'dropbox' and d.status = 'done'
     and d.dropbox_path in ('/QuotesDone Backup/Suppliers/dj zaino/Signed-Terms-Acceptance.pdf',
                            '/QuotesDone Backup/Suppliers/QA Flooring Test Co/Signed-Terms-Acceptance.pdf',
                            '/QuotesDone Backup/Suppliers/QD PATH PROBE - Meridian MEP Contracting LLC registration walk-through not a tra/Signed-Terms-Acceptance.pdf');
  get diagnostics v_n = row_count;
  if v_n <> 3 then raise exception 'expected the 3 test acceptances, found %', v_n; end if;

  -- nothing of theirs may still point into a legacy folder or 'uncategorized'
  if exists (select 1 from public.doc_backups where entity = 'supplier' and entity_id in ('158318', '19398')
               and (dropbox_path ~ '\((158318|19398)\)/' or dropbox_path ~* '/Suppliers/uncategorized/')) then
    raise exception 'a row of 158318 or 19398 still points into its legacy folder';
  end if;
end $$;
