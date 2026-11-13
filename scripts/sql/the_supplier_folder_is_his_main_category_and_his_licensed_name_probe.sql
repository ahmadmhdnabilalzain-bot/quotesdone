-- Assigned: it_engineer
-- PURE PROBE (no DDL) for the_supplier_folder_is_his_main_category_and_his_licensed_name.sql. It always ends in raise exception
-- 'CHK<<...>>', so every row it writes rolls back; it writes only doc_backups (through the enqueue) and the subject's own rows, sends
-- nothing outward (it asserts every notification it caused is to @example.invalid) and reaches no real person: its subject is ONE approved ZZ DEMO supplier at
-- @example.invalid that has live quotes on ZZ DEMO customers' requests, and every queued row is a tagged sandbox row (_sandbox/<tag>/).
-- On production WITHOUT the file it fails (fn_dbx_main_category does not exist). What it asserts:
--   category : the main category is the plain label of his main trade (one trade; the model's covered items first; the largest group)
--   folder   : Suppliers/<main category>/<company as on the licence>/ - no id, no slug, no 'uncategorized'
--   files    : "Trade licence - <original name>" (no storage timestamp), "Signed Supplier Agreement.pdf", "Company Details.pdf",
--              "Job <rfq no>/Quotation <rfq no>.pdf" (gen_kind quotation) and "Job <rfq no>/Original as sent - ..."
--   replaced : a new licence -> the old one MOVES to Earlier versions/ (moved_from = where it is), never beside the new one
--   moved    : a changed main category moves every done file, correspondence too (moved_from set), never a second copy
--   no trade : no category -> no folder and nothing new queued (no 'Uncategorized')
--   legacy   : a supplier whose first folder was opened under the old rule keeps it (the migration is a separate, held file)
--   demo     : without the sandbox tag nothing of his reaches the real tree
do $$
declare
  v_tag text; v_name text;
  v_id bigint; v_q record; v_n int; v_root text; v_folder text; v_cat text; v_lic1 text; v_lic2 text; v_old_id bigint;
  v_max_note bigint; v_outward int; fail text := ''; seen jsonb := '{}'::jsonb; v_real int;
begin
  select l.id into v_id from public.leads l
   where l.is_demo and l.company_name like 'ZZ DEMO%' and l.email like '%@example.invalid' and l.claimed_by like '%@example.invalid'
     and l.approval_status = 'approved'
     and exists (select 1 from public.quotes q join public.inquiries i on i.id = q.inquiry_id join public.customers c on c.id = i.customer_id
                  where q.supplier_id = l.id and q.status not in ('draft', 'withdrawn') and c.is_demo and i.rfq_no is not null)
     and not exists (select 1 from public.quotes q join public.inquiries i on i.id = q.inquiry_id join public.customers c on c.id = i.customer_id
                      where q.supplier_id = l.id and not coalesce(c.is_demo, false))
   order by l.id limit 1;
  if v_id is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: no approved ZZ DEMO supplier with quotes on demo requests'); end if;
  if not exists (select 1 from public.supplier_capabilities where supplier_id = v_id) then
    raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: the subject has no supplier_capabilities row', 'supplier', v_id);
  end if;
  -- THE SANDBOX TAG IS A WORD OF THE SUBJECT'S OWN NAME (its longest, 6 to 40 letters or digits): trg_doc_backups_admit admits a demo
  -- row into _sandbox/<tag>/ only when the tag is in its path, and the probe must not rename the subject to put one there (a changed
  -- name queues the subject a notice: company_name_from_licence).
  select fn_dbx_safe(coalesce(nullif(btrim(licence_legal_name), ''), btrim(company_name))) into v_name from public.leads where id = v_id;
  select w into v_tag from regexp_split_to_table(v_name, '[^A-Za-z0-9]+') w where w ~ '^[A-Za-z0-9]{6,40}$' order by length(w) desc, w limit 1;
  if v_tag is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: the subject''s name has no word to tag the sandbox with', 'supplier', v_id); end if;
  select coalesce(max(id), 0) into v_max_note from public.notifications;
  perform set_config('qd.backup_sandbox', v_tag, true);
  v_root := '/QuotesDone Backup/_sandbox/' || v_tag || '/Suppliers/';
  v_lic1 := 'licenses/' || v_id || '/1794504328051_' || v_tag || '_licence.pdf';
  v_lic2 := 'licenses/' || v_id || '/1794513297753_' || v_tag || '_licence.pdf';

  -- ── category ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  update public.supplier_capabilities set trades = array['real_estate_services'], proposed_trades = '{}', source_docs = '{}'::jsonb where supplier_id = v_id;
  v_cat := public.fn_dbx_main_category(v_id);
  if v_cat is distinct from 'Real estate brokerage & property management' then fail := fail || format('one trade: %s; ', coalesce(v_cat, 'null')); end if;
  update public.supplier_capabilities set trades = array['steel', 'oilfield', 'industrial_pumps'] where supplier_id = v_id;
  if public.fn_dbx_main_category(v_id) is distinct from 'Oilfield & Industrial Supplies' then
    fail := fail || format('largest group: %s; ', coalesce(public.fn_dbx_main_category(v_id), 'null')); end if;
  update public.supplier_capabilities
     set source_docs = jsonb_build_object('reading', jsonb_build_object('evidence', jsonb_build_array(
           jsonb_build_object('trade', 'steel', 'licence', 'covered'), jsonb_build_object('trade', 'oilfield', 'licence', 'not_covered'),
           jsonb_build_object('trade', 'oilfield', 'licence', 'not_covered'))))
   where supplier_id = v_id;
  if public.fn_dbx_main_category(v_id) is distinct from 'Steel & metal fabrication' then
    fail := fail || format('licence-covered first: %s; ', coalesce(public.fn_dbx_main_category(v_id), 'null')); end if;

  -- ── folder and files ─────────────────────────────────────────────────────────────────────────────────────────────────────────
  update public.supplier_capabilities set trades = array['real_estate_services'], source_docs = '{}'::jsonb where supplier_id = v_id;
  -- his name is left as it is (a changed name queues the subject a notice); the folder is the name as on his licence
  update public.leads set license_doc_path = v_lic1, licence_read_state = 'read', licence_read_at = now(),
         signed_terms_path = 'suppliers/1794513504198_' || v_tag || '_TnC-Acceptance.pdf'
   where id = v_id;
  v_folder := v_root || 'Real estate brokerage & property management/' || v_name || '/';
  perform public.fn_enqueue_doc_backups();
  select coalesce(jsonb_object_agg(doc_type || ':' || coalesce(path, gen_ref), replace(dropbox_path, v_folder, '<folder>/')), '{}'::jsonb) into seen
    from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':%' and dropbox_path like v_root || '%';
  if not exists (select 1 from public.doc_backups where path = v_lic1 and dropbox_path = v_folder || 'Trade licence - ' || v_tag || '_licence.pdf') then
    fail := fail || 'licence not filed as "Trade licence - <original name>" in the ruled folder; '; end if;
  if not exists (select 1 from public.doc_backups where dedupe_key = 'SBX:' || v_tag || ':S:' || v_id || ':details' and dropbox_path = v_folder || 'Company Details.pdf') then
    fail := fail || 'Company Details.pdf not in the ruled folder; '; end if;
  if not exists (select 1 from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':S:' || v_id || ':Signed Terms%' and dropbox_path = v_folder || 'Signed Supplier Agreement.pdf') then
    fail := fail || 'agreement not "Signed Supplier Agreement.pdf"; '; end if;
  for v_q in select q.id, i.rfq_no, q.original_file_path from public.quotes q join public.inquiries i on i.id = q.inquiry_id
              where q.supplier_id = v_id and q.status not in ('draft', 'withdrawn') and q.stale_at is null loop
    if not exists (select 1 from public.doc_backups where gen_kind = 'quotation' and gen_ref = v_q.id::text and dedupe_key like 'SBX:' || v_tag || ':%'
                     and dropbox_path like v_folder || 'Job ' || v_q.rfq_no || '/Quotation ' || v_q.rfq_no || '%.pdf') then
      fail := fail || format('job %s: no template quotation in its job folder; ', v_q.rfq_no); end if;
    if v_q.original_file_path is not null and not exists (select 1 from public.doc_backups where path = v_q.original_file_path
                     and dropbox_path like v_folder || 'Job ' || v_q.rfq_no || '/Original as sent - %') then
      fail := fail || format('job %s: his own quotation not filed as "Original as sent"; ', v_q.rfq_no); end if;
  end loop;
  -- (the Customers tree is not this file's subject: only the supplier tree is asserted)
  if exists (select 1 from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':%' and dropbox_path like v_root || '%'
               and (dropbox_path ~ '\(\d+\)/' or dropbox_path ~ '/\d{10,}_' or dropbox_path ~* '/uncategorized/')) then
    fail := fail || 'a path carries an id, a storage timestamp or uncategorized; '; end if;

  -- ── a replaced licence moves to Earlier versions/ ─────────────────────────────────────────────────────────────────────────────
  update public.doc_backups set status = 'done', backed_up_at = now(), verified_at = now() where dedupe_key like 'SBX:' || v_tag || ':%' and source = 'storage';
  select id into v_old_id from public.doc_backups where path = v_lic1;
  update public.leads set license_doc_path = v_lic2 where id = v_id;
  perform public.fn_enqueue_doc_backups();
  if not exists (select 1 from public.doc_backups where path = v_lic2 and dropbox_path = v_folder || 'Trade licence - ' || v_tag || '_licence.pdf') then
    fail := fail || 'the new licence is not the "Trade licence"; '; end if;
  if not exists (select 1 from public.doc_backups where id = v_old_id and dropbox_path like v_folder || 'Earlier versions/Trade licence - % - ' || v_tag || '_licence.pdf'
                   and moved_from = v_folder || 'Trade licence - ' || v_tag || '_licence.pdf' and status = 'pending') then
    fail := fail || 'the replaced licence did not move to Earlier versions/ (moved_from); '; end if;
  select count(*) into v_n from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':%' and dropbox_path like v_folder || 'Trade licence%';
  if v_n <> 1 then fail := fail || format('%s files labelled "Trade licence" beside each other; ', v_n); end if;

  -- ── a changed main category moves every done file ────────────────────────────────────────────────────────────────────────────
  update public.doc_backups set status = 'done', backed_up_at = now(), moved_from = null where dedupe_key like 'SBX:' || v_tag || ':%';
  -- a correspondence PDF of his in the folder: it moves with the folder (its name is not the rule's)
  insert into public.doc_backups(entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key, status)
  values ('zz_demo', 'supplier:' || v_id, 'Correspondence', null, null, 'x.pdf', v_folder || 'Correspondence/2026-11-13 0000 out email - ' || v_tag || ' #1.pdf',
          'storage', 'SBX:' || v_tag || ':CONV:probe:' || v_id, 'done');
  update public.supplier_capabilities set trades = array['steel'] where supplier_id = v_id;
  perform public.fn_enqueue_doc_backups();
  select count(*) into v_n from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':%' and dropbox_path like v_folder || '%';
  if v_n <> 0 then fail := fail || format('%s files left in the old category folder; ', v_n); end if;
  select count(*) into v_n from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':%'
     and dropbox_path like v_root || 'Steel & metal fabrication/' || v_name || '/%' and moved_from like v_folder || '%';
  if v_n = 0 then fail := fail || 'nothing moved to the new category folder; '; end if;
  if not exists (select 1 from public.doc_backups where dedupe_key = 'SBX:' || v_tag || ':CONV:probe:' || v_id
                   and dropbox_path like v_root || 'Steel & metal fabrication/' || v_name || '/Correspondence/%' and moved_from like v_folder || 'Correspondence/%') then
    fail := fail || 'his correspondence did not move with his folder; '; end if;

  -- ── no trade: no folder, nothing new ─────────────────────────────────────────────────────────────────────────────────────────
  update public.supplier_capabilities set trades = '{}', proposed_trades = '{}' where supplier_id = v_id;
  if public.fn_dbx_supplier_folder(v_id) is not null then fail := fail || 'a supplier with no trade still has a folder; '; end if;
  select count(*) into v_n from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':%';
  update public.leads set catalog_doc_paths = array['catalogues/' || v_id || '/' || v_tag || '_cat.pdf'] where id = v_id;
  perform public.fn_enqueue_doc_backups();
  if (select count(*) from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':%') <> v_n then fail := fail || 'files queued for a supplier with no category; '; end if;
  if exists (select 1 from public.doc_backups where dropbox_path ~* '/Suppliers/uncategorized/' and dedupe_key like 'SBX:' || v_tag || ':%') then
    fail := fail || 'an Uncategorized folder; '; end if;

  -- ── demo stays out of the real tree ──────────────────────────────────────────────────────────────────────────────────────────
  update public.supplier_capabilities set trades = array['real_estate_services'] where supplier_id = v_id;
  perform set_config('qd.backup_sandbox', '', true);
  perform public.fn_enqueue_doc_backups();
  select count(*) into v_real from public.doc_backups where dropbox_path like '/QuotesDone Backup/Suppliers/%' and dropbox_path like '%' || v_tag || '%';
  if v_real <> 0 then fail := fail || format('%s demo rows in the real tree; ', v_real); end if;

  -- ── legacy: a first folder opened under the old rule is kept ─────────────────────────────────────────────────────────────────
  delete from public.doc_backups where dedupe_key = 'SBX:' || v_tag || ':S:' || v_id || ':details';
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key, status)
  values ('zz_demo', 'supplier:' || v_id, 'Company Details', 'generated', 'supplier_details', v_id::text,
          '/QuotesDone Backup/Suppliers/some-slug/ZZ DEMO ' || v_tag || ' old (' || v_id || ')/Company Details.pdf', 'S:' || v_id || ':details', 'done')
  on conflict (dedupe_key) do update set dropbox_path = excluded.dropbox_path;
  if public.fn_dbx_supplier_folder(v_id) is distinct from '/QuotesDone Backup/Suppliers/some-slug/ZZ DEMO ' || v_tag || ' old (' || v_id || ')/' then
    fail := fail || format('legacy folder not kept: %s; ', coalesce(public.fn_dbx_supplier_folder(v_id), 'null')); end if;

  -- the subject's own row updates may queue a notice to his @example.invalid address (rolled back); none to anyone else
  select count(*) into v_outward from public.notifications where id > v_max_note
     and (coalesce(to_email, '') !~* '@example\.invalid$' or to_phone is not null);
  if v_outward <> 0 then fail := fail || format('%s notifications to an address that is not @example.invalid; ', v_outward); end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'supplier', v_id, 'notifications_queued', (select count(*) from public.notifications where id > v_max_note), 'first_enqueue', seen);
end $$;
