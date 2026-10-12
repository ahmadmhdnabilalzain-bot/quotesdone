-- every_document_lands_in_its_owners_one_folder_and_a_missing_copy_is_found_the_next_day.sql
--
-- Assigned: sales_engineer (files every document in its owner's one folder) and it_engineer (verifies:
-- the daily duty now reads the whole Dropbox listing, so a missing copy is found the next day).
-- Founder gate, ledger 1162 (7 Oct 2026): "no issue in the Dropbox backup of supplier/customer
-- documents and the folder workflow and organisation".
--
-- What was measured on production before this file (read-only census, 7 Oct 2026, counts only):
--   * 2 of 60 inquiries and 2 of 40 customers are split across two Dropbox folders. The inquiry folder
--     carries the inquiry STATUS ("<date> <id8> - <status>") and was recomputed for every new file, so a
--     document filed after a status change opened a second folder for the same request; a renamed
--     customer or supplier, or a re-scored supplier category, did the same one level up.
--   * 386 files owned by a customer, an inquiry, a quote or a supplier sat in Storage/<bucket>/<path>,
--     outside the entity -> type -> date tree, because no owner rule filed them (the supplier's
--     quotation, the quotation PDF, the reveal invoice/receipt, the comparison report and brief).
--   * The daily it_engineer check re-read only NEW rows; an existing copy was re-read only by a weekly
--     random sample of 20 out of 24,156, so a file deleted from Dropbox could go unnoticed for years.
--     The duty now compares the full Dropbox listing every day (dropbox_backup reconcile v12, with
--     fn_it_backup_listing_expected and fn_it_backup_listing_record below).
--   * No ZZ DEMO document could ever be backed up, so the pipeline could not be proven end to end
--     without a real customer. A TAGGED SANDBOX RUN now goes through the same enqueue, the same
--     uploader and the same listing check, into /QuotesDone Backup/_sandbox/<tag>/ only:
--     fn_backup_sandbox_enqueue, fn_doc_backups_sandbox_next, fn_conversation_archive_pending_sandbox.
--
-- Existing Dropbox files are not moved: the split folders and the 386 swept files stay where they are
-- (they are real customers' and suppliers' files); from now on every new file of an entity goes to the
-- folder its first file opened.
--
-- prevented by: scripts/checks/every_document_lands_in_its_owners_one_folder.test.mjs (schema mirror)
-- and supabase/functions/dropbox_backup/listing.test.ts (the listing comparison).

-- ── the admit trigger: demo rows dropped (unless a tagged sandbox run), ONE folder per entity ──
create or replace function public.trg_doc_backups_admit()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tag text := nullif(btrim(coalesce(current_setting('qd.backup_sandbox', true), '')), '');
  v_root text := '/QuotesDone Backup';
  v_kp text := '';                -- the dedupe-key prefix of the rows this one is filed beside
  v_sandbox boolean := false;
  v_id text; v_cust text; v_inq8 text; v_inq text; v_anchor text;
  v_uuid constant text := '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$';
