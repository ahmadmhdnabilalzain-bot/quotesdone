-- EVERY STORED DOCUMENT SOURCE IS REGISTERED FOR BACKUP, OR REGISTERED AS NOT BACKED UP WITH A REASON.
--
-- Assigned: it_engineer. 14 Sep 2026.
--
-- The founder, 14 Sep 2026: "we need to eliminate all other causes with fixes" (founder_instruction
-- 208). A document source nobody listed is a document nobody backs up, and nothing notices, because
-- the IT engineer's expected list (fn_it_backup_expected) was written from memory: four bucket names
-- typed into its WHERE clause.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production): 49 base-table columns named *_path / *_paths
-- and 16 storage buckets. Five buckets and 15 columns feed fn_enqueue_doc_backups. The rest are
-- either not documents to keep (the Dropbox destination itself, the erasure ledger, redacted copies,
-- repository paths, regenerated reports, mailbox receipts) or documents that are NOT yet in the
-- Dropbox tree. Those are registered as 'OPEN GAP: ...' so the gap is written down, not hidden:
-- quote files (quote-files: 2 objects), compliance-docs (419 objects), message attachments, call
-- recordings, supplier dues letters, refund documents, support/WhatsApp intake, RFQ archives.
--
-- WHAT CHANGES:
--   fn_backup_source_registry() is the one list: every column and every bucket, backed up (with the
--   enqueue section that files it) or not (with the reason). It lives in the schema, so the CI check
--   scripts/checks/every_storage_path_is_in_the_backup_registry.test.mjs reads it from the committed
--   schema mirror and fails when a new *_path column or bucket appears unregistered, or a backed-up
--   source has no enqueue rule. fn_it_backup_expected (the IT engineer's independent expected list)
--   now takes its buckets from the same registry.
--
-- 14 SEP 2026, it_engineer (the daily table export restored): the registry names the dated export
-- files in the backups bucket as a source of their own, and fn_it_backup_expected expects every day's
-- export from the first day the revived writer ran: that day's _manifest.json, page_0000 of every table
-- in fn_table_export_list(), and every page actually written. A missed or failed day therefore leaves
-- expected items that never reach Dropbox, which the IT engineer's backup watch reports. This file
-- reads public.table_export_run in a SQL-language body, so it is applied AFTER
-- every_business_table_is_exported_every_day_again.sql.
--
-- 15 SEP 2026, it_engineer (backup retention): an export day whose files the retention pass removed
-- (table_export_run.pruned_at, the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql) is no
-- longer expected, so pruning never reads as a missing backup. That file adds the column, so it is
-- applied BEFORE this one.
--
-- 14 SEP 2026, accountant (review of #659): fn_it_backup_expected also expects the accountant's files that
-- fn_enqueue_doc_backups: ACCOUNTING files - the month close, the Mashreq statements, the issued documents
-- and the year-end pack - so the backup loop verifies each one reached Dropbox. This file stays the ONE
-- definition; it is applied AFTER the_accountant_files_the_year_end_pack_in_dropbox_and_the_backups_bucket.sql,
-- because a SQL-language body is checked when it is created and reads accountant_year_end_pack.
--
-- 15 SEP 2026, it_engineer (every stored file reaches Dropbox). The founder: "of course that data should
-- never get lost no matter what". MEASURED (production, read-only): the backup_gap duty had 51 open
-- findings because it raised every row below with backed_up = false, the reasoned exemptions included;
-- and several exemptions were not true -- doc_reviews.file_path (7 files in supplier-docs/inbound/, 0
-- queued), the brand kit and the signature and stamp images and compliance-docs/uae_library (not in the
-- repository: git ls-files), board_reports/exec_reports (not in fn_table_export_list(), so their PDFs had
-- no off-site copy at all). Every source is now one of three things:
--   (a) BACKED UP -- by an owner rule of fn_enqueue_doc_backups, or by its STORAGE SWEEP: every file in a
--       swept bucket that no owner rule filed. fn_backup_sweep_objects() below is the ONE list of what
--       the sweep offers (the enqueue files it; fn_it_backup_expected expects it; the backup_gap duty
--       counts what it has not yet queued). Every OPEN GAP is closed this way: the files sit in a swept
--       bucket. A column with no writer today is registered with a null bucket: its files will sit in
--       whichever bucket its writer uses, every bucket must be registered (the CI check), and a swept
--       bucket's unqueued files are raised by the duty.
--   (b) EXEMPT (not a file or not ours) -- a destination, a ledger, a path label, a fixture.
--   (c) EXEMPT (derived) -- a copy made from a file that is itself backed up. None is left: the anonymised
--       drawings looked like one, but 2 of the 3 files in drawing-files/redacted/ have no original left
--       (measured in review, 15 Sep 2026), so "the original is kept" was not safe and they are swept too.
-- The backup_gap duty raises a source that is not backed up and not EXEMPT; the exemptions close.
-- PDPL (review of this change): a swept file carries its REAL owner -- the documents row or the
-- customer's quotation cache that names it, the quote that names it, or the lead / inquiry id in its
-- path -- so fn_pdpl_redact, which collects doc_backups rows by customer, inquiry and quote, finds the
-- sweep's copies too; and a file whose owning customer is erased or has a delete request is never swept.
-- Applied BEFORE every_stored_file_reaches_dropbox_and_the_backup_gap_duty_raises_only_real_gaps.sql,
-- which calls fn_backup_sweep_objects from fn_enqueue_doc_backups and from the duty.
--
--   node scripts/apply_sql.mjs scripts/sql/every_stored_document_source_is_registered_for_backup.sql --apply --ddl

create or replace function public.fn_backup_source_registry()
returns table(source text, kind text, bucket text, backed_up boolean, enqueue_rule text, reason text)
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  values
    -- ── (a) backed up by an owner rule: each names the fn_enqueue_doc_backups section that files it ──
    ('leads.license_doc_path',               'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.iban_doc_path',                  'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.egr_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.insurance_doc_path',             'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.vat_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.iso_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.manufacturer_auth_doc_path',     'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.company_profile_doc_path',       'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.catalog_doc_paths',              'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS (catalogue)', null),
    ('leads.signed_terms_path',              'column', 'signed-terms',  true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('customers.signed_terms_path',          'column', 'signed-terms',  true,  'fn_enqueue_doc_backups: CUSTOMERS', null),
    ('inquiries.drawing_file_path',          'column', 'drawing-files', true,  'fn_enqueue_doc_backups: INQUIRIES', null),
    ('transactions.doc_path',                'column', 'finance-docs',  true,  'fn_enqueue_doc_backups: REVENUE INVOICES', null),
    ('conversation_archive.pdf_path',        'column', 'backups',       true,  'fn_enqueue_doc_backups: CORRESPONDENCE', null),
    ('backups/<YYYY-MM-DD>/<table>/page_NNNN.json', 'export', 'backups', true, 'fn_enqueue_doc_backups: TABLE EXPORTS (written daily by supabase/functions/backup; the tables are fn_table_export_list()); kept 90 days, Friday full copies 12 months (fn_backup_prune_tick)', null),
    -- The accountant's four (open gaps until 14 Sep 2026, closed by
    -- the_accountant_files_the_year_end_pack_in_dropbox_and_the_backups_bucket.sql). A path stored as
    -- '<bucket>/<path>' names its bucket itself, so the bucket column is null for those two.
    ('accountant_month_close.pdf_path',      'column', 'finance-reports', true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('accountant_month_close.csv_path',      'column', 'finance-reports', true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('accountant_issued_document.file_path', 'column', null,              true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('bank_statement_intake.doc_path',       'column', null,              true, 'fn_enqueue_doc_backups: ACCOUNTING', null),

    -- ── (a) the buckets: every file an owner rule did not file is filed by the STORAGE SWEEP ──
    ('supplier-docs',    'bucket', 'supplier-docs',    true, 'fn_enqueue_doc_backups: SUPPLIERS; STORAGE SWEEP for every other file (inbound/, legal/, catalog/ ...)', null),
    ('signed-terms',     'bucket', 'signed-terms',     true, 'fn_enqueue_doc_backups: SUPPLIERS, CUSTOMERS; STORAGE SWEEP for every other signed record', null),
    ('drawing-files',    'bucket', 'drawing-files',    true, 'fn_enqueue_doc_backups: INQUIRIES; STORAGE SWEEP for every other file, the anonymised redacted/ copies included', null),
    ('finance-docs',     'bucket', 'finance-docs',     true, 'fn_enqueue_doc_backups: REVENUE INVOICES; STORAGE SWEEP for every other file', null),
    ('backups',          'bucket', 'backups',          true, 'fn_enqueue_doc_backups: CORRESPONDENCE, ACCOUNTING (the year-end pack in backups/accountant/year-end/), TABLE EXPORTS; dropbox_backup renders generated documents into backups/generated/; STORAGE SWEEP for everything outside the dated export folders, conversations/ and generated/ (archives/, engineering/, imports/ ...)', null),
    ('quote-files',      'bucket', 'quote-files',      true, 'fn_enqueue_doc_backups: STORAGE SWEEP (suppliers'' quotation files and the regenerated quotations)', null),
    ('compliance-docs',  'bucket', 'compliance-docs',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (compliance sources as downloaded, the UAE library)', null),
    ('receipt-files',    'bucket', 'receipt-files',    true, 'fn_enqueue_doc_backups: ACCOUNTING (bank statements); STORAGE SWEEP for the expense receipts (the inbound mailbox keeps about a month)', null),
    ('agent-docs',       'bucket', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (quotations and invoices as sent, weekly reports, incident PDFs)', null),
    ('finance-reports',  'bucket', 'finance-reports',  true, 'fn_enqueue_doc_backups: ACCOUNTING (month close); STORAGE SWEEP for every other report and legal notice', null),
    ('reports',          'bucket', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (board and executive report PDFs; their rows are not in the daily table export)', null),
    ('social-media',     'bucket', 'social-media',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (generated post cards and avatars; not in the repository)', null),
    ('brand',            'bucket', 'brand',            true, 'fn_enqueue_doc_backups: STORAGE SWEEP (brand kit, signature and stamp images; not in the repository)', null),
    ('kb-import-assets', 'bucket', 'kb-import-assets', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (knowledge import runs; only part of it is in the repository)', null),
    ('site',             'bucket', 'site',             true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the static website pages as first published)', null),

    -- ── (a) columns whose files are filed by the STORAGE SWEEP of the bucket they sit in ──
    -- measured 15 Sep 2026 where rows exist; "no writer today" where no code writes the column yet
    ('quotes.original_file_path',            'column', 'quote-files',      true, 'fn_enqueue_doc_backups: STORAGE SWEEP (written by supplier_api)', null),
    ('quote_spec_hold.pdf_path',             'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket in quote_spec_hold.pdf_bucket; the regenerated quotations sit in quote-files)', null),
    ('quote_reviews.original_file_path',     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('quote_committed_items.sub_quote_path', 'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('quote_items.datasheet_path',           'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('rfq_archives.archive_path',            'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket in rfq_archives.bucket; backups/archives/ is swept)', null),
    ('compliance_sources.doc_path',          'column', 'compliance-docs',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (16 of 16 paths in compliance-docs)', null),
    ('support_artifact.storage_path',        'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('support_document_intake.storage_path', 'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the path is the one written into leads.*_doc_path)', null),
    ('wa_document_intake.storage_path',      'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the path is the one written into leads.*_doc_path)', null),
    ('messages.attachment_path',             'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket chosen by the portal, recorded in public.documents)', null),
    ('customer_calls.recording_path',        'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('refunds.doc_path',                     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('supplier_dues.demand_letter_path',     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today; the legal notices on file sit in supplier-docs/legal/ and finance-reports/legal/)', null),
    ('supplier_dues.case_file_path',         'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('supplier_dues.evidence_terms_path',    'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('expense_entries.doc_path',             'column', 'receipt-files',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (52 of 52 paths in receipt-files; the inbound mailbox keeps about a month)', null),
    ('doc_reviews.file_path',                'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (7 of 7 paths in supplier-docs/inbound/, none filed by an owner rule)', null),
    ('supplier_catalog.source_document_path','column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (written by supplier_catalog_ingest into supplier-docs/catalog/)', null),
    ('drawing_redaction_runs.source_path',   'column', 'drawing-files',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the customer''s original drawing; also INQUIRIES)', null),
    ('accountant_weekly_report.pdf_path',    'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/accountant/weekly/)', null),
    ('accountant_spend_report.pdf_path',     'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (finance-reports/accountant/spend/)', null),
    ('finance_reports.html_path',            'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('finance_reports.xlsx_path',            'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('finance_reports.pdf_path',             'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('board_reports.pdf_path',               'column', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (20 of 20 paths in reports)', null),
    ('exec_reports.pdf_path',                'column', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (2 of 2 paths in reports)', null),
    ('it_incident.pdf_path',                 'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs/it_engineer/incidents/)', null),

    -- ── (b) EXEMPT (not a file or not ours) ──
    ('doc_backups.dropbox_path',             'column', null, false, null, 'EXEMPT (not a file or not ours): the Dropbox destination of a backup, not a source'),
    ('pdpl_erase_files.storage_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): the PDPL erasure ledger names files being REMOVED under a data subject''s request; fn_backup_sweep_objects never offers a file it names, so an erased file is never copied again'),
    ('pdpl_erase_files.dropbox_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): the PDPL erasure ledger names Dropbox copies being REMOVED; never a source'),
    -- The knowledge source paths are LABELS: none of the sampled paths exists as a storage object or in
    -- the repository (review, 15 Sep 2026). The knowledge is the table rows, which the daily table export
    -- (fn_table_export_list) carries to Dropbox.
    ('support_knowledge.source_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('ops_knowledge.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('ceo_knowledge.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('demo-assets',                          'bucket', null, false, null, 'EXEMPT (not a file or not ours): a rehearsal fixture (one sample recording), never a record'),

    -- ── (c) EXEMPT (derived): none. The anonymised drawings are derived, but 2 of the 3 redacted files
    -- have no original left (review, 15 Sep 2026), so they are kept like any other stored file. ──
    ('inquiries.drawing_redacted_paths',     'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null),
    ('drawing_redaction_runs.output_paths',  'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null)
$fn$;
revoke execute on function public.fn_backup_source_registry() from public, anon, authenticated;

-- ── fn_backup_sweep_objects: what the STORAGE SWEEP offers, written ONCE (15 Sep 2026) ──────────────
-- Every object in a bucket whose registry rule says STORAGE SWEEP, with its REAL owner, most specific
-- first: the documents row that names it (ref_table customers / inquiries / quotes / leads), the
-- customer's quotation cache (quote_pdf_cache), the quote whose original_file_path it is, then the path
-- conventions -- '<prefix>/<lead id>/' in supplier-docs, '<prefix>/<inquiry id>/' in drawing-files,
-- 'quotes/<n>/<inquiry id>/' in quote-files -- and otherwise the company. fn_pdpl_redact collects
-- doc_backups rows by customer, inquiry and quote id, so a copy the sweep made is found by an erasure.
-- Left out:
--   * a ZZ DEMO file (the pattern trg_doc_backups_admit refuses), and a file whose owner is a demo
--     supplier or belongs to a demo customer -- so the expected list never expects what admission refuses;
--   * the backups bucket's dated export folders and conversations/ -- each has its own rule (retention
--     for the exports; demo conversations are never archived) and its own branch in fn_it_backup_expected;
--   * PDPL: any file named in pdpl_erase_files, and any file whose owning customer is erased
--     ('@removed.invalid') or has a delete request that was not rejected -- never copied again.
-- The casts sit inside CASE, which Postgres evaluates in order: a path segment that is not a number or a
-- uuid never reaches ::bigint / ::uuid (review of this change: 13 supplier-docs paths have a word there).
-- It does not read doc_backups: the enqueue and the duty subtract what is already queued, and the
-- expected list stays independent of the queue it checks.
create or replace function public.fn_backup_sweep_objects()
returns table(bucket text, path text, bytes bigint, created_at timestamptz, entity text, entity_id text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select o.bucket_id, o.name, coalesce((o.metadata->>'size')::bigint, 0), o.created_at,
         split_part(x.owner, ':', 1), substr(x.owner, strpos(x.owner, ':') + 1)
    from storage.objects o
    cross join lateral (select
        case when split_part(o.name, '/', 2) ~ '^\d{1,18}$' then split_part(o.name, '/', 2)::bigint end as seg2_int,
        case when split_part(o.name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             then split_part(o.name, '/', 2)::uuid end as seg2_uuid,
        case when split_part(o.name, '/', 3) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             then split_part(o.name, '/', 3)::uuid end as seg3_uuid) p
    cross join lateral (select coalesce(
        (select case d.ref_table when 'customers' then 'customer' when 'inquiries' then 'inquiry'
                                 when 'quotes' then 'quote' when 'leads' then 'supplier' end || ':' || d.ref_id
           from public.documents d
          where d.bucket = o.bucket_id and d.path = o.name
            and d.ref_table in ('customers', 'inquiries', 'quotes', 'leads') and coalesce(d.ref_id, '') <> '' limit 1),
        (select 'customer:' || c.customer_id from public.quote_pdf_cache c
          where c.bucket = o.bucket_id and c.path = o.name and c.customer_id is not null limit 1),
        (select 'quote:' || q.id from public.quotes q where o.bucket_id = 'quote-files' and q.original_file_path = o.name limit 1),
        (select 'supplier:' || l.id from public.leads l where o.bucket_id = 'supplier-docs' and l.id = p.seg2_int),
        (select 'inquiry:' || i.id from public.inquiries i where o.bucket_id = 'drawing-files' and i.id = p.seg2_uuid),
        (select 'inquiry:' || i.id from public.inquiries i where o.bucket_id = 'quote-files' and i.id = p.seg3_uuid),
        'company:storage/' || o.bucket_id) as owner) x
    -- the supplier and the customer behind that owner, for the demo and PDPL tests
    left join lateral (select
        case split_part(x.owner, ':', 1)
          when 'supplier' then (select l.id from public.leads l where l.id::text = substr(x.owner, 10))
          when 'quote'    then (select q.supplier_id from public.quotes q where q.id::text = substr(x.owner, 7)) end as supplier_id,
        case split_part(x.owner, ':', 1)
          when 'customer' then (select c.id from public.customers c where c.id::text = substr(x.owner, 10))
          when 'inquiry'  then (select i.customer_id from public.inquiries i where i.id::text = substr(x.owner, 9))
          when 'quote'    then (select i.customer_id from public.quotes q join public.inquiries i on i.id = q.inquiry_id
                                 where q.id::text = substr(x.owner, 7)) end as customer_id) w on true
    left join public.leads ol on ol.id = w.supplier_id
    left join public.customers oc on oc.id = w.customer_id
   where o.bucket_id in (select r.bucket from public.fn_backup_source_registry() r
                          where r.kind = 'bucket' and r.backed_up and r.enqueue_rule like '%STORAGE SWEEP%')
     and right(o.name, 1) <> '/' and o.name !~ '(^|/)\.emptyFolderPlaceholder$'
     and o.name !~* 'zz[ _-]?demo'
     and not (o.bucket_id = 'backups' and o.name ~ '^(\d{4}-\d{2}-\d{2}|conversations)/')
     and not coalesce(ol.is_demo, false)
     and not coalesce(oc.is_demo, false)
     and not exists (select 1 from public.pdpl_erase_files e where e.bucket = o.bucket_id and e.storage_path = o.name)
     and not (oc.id is not null and (coalesce(oc.email, '') ~* '@removed\.invalid$'
              or exists (select 1 from public.pdpl_requests r where r.kind = 'delete' and r.status is distinct from 'rejected'
                           and lower(r.email) = lower(oc.email))));
$fn$;
revoke execute on function public.fn_backup_sweep_objects() from public, anon, authenticated;

-- fn_it_backup_expected: the MANIFEST-last definition (the_it_engineer_knows_what_should_be_backed_up_
-- and_closes_the_loop.sql, after the review of #628) with ONE change: the buckets come from the registry.
-- 15 Sep 2026: every file the STORAGE SWEEP offers is expected too, unless another branch already
-- expects it under its real owner.
create or replace function public.fn_it_backup_expected()
returns table(item_key text, kind text, bucket text, path text, gen_kind text, gen_ref text, owner text, since timestamptz)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with rl as (select * from public.leads where not coalesce(is_demo, false)),
       rc as (select * from public.customers where not coalesce(is_demo, false)),
       ri as (select i.* from public.inquiries i join rc on rc.id = i.customer_id),
  base as (
  select 'obj:' || o.bucket_id || ':' || o.name as item_key, 'storage' as kind, o.bucket_id as bucket, o.name as path,
         null::text as gen_kind, null::text as gen_ref, x.owner, o.created_at as since
    from storage.objects o
    cross join lateral (select case
      when o.bucket_id = 'supplier-docs' then (select 'supplier:' || l.id from rl l
             where l.id::text = split_part(o.name, '/', 2)
                or o.name in (l.license_doc_path, l.iban_doc_path, l.egr_doc_path, l.insurance_doc_path, l.vat_doc_path,
                              l.iso_doc_path, l.manufacturer_auth_doc_path, l.company_profile_doc_path)
                or o.name = any(coalesce(l.catalog_doc_paths, '{}')) limit 1)
      when o.bucket_id = 'signed-terms' then coalesce(
             (select 'customer:' || c.id from rc c where c.signed_terms_path = o.name limit 1),
             (select 'supplier:' || l.id from rl l where l.signed_terms_path = o.name limit 1))
      when o.bucket_id = 'drawing-files' then (select 'inquiry:' || i.id from ri i
             where i.id::text = split_part(o.name, '/', 2) or i.drawing_file_path = o.name limit 1)
      when o.bucket_id = 'finance-docs' then (select 'transaction:' || t.id from public.transactions t where t.doc_path = o.name limit 1)
    end as owner) x
   where o.bucket_id in (select r.bucket from public.fn_backup_source_registry() r where r.kind = 'bucket' and r.backed_up)
     and x.owner is not null and o.name !~* 'zz[_ -]?demo'
  union all
  -- a Stripe invoice the transaction names but storage no longer holds is still expected
  select 'obj:finance-docs:' || t.doc_path, 'invoice', 'finance-docs', t.doc_path, null, null, 'transaction:' || t.id, t.revealed_at
    from public.transactions t
    -- transactions carries no is_demo of its own: a sale is demo when either party is (review of
    -- #628). Without this, a purged demo invoice would read never_queued forever and escalate.
    left join public.customers tc on tc.id = t.customer_id
    left join public.leads tl on tl.id = t.supplier_id
   where t.doc_path is not null
     and not coalesce(tc.is_demo, false) and not coalesce(tl.is_demo, false)
     and coalesce(tc.email, '') !~* 'example\.invalid' and coalesce(tl.email, '') !~* 'example\.invalid'
     and not exists (select 1 from storage.objects o where o.bucket_id = 'finance-docs' and o.name = t.doc_path)
  union all
  select 'msg:' || m.source_table || ':' || m.source_id, 'conversation', c.pdf_bucket, c.pdf_path, null, null,
         coalesce(m.party_kind || ':' || m.party_id, 'company'), m.occurred_at
    from public.v_conversation_message m
    left join public.conversation_archive c on c.source_table = m.source_table and c.source_id = m.source_id
   where not m.is_demo
  union all
  select 'gen:supplier_details:' || l.id, 'generated', null, null, 'supplier_details', l.id::text, 'supplier:' || l.id, l.created_at
    from rl l
   where l.approved_at is not null or l.registration_submitted_at is not null or l.signed_terms_path is not null
      or l.company_profile_doc_path is not null or l.license_doc_path is not null or coalesce(l.claimed, false)
  union all
  select 'gen:customer_details:' || c.id, 'generated', null, null, 'customer_details', c.id::text, 'customer:' || c.id, c.created_at from rc c
  union all
  select 'gen:inquiry_summary:' || i.id, 'generated', null, null, 'inquiry_summary', i.id::text, 'inquiry:' || i.id, i.created_at from ri i
  union all
  -- ── ACCOUNTING (14 Sep 2026, accountant duty 4): what fn_enqueue_doc_backups files under Finance ──
  select 'obj:' || c.pdf_bucket || ':' || v.path, 'storage', c.pdf_bucket, v.path, null, null,
         'finance:close:' || to_char(c.month, 'YYYY-MM'), c.rendered_at
    from public.accountant_month_close c cross join lateral (values (c.pdf_path), (c.csv_path)) v(path)
   where c.rendered_at is not null and c.pdf_bucket is not null and length(coalesce(v.path, '')) > 0
  union all
  select 'obj:' || split_part(b.doc_path, '/', 1) || ':' || substr(b.doc_path, strpos(b.doc_path, '/') + 1), 'storage',
         split_part(b.doc_path, '/', 1), substr(b.doc_path, strpos(b.doc_path, '/') + 1), null, null,
         'finance:bank_statement:' || b.source_ref, b.received_at
    from public.bank_statement_intake b
   where b.doc_path ~ '^[a-z0-9-]+/.+' and b.account <> 'zz_demo'
  union all
  select 'obj:' || split_part(d.file_path, '/', 1) || ':' || substr(d.file_path, strpos(d.file_path, '/') + 1), 'storage',
         split_part(d.file_path, '/', 1), substr(d.file_path, strpos(d.file_path, '/') + 1), null, null,
         'finance:issued:' || d.id, d.issued_at
    from public.accountant_issued_document d
   where d.file_path ~ '^[a-z0-9-]+/.+' and d.recipient !~* 'example\.invalid'
  union all
  select 'obj:' || (f->>'bucket') || ':' || (f->>'path'), 'storage', f->>'bucket', f->>'path', null, null,
         'finance:year_end:' || p.year, p.rendered_at
    from public.accountant_year_end_pack p cross join lateral jsonb_array_elements(p.files) f
   where p.rendered_at is not null and (f->>'path') !~* 'zz[_ -]?demo'
  union all
  -- ── TABLE EXPORTS (14 Sep 2026): each Asia/Dubai day from the first the revived writer ran ──
  -- due from 03:00 Dubai that day; the expected-status grace then decides when a gap is a finding
  select 'obj:backups:' || f.path, 'storage', 'backups', f.path, null, null,
         'company:table_export:' || to_char(d.day, 'YYYY-MM-DD'), (d.day::date + time '03:00') at time zone 'Asia/Dubai'
    from generate_series((select min(r.stamp) from public.table_export_run r),
                         (now() at time zone 'Asia/Dubai')::date, interval '1 day') d(day)
    -- a day removed under the retention rules is no longer expected (15 Sep 2026)
    join lateral (select not exists (select 1 from public.table_export_run pr
                                      where pr.stamp = d.day::date and pr.pruned_at is not null) as kept) k on k.kept
    cross join lateral (
      select to_char(d.day, 'YYYY-MM-DD') || '/_manifest.json' as path
      union select to_char(d.day, 'YYYY-MM-DD') || '/' || x.table_name || '/page_0000.json' from public.fn_table_export_list() x
      union select o.name from storage.objects o where o.bucket_id = 'backups' and o.name like to_char(d.day, 'YYYY-MM-DD') || '/%') f
  )
  select * from base
  union all
  -- ── STORAGE SWEEP (15 Sep 2026): every other stored file the registry sweeps ──
  select 'obj:' || s.bucket || ':' || s.path, 'storage', s.bucket, s.path, null, null, s.entity || ':' || s.entity_id, s.created_at
    from public.fn_backup_sweep_objects() s
   where not exists (select 1 from base b where b.item_key = 'obj:' || s.bucket || ':' || s.path);
$fn$;
revoke execute on function public.fn_it_backup_expected() from public, anon, authenticated;

-- ── PROBE: the registry covers what production holds today ─────────────────────────────────────────
do $probe$
declare v_cols text; v_buckets text; v_rules int; v_class text;
begin
  select string_agg(c.table_name || '.' || c.column_name, ', ') into v_cols
    from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
   where c.table_schema = 'public' and c.column_name ~ '(_path|_paths)$'
     and not exists (select 1 from public.fn_backup_source_registry() r where r.kind = 'column' and r.source = c.table_name || '.' || c.column_name);
  select string_agg(b.id, ', ') into v_buckets from storage.buckets b
   where not exists (select 1 from public.fn_backup_source_registry() r where r.kind = 'bucket' and r.source = b.id);
  select count(*) into v_rules from public.fn_backup_source_registry() r
   where (r.backed_up and coalesce(r.enqueue_rule, '') = '') or (not r.backed_up and coalesce(r.reason, '') = '');
  select string_agg(r.source, ', ') into v_class from public.fn_backup_source_registry() r
   where not r.backed_up and r.reason !~ '^(OPEN GAP|EXEMPT \((not a file or not ours|derived)\)): ';
  assert v_cols is null, 'unregistered path columns: ' || v_cols;
  assert v_buckets is null, 'unregistered buckets: ' || v_buckets;
  assert v_rules = 0, 'a registry row has neither an enqueue rule nor a reason';
  assert v_class is null, 'a source not backed up is neither an OPEN GAP nor a classified EXEMPT: ' || v_class;
  raise notice 'registry: % sources (% backed up, % open gaps, % exempt); sweep offers % files; expected items now %',
    (select count(*) from public.fn_backup_source_registry()),
    (select count(*) from public.fn_backup_source_registry() where backed_up),
    (select count(*) from public.fn_backup_source_registry() where reason like 'OPEN GAP%'),
    (select count(*) from public.fn_backup_source_registry() where reason like 'EXEMPT%'),
    (select count(*) from public.fn_backup_sweep_objects()),
    (select count(*) from public.fn_it_backup_expected());
end $probe$;
