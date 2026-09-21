-- THE LAST TRACES OF BANK DETAILS, NEGOTIATIONS AND THE NETWORK MAP LEAVE (21 Sep 2026, it_engineer,
-- founder instructions 525/526/527). Money moves only through Stripe; the portals carry no negotiation
-- and no network map. Three earlier files removed the surfaces and left these traces.
--
-- MEASURED, read-only on production htdblwldjkcgjvmqkbeh, 21 Sep 2026, before this file was written:
--   * fn_supplier_negotiation(uuid), fn_supplier_network_map(), fn_negotiation_guidance(uuid,uuid):
--     0 other routine bodies name them (pg_proc.prosrc, every schema), 0 views, 0 triggers, 0 cron.job
--     commands, 0 policies. supabase/functions and src: comments only (supplier_portal line 202).
--     scripts/staging/audit_session_parity.mjs listed two of them as names to expect; edited in this PR.
--     ACL on all three: postgres + service_role only.
--   * v_supplier_doc_score: 0 routine bodies, 0 views, 0 triggers, 0 cron commands read it.
--   * public.supplier_negotiation_policy (1 row) is NOT dropped: fn_customer_savings(uuid) reads its
--     min_sample, and fn_table_export_list() backs it up. It has readers, so it stays.
--   * iban_doc_path / iban_doc_name on public.leads: 0 non-null values (nulled by
--     the_founder_removed_bank_details_from_the_estate.sql). The objects that reference them, all read
--     here line by line: 6 routines (fn_backup_enqueue_watch, fn_backup_source_registry,
--     fn_enqueue_doc_backups, fn_entity_files, fn_it_backup_expected, fn_ws_supplier_360), 1 view
--     (v_supplier_doc_score, dropped below) and 1 trigger (z70_document_landed_kicks_backup on leads,
--     column list). fn_supplier_certifications now names IBAN only in a comment. In every routine the
--     reference is one list element or one `if ... then docs := docs || ...` line, independent of its
--     neighbours, so removing it cannot change any other document's handling.
--   * public.company_faq: 3 rows name IBAN — id 37 (public, supplier: "What documents are required?"),
--     ids 223 and 232 (internal, read by the support seat when it answers suppliers). 0 Arabic rows.
--
-- WHAT CHANGES, in one transaction:
--   1. Refuses to run if any of the above gained a reader since it was measured.
--   2. Drops the three routines and the view.
--   3. Removes the IBAN mention from the three FAQ rows (the sentences stay grammatical). Their
--      embeddings are kept: the question is unchanged and the vector is of the question's subject.
--   4. Redefines the 6 routines from their live bodies (pg_get_functiondef) with only the iban lines
--      removed. CREATE OR REPLACE keeps each ACL (postgres + service_role) and each pinned search_path.
--   5. Re-creates z70_document_landed_kicks_backup on leads without iban_doc_path in its column list.
--   6. Drops leads.iban_doc_path and leads.iban_doc_name.
--   7. Returns ONE verdict row: PROBE OK or PROBE FAILED.
--
-- WHAT THIS DOES NOT CHANGE: supplier_negotiation_policy and fn_customer_savings; the TRUNCATE guard;
-- storage.objects (0 objects under an iban path); any other document column or backup rule.
-- APPLY ORDER: independent of any edge function deploy (no deployed function reads these objects).

-- 1. Refuse if a reader appeared since the measurement.
do $chk$
declare n int;
begin
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname not in ('pg_catalog', 'information_schema')
     and p.proname not in ('fn_supplier_negotiation', 'fn_supplier_network_map', 'fn_negotiation_guidance')
     and p.prosrc ~* '(fn_supplier_negotiation|fn_supplier_network_map|fn_negotiation_guidance|v_supplier_doc_score)';
  if n > 0 then raise exception '% routine body(ies) now name a routine or view this file drops - refusing', n; end if;

  select count(*) into n from pg_class c
   where c.relkind in ('v', 'm') and c.relname <> 'v_supplier_doc_score'
     and pg_get_viewdef(c.oid) ~* '(fn_supplier_negotiation|fn_supplier_network_map|fn_negotiation_guidance|v_supplier_doc_score|iban_doc_)';
  if n > 0 then raise exception '% view(s) now read a dropped object or an iban column - refusing', n; end if;

  select count(*) into n from cron.job
   where command ~* '(fn_supplier_negotiation|fn_supplier_network_map|fn_negotiation_guidance|v_supplier_doc_score)';
  if n > 0 then raise exception '% cron job(s) name a dropped object - refusing', n; end if;

  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~* 'iban_doc_'
     and p.proname not in ('fn_backup_enqueue_watch', 'fn_backup_source_registry', 'fn_enqueue_doc_backups',
                           'fn_entity_files', 'fn_it_backup_expected', 'fn_ws_supplier_360');
  if n > 0 then raise exception '% routine(s) outside the six redefined here read an iban column - refusing', n; end if;

  select count(*) into n from public.leads
   where coalesce(nullif(btrim(iban_doc_path), ''), nullif(btrim(iban_doc_name), '')) is not null;
  if n > 0 then raise exception '% lead(s) hold an iban document again - refusing to drop the columns', n; end if;