begin
  new.dropbox_path := public.fn_dbx_path(new.dropbox_path);
  -- A rehearsal's documents are never queued: its fixtures are torn down minutes later, and a queued
  -- row could never drain (a_rehearsal_never_queues_a_backup.sql). A row a probe inserts as 'zz_demo'
  -- itself is still admitted. 7 Oct 2026: an inquiry of a demo customer is demo too.
  if new.entity is distinct from 'zz_demo' and (
       coalesce(new.dropbox_path, '') ~* 'zz[ _-]?demo' or coalesce(new.path, '') ~* 'zz[ _-]?demo'
       or (new.entity = 'supplier' and exists (select 1 from public.leads l where l.id::text = new.entity_id and l.is_demo))
       or (new.entity = 'customer' and exists (select 1 from public.customers c where c.id::text = new.entity_id and c.is_demo))
       or (new.entity = 'inquiry' and new.entity_id ~ v_uuid and exists (
             select 1 from public.inquiries i join public.customers c on c.id = i.customer_id
              where i.id = new.entity_id::uuid and c.is_demo))) then
    -- A TAGGED SANDBOX RUN (fn_backup_sandbox_enqueue sets qd.backup_sandbox for its own transaction)
    -- admits the demo documents that carry its tag, re-rooted under _sandbox/<tag>/; every other demo
    -- row is dropped exactly as before.
    if v_tag is null or v_tag !~ '^[A-Za-z0-9-]{6,40}$'
       or position(lower(v_tag) in lower(coalesce(new.dropbox_path, '') || ' ' || coalesce(new.path, ''))) = 0
       or coalesce(new.dropbox_path, '') !~ '^/QuotesDone Backup/' then
      return null;
    end if;
    v_sandbox := true;
    v_kp := 'SBX:' || v_tag || ':';
    v_root := '/QuotesDone Backup/_sandbox/' || v_tag;
    new.dropbox_path := v_root || substr(new.dropbox_path, length('/QuotesDone Backup') + 1);
    new.dedupe_key := v_kp || coalesce(new.dedupe_key, '');
  end if;

  -- ONE FOLDER PER ENTITY. The first file of a supplier, a customer or a request decides its folder
  -- (the Company Details, Customer Details and Inquiry Summary rows are queued for every entity and
  -- never re-queued); every later file is filed beside it, whatever the name, category or status reads
  -- now. Each anchor is one lookup on the unique dedupe key.
  v_id := substring(new.dropbox_path from '^' || v_root || '/Suppliers/[^/]+/[^/]* \((\d+)\)/');
  if v_id is not null then
    select substring(d.dropbox_path from '^(' || v_root || '/Suppliers/[^/]+/[^/]* \(' || v_id || '\)/)') into v_anchor
      from public.doc_backups d where d.dedupe_key = v_kp || 'S:' || v_id || ':details';
    -- 12 Oct 2026 (review): a first folder opened before the name was known reads 'Supplier (<id>)'
    -- (fn_enqueue_doc_backups writes coalesce(company_name, 'Supplier')); it never wins over the name.
    if v_anchor is not null and v_anchor !~ ('/Supplier \(' || v_id || '\)/$') then
      new.dropbox_path := v_anchor || substring(new.dropbox_path from '^' || v_root || '/Suppliers/[^/]+/[^/]* \(' || v_id || '\)/(.*)$');
    end if;
  elsif new.dropbox_path ~ ('^' || v_root || '/Customers/[^/]+/') then
    v_cust := case
      when new.entity = 'customer' then new.entity_id
      when new.entity = 'inquiry' and new.entity_id ~ v_uuid then
        (select i.customer_id::text from public.inquiries i where i.id = new.entity_id::uuid) end;
    if v_cust is not null then
      -- 12 Oct 2026 (review): the CUSTOMER folder is the NAMED one. A customer whose first file was filed
      -- before the name was saved sits in 'Customer (<id8>)' (coalesce(full_name, 'Customer')); anchoring
      -- on that put every later file there and lost the name. The first folder wins only when it carries
      -- a name; otherwise the current name does. (Files already in a 'Customer (<id8>)' folder are refiled
      -- under the name by scripts/it/dropbox_tree_repair.ts, held for the founder's OK.)
      select substring(d.dropbox_path from '^(' || v_root || '/Customers/[^/]+/)') into v_anchor
        from public.doc_backups d where d.dedupe_key = v_kp || 'C:' || v_cust || ':details';
      if v_anchor is not null and v_anchor !~ '/Customer \([0-9a-f]{8}\)/$' then
        new.dropbox_path := v_anchor || substring(new.dropbox_path from '^' || v_root || '/Customers/[^/]+/(.*)$');
      end if;
      v_inq8 := substring(new.dropbox_path from '^' || v_root || '/Customers/[^/]+/Inquiries/\d{4}-\d{2}-\d{2} ([0-9a-f]{8})[^/]*/');
      if v_inq8 is not null and v_cust ~ v_uuid then
        v_inq := case when new.entity = 'inquiry' then new.entity_id else
          (select i.id::text from public.inquiries i
            where i.customer_id = v_cust::uuid and left(i.id::text, 8) = v_inq8 order by i.created_at limit 1) end;
        v_anchor := null;
        -- the request's own subfolder (date, id, first status) comes from its first file; the customer
        -- folder above it is the one decided just above (the named one)
        select substring(d.dropbox_path from '^' || v_root || '/Customers/[^/]+/Inquiries/([^/]+)/') into v_anchor
          from public.doc_backups d where d.dedupe_key = v_kp || 'I:' || v_inq || ':summary';
        if v_anchor is not null then
          new.dropbox_path := substring(new.dropbox_path from '^(' || v_root || '/Customers/[^/]+/Inquiries/)') || v_anchor || '/'
            || substring(new.dropbox_path from '^' || v_root || '/Customers/[^/]+/Inquiries/[^/]+/(.*)$');
        end if;
      end if;
    end if;
  end if;

  if new.source = 'storage' and new.status = 'pending'
     and not exists (select 1 from storage.objects o where o.bucket_id = new.bucket and o.name = new.path) then
    new.status := 'waiting_source';
    new.error := left('waiting: storage holds no object at ' || coalesce(new.bucket, '?') || '/' || coalesce(new.path, '?'), 300);
  end if;
  if v_sandbox then
    new.entity_id := new.entity || ':' || new.entity_id;
    new.entity := 'zz_demo';
  end if;
  return new;
end $function$;

-- ── fn_enqueue_doc_backups: CUSTOMER DOCUMENTS filed under their request; a tagged sandbox lets its demo messages through ──
CREATE OR REPLACE FUNCTION public.fn_enqueue_doc_backups()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer := 0; m integer;
begin
  -- ============ SUPPLIERS ============
  with s as (
    select l.*,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)
  ),
  sd as (
    select s.id, s.base, v.doc_type, v.bucket, v.path
    from s cross join lateral (values
      ('Trade licence','supplier-docs', s.license_doc_path),
      ('Establishment card','supplier-docs', s.egr_doc_path),
      ('Insurance','supplier-docs', s.insurance_doc_path),
      ('VAT certificate','supplier-docs', s.vat_doc_path),
      ('ISO certificate','supplier-docs', s.iso_doc_path),
      ('Manufacturer authorization','supplier-docs', s.manufacturer_auth_doc_path),
      ('Company profile','supplier-docs', s.company_profile_doc_path),
      ('Signed Terms & Conditions','signed-terms', s.signed_terms_path)
    ) v(doc_type,bucket,path)
    where v.path is not null and length(v.path)>0
  )
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', sd.id::text, sd.doc_type, sd.bucket, sd.path,
         regexp_replace(sd.path,'^.*/',''),
         sd.base || sd.doc_type || ' - ' || regexp_replace(sd.path,'^.*/',''),
         'storage', 'S:'||sd.id||':'||sd.doc_type||':'||sd.path
  from sd on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', s.id::text, 'Catalogue', 'supplier-docs', cat,
         regexp_replace(cat,'^.*/',''), s.base || 'Catalogue - ' || regexp_replace(cat,'^.*/',''),
         'storage', 'S:'||s.id||':cat:'||cat
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base,
      l.catalog_doc_paths
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)) and l.catalog_doc_paths is not null ) s,
    unnest(s.catalog_doc_paths) cat
  where cat is not null and length(cat)>0 on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'supplier', s.id::text, 'Company Details','generated','supplier_details', s.id::text,
         s.base || 'Company Details.pdf', 'S:'||s.id||':details'
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false) ) s
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CUSTOMERS ============
  -- This is the row that carries a signed T&C certificate into Dropbox. compliance_archive writes
  -- customers.signed_terms_path and stops; the file is placed here, in one folder, once.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'customer', c.id::text, 'Signed Terms & Conditions','signed-terms', c.signed_terms_path,
         regexp_replace(c.signed_terms_path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Signed Terms & Conditions - '||regexp_replace(c.signed_terms_path,'^.*/',''),
         'storage', 'C:'||c.id||':terms:'||c.signed_terms_path
  from public.customers c where c.signed_terms_path is not null and length(c.signed_terms_path)>0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ INQUIRIES (under their customer) ============
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, 'RFQ drawing','drawing-files', i.drawing_file_path,
         coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Drawing - '||coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         'storage', 'I:'||i.id||':drawing:'||i.drawing_file_path
  from public.inquiries i join public.customers c on c.id=i.customer_id
  where i.drawing_file_path is not null and length(i.drawing_file_path)>0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf', 'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- The gen_kind='comparison' block that stood here is deliberately absent. See the header.

  -- ============ REVENUE INVOICES (9 SEP 2026) ============
  -- The founder: "our accountant need to retrieve that and be connected, then add it to his
  -- records, sync it with back up on dropbox." This is the sync half. The trigger is doc_path
  -- being non-null, NOT who wrote it, so a backfill or a hand-repair mirrors on the same rule as
  -- the webhook. They are filed under Finance rather than under the customer, because the person
  -- who opens this folder is the accountant reconciling a month, not someone reading one customer.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'transaction', t.id::text, 'Stripe invoice', 'finance-docs', t.doc_path,
         coalesce(t.doc_name, regexp_replace(t.doc_path,'^.*/','')),
         '/QuotesDone Backup/Finance/Revenue Invoices/'
           || to_char(coalesce(t.revealed_at, now()), 'YYYY') || '/'
           || to_char(coalesce(t.revealed_at, now()), 'YYYY-MM') || '/'
           || public.fn_dbx_safe(coalesce(t.stripe_invoice_number, t.stripe_invoice_id, left(t.id::text,8)))
           || ' - ' || coalesce(t.doc_name, regexp_replace(t.doc_path,'^.*/','')),
         'storage', 'T:'||t.id||':invoice:'||t.doc_path
  from public.transactions t
  where t.doc_path is not null and length(t.doc_path) > 0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CORRESPONDENCE (14 SEP 2026) ============
  -- The founder: "by back up i mean 2 points. supabase and dropbox." Every conversation message whose
  -- PDF is in backups/conversations/ (public.conversation_archive) is mirrored to Dropbox on his
  -- entity -> type -> date tree. A customer's message on an inquiry goes under that inquiry; a
  -- supplier's goes under the supplier ONLY when the supplier is a registrant (the same predicate the
  -- supplier documents use above); everything else is Company correspondence by month. Demo rows are
  -- never queued. Times are Dubai time.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select x.entity, x.entity_id, 'Correspondence', a.pdf_bucket, a.pdf_path, x.fname, x.base || x.fname, 'storage',
         'CONV:' || a.source_table || ':' || a.source_id
  -- 21 SEP 2026 (it_engineer): ONLY ARCHIVE ROWS THAT HAVE NO CORRESPONDENCE ROW YET. This block used to
  -- join every conversation_archive row (257) to v_conversation_message on every call and let ON CONFLICT
  -- discard all of them; the view resolves each message's party through fn_conversation_party, 20-45 ms
  -- a row, so the call cost 7,006 ms (EXPLAIN ANALYZE, 21 Sep) and PostgREST cancels at 8 s. The OFFSET 0
  -- fences keep the anti-join FIRST and the view LATERAL, so a call with nothing new costs 1.7 ms and a
  -- new message costs one party lookup. The dedupe key is unchanged, so what is queued is unchanged.
  from (select ca.* from public.conversation_archive ca
         where not exists (select 1 from public.doc_backups d
                            where d.dedupe_key = 'CONV:' || ca.source_table || ':' || ca.source_id)
         offset 0) a
  cross join lateral (select * from public.v_conversation_message v0
                       where v0.source_table = a.source_table and v0.source_id = a.source_id offset 0) v
  left join public.customers c on v.party_kind = 'customer' and c.id::text = v.party_id
  left join public.inquiries i on c.id is not null and i.id::text = v.inquiry_id
  left join public.leads l on v.party_kind = 'supplier' and l.id::text = v.party_id
       and (l.approved_at is not null or l.registration_submitted_at is not null
         or l.signed_terms_path is not null or l.company_profile_doc_path is not null
         or l.license_doc_path is not null or coalesce(l.claimed,false))
  cross join lateral (select
      case when c.id is not null then 'customer' when l.id is not null then 'supplier' else 'company' end as entity,
      coalesce(c.id::text, l.id::text, v.source_table || ':' || v.source_id) as entity_id,
      case when c.id is not null then
             '/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(c.full_name,'Customer')) || ' (' || left(c.id::text,8) || ')/'
             || case when i.id is not null then 'Inquiries/' || to_char(i.created_at,'YYYY-MM-DD') || ' ' || left(i.id::text,8)
                       || ' - ' || public.fn_dbx_safe(coalesce(i.status,'inquiry')) || '/' else '' end
             || 'Correspondence/'
           when l.id is not null then
             '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id) || '/'
             || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/Correspondence/'
           else '/QuotesDone Backup/Company/Correspondence/' || to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
      end as base,
      to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM-DD HH24MI') || ' ' || v.direction || ' ' || v.channel || ' - '
        || public.fn_dbx_safe(left(coalesce(nullif(btrim(v.subject),''),'(no subject)'),80)) || ' #' || v.source_id || '.pdf' as fname) x
  -- a tagged sandbox run (fn_backup_sandbox_enqueue) lets its own demo messages through; trg_doc_backups_admit
  -- files them under _sandbox/<tag>/ and drops every other demo row exactly as before
  where (not v.is_demo or coalesce(current_setting('qd.backup_sandbox', true), '') <> '')
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ ACCOUNTING (14 SEP 2026, accountant duty 4 of the five further duties) ============
  -- The founder, 14 Sep 2026: "add all for accountant and IT". The accountant's own documents are filed on
  -- the entity -> type -> date tree under Finance: the month close the CEO signed for (PDF and CSV), the
  -- Mashreq statements, every document the accountant issued in the founder's name, and the year-end pack.
  -- A path stored as '<bucket>/<path>' (bank_statement_intake.doc_path, accountant_issued_document.file_path)
  -- is split at its first slash; any other shape is not queued. Demo rows are filtered exactly as
  -- fn_it_backup_expected filters them (a zz_demo account, an @example.invalid recipient, a ZZ DEMO path):
  -- no demo document reaches Dropbox or the backups bucket.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'close:' || to_char(c.month,'YYYY-MM'), v.doc_type, c.pdf_bucket, v.path,
         regexp_replace(v.path,'^.*/',''),
         '/QuotesDone Backup/Finance/Month Close/' || to_char(c.month,'YYYY') || '/' || to_char(c.month,'YYYY-MM')
           || ' - ' || regexp_replace(v.path,'^.*/',''),
         'storage', 'ACCT:close:' || to_char(c.month,'YYYY-MM') || ':' || v.path
  from public.accountant_month_close c
  cross join lateral (values ('Month close (PDF)', c.pdf_path), ('Month close (CSV)', c.csv_path)) v(doc_type, path)
  where c.rendered_at is not null and c.pdf_bucket is not null and length(coalesce(v.path,'')) > 0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'bank_statement:' || b.source_ref, 'Bank statement', split_part(b.doc_path,'/',1),
         substr(b.doc_path, strpos(b.doc_path,'/') + 1), regexp_replace(b.doc_path,'^.*/',''),
         '/QuotesDone Backup/Finance/Bank Statements/' || initcap(b.account) || '/'
           || to_char(coalesce(b.statement_month, (b.received_at at time zone 'Asia/Dubai')::date),'YYYY') || '/'
           || to_char(coalesce(b.statement_month, (b.received_at at time zone 'Asia/Dubai')::date),'YYYY-MM')
           || ' - ' || regexp_replace(b.doc_path,'^.*/',''),
         'storage', 'ACCT:bank:' || b.source_ref
  from public.bank_statement_intake b
  where b.doc_path ~ '^[a-z0-9-]+/.+' and b.account <> 'zz_demo'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'issued:' || d.id, 'Issued document', split_part(d.file_path,'/',1),
         substr(d.file_path, strpos(d.file_path,'/') + 1), regexp_replace(d.file_path,'^.*/',''),
         '/QuotesDone Backup/Finance/Issued Documents/' || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY') || '/'
           || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
           || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY-MM-DD') || ' ' || d.document_kind || ' #' || d.id
           || ' - ' || regexp_replace(d.file_path,'^.*/',''),
         'storage', 'ACCT:issued:' || d.id
  from public.accountant_issued_document d
  where d.file_path ~ '^[a-z0-9-]+/.+' and d.recipient !~* 'example\.invalid'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'year_end:' || p.year, 'Year-end pack', f->>'bucket', f->>'path', f->>'name',
         '/QuotesDone Backup/Finance/Year End/' || p.year || '/' || (f->>'name'),
         'storage', 'ACCT:year_end:' || p.year || ':' || (f->>'name')
  from public.accountant_year_end_pack p cross join lateral jsonb_array_elements(p.files) f
  where p.rendered_at is not null and (f->>'path') !~* 'zz[_ -]?demo'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CUSTOMER DOCUMENTS (7 OCT 2026, sales_engineer) ============
  -- Founder gate, ledger 1162: "no issue in the Dropbox backup of supplier/customer documents and the
  -- folder workflow and organisation". Measured 7 Oct 2026: 386 files that belong to a customer, an
  -- inquiry, a quote or a supplier were filed by the STORAGE SWEEP under Storage/<bucket>/<path>, outside
  -- the entity -> type -> date tree (quote-files 274, agent-docs 92, drawing-files 33 ...). The documents
  -- of a request are filed under that request, in the customer's folder:
  --   Quotes/   the supplier's quotation as uploaded, and the quotation PDF the customer downloaded
  --   Payment/  every reveal invoice and receipt (agent-docs/reveal_invoice/<sale id8>/)
  --   Reports/  the comparison report and the request brief (agent-docs/compare|brief/<inquiry id>/,
  --             the folders customer_api writes since this change)
  -- A file already queued by any rule (the sweep included) is skipped on (bucket, path), so nothing is
  -- filed twice and nothing already in Dropbox is moved. The folder of the request is the one its
  -- Inquiry Summary was filed in (trg_doc_backups_admit), so a status change never splits it.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, x.doc_type, x.bucket, x.path, regexp_replace(x.path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/' || x.folder || '/' || public.fn_dbx_safe(x.fname),
         'storage', x.dkey
  from (
    select q.inquiry_id, 'Supplier quotation' as doc_type, 'quote-files' as bucket, q.original_file_path as path, 'Quotes' as folder,
           to_char(q.created_at at time zone 'Asia/Dubai','YYYY-MM-DD') || ' Quote ' || left(q.id::text,8) || ' - '
             || coalesce(nullif(btrim(q.original_file_name),''), regexp_replace(q.original_file_path,'^.*/','')) as fname,
           'Q:' || q.id || ':original:' || q.original_file_path as dkey
      from public.quotes q
     where length(coalesce(q.original_file_path,'')) > 0
    union all
    select q.inquiry_id, 'Quotation PDF', p.bucket, p.path, 'Quotes',
           'Quote ' || left(q.id::text,8) || ' (' || upper(coalesce(p.lang,'')) || ') - ' || regexp_replace(p.path,'^.*/',''),
           'QPDF:' || p.bucket || ':' || p.path
      from public.quote_pdf_cache p join public.quotes q on q.id = p.quote_id
     where length(coalesce(p.path,'')) > 0 and p.bucket is not null
    union all
    select t.inquiry_id, 'Reveal invoice or receipt', o.bucket_id, o.name, 'Payment', regexp_replace(o.name,'^.*/',''),
           'RCPT:' || o.bucket_id || ':' || o.name
      from storage.objects o join public.transactions t on left(t.id::text,8) = split_part(o.name,'/',2)
     where o.bucket_id = 'agent-docs' and o.name like 'reveal\_invoice/%' and t.inquiry_id is not null
    union all
    select i2.id, case split_part(o.name,'/',1) when 'compare' then 'Comparison report' else 'Request brief' end,
           o.bucket_id, o.name, 'Reports', regexp_replace(o.name,'^.*/',''), 'IDOC:' || o.bucket_id || ':' || o.name
      from storage.objects o join public.inquiries i2 on i2.id::text = split_part(o.name,'/',2)
     where o.bucket_id = 'agent-docs' and (o.name like 'compare/%' or o.name like 'brief/%')
  ) x
  join public.inquiries i on i.id = x.inquiry_id
  join public.customers c on c.id = i.customer_id
  where not exists (select 1 from public.doc_backups d where d.bucket = x.bucket and d.path = x.path)
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ TABLE EXPORTS (14 SEP 2026, it_engineer) ============
  -- Every file of a FINISHED day's export (public.table_export_run.status = 'done'), filed as
  -- Company -> Database Exports -> month -> day. Only finished days: a day that is re-run rewrites its
  -- pages, and a page mirrored mid-run would be a copy of an export that never completed. Demo rows
  -- never reach these files (fn_table_export_page). A (bucket, path) already queued by another rule
  -- (a refile) is skipped rather than allowed to fail this whole routine on the unique key.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'table_export:' || to_char(r.stamp,'YYYY-MM-DD'), 'Database export', 'backups', o.name,
         regexp_replace(o.name,'^.*/',''),
         '/QuotesDone Backup/Company/Database Exports/' || to_char(r.stamp,'YYYY-MM') || '/' || o.name,
         'storage', 'EXPORT:' || o.name
  from public.table_export_run r
  join storage.objects o on o.bucket_id = 'backups' and o.name like to_char(r.stamp,'YYYY-MM-DD') || '/%'
  where r.status = 'done'
    and not exists (select 1 from public.doc_backups d where d.bucket = 'backups' and d.path = o.name)
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- LEGACY EXPORTS and the STORAGE SWEEP are fn_enqueue_doc_backups_backfill (15 Sep 2026): together they
  -- took this call from milliseconds to 50 s, past PostgREST's 8 s, and every new document stopped.
  return n;
end $function$
;

-- ── the tagged sandbox run (sales_engineer files, it_engineer verifies; ZZ DEMO data only) ──
-- The same fn_enqueue_doc_backups, with qd.backup_sandbox set for this transaction only: the admit
-- trigger re-roots the demo rows that carry the tag under /QuotesDone Backup/_sandbox/<tag>/ as entity
-- 'zz_demo', which the scheduled uploader never claims (fn_doc_backups_next) and the daily checks skip.
create or replace function public.fn_backup_sandbox_enqueue(p_tag text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_n integer;
begin
  if coalesce(p_tag, '') !~ '^[A-Za-z0-9-]{6,40}$' then
    raise exception 'fn_backup_sandbox_enqueue: the tag is 6-40 letters, digits or hyphens (got %)', p_tag;
  end if;
  perform set_config('qd.backup_sandbox', p_tag, true);
  v_n := public.fn_enqueue_doc_backups();
  perform set_config('qd.backup_sandbox', '', true);
  return jsonb_build_object('tag', p_tag, 'enqueued', v_n,
    'sandbox_rows', (select count(*) from public.doc_backups d where d.entity = 'zz_demo' and d.dedupe_key like 'SBX:' || p_tag || ':%'));
end $function$;
revoke execute on function public.fn_backup_sandbox_enqueue(text) from public, anon, authenticated;

-- The sandbox's own claim: fn_doc_backups_next's rules (10-minute claim expiry, waiting_source release,
-- five attempts, exponential backoff, resume first) on the rows of ONE tag.
create or replace function public.fn_doc_backups_sandbox_next(p_tag text, p_limit integer, p_run text)
 returns setof public.doc_backups
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if coalesce(p_tag, '') !~ '^[A-Za-z0-9-]{6,40}$' then raise exception 'fn_doc_backups_sandbox_next: bad tag %', p_tag; end if;
  if coalesce(btrim(p_run), '') = '' then raise exception 'fn_doc_backups_sandbox_next: p_run is required'; end if;
  update public.doc_backups d set status = 'pending', claimed_at = null, claimed_by = null,
         error = left('claim by ' || coalesce(d.claimed_by, '?') || ' expired after 10 minutes; requeued', 300)
   where d.entity = 'zz_demo' and d.dedupe_key like 'SBX:' || p_tag || ':%'
     and d.status = 'processing' and d.claimed_at < now() - interval '10 minutes';
  update public.doc_backups d set status = 'pending', error = null
   where d.entity = 'zz_demo' and d.dedupe_key like 'SBX:' || p_tag || ':%' and d.status = 'waiting_source'
     and exists (select 1 from storage.objects o where o.bucket_id = d.bucket and o.name = d.path);
  return query
    with c as (
      select d.id from public.doc_backups d
       where d.entity = 'zz_demo' and d.dedupe_key like 'SBX:' || p_tag || ':%'
         and d.status in ('pending', 'error') and d.attempts < 5
         and (d.status = 'pending' or d.last_attempt_at is null
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.attempts, 8)))
       order by (d.upload_state is not null) desc, d.id
       limit greatest(1, least(coalesce(p_limit, 8), 25))
       for update skip locked)
    update public.doc_backups d set status = 'processing', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $function$;
