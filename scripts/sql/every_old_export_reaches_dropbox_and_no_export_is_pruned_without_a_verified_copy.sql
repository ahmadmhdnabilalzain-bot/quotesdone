-- EVERY OLD EXPORT REACHES DROPBOX, AND NO EXPORT IS PRUNED WITHOUT A VERIFIED COPY.
--
-- Assigned: it_engineer. 15 Sep 2026.
--
-- The founder's standing rule: "that data should never get lost no matter what". The decision (the
-- coordinating session, 15 Sep 2026, on that rule; Dropbox measured 11.6% full, about 62 of 539 GB): the
-- dated exports backup v1 wrote before 7 Sep MUST reach Dropbox, and nothing may ever delete an export
-- from storage that has no verified Dropbox copy.
--
-- MEASURED BEFORE WRITING (15 Sep 2026, production, read-only):
--   * 5,199 files in 'backups' under 64 dated folders 2026-06-23 .. 2026-09-07 (backup v1), 13.15 GiB
--     (13,470 MB), median 2.6 MB, largest 42 MB (none reaches the uploader's 140 MB skip; over 8 MiB is a
--     chunked, resumable session). None has a doc_backups row: the TABLE EXPORTS rule files only days with
--     a finished table_export_run, and there is one such day (2026-09-15). The storage sweep
--     (every_stored_file_reaches_dropbox_and_the_backup_gap_duty_raises_only_real_gaps.sql) leaves dated
--     folders to these rules.
--   * THE DRAIN: dropbox_backup claims at most 25 rows a run under a 110 s deadline (150 s edge limit),
--     and chains itself (process_only, up to 20 links) while batches are full. When the revived 2026-09-15
--     export (about 7.3 GB) was queued it uploaded 1,833 files / 7,645.6 MB in the 07:00 UTC hour and
--     1,007 / 3,931.0 MB in the 06:00 hour: 342 and 192 runs, 3 and 13 of them errors, 0 rows with a
--     rate-limit (429) error. Every upload is verified before it is marked done (verifyUploaded: content
--     hash and size), which is what sets doc_backups.verified_at.
--   * ETA: at the measured peak, 5,199 files take about 2.8 hours by file count (1,833/h) and 1.8 hours by
--     bytes (7.47 GiB/h); at the average of those two hours (1,420 files/h, 5.6 GiB/h), about 3.7 hours.
--     Enqueue refills happen on each non-chained run (~18/h measured), 200 at a time, well above that rate.
--   * Retention is in DRY RUN (no app_secrets backup_prune_mode row) and backup_prune_log is empty, so
--     nothing has been deleted; the first legacy day becomes deletable on 2026-09-27 at the earliest.
--
-- WHAT CHANGES:
--   1. fn_enqueue_doc_backups (the body of the file above, unchanged) gains LEGACY EXPORTS: every file of a
--      legacy day (the definition fn_backup_prune_days uses: dated on or before 2026-09-07 with no
--      table_export_run row) is filed exactly as the TABLE EXPORTS rule files a day -- doc_type 'Database
--      export', dedupe_key 'EXPORT:<path>', /QuotesDone Backup/Company/Database Exports/<YYYY-MM>/<path> --
--      so retention recognises the copies. Idempotent on (bucket, path) and on the dedupe key. BOUNDED: it
--      keeps at most 200 legacy rows waiting, oldest day first, so new customer and supplier documents
--      never queue behind 13 GB (the uploader claims lowest id first; the most they wait behind is 200
--      files, about 520 MB, a few minutes). backup v1's document inventories (<day>/_storage_<bucket>.json)
--      are filed too; retention never selects them.
--   2. THE GUARD, in the retention path:
--      * storage: fn_backup_prune_storage_next hands over only a file whose doc_backups row is status
--        'done' with verified_at set. A file without one stays, and the day is not marked deleted
--        (fn_backup_prune_storage_done counts it as left).
--      * Dropbox: a day's copies join the delete queue (fn_backup_prune_tick) and are claimed
--        (fn_doc_backups_prune_next) only AFTER that day's storage deletion finished, and only rows that
--        were done and verified. Before, both halves ran at once: the tick moved every row of the day,
--        uploaded or not, into prune_pending, so a file never uploaded was "deleted" from Dropbox (a
--        missing path counts as success) and marked pruned while storage was still the only copy.
--   3. Every other line of the three retention routines is the MANIFEST-last body
--      (the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql).
--
-- WHAT THIS DOES NOT CHANGE: dropbox_backup/index.ts, _shared/dropbox.ts and supabase/functions/backup.
-- It does not switch deletion on.
--
-- APPLY ORDER: after PR #716's two files (this redefines the fn_enqueue_doc_backups they define):
--   node scripts/apply_sql.mjs scripts/sql/every_stored_document_source_is_registered_for_backup.sql --apply --ddl
--   node scripts/apply_sql.mjs scripts/sql/every_stored_file_reaches_dropbox_and_the_backup_gap_duty_raises_only_real_gaps.sql --apply --ddl
--   node scripts/apply_sql.mjs scripts/sql/every_old_export_reaches_dropbox_and_no_export_is_pruned_without_a_verified_copy.sql --apply --ddl
-- Probe (aborted transaction, commits nothing):
--   node scripts/apply_sql.mjs scripts/checks/no_export_is_pruned_without_a_verified_copy.probe.sql --apply