end
$chk$;

-- 2. The routines and the view with no caller.
drop function if exists public.fn_supplier_negotiation(uuid);
drop function if exists public.fn_supplier_network_map();
drop function if exists public.fn_negotiation_guidance(uuid, uuid);
drop view if exists public.v_supplier_doc_score;

-- 3. The FAQ rows.
update public.company_faq
   set answer = replace(answer, 'your VAT certificate (TRN), bank IBAN, insurance,', 'your VAT certificate (TRN), insurance,'),
       updated_at = now()
 where id = 37 and answer like '%(TRN), bank IBAN, insurance,%';
update public.company_faq
   set answer = replace(answer, 'VAT/TRN certificate, bank/IBAN letter, insurance,', 'VAT/TRN certificate, insurance,'),
       updated_at = now()
 where id = 223 and answer like '%bank/IBAN letter, insurance,%';
update public.company_faq
   set answer = replace(answer, '(bad TRN/IBAN)', '(bad TRN)'),
       updated_at = now()
 where id = 232 and answer like '%(bad TRN/IBAN)%';

-- 4. The six routines, each its live body with the iban lines removed.
CREATE OR REPLACE FUNCTION public.fn_backup_enqueue_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_n integer; v_oldest timestamptz; v_sample jsonb; v_items jsonb := '[]'::jsonb;
begin
  with reg as (
    select l.* from public.leads l
     where not coalesce(l.is_demo, false)
       and (l.approved_at is not null or l.registration_submitted_at is not null
         or l.signed_terms_path is not null or l.company_profile_doc_path is not null
         or l.license_doc_path is not null or coalesce(l.claimed, false))
  ),
  files(bucket, path, owner) as (
    select v.bucket, v.path, 'supplier:' || l.id
      from reg l cross join lateral (values
        ('supplier-docs', l.license_doc_path), ('supplier-docs', l.egr_doc_path),
        ('supplier-docs', l.insurance_doc_path), ('supplier-docs', l.vat_doc_path), ('supplier-docs', l.iso_doc_path),
        ('supplier-docs', l.manufacturer_auth_doc_path), ('supplier-docs', l.company_profile_doc_path),
        ('signed-terms', l.signed_terms_path)) v(bucket, path)
    union all
    select 'supplier-docs', cat, 'supplier:' || l.id from reg l cross join lateral unnest(coalesce(l.catalog_doc_paths, '{}')) cat
    union all
    select 'signed-terms', c.signed_terms_path, 'customer:' || c.id from public.customers c where not coalesce(c.is_demo, false)
    union all
    select 'drawing-files', i.drawing_file_path, 'inquiry:' || i.id
      from public.inquiries i join public.customers c on c.id = i.customer_id where not coalesce(c.is_demo, false)
    union all
    select 'finance-docs', t.doc_path, 'transaction:' || t.id from public.transactions t
  ),
  missing as (
    select f.owner, f.bucket || '/' || f.path as item, o.created_at as since
      from files f join storage.objects o on o.bucket_id = f.bucket and o.name = f.path
     where length(coalesce(f.path, '')) > 0 and f.path !~* 'zz[_ -]?demo'
       and o.created_at < now() - interval '1 hour'
       and not exists (select 1 from public.doc_backups d where d.bucket = f.bucket and d.path = f.path)
    union all
    -- dated from when the lead became a registrant where leads records it (review, 15 Sep 2026: a lead
    -- created weeks ago and approved a minute ago is not yet late); claimed and the document paths carry no
    -- date of their own, so those fall back to created_at
    select 'supplier:' || l.id, 'Company Details.pdf',
           greatest(l.created_at, coalesce(l.approved_at, l.registration_submitted_at, l.created_at)) from reg l
     where greatest(l.created_at, coalesce(l.approved_at, l.registration_submitted_at, l.created_at)) < now() - interval '1 hour'
       and not exists (select 1 from public.doc_backups d where d.dedupe_key = 'S:' || l.id || ':details')
    union all
    select 'customer:' || c.id, 'Customer Details.pdf', c.created_at from public.customers c
     where not coalesce(c.is_demo, false) and c.created_at < now() - interval '1 hour'
       and not exists (select 1 from public.doc_backups d where d.dedupe_key = 'C:' || c.id || ':details')
    union all
    select 'inquiry:' || i.id, 'Inquiry Summary.pdf', i.created_at
      from public.inquiries i join public.customers c on c.id = i.customer_id
     where not coalesce(c.is_demo, false) and i.created_at < now() - interval '1 hour'
       and not exists (select 1 from public.doc_backups d where d.dedupe_key = 'I:' || i.id || ':summary')
  )
  select count(*), min(since),
         coalesce(jsonb_agg(jsonb_build_object('owner', owner, 'item', item, 'since', since) order by since)
                    filter (where rn <= 10), '[]'::jsonb)
    into v_n, v_oldest, v_sample
    from (select m.*, row_number() over (order by m.since) rn from missing m) z;

  if v_n > 0 then
    v_items := jsonb_build_array(jsonb_build_object(
      'item', 'unqueued_documents', 'owner_seat', 'it_engineer', 'subject', 'dropbox_backup', 'blast', 'agent_facing',
      'affected', v_n,
      'title', left(format('%s customer/supplier document(s) over an hour old have no Dropbox backup row (oldest %s)',
                           v_n, to_char(v_oldest at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')), 300),
      'evidence', jsonb_build_object('count', v_n, 'oldest', v_oldest, 'first', v_sample,
        'why', 'fn_enqueue_doc_backups is not filing new documents: see duty:backup_enqueue_new_documents:failing and dropbox_backup agent_runs signal enqueue_failed')));
  end if;
  return public.fn_it_duty_settle('backup_enqueue_watch', v_items) || jsonb_build_object('unqueued', v_n, 'oldest', v_oldest);
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_backup_source_registry()
 RETURNS TABLE(source text, kind text, bucket text, backed_up boolean, enqueue_rule text, reason text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  values
    -- ── (a) backed up by an owner rule: each names the fn_enqueue_doc_backups section that files it ──
    ('leads.license_doc_path',               'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
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

    -- ── (c) EXEMPT (derived): no registry source. The one derived thing left out is a folder, not a
    -- source: signed-terms/registers/ (the customer register compliance_archive uploads to Dropbox
    -- itself), excluded in fn_backup_sweep_objects. The anonymised drawings are derived, but 2 of the 3
    -- redacted files have no original left (review, 15 Sep 2026), so they are kept like any other file. ──
    ('inquiries.drawing_redacted_paths',     'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null),
    ('drawing_redaction_runs.output_paths',  'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null)
$function$
;

CREATE OR REPLACE FUNCTION public.fn_enqueue_doc_backups()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
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

  -- LEGACY EXPORTS and the STORAGE SWEEP are fn_enqueue_doc_backups_backfill (15 Sep 2026): together they
  -- took this call from milliseconds to 50 s, past PostgREST's 8 s, and every new document stopped.
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_entity_files(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb := '[]'::jsonb; l public.leads%rowtype;
begin
  if p_entity = 'supplier' then
    select * into l from public.leads where id = p_id::bigint;
    if l.id is not null then
      if l.license_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Trade licence','name',coalesce(l.license_doc_name,'trade licence'),'bucket','supplier-docs','path',l.license_doc_path); end if;
      if l.egr_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Establishment card','name',coalesce(l.egr_doc_name,'establishment card'),'bucket','supplier-docs','path',l.egr_doc_path); end if;
      if l.insurance_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Insurance','name','insurance','bucket','supplier-docs','path',l.insurance_doc_path); end if;
      if l.vat_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','VAT certificate','name','vat certificate','bucket','supplier-docs','path',l.vat_doc_path); end if;
      if l.company_profile_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Company profile','name','company profile','bucket','supplier-docs','path',l.company_profile_doc_path); end if;
      if l.signed_terms_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Signed terms','name','signed terms','bucket','signed-terms','path',l.signed_terms_path); end if;
      if l.catalog_doc_paths is not null then
        out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Catalogues','type','Catalogue','name','catalogue','bucket','supplier-docs','path',x)) from unnest(l.catalog_doc_paths) x),'[]'::jsonb);
      end if;
      -- Storage scan: surface any stored documents whose column pointers are null (files live under <folder>/<supplier_id>/<file>).
      out := out || coalesce((
        select jsonb_agg(jsonb_build_object(
          'group', case when split_part(o.name,'/',1) in ('catalogs','catalogues') then 'Catalogues'
                        when o.bucket_id = 'signed-terms' then 'Signed terms'
                        else 'Compliance documents' end,
          'type', case split_part(o.name,'/',1)
                    when 'licence' then 'Trade licence' when 'license' then 'Trade licence' when 'licenses' then 'Trade licence'
                    when 'certs' then 'Certificate' when 'cert' then 'Certificate' when 'insurance' then 'Insurance'
                    when 'profile' then 'Company profile' when 'company_profile' then 'Company profile'
                    when 'catalogs' then 'Catalogue' when 'catalogues' then 'Catalogue'
                    when 'vat' then 'VAT certificate' when 'egr' then 'Establishment card'
                    when 'terms' then 'Signed terms'
                    else initcap(replace(split_part(o.name,'/',1),'_',' ')) end,
          'name', regexp_replace(split_part(o.name,'/', greatest(array_length(string_to_array(o.name,'/'),1),1)), '^[0-9]+_', ''),
          'bucket', o.bucket_id,
          'path', o.name))
        from storage.objects o
        where o.bucket_id in ('supplier-docs','signed-terms')
          and split_part(o.name,'/',2) = p_id
          and not exists (select 1 from jsonb_array_elements(out) xx where xx->>'path' = o.name)
      ), '[]'::jsonb);
    end if;
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations submitted','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q where q.supplier_id = p_id::bigint and q.original_file_path is not null),'[]'::jsonb);

  elsif p_entity = 'customer' then
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Drawings & RFQ files','type','RFQ drawing','name',coalesce(i.drawing_file_name,'drawing'),'bucket','drawing-files','path',i.drawing_file_path) order by i.created_at desc)
                            from public.inquiries i where i.customer_id = p_id::uuid and i.drawing_file_path is not null),'[]'::jsonb);
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations received','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q join public.inquiries i on i.id = q.inquiry_id where i.customer_id = p_id::uuid and q.original_file_path is not null),'[]'::jsonb);

  elsif p_entity in ('rfq','inquiry') then
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Drawing','type','RFQ drawing','name',coalesce(i.drawing_file_name,'drawing'),'bucket','drawing-files','path',i.drawing_file_path))
                            from public.inquiries i where i.id = p_id::uuid and i.drawing_file_path is not null),'[]'::jsonb);
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q where q.inquiry_id = p_id::uuid and q.original_file_path is not null),'[]'::jsonb);
  end if;
  return out;
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_it_backup_expected()
 RETURNS TABLE(item_key text, kind text, bucket text, path text, gen_kind text, gen_ref text, owner text, since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                or o.name in (l.license_doc_path, l.egr_doc_path, l.insurance_doc_path, l.vat_doc_path,
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
$function$
;

CREATE OR REPLACE FUNCTION public.fn_ws_supplier_360(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare l public.leads%rowtype; j jsonb; docs jsonb := '[]'::jsonb;
begin
  select * into l from public.leads where id=p_id;
  if l.id is null then return jsonb_build_object('error','supplier not found'); end if;

  -- documents from path fields
  if l.license_doc_path is not null then docs:=docs||jsonb_build_object('type','Trade licence','name',coalesce(l.license_doc_name,'licence'),'path',l.license_doc_path); end if;
  if l.egr_doc_path is not null then docs:=docs||jsonb_build_object('type','Establishment card','name',coalesce(l.egr_doc_name,'egr'),'path',l.egr_doc_path); end if;
  if l.insurance_doc_path is not null then docs:=docs||jsonb_build_object('type','Insurance','name','insurance','path',l.insurance_doc_path); end if;
  if l.vat_doc_path is not null then docs:=docs||jsonb_build_object('type','VAT certificate','name','vat','path',l.vat_doc_path); end if;
  if l.company_profile_doc_path is not null then docs:=docs||jsonb_build_object('type','Company profile','name','profile','path',l.company_profile_doc_path); end if;
  if l.signed_terms_path is not null then docs:=docs||jsonb_build_object('type','Signed terms','name','terms','path',l.signed_terms_path); end if;
  if l.catalog_doc_paths is not null then
    docs := docs || coalesce((select jsonb_agg(jsonb_build_object('type','Catalogue','name','catalogue','path',x))
                              from unnest(l.catalog_doc_paths) x),'[]'::jsonb);
  end if;

  j := jsonb_build_object(
    'profile', jsonb_build_object(
      'id', l.id, 'company_name', l.company_name, 'sector', l.sector, 'sub_type', l.sub_type,
      'emirate', l.emirate, 'city', l.city, 'phone', coalesce(l.phone_e164,l.phone), 'email', l.email,
      'website', l.website, 'contact_name', l.contact_name, 'founded_year', l.founded_year,
      'company_size', l.company_size, 'employee_count', l.employee_count, 'business_role', l.business_role,
      'lifecycle_stage', l.lifecycle_stage, 'claimed', l.claimed
    ),
    'status', jsonb_build_object(
      'approval_status', l.approval_status, 'verified', l.verified, 'verification_status', l.verification_status,
      'registration_status', l.registration_status, 'matching_blocked', l.matching_blocked,
      'matching_block_reason', l.matching_block_reason, 'banned', l.banned, 'banned_reason', l.banned_reason,
      'chat_strikes', l.chat_strikes
    ),
    'ai', jsonb_build_object(
      'capability_summary', l.capability_summary, 'capability_score', l.capability_score,
      'review_notes', l.ai_review_notes, 'review_flags', l.ai_review_flags, 'reviewed_at', l.ai_reviewed_at,
      'twin', coalesce((select to_jsonb(tw) from public.supplier_twin tw where tw.supplier_id=p_id),'{}'::jsonb)
    ),
    'compliance', jsonb_build_object(
      'trade_license_no', l.trade_license_no, 'license_authority', l.license_authority,
      'license_expiry', l.license_expiry, 'trn', l.trn, 'vat_number', l.vat_number,
      'insurance_expiry', l.insurance_expiry, 'iso_certifications', l.iso_certifications,
      'certifications', l.certifications, 'accepted_terms_at', l.accepted_terms_at,
      'registration_expires_at', l.registration_expires_at,
      'license_expiring', (l.license_expiry is not null and l.license_expiry < current_date + 30),
      'insurance_expiring', (l.insurance_expiry is not null and l.insurance_expiry < current_date + 30)
    ),
    'capabilities', jsonb_build_object(
      'brands_carried', l.brands_carried, 'machinery', l.machinery, 'engineers_count', l.engineers_count,
      'team_size', l.team_size, 'warehouse_area', l.warehouse_area, 'service_emirates', l.service_emirates,
      'manufacturer_authorizations', l.manufacturer_authorizations, 'client_references', l.client_references,
      'products', l.products, 'services', l.services,
      'detail', coalesce((select to_jsonb(c) from public.supplier_capabilities c where c.supplier_id=p_id),'{}'::jsonb)
    ),
    'performance', coalesce((select jsonb_build_object(
        'matched',pf.matched,'quoted',pf.quoted,'won',pf.won,'quote_rate',pf.quote_rate,
        'win_rate',pf.win_rate,'perf_score',pf.perf_score,'rating',pf.rating,'review_count',pf.review_count)
        from public.supplier_perf pf where pf.supplier_id=p_id),'{}'::jsonb)
      || jsonb_build_object('rv_reveals',l.rv_reveals,'rv_responded',l.rv_responded,'rv_response_rate',l.rv_response_rate,
                            'app_rating',l.app_rating,'app_reviews',l.app_reviews),
    'reputation', coalesce((select to_jsonb(rp) - 'supplier_id' - 'company_name' from public.supplier_reputation rp where rp.supplier_id=p_id),'{}'::jsonb),
    'financials', (
      select jsonb_build_object(
        'deals_count', count(*) filter (where t.id is not null),
        'deal_value_total', coalesce(sum(t.quote_amount),0),
        'reveal_fees_generated', coalesce(sum(t.reveal_fee) filter (where t.fee_status='paid'),0)
      ) from public.transactions t where t.supplier_id=p_id
    ) || (
      select jsonb_build_object(
        'commission_total', coalesce(sum(amount_due),0),
        'commission_paid', coalesce(sum(amount_due) filter (where status in ('paid','settled')),0),
        'commission_owed', coalesce(sum(amount_due) filter (where public.fn_supplier_due_is_owed(status, paid_at)),0)
      ) from public.supplier_dues where supplier_id=p_id
    ),
    'documents', docs,
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'amount',q.quote_amount,'status',q.status,'created_at',q.created_at) order by q.created_at desc)
                        from (select * from public.quotes where supplier_id=p_id order by created_at desc limit 10) q),'[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('rating',r.rating,'comment',r.comment,'created_at',r.created_at) order by r.created_at desc)
                        from (select * from public.reviews where supplier_id=p_id order by created_at desc limit 8) r),'[]'::jsonb),
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',l.created_at,'event','Added to directory') e where l.created_at is not null
        union all select jsonb_build_object('at',l.registration_submitted_at,'event','Registration submitted') where l.registration_submitted_at is not null
        union all select jsonb_build_object('at',l.approved_at,'event','Approved'||coalesce(' by '||l.approval_decided_by,'')) where l.approved_at is not null
        union all select jsonb_build_object('at',l.accepted_terms_at,'event','Accepted terms') where l.accepted_terms_at is not null
      ) tl),
    -- WHY WE DECIDED WHAT WE DECIDED about this supplier. decision_record holds the reasoning behind
    -- past decisions and decision_trace the policies that were applied; neither reached the supplier
    -- view, so "why did we reject Supplier X?" had no answer on the screen that shows X.
    'rejection_reason', coalesce((select jsonb_agg(jsonb_build_object(
        'id', dr.id, 'problem', dr.problem, 'recommendation', dr.recommendation,
        'risks', dr.risks, 'status', dr.status, 'decided_by', dr.decided_by,
        'actual_outcome', dr.actual_outcome, 'at', dr.created_at) order by dr.created_at desc)
      from public.decision_record dr
      where coalesce(l.company_name,'') <> ''
        and (dr.problem ilike '%'||l.company_name||'%' or dr.context ilike '%'||l.company_name||'%')), '[]'::jsonb),
    'decision_trace', coalesce((select jsonb_agg(jsonb_build_object(
        'entity_id', dt.entity_id, 'policy_keys', dt.policy_keys) order by dt.entity_id)
      from public.decision_trace dt where dt.entity_id = p_id::text), '[]'::jsonb)
  );
  return j;