revoke execute on function public.fn_doc_backups_sandbox_next(text, integer, text) from public, anon, authenticated;

-- conversation_archive action 'sandbox': the demo messages of one tag (the tag in the subject), never
-- archived yet. fn_conversation_archive_pending keeps refusing every demo message.
create or replace function public.fn_conversation_archive_pending_sandbox(p_tag text, p_limit integer default 5)
 returns setof public.v_conversation_message
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select v.* from public.v_conversation_message v
   where coalesce(p_tag, '') ~ '^[A-Za-z0-9-]{6,40}$'
     and v.subject ilike '%' || p_tag || '%'
     and v.is_demo
     and not exists (select 1 from public.conversation_archive a
                      where a.source_table = v.source_table and a.source_id = v.source_id)
   order by v.occurred_at
   limit greatest(1, least(coalesce(p_limit, 5), 25));
$function$;
revoke execute on function public.fn_conversation_archive_pending_sandbox(text, integer) from public, anon, authenticated;

-- ── it_engineer: the daily listing check ──
-- Every doc_backups row whose Dropbox copy sits under p_root, as one value (PostgREST caps a row set
-- at 1,000; one jsonb is not capped): [id, dropbox_path, dropbox_content_hash, status]. The caller lists
-- the same folder in Dropbox and compares (dropbox_backup/listing.ts). Demo rows only under _sandbox/.
create or replace function public.fn_it_backup_listing_expected(p_root text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(jsonb_agg(jsonb_build_array(d.id, d.dropbox_path, d.dropbox_content_hash, d.status) order by d.id), '[]'::jsonb)
    from public.doc_backups d
   where coalesce(p_root, '') ~ '^/QuotesDone Backup/[^/]'
     and starts_with(lower(d.dropbox_path), lower(p_root) || '/')
     and (d.entity = 'zz_demo') = starts_with(p_root, '/QuotesDone Backup/_sandbox/');
$function$;
revoke execute on function public.fn_it_backup_listing_expected(text) from public, anon, authenticated;

-- The day's listing reading, on the record: one it_engineer row per check, 'warn' when a copy is
-- missing or changed or a folder could not be listed in time. Findings themselves go through
-- fn_it_backup_check (the hand-over to the sales engineer), exactly as the sample's do.
create or replace function public.fn_it_backup_listing_record(p_summary jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_bad integer := coalesce((p_summary->>'missing')::int, 0) + coalesce((p_summary->>'changed')::int, 0)
                       + coalesce((p_summary->>'unlisted_roots')::int, 0);
        v_status text;
begin
  v_status := case when v_bad > 0 then 'warn' else 'ok' end;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, jsonb_build_object('job', 'dropbox_listing_check') || coalesce(p_summary, '{}'::jsonb),
          left('IT engineer Dropbox listing check: ' || coalesce(p_summary->>'expected', '0') || ' backed-up files expected, '
               || coalesce(p_summary->>'listed', '0') || ' listed in Dropbox, ' || coalesce(p_summary->>'missing', '0') || ' missing ('
               || coalesce(p_summary->>'confirmed_missing', '0') || ' confirmed one by one), ' || coalesce(p_summary->>'changed', '0')
               || ' changed, ' || coalesce(p_summary->>'stray', '0') || ' in Dropbox with no record, '
               || coalesce(p_summary->>'unlisted_roots', '0') || ' folder(s) not listed in time.', 500),
          now(), now());
  return jsonb_build_object('status', v_status);
end $function$;
revoke execute on function public.fn_it_backup_listing_record(jsonb) from public, anon, authenticated;

-- ── it_engineer: public.dropbox_files follows the daily walk (last synced 7 Sep 2026; seven routines read it) ──
-- dropbox_backup sends each completely listed root in slices of 2,000: each slice is upserted on the
-- Dropbox file id with this walk's stamp; the FINAL slice removes the rows under that root the walk did
-- not see (a file moved or deleted in Dropbox). A root the walk did not finish is never touched.
create or replace function public.fn_dropbox_files_refresh(p_root text, p_rows jsonb, p_stamp timestamptz, p_final boolean)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_up integer := 0; v_rm integer := 0;
begin
  if coalesce(p_root, '') !~ '^/QuotesDone Backup/[^/]' or p_stamp is null then
    raise exception 'fn_dropbox_files_refresh: a root under /QuotesDone Backup/ and the walk stamp are required';
  end if;
  insert into public.dropbox_files (dropbox_id, path, name, is_folder, size, content_hash, server_modified, synced_at)
  select r->>'id', r->>'path', r->>'name', false, (r->>'size')::bigint, r->>'hash', (r->>'modified')::timestamptz, p_stamp
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
   where coalesce(r->>'id', '') <> '' and starts_with(lower(r->>'path'), lower(p_root) || '/')
  on conflict (dropbox_id) do update set path = excluded.path, name = excluded.name, size = excluded.size,
        content_hash = excluded.content_hash, server_modified = excluded.server_modified, synced_at = excluded.synced_at;
  get diagnostics v_up = row_count;
  if p_final then
    delete from public.dropbox_files f where starts_with(lower(f.path), lower(p_root) || '/') and f.synced_at < p_stamp;
    get diagnostics v_rm = row_count;
  end if;
  return jsonb_build_object('upserted', v_up, 'removed', v_rm);
end $function$;
revoke execute on function public.fn_dropbox_files_refresh(text, jsonb, timestamptz, boolean) from public, anon, authenticated;

-- dropbox_files has a writer again, so it is no longer 'no_writer': it is a CACHE of the Dropbox listing,
-- rebuilt from Dropbox every day; Dropbox itself is the record, so the daily table export leaves it out.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('dropbox_files', false, 'cache', 'A cache of the Dropbox listing, rebuilt every day by the it_engineer''s full-tree walk (fn_dropbox_files_refresh); Dropbox is the record.', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── probe: the trigger files a second document of an entity beside its first, sandbox and demo rules ──
-- Runs on rows it creates and removes in this transaction; it touches no real row (it reads the
-- count of real rows before and after) and returns one verdict row.
do $probe$
declare
  v_before bigint; v_after bigint; v_p text; v_q text; v_r text; v_drop int; v_fail text := '';
  v_tag constant text := 'probe-onefolder-' || to_char(clock_timestamp(), 'HH24MISS');
begin
  select count(*) into v_before from public.doc_backups where dedupe_key not like 'PROBE1162:%' and dedupe_key not like 'SBX:probe-onefolder-%';
  -- a supplier's first file opens its folder; a later file under a different category and name lands beside it
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  values ('company', 'probe', 'probe', 'generated', 'probe', 'probe', '/QuotesDone Backup/Suppliers/Cat A/Probe Co (999999991)/Company Details.pdf', 'S:999999991:details');
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  values ('company', 'probe', 'probe', 'generated', 'probe', 'probe', '/QuotesDone Backup/Suppliers/Cat B/Probe Co Renamed (999999991)/Correspondence/x.pdf', 'PROBE1162:s2')
  returning dropbox_path into v_p;
  if v_p <> '/QuotesDone Backup/Suppliers/Cat A/Probe Co (999999991)/Correspondence/x.pdf' then v_fail := v_fail || ' supplier:' || v_p; end if;
  -- a customer whose first folder was opened before the name was known: a later file goes to the NAMED folder
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  values ('customer', '99999999-0000-4000-8000-000000001162', 'probe', 'generated', 'probe', 'probe', '/QuotesDone Backup/Customers/Customer (99999999)/Customer Details.pdf', 'C:99999999-0000-4000-8000-000000001162:details');
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  values ('customer', '99999999-0000-4000-8000-000000001162', 'probe', 'generated', 'probe', 'probe', '/QuotesDone Backup/Customers/Probe Named (99999999)/Correspondence/y.pdf', 'PROBE1162:c2')
  returning dropbox_path into v_p;
  if v_p <> '/QuotesDone Backup/Customers/Probe Named (99999999)/Correspondence/y.pdf' then v_fail := v_fail || ' customer_named:' || v_p; end if;
  -- a demo row is dropped outside a sandbox
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  values ('company', 'probe', 'probe', 'generated', 'probe', 'probe', '/QuotesDone Backup/Company/ZZ DEMO probe.pdf', 'PROBE1162:demo');
  get diagnostics v_drop = row_count;
  if v_drop <> 0 then v_fail := v_fail || ' demo_admitted'; end if;
  -- inside a tagged sandbox: re-rooted, zz_demo, prefixed key; a demo row of another tag still dropped
  perform set_config('qd.backup_sandbox', v_tag, true);
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  values ('company', 'probe', 'probe', 'generated', 'probe', 'probe', '/QuotesDone Backup/Company/ZZ DEMO ' || v_tag || '.pdf', 'PROBE1162:sbx')
  returning dropbox_path || '|' || entity || '|' || dedupe_key into v_q;
  if v_q <> '/QuotesDone Backup/_sandbox/' || v_tag || '/Company/ZZ DEMO ' || v_tag || '.pdf|zz_demo|SBX:' || v_tag || ':PROBE1162:sbx' then v_fail := v_fail || ' sandbox:' || v_q; end if;
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  values ('company', 'probe', 'probe', 'generated', 'probe', 'probe', '/QuotesDone Backup/Company/ZZ DEMO other-tag.pdf', 'PROBE1162:other');
  get diagnostics v_drop = row_count;
  if v_drop <> 0 then v_fail := v_fail || ' other_tag_admitted'; end if;
  perform set_config('qd.backup_sandbox', '', true);
  -- dropbox_files: a listed file is upserted; a later complete walk that no longer sees it removes it
  v_r := public.fn_dropbox_files_refresh('/QuotesDone Backup/_probe1162', '[{"id":"id:probe1162","path":"/QuotesDone Backup/_probe1162/a.pdf","name":"a.pdf","size":1,"hash":"h"}]'::jsonb, now() - interval '1 minute', false)->>'upserted';
  if v_r <> '1' then v_fail := v_fail || ' files_upsert:' || v_r; end if;
  v_r := public.fn_dropbox_files_refresh('/QuotesDone Backup/_probe1162', '[]'::jsonb, now(), true)->>'removed';
  if v_r <> '1' or exists (select 1 from public.dropbox_files where dropbox_id = 'id:probe1162') then v_fail := v_fail || ' files_remove:' || v_r; end if;
  -- the enqueue still runs inside its budget (the new CUSTOMER DOCUMENTS block included)
  v_r := clock_timestamp()::text;
  perform public.fn_enqueue_doc_backups();
  if clock_timestamp() - v_r::timestamptz > interval '6 seconds' then v_fail := v_fail || ' enqueue_slow'; end if;
  delete from public.doc_backups where dedupe_key in ('S:999999991:details', 'C:99999999-0000-4000-8000-000000001162:details', 'PROBE1162:c2', 'PROBE1162:s2', 'PROBE1162:demo', 'PROBE1162:other')
     or dedupe_key like 'SBX:probe-onefolder-%';
  select count(*) into v_after from public.doc_backups where dedupe_key not like 'PROBE1162:%' and dedupe_key not like 'SBX:probe-onefolder-%';
  if exists (select 1 from public.doc_backups where dedupe_key like 'PROBE1162:%' or dedupe_key in ('S:999999991:details', 'C:99999999-0000-4000-8000-000000001162:details') or dedupe_key like 'SBX:probe-onefolder-%') then
    v_fail := v_fail || ' probe_rows_left';
  end if;
  if v_after < v_before then v_fail := v_fail || ' real_rows_fell'; end if;
  perform set_config('qd.probe_1162', coalesce(nullif(v_fail, ''), 'ok'), true);
end $probe$;
select case when current_setting('qd.probe_1162', true) = 'ok' then 'PROBE OK'
            else 'PROBE FAILED: ' || coalesce(current_setting('qd.probe_1162', true), 'no verdict') end as verdict;