-- ── 1. fn_enqueue_doc_backups with LEGACY EXPORTS ─────────────────────────────────────────────────

create or replace function public.fn_enqueue_doc_backups()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
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
      ('Bank IBAN','supplier-docs', s.iban_doc_path),
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
  from public.conversation_archive a
  join public.v_conversation_message v on v.source_table = a.source_table and v.source_id = a.source_id
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
  where not v.is_demo
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

  -- ============ LEGACY EXPORTS (15 SEP 2026, it_engineer) ============
  -- The founder: "that data should never get lost no matter what". backup v1's dated folders (on or
  -- before 2026-09-07, no table_export_run row: the legacy-day definition fn_backup_prune_days uses) are
  -- filed exactly like a TABLE EXPORTS day, so retention recognises the copies. At most 200 legacy rows
  -- wait at a time, oldest day first: the uploader claims lowest id first, so a new customer or supplier
  -- document waits behind at most 200 export pages (measured median 2.6 MB). Refilled on every
  -- non-chained dropbox_backup run.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'table_export:' || split_part(o.name,'/',1), 'Database export', 'backups', o.name,
         regexp_replace(o.name,'^.*/',''),
         '/QuotesDone Backup/Company/Database Exports/' || left(o.name, 7) || '/' || o.name,
         'storage', 'EXPORT:' || o.name
  from storage.objects o
  where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/' and split_part(o.name,'/',1) <= '2026-09-07'
    and not exists (select 1 from public.table_export_run r where r.stamp::text = split_part(o.name,'/',1))
    and not exists (select 1 from public.doc_backups d where d.bucket = 'backups' and d.path = o.name)
  order by o.name
  limit greatest(0, 200 - (select count(*) from public.doc_backups w
                             where w.dedupe_key like 'EXPORT:%' and w.status in ('pending', 'processing', 'error', 'waiting_source')
                               and w.bucket = 'backups' and split_part(w.path,'/',1) <= '2026-09-07'
                               and not exists (select 1 from public.table_export_run r2 where r2.stamp::text = split_part(w.path,'/',1))))
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ STORAGE SWEEP (15 SEP 2026, it_engineer) ============
  -- The founder: "of course that data should never get lost no matter what". Every stored file no rule
  -- above filed: fn_backup_sweep_objects() is the one list of what may be swept (the registry's swept
  -- buckets, without ZZ DEMO, demo owners, the export and conversation folders of backups, or any file
  -- of a customer PDPL is erasing; each row carries its real owner). Filed under Storage/<bucket>/<path> so the
  -- original path, which carries the supplier, inquiry or quote id, is kept. Only files over an hour
  -- old, so an owner rule that runs on the same upload files it first under its owner. At most 200 per
  -- call, oldest first: the backfill of existing files drains over successive dropbox_backup runs.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select s.entity, s.entity_id, 'Stored file', s.bucket, s.path, regexp_replace(s.path,'^.*/',''),
         '/QuotesDone Backup/Storage/' || s.bucket || '/' || s.path,
         'storage', 'SWEEP:' || s.bucket || ':' || s.path
  from public.fn_backup_sweep_objects() s
  where s.created_at < now() - interval '1 hour'
    and not exists (select 1 from public.doc_backups d where d.bucket = s.bucket and d.path = s.path)
  order by s.created_at, s.bucket, s.path
  limit 200
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $function$;
revoke execute on function public.fn_enqueue_doc_backups() from public, anon, authenticated;

-- ── 2. THE GUARD: storage is deleted only under a verified copy, and Dropbox only after storage ─────
-- fn_backup_prune_tick: the MANIFEST-last body with ONE change, the move into the Dropbox delete queue.
create or replace function public.fn_backup_prune_tick()
returns jsonb
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_mode text := public.fn_backup_prune_mode();
  v_export public.table_export_run;
  v_pass jsonb := null; v_logged int := 0; v_items jsonb := '[]'::jsonb; v_settle jsonb; x record;