end $function$
;


-- 5. The trigger's column list, without iban_doc_path. Must precede the column drop: a column named in
--    UPDATE OF is a dependency and the drop would otherwise fail.
drop trigger if exists z70_document_landed_kicks_backup on public.leads;
create trigger z70_document_landed_kicks_backup
  after insert or update of license_doc_path, egr_doc_path, insurance_doc_path, vat_doc_path, iso_doc_path,
    manufacturer_auth_doc_path, company_profile_doc_path, catalog_doc_paths, signed_terms_path
  on public.leads for each statement execute function public.trg_document_landed_kicks_backup();

-- 6. The columns.
alter table public.leads
  drop column if exists iban_doc_path,
  drop column if exists iban_doc_name;

-- 7. The verdict row.
select case
         when exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                       where s.nspname = 'public'
                         and p.proname in ('fn_supplier_negotiation', 'fn_supplier_network_map', 'fn_negotiation_guidance'))
           then 'PROBE FAILED: a negotiation or network-map routine survived'
         when to_regclass('public.v_supplier_doc_score') is not null
           then 'PROBE FAILED: v_supplier_doc_score survived'
         when exists (select 1 from information_schema.columns
                       where table_schema = 'public' and table_name = 'leads' and column_name like 'iban%')
           then 'PROBE FAILED: an iban column survived on leads'
         when exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
                       where s.nspname = 'public' and p.prosrc ~* 'iban_doc_')
           then 'PROBE FAILED: a routine still reads an iban column'
         when exists (select 1 from public.company_faq where question ~* '(iban|آيبان|أيبان)' or answer ~* '(iban|آيبان|أيبان)')
           then 'PROBE FAILED: an FAQ row still names IBAN'
         when (select count(*) from pg_trigger where tgname = 'z70_document_landed_kicks_backup'
                  and tgrelid = 'public.leads'::regclass) <> 1
           then 'PROBE FAILED: the leads document-landed trigger is missing'
         when to_regclass('public.supplier_negotiation_policy') is null
           or to_regprocedure('public.fn_customer_savings(uuid)') is null
           then 'PROBE FAILED: the policy table or its reader fn_customer_savings went missing'
         else 'PROBE OK: 3 routines and v_supplier_doc_score dropped; 6 routines and the leads trigger rewritten; '
              || 'iban_doc_path/iban_doc_name dropped; 0 FAQ rows name IBAN'
       end as verdict;
