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
--   15 min   : #1985's rule: a licence upload our reader is still on is not filed, and the licence on file does not move (D5)
--   revision : a quotation revised in place files a new current PDF; the earlier one moves to Job/Earlier versions/ (D4), customer too
--   customer : every live quote is also in the customer's request Quotes/, a file of its own (D6)
--   same name: the plain folder stays with the first opener, even of the higher id; two long names equal after the cut differ (D3)
--   late row : a file being uploaded when the folder changed is moved by the next run (D7)
--   scope    : the backup credential opens customer_api.quotation_for_backup and not customer_api (D2)
--   demo     : without the sandbox tag nothing of his reaches the real tree
do $$
declare
  v_tag text; v_name text;
  v_id bigint; v_q record; v_n int; v_root text; v_folder text; v_cat text; v_lic1 text; v_lic2 text; v_old_id bigint;
  v_max_note bigint; v_outward int; v_b bigint; v_q1 uuid; v_rfq1 text; v_a_legal text; v_b_legal text; v_a_name text; v_b_name text; v_sec text; v_fa text; v_fb text; fail text := ''; seen jsonb := '{}'::jsonb; v_real int;
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
  -- a second ZZ DEMO supplier, for the same-name case (D3)
  select l.id into v_b from public.leads l
   where l.is_demo and l.id <> v_id and l.company_name like 'ZZ DEMO%' and l.email like '%@example.invalid'
     and (l.claimed_by is null or l.claimed_by like '%@example.invalid') and l.approval_status = 'approved'
     and not exists (select 1 from public.quotes q where q.supplier_id = l.id)
   order by l.id limit 1;
  if v_b is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: no second approved ZZ DEMO supplier for the same-name case'); end if;
  -- INCAPABLE OF REACHING A PERSON: the subjects' and their demo customers' phone numbers are blanked for this transaction (a name the
  -- probe sets queues the subject a notice: it can then only go to his @example.invalid address)
  update public.leads set phone = null, phone_e164 = null, whatsapp = null, whatsapp_phone = null where id in (v_id, v_b);
  update public.customers c set phone = null where c.is_demo and c.id in (select i.customer_id from public.quotes q join public.inquiries i on i.id = q.inquiry_id where q.supplier_id = v_id);
  -- a licensed name the probe sets is copied to company_name by the licence trigger: both are put back afterwards
  select licence_legal_name, company_name into v_a_legal, v_a_name from public.leads where id = v_id;
  select licence_legal_name, company_name into v_b_legal, v_b_name from public.leads where id = v_b;
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

  -- ── the customer's copy (D6): each live quote is in his request's Quotes/ as he was shown it, a file of its own ─────────────────
  for v_q in select q.id, i.rfq_no from public.quotes q join public.inquiries i on i.id = q.inquiry_id
              where q.supplier_id = v_id and q.status not in ('draft', 'withdrawn') and q.stale_at is null loop
    if not exists (select 1 from public.doc_backups where gen_kind = 'quotation_customer' and gen_ref = v_q.id::text and dedupe_key like 'SBX:' || v_tag || ':CQ:%'
                     and dropbox_path ~ ('^/QuotesDone Backup/_sandbox/' || v_tag || '/Customers/[^/]+/Inquiries/[^/]+/Quotes/Quotation QD-' || v_q.rfq_no || '-[A-Z]\.pdf$')) then
      fail := fail || format('job %s: the customer''s request folder has no quotation; ', v_q.rfq_no); end if;
  end loop;

  -- ── a revised quotation (D4): the new revision is the plain "Quotation <job>.pdf", the earlier one moves to Earlier versions/ ───
  update public.doc_backups set status = 'done', backed_up_at = now(), verified_at = now(), bucket = 'backups', path = 'generated/' || v_tag || '_probe_' || id || '.pdf',
         dropbox_content_hash = 'probe'
   where dedupe_key like 'SBX:' || v_tag || ':%' and gen_kind in ('quotation', 'quotation_customer');
  select q.id, i.rfq_no::text into v_q1, v_rfq1 from public.quotes q join public.inquiries i on i.id = q.inquiry_id
   where q.supplier_id = v_id and q.status not in ('draft', 'withdrawn') and q.stale_at is null order by i.rfq_no limit 1;
  update public.quotes set committed_hash = coalesce(committed_hash, '') || '-probe-revision' where id = v_q1;
  perform public.fn_enqueue_doc_backups();
  if not exists (select 1 from public.doc_backups where gen_ref = v_q1::text and gen_kind = 'quotation' and status = 'pending' and dedupe_key not like '%:earlier'
                   and dropbox_path = v_folder || 'Job ' || v_rfq1 || '/Quotation ' || v_rfq1 || '.pdf') then
    fail := fail || 'the revised quotation is not filed as the current one; '; end if;
  if not exists (select 1 from public.doc_backups where gen_ref = v_q1::text and gen_kind = 'quotation' and dedupe_key like '%:earlier'
                   and dropbox_path like v_folder || 'Job ' || v_rfq1 || '/Earlier versions/Quotation ' || v_rfq1 || ' - %.pdf'
                   and moved_from = v_folder || 'Job ' || v_rfq1 || '/Quotation ' || v_rfq1 || '.pdf') then
    fail := fail || 'the earlier revision did not move to Job/Earlier versions/; '; end if;
  if not exists (select 1 from public.doc_backups where gen_ref = v_q1::text and gen_kind = 'quotation_customer' and dedupe_key like '%:earlier'
                   and dropbox_path ~ '/Quotes/Earlier versions/Quotation QD-' and moved_from ~ '/Quotes/Quotation QD-') then
    fail := fail || 'the customer''s earlier revision did not move to Quotes/Earlier versions/; '; end if;

  -- ── the same licensed name in the same category (D3): the folder stays with whoever opened it first ─────────────────────────────
  insert into public.supplier_capabilities(supplier_id, trades) values (v_b, array['real_estate_services'])
  on conflict (supplier_id) do update set trades = excluded.trades, proposed_trades = '{}';
  update public.leads set licence_legal_name = v_name, trade_license_no = 'ZZDEMO-77' where id = v_b;
  -- B (the HIGHER id) opened the plain folder a day before A did: B keeps it, A (the lower id) is the one with the suffix
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key, status, created_at)
  values ('zz_demo', 'supplier:' || v_b, 'Company Details', 'generated', 'supplier_details', v_b::text, v_folder || 'Company Details.pdf',
          'SBX:' || v_tag || ':S:' || v_b || ':details', 'done', now() - interval '1 day');
  v_fa := public.fn_dbx_supplier_folder(v_id); v_fb := public.fn_dbx_supplier_folder(v_b);
  if v_fb is distinct from '/QuotesDone Backup/Suppliers/Real estate brokerage & property management/' || v_name || '/' then
    fail := fail || format('same name: the first opener lost the plain folder (%s); ', coalesce(v_fb, 'null')); end if;
  if v_fa is not distinct from v_fb or v_fa !~ (' - (licence .+|\d+)/$') then
    fail := fail || format('same name: the later opener shares or lacks a suffix (%s); ', coalesce(v_fa, 'null')); end if;
  -- two long names equal in their first 170 characters are two folders
  update public.leads set licence_legal_name = 'ZZ DEMO ' || v_tag || ' ' || repeat('Long Name ', 25) || 'Alpha' where id = v_id;
  update public.leads set licence_legal_name = 'ZZ DEMO ' || v_tag || ' ' || repeat('Long Name ', 25) || 'Beta' where id = v_b;
  v_fa := public.fn_dbx_supplier_folder(v_id); v_fb := public.fn_dbx_supplier_folder(v_b);
  if v_fa is null or v_fb is null or lower(public.fn_dbx_path(v_fa)) = lower(public.fn_dbx_path(v_fb)) then
    fail := fail || 'two long names equal after the cut share one folder; '; end if;
  -- B leaves; A is as before
  delete from public.doc_backups where dedupe_key like 'SBX:' || v_tag || ':%' and entity_id = 'supplier:' || v_b;
  update public.supplier_capabilities set trades = '{}' where supplier_id = v_b;
  update public.leads set licence_legal_name = v_b_legal, company_name = v_b_name where id = v_b;
  update public.leads set licence_legal_name = v_a_legal, company_name = v_a_name where id = v_id;
  if public.fn_dbx_supplier_folder(v_id) is distinct from '/QuotesDone Backup/Suppliers/Real estate brokerage & property management/' || v_name || '/' then
    fail := fail || 'A did not get his plain folder back once B left; '; end if;

  -- ── a replaced licence moves to Earlier versions/ ─────────────────────────────────────────────────────────────────────────────
  update public.doc_backups set status = 'done', backed_up_at = now(), verified_at = now() where dedupe_key like 'SBX:' || v_tag || ':%' and source = 'storage';
  select id into v_old_id from public.doc_backups where path = v_lic1;
  -- #1985's 15 MINUTES (D5): a new upload in the licence slot that our reader is still on is not filed, and the licence on file stays
  update public.leads set license_doc_path = v_lic2, licence_read_state = 'ours_failed', licence_read_at = now() where id = v_id;
  perform public.fn_enqueue_doc_backups();
  if exists (select 1 from public.doc_backups where path = v_lic2) then fail := fail || 'a licence file was filed in its first 15 minutes of being read; '; end if;
  if not exists (select 1 from public.doc_backups where id = v_old_id and dropbox_path = v_folder || 'Trade licence - ' || v_tag || '_licence.pdf' and moved_from is null) then
    fail := fail || 'the licence on file moved while the new upload was being read; '; end if;
  update public.leads set licence_read_at = now() - interval '16 minutes' where id = v_id;
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
  -- and one being uploaded at the moment the folder changes (D7): it finishes where it was and the NEXT run moves it
  insert into public.doc_backups(entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key, status)
  values ('zz_demo', 'supplier:' || v_id, 'Correspondence', null, null, 'y.pdf', v_folder || 'Correspondence/2026-11-13 0001 out email - ' || v_tag || ' #2.pdf',
          'storage', 'SBX:' || v_tag || ':CONV:probe2:' || v_id, 'processing');
  update public.supplier_capabilities set trades = array['steel'] where supplier_id = v_id;
  perform public.fn_enqueue_doc_backups();
  update public.doc_backups set status = 'done', backed_up_at = now() where dedupe_key = 'SBX:' || v_tag || ':CONV:probe2:' || v_id;
  perform public.fn_enqueue_doc_backups();
  if not exists (select 1 from public.doc_backups where dedupe_key = 'SBX:' || v_tag || ':CONV:probe2:' || v_id
                   and dropbox_path like v_root || 'Steel & metal fabrication/' || v_name || '/Correspondence/%' and moved_from like v_folder || 'Correspondence/%') then
    fail := fail || 'a file being uploaded when the folder changed stayed behind; '; end if;
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

  -- ── the credential (D2): the backup's credential opens the backup door and not the function-wide scope of customer_api ─────────
  select value into v_sec from public.app_secrets where key = 'cred_fn_dropbox_backup';
  if coalesce((public.fn_internal_auth(v_sec, 'customer_api') ->> 'ok')::boolean, false) then
    fail := fail || 'the backup credential opens every door of customer_api; '; end if;
  if not coalesce((public.fn_internal_auth(v_sec, 'customer_api.quotation_for_backup') ->> 'ok')::boolean, false) then
    fail := fail || 'the backup credential does not open the backup door; '; end if;
  v_sec := null;

  -- the subject's own row updates may queue a notice to his @example.invalid address (rolled back); none to anyone else
  select count(*) into v_outward from public.notifications where id > v_max_note
     and (coalesce(to_email, '') !~* '@example\.invalid$' or to_phone is not null);
  if v_outward <> 0 then fail := fail || format('%s notifications to an address that is not @example.invalid; ', v_outward); end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'supplier', v_id, 'notifications_queued', (select count(*) from public.notifications where id > v_max_note), 'first_enqueue', seen);
end $$;
