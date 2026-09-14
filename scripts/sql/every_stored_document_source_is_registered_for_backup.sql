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
--   node scripts/apply_sql.mjs scripts/sql/every_stored_document_source_is_registered_for_backup.sql --apply --ddl

create or replace function public.fn_backup_source_registry()
returns table(source text, kind text, bucket text, backed_up boolean, enqueue_rule text, reason text)
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  values
    -- ── backed up: each names the fn_enqueue_doc_backups section that files it ──
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
    ('supplier-docs',                        'bucket', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('signed-terms',                         'bucket', 'signed-terms',  true,  'fn_enqueue_doc_backups: SUPPLIERS, CUSTOMERS', null),
    ('drawing-files',                        'bucket', 'drawing-files', true,  'fn_enqueue_doc_backups: INQUIRIES', null),
    ('finance-docs',                         'bucket', 'finance-docs',  true,  'fn_enqueue_doc_backups: REVENUE INVOICES', null),
    ('backups',                              'bucket', 'backups',       true,  'fn_enqueue_doc_backups: CORRESPONDENCE; dropbox_backup renders generated documents into backups/generated/', null),
    -- ── not a document to keep ──
    ('doc_backups.dropbox_path',             'column', null, false, null, 'the Dropbox destination of a backup, not a source'),
    ('pdpl_erase_files.storage_path',        'column', null, false, null, 'the PDPL erasure ledger: names files being removed, never a document to keep'),
    ('pdpl_erase_files.dropbox_path',        'column', null, false, null, 'the PDPL erasure ledger: names files being removed, never a document to keep'),
    ('inquiries.drawing_redacted_paths',     'column', null, false, null, 'anonymised copies made from the customer''s drawing; the original (inquiries.drawing_file_path) is backed up'),
    ('drawing_redaction_runs.source_path',   'column', null, false, null, 'the customer''s drawing, backed up through inquiries.drawing_file_path'),
    ('drawing_redaction_runs.output_paths',  'column', null, false, null, 'anonymised copies made from the customer''s drawing; the original is backed up'),
    ('supplier_catalog.source_document_path','column', null, false, null, 'the supplier''s catalogue upload, backed up through leads.catalog_doc_paths'),
    ('doc_reviews.file_path',                'column', null, false, null, 'a review of a supplier document that is backed up through leads.*_doc_path'),
    ('support_knowledge.source_path',        'column', null, false, null, 'a repository path of a knowledge source, not a storage object; the repository is its backup'),
    ('ops_knowledge.source_path',            'column', null, false, null, 'a repository path of a knowledge source, not a storage object; the repository is its backup'),
    ('ceo_knowledge.source_path',            'column', null, false, null, 'a repository path of a knowledge source, not a storage object; the repository is its backup'),
    ('board_reports.pdf_path',               'column', null, false, null, 'a report generated from the database, regenerated on demand'),
    ('exec_reports.pdf_path',                'column', null, false, null, 'a report generated from the database, regenerated on demand'),
    ('finance_reports.html_path',            'column', null, false, null, 'a report generated from the database, regenerated on demand'),
    ('finance_reports.xlsx_path',            'column', null, false, null, 'a report generated from the database, regenerated on demand'),
    ('finance_reports.pdf_path',             'column', null, false, null, 'a report generated from the database, regenerated on demand'),
    ('accountant_weekly_report.pdf_path',    'column', null, false, null, 'a report generated from the database, regenerated on demand'),
    ('accountant_spend_report.pdf_path',     'column', null, false, null, 'a report generated from the database, regenerated on demand'),
    ('expense_entries.doc_path',             'column', null, false, null, 'an expense receipt; the source of truth is the expenses mailbox, whose folders are the durable record'),
    ('site',                                 'bucket', null, false, null, 'public website assets; their source is the repository'),
    ('brand',                                'bucket', null, false, null, 'public brand assets; their source is the repository'),
    ('social-media',                         'bucket', null, false, null, 'published social posts; their source is the repository and the platforms'),
    ('demo-assets',                          'bucket', null, false, null, 'rehearsal fixtures, never kept'),
    ('agent-docs',                           'bucket', null, false, null, 'documents generated from the database, regenerated on demand'),
    ('reports',                              'bucket', null, false, null, 'documents generated from the database, regenerated on demand'),
    ('finance-reports',                      'bucket', null, false, null, 'documents generated from the database, regenerated on demand'),
    ('kb-import-assets',                     'bucket', null, false, null, 'knowledge import assets; the source packs are in the repository'),
    ('receipt-files',                        'bucket', null, false, null, 'expense receipts; the source of truth is the expenses mailbox'),
    -- ── OPEN GAPS: documents that are kept in Supabase storage only (14 Sep 2026) ──
    ('quotes.original_file_path',            'column', null, false, null, 'OPEN GAP: a supplier''s quotation file is not yet in the Dropbox tree'),
    ('quote_reviews.original_file_path',     'column', null, false, null, 'OPEN GAP: a supplier''s quotation file is not yet in the Dropbox tree'),
    ('quote_committed_items.sub_quote_path', 'column', null, false, null, 'OPEN GAP: a committed sub-quote file is not yet in the Dropbox tree'),
    ('quote_items.datasheet_path',           'column', null, false, null, 'OPEN GAP: a quoted item''s datasheet is not yet in the Dropbox tree'),
    ('quote_spec_hold.pdf_path',             'column', null, false, null, 'OPEN GAP: a spec-hold PDF is not yet in the Dropbox tree'),
    ('rfq_archives.archive_path',            'column', null, false, null, 'OPEN GAP: an RFQ archive is not yet in the Dropbox tree'),
    ('compliance_sources.doc_path',          'column', null, false, null, 'OPEN GAP: a compliance source document is not yet in the Dropbox tree'),
    ('support_artifact.storage_path',        'column', null, false, null, 'OPEN GAP: a support artefact is not yet in the Dropbox tree'),
    ('support_document_intake.storage_path', 'column', null, false, null, 'OPEN GAP: a document sent to support is not yet in the Dropbox tree'),
    ('wa_document_intake.storage_path',      'column', null, false, null, 'OPEN GAP: a document sent on WhatsApp is not yet in the Dropbox tree'),
    ('messages.attachment_path',             'column', null, false, null, 'OPEN GAP: a portal message attachment is not yet in the Dropbox tree (the message itself is, as correspondence)'),
    ('customer_calls.recording_path',        'column', null, false, null, 'OPEN GAP: a call recording is not yet in the Dropbox tree'),
    ('refunds.doc_path',                     'column', null, false, null, 'OPEN GAP: a refund document is not yet in the Dropbox tree'),
    ('supplier_dues.demand_letter_path',     'column', null, false, null, 'OPEN GAP: a demand letter is not yet in the Dropbox tree'),
    ('supplier_dues.case_file_path',         'column', null, false, null, 'OPEN GAP: a supplier dues case file is not yet in the Dropbox tree'),
    ('supplier_dues.evidence_terms_path',    'column', null, false, null, 'OPEN GAP: signed-terms evidence for a due is not yet in the Dropbox tree'),
    ('quote-files',                          'bucket', null, false, null, 'OPEN GAP: quotation files are not yet in the Dropbox tree'),
    ('compliance-docs',                      'bucket', null, false, null, 'OPEN GAP: compliance documents are not yet in the Dropbox tree')
$fn$;
revoke execute on function public.fn_backup_source_registry() from public, anon, authenticated;

-- fn_it_backup_expected: the MANIFEST-last definition (the_it_engineer_knows_what_should_be_backed_up_
-- and_closes_the_loop.sql, after the review of #628) with ONE change: the buckets come from the registry.
create or replace function public.fn_it_backup_expected()
returns table(item_key text, kind text, bucket text, path text, gen_kind text, gen_ref text, owner text, since timestamptz)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with rl as (select * from public.leads where not coalesce(is_demo, false)),
       rc as (select * from public.customers where not coalesce(is_demo, false)),
       ri as (select i.* from public.inquiries i join rc on rc.id = i.customer_id)
  select 'obj:' || o.bucket_id || ':' || o.name, 'storage', o.bucket_id, o.name, null::text, null::text, x.owner, o.created_at
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
  select 'gen:inquiry_summary:' || i.id, 'generated', null, null, 'inquiry_summary', i.id::text, 'inquiry:' || i.id, i.created_at from ri i;
$fn$;
revoke execute on function public.fn_it_backup_expected() from public, anon, authenticated;

-- ── PROBE: the registry covers what production holds today ─────────────────────────────────────────
do $probe$
declare v_cols text; v_buckets text; v_rules int;
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
  assert v_cols is null, 'unregistered path columns: ' || v_cols;
  assert v_buckets is null, 'unregistered buckets: ' || v_buckets;
  assert v_rules = 0, 'a registry row has neither an enqueue rule nor a reason';
  raise notice 'registry: % sources (% backed up, % open gaps); expected items now %',
    (select count(*) from public.fn_backup_source_registry()),
    (select count(*) from public.fn_backup_source_registry() where backed_up),
    (select count(*) from public.fn_backup_source_registry() where reason like 'OPEN GAP%'),
    (select count(*) from public.fn_it_backup_expected());
end $probe$;