begin
  -- A PASS: once per Dubai day, after that day's export finished.
  select * into v_export from public.table_export_run r where r.stamp = v_today;
  if found and (v_export.status = 'done' or (v_export.status = 'failed' and v_export.attempts >= 6))
     and not exists (select 1 from public.agent_runs ar
                      where ar.agent = 'it_engineer' and ar.counts->>'job' = 'backup_prune'
                        and (ar.started_at at time zone 'Asia/Dubai')::date = v_today) then
    insert into public.backup_prune_log (decided_for, mode, day, origin, kind, day_status, reason, objects, bytes, dropbox_files)
    select v_today, v_mode, p.day, p.origin, p.kind, p.day_status, p.reason, p.objects, p.bytes, p.dropbox_files
      from public.fn_backup_prune_plan(v_today) p
     where p.decision = 'delete'
       and not exists (select 1 from public.backup_prune_log l
                        where l.day = p.day and l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null)
    on conflict do nothing;
    get diagnostics v_logged = row_count;
    v_pass := jsonb_build_object('days', v_logged);
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'ok', jsonb_build_object('job', 'backup_prune', 'mode', v_mode, 'days', v_logged),
            left(case when v_mode = 'delete' then 'Backup retention: ' || v_logged || ' export day(s) logged for deletion.'
                      else 'Backup retention DRY RUN: ' || v_logged || ' export day(s) would be deleted; nothing was touched.' end, 500),
            now(), now());
  end if;

  if v_mode = 'delete' then
    perform public.fn_backup_prune_recheck();
    -- the day's Dropbox copies leave the upload queue and join the delete queue; the status they had is kept.
    -- 15 Sep 2026 (the guard): only AFTER the day's storage deletion finished -- which itself happens only
    -- under verified copies -- and only a copy that was uploaded and verified. Before, every row of the day
    -- moved at once, uploaded or not, so a never-uploaded file was "deleted" from Dropbox (a missing path
    -- is success), marked pruned, and never uploaded while storage still held the only copy.
    update public.doc_backups b set status = 'prune_pending', status_before_prune = b.status, claimed_at = null, claimed_by = null
      from public.backup_prune_log l
     where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
       and l.storage_deleted_at is not null
       and b.dedupe_key like 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/%'
       and b.status = 'done' and b.verified_at is not null
       and public.fn_backup_prune_dropbox_allowed(b.bucket, b.path, b.dedupe_key, b.doc_type, b.dropbox_path);
    update public.doc_backups b set status = 'pruned', error = null
     where b.status = 'prune_pending' and b.dropbox_path is null;
    update public.backup_prune_log l set dropbox_done_at = now()
     where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
       and not exists (select 1 from public.doc_backups b
                        where b.dedupe_key like 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/%' and b.status <> 'pruned');
  end if;

  -- A prune failure is an it_engineer finding; the same settle closes it once the deletion completes.
  for x in select l.* from public.backup_prune_log l
            where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null
              and (l.storage_attempts >= 3 or l.decided_at < now() - interval '2 days') loop
    v_items := v_items || jsonb_build_object('item', 'storage:' || x.day, 'owner_seat', 'it_engineer', 'subject', 'backups',
      'title', 'Backup retention could not remove the ' || x.day || ' export from the backups bucket',
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('backup_prune_log_id', x.id, 'attempts', x.storage_attempts, 'error', x.storage_error,
                                     'objects_removed', x.objects_removed, 'logged_at', x.decided_at));
  end loop;
  for x in select split_part(substr(b.dedupe_key, 8), '/', 1) as dy, count(*) as n, max(b.error) as err
             from public.doc_backups b
            where b.status in ('prune_pending', 'pruning') and b.prune_attempts >= 5
            group by 1 loop
    v_items := v_items || jsonb_build_object('item', 'dropbox:' || x.dy, 'owner_seat', 'it_engineer', 'subject', 'dropbox',
      'title', 'Backup retention could not remove ' || x.n || ' Dropbox copy(ies) of the ' || x.dy || ' export',
      'blast', 'agent_facing', 'affected', x.n, 'evidence', jsonb_build_object('last_error', x.err));
  end loop;
  v_settle := public.fn_it_duty_settle('backup_prune', v_items);

  return jsonb_build_object('mode', v_mode, 'pass', v_pass,
    'storage_pending', case when v_mode = 'delete' then (select count(*) from public.backup_prune_log l
                          where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null) else 0 end,
    'dropbox_pending', case when v_mode = 'delete' then (select count(*) from public.doc_backups b
                          where b.status = 'prune_pending' and b.prune_attempts < 5) else 0 end,
    'findings', v_settle->'failing');
end $fn$;
revoke execute on function public.fn_backup_prune_tick() from public, anon, authenticated;

-- fn_backup_prune_storage_next: the MANIFEST-last body with ONE change, the names it hands over.
create or replace function public.fn_backup_prune_storage_next()
returns jsonb
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_log public.backup_prune_log; v_cancelled integer; v_names text[];
begin
  if public.fn_backup_prune_mode() <> 'delete' then return jsonb_build_object('log_id', null, 'reason', 'dry run'); end if;
  v_cancelled := public.fn_backup_prune_recheck();
  select * into v_log from public.backup_prune_log l
   where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null and l.storage_attempts < 3
   order by l.day limit 1 for update skip locked;
  if not found then return jsonb_build_object('log_id', null, 'cancelled', v_cancelled); end if;
  select coalesce(array_agg(o.name order by o.name), '{}') into v_names
    from (select o2.name from storage.objects o2
           where o2.bucket_id = 'backups' and o2.name like to_char(v_log.day, 'YYYY-MM-DD') || '/%'
             and public.fn_backup_prune_path_allowed(o2.bucket_id, o2.name)
             -- 15 Sep 2026 (the guard): only a file whose Dropbox copy was uploaded AND verified. A file
             -- without one stays, and fn_backup_prune_storage_done counts it as left, so the day is never
             -- marked deleted and its Dropbox half never starts.
             and exists (select 1 from public.doc_backups d
                          where d.bucket = o2.bucket_id and d.path = o2.name
                            and d.status = 'done' and d.verified_at is not null)
           order by o2.name limit 1000) o;
  return jsonb_build_object('log_id', v_log.id, 'day', v_log.day, 'names', to_jsonb(v_names));
end $fn$;
revoke execute on function public.fn_backup_prune_storage_next() from public, anon, authenticated;

-- fn_doc_backups_prune_next: the MANIFEST-last body with ONE change, what it may claim.
create or replace function public.fn_doc_backups_prune_next(p_limit integer default 25, p_run text default null)
returns setof public.doc_backups
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_run), '') = '' then raise exception 'fn_doc_backups_prune_next: p_run (the claiming run id) is required'; end if;
  if public.fn_backup_prune_mode() <> 'delete' then return; end if;
  -- the rules again, before a single Dropbox path is handed over; a cancelled day's rows revert here
  perform public.fn_backup_prune_recheck();
  update public.doc_backups d set status = 'prune_pending', claimed_at = null, claimed_by = null
   where d.status = 'pruning' and d.claimed_at < now() - interval '10 minutes';
  return query
    with c as (
      select d.id from public.doc_backups d
       where d.status = 'prune_pending' and d.prune_attempts < 5
         and public.fn_backup_prune_dropbox_allowed(d.bucket, d.path, d.dedupe_key, d.doc_type, d.dropbox_path)
         -- 15 Sep 2026 (the guard): a Dropbox copy is claimed for deletion only once its day's storage
         -- deletion finished, and only a copy that was verified when it was uploaded
         and d.verified_at is not null
         and exists (select 1 from public.backup_prune_log bl
                      where bl.mode = 'delete' and bl.cancelled_at is null and bl.storage_deleted_at is not null
                        and d.dedupe_key like 'EXPORT:' || to_char(bl.day, 'YYYY-MM-DD') || '/%')
         and (d.last_attempt_at is null or d.prune_attempts = 0
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.prune_attempts, 8)))
       order by d.id limit greatest(1, least(coalesce(p_limit, 25), 25))
       for update skip locked)
    update public.doc_backups d set status = 'pruning', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $fn$;
revoke execute on function public.fn_doc_backups_prune_next(integer, text) from public, anon, authenticated;

-- ── PROBE: pure reads, writes nothing. The fixture probe is
-- scripts/checks/no_export_is_pruned_without_a_verified_copy.probe.sql. ──
do $probe$
declare v_left int; v_gb numeric; v_open int;
begin
  select count(*), round(coalesce(sum((o.metadata->>'size')::bigint), 0) / 1073741824.0, 2) into v_left, v_gb
    from storage.objects o
   where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/' and split_part(o.name, '/', 1) <= '2026-09-07'
     and not exists (select 1 from public.table_export_run r where r.stamp::text = split_part(o.name, '/', 1))
     and not exists (select 1 from public.doc_backups d where d.bucket = 'backups' and d.path = o.name);
  select count(*) into v_open from public.backup_prune_log l where l.mode = 'delete' and l.cancelled_at is null;
  raise notice 'legacy exports not yet queued: % file(s), % GiB; queued at most 200 waiting at a time. Open delete-mode retention days: %', v_left, v_gb, v_open;
end $probe$;
