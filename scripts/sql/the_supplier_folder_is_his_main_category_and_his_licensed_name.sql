-- the_supplier_folder_is_his_main_category_and_his_licensed_name.sql
--
-- Seat: it_engineer (the Dropbox backup: function_owner dropbox_backup, founder instruction 583). Built 13 Nov 2026.
-- Founder ruling 1680 (13 Nov 2026, verbatim in public.founder_instruction): "a main folder that is [QuotesDone] backup ... two main
-- folders, customers, suppliers. You go to supplier ... a folder for every category ... real estate ... a folder that should be called
-- 666 real estate company ... we should see a trade license, company profile, and a folder for every job quoted ... there will be a
-- quotation actually from them as per our template, the one that we shared with the customer, and it will be there as per the job
-- number." With ruling 1672 (category and company name are read from the licence and profile, never typed; "legally we care about the
-- trade license the most") and 1671 (every document we produce is a PDF in our template).
--
-- MEASURED ON PRODUCTION, 13 Nov 2026 (SELECT only; scripts in the session report):
--   * fn_dbx_category matched only the 86 catalog_supplier_categories SLUGS (lead_category, leads.categories, leads.sector). What the
--     model reads for a supplier is his TRADES (supplier_capabilities.trades / proposed_trades, 223 taxonomy_trade codes); nothing
--     mapped one to the other, so the founder's own company (trade real_estate_services, read from his documents) was filed under
--     'uncategorized', and 19398 under the slug 'industrial-equipment-suppliers'.
--   * the company folder was '<company_name> (<lead id>)' and every file '<label> - <storage timestamp>_<original name>'; each new
--     upload of the licence slot added one more 'Trade licence - ...' beside the last (the founder's folder holds three: two uploads of
--     his licence and the company profile he put in the licence slot on purpose, filed before #1985 as 'Trade licence').
--   * NO quoted job is filed under any supplier. A supplier's quotation reached Dropbox only under the CUSTOMER's request
--     (Customers/<name> (<id8>)/Inquiries/.../Quotes/), and in practice not even there: 0 doc_backups rows carry the keys 'Q:' or
--     'QPDF:' because the hourly storage sweep had already claimed every (bucket, path) - 474 quote-files and 92 quotation PDFs sit in
--     the raw Storage/ mirror or _archive/. The template quotation exists only when a customer pressed "download" (quote_pdf_cache).
--   * the worker could not MOVE a file: a changed path was uploaded again and the old copy stayed (a second copy, same label).
--
-- WHAT THIS CHANGES (everything filed FROM NOW ON; nothing already in Dropbox is moved by applying this file):
--   /QuotesDone Backup/Suppliers/<main category>/<company as on the trade licence>/
--       Trade licence - <original name>          the licence on his row now
--       Company profile - <original name>
--       Signed Supplier Agreement.pdf            our certificate (re-issued in the licensed name since #1990)
--       Company Details.pdf                      ours, on the template (pdf_native, letterhead)
--       Catalogues/<original name>   Certificates/<kind> - <original name>   Correspondence/... and cases/... (names unchanged; they
--                                                                             move with his folder)
--       Earlier versions/<kind> - <Dubai date and time> - <original name>     every replaced upload, and a file the model said was
--                                                                             not a licence, named by what it is ("... (sent as trade licence)")
--       Job <job number>/Quotation <job number>.pdf        OUR template quotation, rendered as the customer is shown it (gen_kind
--                                                         'quotation': customer_api renders it, the same code as the portal download)
--       Job <job number>/Original as sent - <his file>     his own uploaded quotation, when he sent one
--       Job <job number>/Earlier versions/...              a quotation that went stale (a revision replaced it)
--   * MAIN CATEGORY (fn_dbx_main_category): the plain label of his main trade (taxonomy_trade.label, the "categories" he confirms in
--     the portal). The trades are the model's reading of his licence and profile; code only ranks the model's own answer: the trade
--     with the most items the model judged covered by his licence, then the most items in the model's reading, then the trade whose
--     group holds most of his trades, then the order he confirmed them in. No keyword list. A supplier with no trade yet has no
--     category and gets no folder: his files are safe in the hourly Storage/ mirror and are moved into his folder the moment the model
--     has named a trade (the re-file below). There is no 'Uncategorized' folder any more.
--   * NO DATABASE ID AND NO STORAGE TIMESTAMP in a name a person reads: ids stay in doc_backups (entity_id, dedupe_key). Two companies
--     whose licensed names are the same in one category: the later registration's folder adds " - licence <number>".
--   * A FOLDER THAT MUST CHANGE IS MOVED, NOT COPIED: doc_backups.moved_from (new column) holds the path a done file is in; the worker
--     (dropbox_backup row.ts, move.ts) calls files/move_v2 and confirms the moved file's size and hash, and uploads only when the old
--     copy is gone. So a category the model changes, a licensed name that changes, a licence that is replaced, all move.
--   * LEGACY FOLDERS ARE LEFT AS THEY ARE until the founder's migration (scripts/sql/the_two_real_suppliers_are_moved_into_the_ruled_tree.sql,
--     held): a supplier whose first folder was opened under the old rule ('<slug>/<name> (<id>)/') keeps getting files there with the
--     old names, exactly as before; only his quoted jobs (new) are added. Re-filing his Company Details row is the migration.
--   * DEMO rows stay out of the real tree exactly as before (trg_doc_backups_admit drops them unless a tagged sandbox run re-roots
--     them under _sandbox/<tag>/); a quotation on a DEMO customer's request is not filed in a real supplier's folder.
--   * ANONYMITY: the template quotation names no customer (trade, emirate, the request in the customer's words with contacts masked,
--     the anonymous letter); after a paid reveal it names the supplier, which is his own name. His own file is his.
--   * fn.dropbox_backup's internal credential gains scope customer_api (it rendered with pdf_native only), for the quotation door.
-- WHAT THIS DOES NOT CHANGE: the Customers tree, Finance, Company, Storage sweep rules, correspondence file names (they still end
-- " #<message id>": two messages in one minute with one subject would otherwise overwrite each other; the founder's question 3),
-- and fn_dbx_category (no longer called by anything; left for a retirement file so no other caller breaks unseen).
-- fn_enqueue_doc_backups, trg_doc_backups_admit and fn_support_case_summary_backup_enqueue are replaced from their LIVE definitions
-- (pg_get_functiondef, 13 Nov 2026 04:30 UTC, after #1985/#1987); CREATE OR REPLACE keeps their ACL (postgres, service_role).
-- INDEPENDENT REVIEW OF #1997 (13 Nov 2026), fixed here: D1 the claim routines give a quotation or a move only to a worker that says it
-- can ('moves1'), and the worker names moved_from only for a row that carries it, so apply and deploy may come in either order; D2 the
-- backup credential gets the door-only scope customer_api.quotation_for_backup; D3 the plain folder stays with whoever opened it first;
-- D4 a quotation is keyed on its revision (fn_dbx_quote_revision) and an earlier revision moves to Earlier versions/; D5 the probe
-- guards #1985's 15 minutes again; D6 the customer's request folder gets its own quotation file (fn_dbx_customer_quotation_files);
-- D7 a file of his outside his ruled folder is moved on every later run, not only once; D8 correspondence computes one supplier.
-- RELEASE ORDER: merge; apply this file; deploy customer_api and dropbox_backup; MANIFEST (scripts/sql/pending/<this file>.txt). Probe:
-- the_supplier_folder_is_his_main_category_and_his_licensed_name_probe.sql (rolled back).

alter table public.doc_backups add column if not exists moved_from text;
comment on column public.doc_backups.moved_from is
  'The Dropbox path a DONE file is in when its dropbox_path was changed (ruling 1680, 13 Nov 2026): the worker moves it (files/move_v2) instead of uploading a second copy; null once moved.';

-- ── what a person reads: the original file name, without the storage timestamp ────────────────────────────────────────────────
create or replace function public.fn_dbx_original_name(p_path text)
returns text
language sql
immutable
set search_path to 'public', 'pg_catalog'
as $fn$
  -- supplier_api stores '<ms since 1970>_<name as uploaded>' (e.g. 1794504328051_SecureCertificate201803.aspx.pdf): the 13 digits
  -- are storage bookkeeping, the rest is what the supplier called his file
  select public.fn_dbx_safe(coalesce(nullif(regexp_replace(regexp_replace(coalesce(p_path, ''), '^.*/', ''), '^\d{10,}_', ''), ''),
                                     regexp_replace(coalesce(p_path, ''), '^.*/', '')))
$fn$;
revoke execute on function public.fn_dbx_original_name(text) from public, anon, authenticated;

-- ── the supplier's main category: the plain label of his main trade, or null while the model has named none ───────────────────
create or replace function public.fn_dbx_main_category(p_lead_id bigint)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with c as (
    -- the trades he confirmed; before he confirms, the trades the model proposed from his documents
    select case when cardinality(sc.trades) > 0 then sc.trades else sc.proposed_trades end as cand,
           case when jsonb_typeof(sc.source_docs -> 'reading' -> 'evidence') = 'array' then sc.source_docs -> 'reading' -> 'evidence'
                else '[]'::jsonb end as ev
      from public.supplier_capabilities sc where sc.supplier_id = p_lead_id),
  t as (
    select u.code, u.ord, tt.label, tt.group_code
      from c cross join lateral unnest(c.cand) with ordinality u(code, ord)
      join public.taxonomy_trade tt on tt.code = u.code and tt.active),
  s as (
    select t.label, t.ord,
           (select count(*) from c, jsonb_array_elements(c.ev) e where e ->> 'trade' = t.code and e ->> 'licence' = 'covered') as covered,
           (select count(*) from c, jsonb_array_elements(c.ev) e where e ->> 'trade' = t.code) as items,
           (select count(*) from t t2 where t2.group_code = t.group_code) as in_group
      from t)
  select public.fn_dbx_safe(s.label) from s order by s.covered desc, s.items desc, s.in_group desc, s.ord limit 1
$fn$;
revoke execute on function public.fn_dbx_main_category(bigint) from public, anon, authenticated;
grant execute on function public.fn_dbx_main_category(bigint) to service_role;

-- ── every supplier's folder (or one supplier's: p_lead_id) ───────────────────────────────────────────────────────────────────────
-- folder is null while he has no name or no category. legacy = his first folder was opened under the old rule and stays until the
-- migration re-files his Company Details row.
-- SAME NAME, SAME CATEGORY (review of #1997, D3): the plain folder belongs to whoever OPENED it first (the creation time of his
-- Company Details row, then his id) and never changes hands; a later company always gets " - licence <number>", and a further
-- " - <n>" when that too collides or he has no number. A name longer than 170 characters is cut to 169 + "…" here, before the
-- comparison, so two long names equal after the cut are numbered too (fn_dbx_component would otherwise cut them to one folder).
-- p_lead_id (review D8): the folder of ONE supplier, computing only him and the companies whose name equals his (the correspondence
-- block asks for one supplier per message; it used to compute every registered supplier and his category each time).
create or replace function public.fn_dbx_supplier_folders(p_lead_id bigint default null)
returns table(lead_id bigint, folder text, legacy boolean, is_demo boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with me as (
    select lower(left(public.fn_dbx_safe(coalesce(nullif(btrim(l.licence_legal_name), ''), btrim(l.company_name))), 169)) as key
      from public.leads l where l.id = p_lead_id),
  r0 as (
    select l.id, coalesce(l.is_demo, false) as is_demo, l.trade_license_no,
           public.fn_dbx_safe(coalesce(nullif(btrim(l.licence_legal_name), ''), btrim(l.company_name))) as name0
      from public.leads l
     where (l.approved_at is not null or l.registration_submitted_at is not null
         or l.signed_terms_path is not null or l.company_profile_doc_path is not null
         or l.license_doc_path is not null or coalesce(l.claimed, false))
       and coalesce(btrim(l.company_name), '') <> ''),
  r as (
    select r0.id, r0.is_demo, r0.trade_license_no,
           case when char_length(r0.name0) > 170 then left(r0.name0, 169) || '…' else r0.name0 end as name,
           public.fn_dbx_main_category(r0.id) as cat,
           (select substring(d.dropbox_path from '^(/QuotesDone Backup/Suppliers/[^/]+/[^/]* \(' || r0.id || '\)/)')
              from public.doc_backups d where d.dedupe_key = 'S:' || r0.id || ':details') as old_folder,
           (select min(d.created_at) from public.doc_backups d
             where d.dedupe_key = 'S:' || r0.id || ':details'
                or d.dedupe_key = 'SBX:' || coalesce(nullif(current_setting('qd.backup_sandbox', true), ''), '-') || ':S:' || r0.id || ':details') as opened_at
      from r0
     where p_lead_id is null or r0.id = p_lead_id or lower(left(r0.name0, 169)) = (select key from me)),
  k as (
    select r.*, row_number() over (partition by lower(r.cat), lower(r.name) order by r.opened_at nulls last, r.id) as n
      from r where r.cat is not null and r.old_folder is null),
  k1 as (
    select k.*, case when k.n = 1 then k.name
                     else k.name || ' - ' || coalesce('licence ' || public.fn_dbx_safe(nullif(btrim(k.trade_license_no), '')), k.n::text) end as cand
      from k),
  k2 as (
    select k1.*, row_number() over (partition by lower(k1.cat), lower(k1.cand) order by k1.n, k1.opened_at nulls last, k1.id) as n2 from k1)
  select r.id,
         coalesce(r.old_folder,
                  case when k2.id is not null then '/QuotesDone Backup/Suppliers/' || k2.cat || '/' || k2.cand
                    || case when k2.n2 > 1 then ' - ' || k2.n2 else '' end || '/' end),
         r.old_folder is not null, r.is_demo
    from r left join k2 on k2.id = r.id
   where p_lead_id is null or r.id = p_lead_id
$fn$;
revoke execute on function public.fn_dbx_supplier_folders(bigint) from public, anon, authenticated;

create or replace function public.fn_dbx_supplier_folder(p_lead_id bigint)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select f.folder from public.fn_dbx_supplier_folders(p_lead_id) f
$fn$;
revoke execute on function public.fn_dbx_supplier_folder(bigint) from public, anon, authenticated;

-- ── a quotation's revision (review of #1997, D4) ─────────────────────────────────────────────────────────────────────────────────
-- quotes carries no updated_at and a revision is written IN PLACE (supplier_api submit_quote re-prices the same row). The revision is
-- what the customer's document prints: the priced terms and every priced line. A change of any of them is a new revision: a new
-- "Quotation <job>.pdf" is filed as current and the previous one moves to Earlier versions/ (fn_enqueue_doc_backups).
create or replace function public.fn_dbx_quote_revision(p_quote_id uuid)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select left(md5(concat_ws('|', q.quote_amount, q.price_ex_vat, q.vat_amount, q.gross_amount, q.discount_amount, q.discount_label,
                             q.vat_treatment, q.lead_time, q.validity, q.payment_terms, q.warranty, q.scope, q.conditions, q.exclusions,
                             q.committed_hash,
                             (select string_agg(concat_ws('~', qi.line_no, qi.description, qi.qty, qi.unit, qi.unit_price, qi.amount,
                                                          qi.brand, qi.model, qi.specification), '|' order by qi.line_no)
                                from public.quote_items qi where qi.quote_id = q.id::text))), 12)
    from public.quotes q where q.id = p_quote_id
$fn$;
revoke execute on function public.fn_dbx_quote_revision(uuid) from public, anon, authenticated;

-- ── the customer's side of the same quotation (review of #1997, D6) ──────────────────────────────────────────────────────────────
-- His request folder holds the quotation AS HE WAS SHOWN IT: a generated row of its own (gen_kind quotation_customer, rendered for the
-- customer, his own words unmasked), named by the letter he sees (A, B ... by ascending price among live quotes, as customer_api
-- letterOf numbers them). It is a separate file from the supplier's copy, so each is ONE record of ONE file and neither starves the
-- other. The supplier's ORIGINAL upload has one home, his Job folder: the customer was never shown it (it carries the supplier's brand).
create or replace function public.fn_dbx_customer_quotation_files()
returns table(inquiry_id uuid, quote_id uuid, dropbox_path text, dedupe_key text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with q as (
    select qq.id, qq.inquiry_id, qq.stale_at, qq.created_at, i.created_at as inq_created, i.status as inq_status, c.id as cid, c.full_name,
           coalesce(nullif(btrim(i.rfq_no::text), ''), upper(left(i.id::text, 8))) as job,
           row_number() over (partition by qq.inquiry_id order by qq.quote_amount nulls last, qq.created_at) as n
      from public.quotes qq join public.inquiries i on i.id = qq.inquiry_id join public.customers c on c.id = i.customer_id
     where coalesce(qq.status, '') not in ('draft', 'withdrawn')
       and (not coalesce(c.is_demo, false) or coalesce(current_setting('qd.backup_sandbox', true), '') <> ''))
  select q.inquiry_id, q.id,
         public.fn_dbx_path('/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(q.full_name, 'Customer')) || ' (' || left(q.cid::text, 8) || ')/Inquiries/'
           || to_char(q.inq_created, 'YYYY-MM-DD') || ' ' || left(q.inquiry_id::text, 8) || ' - ' || public.fn_dbx_safe(coalesce(q.inq_status, 'inquiry'))
           || '/Quotes/' || case when q.stale_at is not null then 'Earlier versions/' else '' end
           || 'Quotation QD-' || public.fn_dbx_safe(q.job) || '-' || case when q.n <= 26 then chr(64 + q.n::int) else q.n::text end
           || case when q.stale_at is not null then ' - ' || to_char(q.created_at at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24MI') else '' end || '.pdf'),
         'CQ:' || q.id || ':' || public.fn_dbx_quote_revision(q.id)
    from q
$fn$;
revoke execute on function public.fn_dbx_customer_quotation_files() from public, anon, authenticated;

-- ── every file the rule wants in a supplier's folder, and where ────────────────────────────────────────────────────────────────
-- row_id is set for a file that is already queued and only has to move (an earlier version).
create or replace function public.fn_dbx_supplier_files()
returns table(lead_id bigint, is_demo boolean, legacy boolean, doc_type text, bucket text, path text, file_name text,
              gen_kind text, gen_ref text, dropbox_path text, dedupe_key text, row_id bigint)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with f as (select * from public.fn_dbx_supplier_folders() x where x.folder is not null),
  l as (select l.*, f.folder, f.legacy, f.is_demo as demo from public.leads l join f on f.lead_id = l.id),
  docs as (
    select l.id, l.demo, l.legacy, l.folder, v.doc_type, v.bucket, v.path, v.sub, v.label
      from l cross join lateral (values
        -- a licence file is not filed in the first 15 minutes our reader is on it (a_licence_file_is_filed_in_the_backup_only_once_it_is_read.sql)
        ('Trade licence', 'supplier-docs', case when coalesce(l.licence_read_state, '') = 'ours_failed' and l.licence_read_at > now() - interval '15 minutes'
                                                then null else l.license_doc_path end, '', 'Trade licence'),
        ('Company profile', 'supplier-docs', l.company_profile_doc_path, '', 'Company profile'),
        ('Signed Terms & Conditions', 'signed-terms', l.signed_terms_path, '', 'Signed Supplier Agreement'),
        ('Establishment card', 'supplier-docs', l.egr_doc_path, 'Certificates/', 'Establishment card'),
        ('Insurance', 'supplier-docs', l.insurance_doc_path, 'Certificates/', 'Insurance'),
        ('VAT certificate', 'supplier-docs', l.vat_doc_path, 'Certificates/', 'VAT certificate'),
        ('ISO certificate', 'supplier-docs', l.iso_doc_path, 'Certificates/', 'ISO certificate'),
        ('Manufacturer authorization', 'supplier-docs', l.manufacturer_auth_doc_path, 'Certificates/', 'Manufacturer authorisation')
      ) v(doc_type, bucket, path, sub, label)
     where length(coalesce(v.path, '')) > 0
    union all
    select l.id, l.demo, l.legacy, l.folder, 'Catalogue', 'supplier-docs', cat, 'Catalogues/', null
      from l cross join lateral unnest(l.catalog_doc_paths) cat where length(coalesce(cat, '')) > 0),
  q as (
    -- the jobs he QUOTED: a live quote (not a draft, not withdrawn) on a request of a real customer (a demo request only in a sandbox run)
    select l.id, l.demo, l.folder, qq.id as quote_id, qq.original_file_path, qq.original_file_name, qq.created_at, qq.stale_at,
           'Job ' || public.fn_dbx_safe(coalesce(nullif(btrim(i.rfq_no::text), ''), upper(left(i.id::text, 8)))) as job,
           count(*) filter (where qq.stale_at is null) over (partition by l.id, i.id) as live_n,
           row_number() over (partition by l.id, i.id, (qq.stale_at is null) order by qq.option_no nulls last, qq.created_at) as opt
      from l join public.quotes qq on qq.supplier_id = l.id
      join public.inquiries i on i.id = qq.inquiry_id
      left join public.customers c on c.id = i.customer_id
     where coalesce(qq.status, '') not in ('draft', 'withdrawn')
       and (not coalesce(c.is_demo, false) or coalesce(current_setting('qd.backup_sandbox', true), '') <> ''))
  -- the documents on his row now
  select d.id, d.demo, d.legacy, d.doc_type, d.bucket, d.path, regexp_replace(d.path, '^.*/', ''), null::text, null::text,
         public.fn_dbx_path(d.folder || case
           when d.legacy and d.doc_type = 'Catalogue' then 'Catalogue - ' || regexp_replace(d.path, '^.*/', '')
           when d.legacy then d.doc_type || ' - ' || regexp_replace(d.path, '^.*/', '')
           when d.doc_type = 'Signed Terms & Conditions' then 'Signed Supplier Agreement.pdf'
           when d.doc_type = 'Catalogue' then d.sub || public.fn_dbx_original_name(d.path)
           else d.sub || d.label || ' - ' || public.fn_dbx_original_name(d.path) end),
         'S:' || d.id || ':' || case when d.doc_type = 'Catalogue' then 'cat' else d.doc_type end || ':' || d.path, null::bigint
    from docs d
  union all
  -- Company Details.pdf, ours, on the template
  select l.id, l.demo, l.legacy, 'Company Details', null, null, null, 'supplier_details', l.id::text,
         public.fn_dbx_path(l.folder || 'Company Details.pdf'), 'S:' || l.id || ':details', null::bigint
    from l
  union all
  -- one folder per job he quoted: our template quotation, as the customer is shown it
  select q.id, q.demo, false, 'Quotation', null, null, null, 'quotation', q.quote_id::text,
         public.fn_dbx_path(q.folder || q.job || '/' || case
           when q.stale_at is not null then 'Earlier versions/Quotation ' || substr(q.job, 5) || ' - '
                || to_char(q.created_at at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24MI') || '.pdf'
           when q.live_n > 1 then 'Quotation ' || substr(q.job, 5) || ' - option ' || q.opt || '.pdf'
           else 'Quotation ' || substr(q.job, 5) || '.pdf' end),
         'SQ:' || q.id || ':' || q.quote_id || ':' || public.fn_dbx_quote_revision(q.quote_id), null::bigint
    from q
  union all
  -- and his own file, when he uploaded one
  select q.id, q.demo, false, 'Supplier quotation (original)', 'quote-files', q.original_file_path, regexp_replace(q.original_file_path, '^.*/', ''),
         null, null,
         public.fn_dbx_path(q.folder || q.job || '/' || case when q.stale_at is not null then 'Earlier versions/' else '' end
           || 'Original as sent - ' || coalesce(public.fn_dbx_safe(nullif(btrim(q.original_file_name), '')), public.fn_dbx_original_name(q.original_file_path))),
         'SQO:' || q.id || ':' || q.quote_id, null::bigint
    from q where length(coalesce(q.original_file_path, '')) > 0
  union all
  -- EARLIER VERSIONS: a file of his already queued that is no longer on his row (a replaced licence, profile, agreement, catalogue,
  -- certificate). It is named by its own doc_type, so a row whose doc_type was corrected keeps the correction.
  select l.id, l.demo, false, d.doc_type, d.bucket, d.path, d.file_name, null, null,
         public.fn_dbx_path(l.folder || 'Earlier versions/'
           || case d.doc_type when 'Signed Terms & Conditions' then 'Signed Supplier Agreement' when 'Manufacturer authorization' then 'Manufacturer authorisation'
                              else d.doc_type end
           || ' - ' || to_char(coalesce(o.created_at, d.created_at) at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24MI')
           || case when d.doc_type = 'Signed Terms & Conditions' then '.pdf' else ' - ' || public.fn_dbx_original_name(d.path) end),
         regexp_replace(d.dedupe_key, '^SBX:[A-Za-z0-9-]+:', ''), d.id
    from public.doc_backups d
    join l on l.id::text = case when d.entity = 'zz_demo' then substr(d.entity_id, 10) else d.entity_id end
    left join storage.objects o on o.bucket_id = d.bucket and o.name = d.path
   where d.entity in ('supplier', 'zz_demo') and (d.entity = 'supplier' or d.entity_id like 'supplier:%')
     and not l.legacy and d.source = 'storage' and d.bucket in ('supplier-docs', 'signed-terms')
     and d.dedupe_key ~ ('^(SBX:[A-Za-z0-9-]+:)?S:' || l.id || ':')
     and not exists (select 1 from docs x where x.id = l.id and x.bucket = d.bucket and x.path = d.path)
     -- while the licence slot is being read (the 15 minutes above) the licence on file stays where it is: if the new upload is not a
     -- licence, the row is put back to it and nothing has moved
     and not (d.doc_type = 'Trade licence' and coalesce(l.licence_read_state, '') = 'ours_failed' and l.licence_read_at > now() - interval '15 minutes')
     and not exists (select 1 from public.agent_actions a where a.kind = 'licence_wrong_document' and a.target_id = l.id::text
                        and a.detail ->> 'path' = d.path)
  union all
  -- A FILE THE MODEL SAID IS NOT A LICENCE (agent_actions licence_wrong_document, #1985/#1992): never "Trade licence"; it is filed
  -- with the earlier versions under what the model read it as. Until today it reached Dropbox only in the raw Storage/ mirror.
  select l.id, l.demo, false, w.label || ' (sent as trade licence)', 'supplier-docs', w.path, regexp_replace(w.path, '^.*/', ''), null, null,
         public.fn_dbx_path(l.folder || 'Earlier versions/' || w.label || ' (sent as trade licence) - '
           || to_char(coalesce(o.created_at, w.at) at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24MI') || ' - ' || public.fn_dbx_original_name(w.path)),
         'S:' || l.id || ':wrong:' || w.path, null::bigint
    from l
    join lateral (select distinct on (a.detail ->> 'path') a.detail ->> 'path' as path, a.created_at as at,
                         case a.detail ->> 'kind' when 'company_profile' then 'Company profile' when 'catalogue' then 'Catalogue'
                              when 'quotation_or_invoice' then 'Quotation or invoice' when 'identity_document' then 'Identity document'
                              when 'certificate' then 'Certificate' else 'Not a trade licence' end as label
                    from public.agent_actions a
                   where a.kind = 'licence_wrong_document' and a.target_id = l.id::text and length(coalesce(a.detail ->> 'path', '')) > 0
                   order by a.detail ->> 'path', a.created_at) w on true
    left join storage.objects o on o.bucket_id = 'supplier-docs' and o.name = w.path
   where not l.legacy
     and w.path is distinct from l.license_doc_path
$fn$;
revoke execute on function public.fn_dbx_supplier_files() from public, anon, authenticated;

-- the internal credential dropbox_backup presents (app_secrets cred_fn_dropbox_backup = internal_credential fn.dropbox_backup, scope
-- pdf_native, measured 13 Nov 2026) may now open ONE door of customer_api: quotation_for_backup, which checks the door-only scope
-- 'customer_api.quotation_for_backup' (review of #1997, D2). The function-wide scope 'customer_api' also opens compare_arabic_finish
-- (sends a comparison report to a customer) and rematch_waiting (e-mails suppliers); the backup credential is not given it.
update public.internal_credential
   set scope = scope || array['customer_api.quotation_for_backup']
 where context = 'fn.dropbox_backup' and active and not ('customer_api.quotation_for_backup' = any(scope));

-- ── the two claim routines (live definitions; a row the old worker cannot do is claimed only by the new one) ─────────────────
CREATE OR REPLACE FUNCTION public.fn_doc_backups_next(p_limit integer DEFAULT 8, p_run text DEFAULT NULL::text, p_demo boolean DEFAULT false)
 RETURNS SETOF doc_backups
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if coalesce(btrim(p_run), '') = '' then raise exception 'fn_doc_backups_next: p_run (the claiming run id) is required'; end if;
  update public.doc_backups d set status = 'pending', claimed_at = null, claimed_by = null,
         error = left('claim by ' || coalesce(d.claimed_by, '?') || ' expired after 10 minutes; requeued', 300)
   where d.status = 'processing' and d.claimed_at < now() - interval '10 minutes';
  update public.doc_backups d set status = 'pending', error = null
   where d.status = 'waiting_source'
     and exists (select 1 from storage.objects o where o.bucket_id = d.bucket and o.name = d.path);
  return query
    with c as (
      select d.id from public.doc_backups d
       where d.status in ('pending', 'error') and d.attempts < 5
         -- a row the old worker cannot do (a quotation to render, a file to MOVE) is claimed only by a worker that says it can
         -- ('moves1' in its run id, dropbox_backup since 13 Nov 2026): between this file and that deploy the old worker would fail
         -- a quotation five times and upload a second copy instead of moving (review of #1997, D1)
         and ((d.gen_kind is distinct from 'quotation' and d.gen_kind is distinct from 'quotation_customer' and d.moved_from is null)
              or position('moves1' in p_run) > 0)
         and (d.entity = 'zz_demo') = coalesce(p_demo, false)
         and (d.status = 'pending' or d.last_attempt_at is null
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.attempts, 8)))
       order by (d.upload_state is not null) desc, d.id
       limit greatest(1, least(coalesce(p_limit, 8), 25))
       for update skip locked)
    update public.doc_backups d set status = 'processing', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_doc_backups_sandbox_next(p_tag text, p_limit integer, p_run text)
 RETURNS SETOF doc_backups
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
         -- a row the old worker cannot do (a quotation to render, a file to MOVE) is claimed only by a worker that says it can
         -- ('moves1' in its run id, dropbox_backup since 13 Nov 2026): between this file and that deploy the old worker would fail
         -- a quotation five times and upload a second copy instead of moving (review of #1997, D1)
         and ((d.gen_kind is distinct from 'quotation' and d.gen_kind is distinct from 'quotation_customer' and d.moved_from is null)
              or position('moves1' in p_run) > 0)
         and (d.status = 'pending' or d.last_attempt_at is null
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.attempts, 8)))
       order by (d.upload_state is not null) desc, d.id
       limit greatest(1, least(coalesce(p_limit, 8), 25))
       for update skip locked)
    update public.doc_backups d set status = 'processing', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $function$
;

-- ── the enqueue (live definition; the supplier section and the supplier correspondence folder are new) ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_enqueue_doc_backups()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer := 0; m integer;
  -- the dedupe-key prefix of a tagged sandbox run (trg_doc_backups_admit adds it on insert; the re-file below matches with it)
  v_kp text := case when coalesce(current_setting('qd.backup_sandbox', true), '') ~ '^[A-Za-z0-9-]{6,40}$'
                    then 'SBX:' || current_setting('qd.backup_sandbox', true) || ':' else '' end;
begin
  -- ============ SUPPLIERS (13 Nov 2026, ruling 1680: Suppliers/<main category>/<company as on the trade licence>/) ============
  -- The rule is fn_dbx_supplier_files (one pass): every file of every registered supplier who has a name and a main category, and
  -- where it goes. Two steps, in this order:
  -- (0) A FOLDER THAT CHANGED (the model changed his main category, or the name on his licence changed): every row of his that sits
  --     in a supplier folder other than his ruled one - his correspondence and case summaries too - is pointed at the ruled folder
  --     (same relative path) and MOVED (moved_from), never copied; step (1) then names each document. A row being uploaded while the
  --     folder changed finishes in the old folder and is moved by the next run (review of #1997, D7: it used to stay behind for good).
  --     Not for a legacy folder (that is the founder's migration).
  update public.doc_backups d
     set moved_from = case when d.status = 'done' then coalesce(d.moved_from, d.dropbox_path) else d.moved_from end,
         dropbox_path = case when d.entity = 'zz_demo' then x.sbx_folder else x.folder end
                        || substring(d.dropbox_path from '^/QuotesDone Backup(?:/_sandbox/[^/]+)?/Suppliers/[^/]+/[^/]+/(.*)$'),
         status = 'pending', error = null, attempts = 0, upload_state = null, backed_up_at = null, verified_at = null, requeued_at = now()
    from (select f.lead_id, f.is_demo, f.folder,
                 case when v_kp <> '' then '/QuotesDone Backup/_sandbox/' || split_part(v_kp, ':', 2) || substr(f.folder, 19) end as sbx_folder
            from public.fn_dbx_supplier_folders() f where f.folder is not null and not f.legacy) x
   where ((d.entity = 'supplier' and d.entity_id = x.lead_id::text and not x.is_demo)
       or (v_kp <> '' and d.entity = 'zz_demo' and d.entity_id = 'supplier:' || x.lead_id and d.dedupe_key like v_kp || '%'))
     and d.dropbox_path ~ '^/QuotesDone Backup(/_sandbox/[^/]+)?/Suppliers/[^/]+/[^/]+/.'
     and case when d.entity = 'zz_demo' then x.sbx_folder else x.folder end is not null
     and not starts_with(d.dropbox_path, case when d.entity = 'zz_demo' then x.sbx_folder else x.folder end)
     and d.status in ('done', 'error', 'pending', 'waiting_source');
  get diagnostics m = row_count; n := n + m;

  -- (Q) A QUOTATION THAT WAS REVISED (review of #1997, D4): the row of the earlier revision - in his Job folder or in the customer's
  --     Quotes/ - moves to Earlier versions/ beside it, "<name> - <Dubai date time it was filed>.pdf", and step (2) files the current
  --     revision under the plain name. A revision never filed yet (still queued) is abandoned: it would render the new figures.
  update public.doc_backups d
     set moved_from = case when d.status = 'done' then coalesce(d.moved_from, d.dropbox_path) else d.moved_from end,
         dropbox_path = regexp_replace(d.dropbox_path, '/([^/]+)\.pdf$',
                          '/Earlier versions/\1 - ' || to_char(coalesce(d.backed_up_at, d.created_at) at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24MI') || '.pdf'),
         dedupe_key = d.dedupe_key || ':earlier',
         status = case when d.status = 'done' then 'pending' else 'abandoned' end,
         error = case when d.status = 'done' then null else 'superseded by a later revision of the quotation before it was filed' end,
         attempts = 0, upload_state = null, backed_up_at = null, verified_at = null, requeued_at = now()
    from (select f.gen_ref, f.dedupe_key, 'SQ' as side from public.fn_dbx_supplier_files() f where f.gen_kind = 'quotation'
          union all
          select c.quote_id::text, c.dedupe_key, 'CQ' from public.fn_dbx_customer_quotation_files() c) cur
   where d.gen_kind in ('quotation', 'quotation_customer') and d.gen_ref = cur.gen_ref
     and substring(d.dedupe_key from '(?:^|:)(SQ|CQ):') = cur.side
     and regexp_replace(d.dedupe_key, '^SBX:[A-Za-z0-9-]+:', '') <> cur.dedupe_key
     and d.dedupe_key !~ ':earlier$' and d.dropbox_path !~ '/Earlier versions/'
     and (d.dedupe_key not like 'SBX:%' or (v_kp <> '' and d.dedupe_key like v_kp || '%'))
     and d.status in ('done', 'error', 'pending', 'waiting_source');
  get diagnostics m = row_count; n := n + m;

  -- (1) A FILE ALREADY QUEUED THAT THE RULE PUTS SOMEWHERE ELSE IS RE-FILED, NOT COPIED: the same row, pointed at the ruled path and
  --     queued again; when it was already in Dropbox, moved_from keeps where it is and the worker MOVES it (files/move_v2). This covers
  --     a category or licensed name that changed, a replaced upload going to Earlier versions/, and a file the hourly Storage/ sweep
  --     claimed first (doc_backups is unique on (bucket, path), so an insert could never file it: before today only a supplier named
  --     from no name had his sweep rows re-filed, and they were copied, leaving a second copy in Storage/). Inside a LEGACY folder
  --     (opened under the old rule) nothing of his is renamed: only a file the sweep claimed is brought in, under the old naming.
  --     Never a demo file into the real tree (a tagged sandbox run re-files only its own rows, under _sandbox/<tag>/), never a row
  --     being uploaded, pruned or abandoned, never onto a key another row holds.
  update public.doc_backups d
     set moved_from = case when d.status = 'done' then coalesce(d.moved_from, d.dropbox_path) else d.moved_from end,
         dropbox_path = x.to_path,
         entity = case when d.entity = 'zz_demo' then 'zz_demo' else 'supplier' end,
         entity_id = case when d.entity = 'zz_demo' then 'supplier:' || x.lead_id else x.lead_id::text end,
         doc_type = x.doc_type, dedupe_key = x.to_key,
         status = 'pending', error = null, attempts = 0, upload_state = null, backed_up_at = null, verified_at = null, requeued_at = now()
    from (select d0.id, f.lead_id, f.doc_type,
                 case when d0.dedupe_key like 'SBX:%' then '/QuotesDone Backup/_sandbox/' || split_part(d0.dedupe_key, ':', 2) || substr(f.dropbox_path, 19)
                      else f.dropbox_path end as to_path,
                 case when d0.dedupe_key like 'SBX:%' then 'SBX:' || split_part(d0.dedupe_key, ':', 2) || ':' || f.dedupe_key else f.dedupe_key end as to_key
            from public.fn_dbx_supplier_files() f
            join public.doc_backups d0
              on d0.id = f.row_id
              or (f.row_id is null and (d0.dedupe_key = f.dedupe_key or (v_kp <> '' and d0.dedupe_key = v_kp || f.dedupe_key)))
              or (f.row_id is null and f.bucket is not null and d0.bucket = f.bucket and d0.path = f.path)
           where d0.status in ('done', 'error', 'pending', 'waiting_source')
             and (not f.is_demo or d0.dedupe_key like 'SBX:%')
             and (d0.dedupe_key not like 'SBX:%' or (v_kp <> '' and d0.dedupe_key like v_kp || '%'))
             and (not f.legacy or d0.dedupe_key !~ '^(SBX:[A-Za-z0-9-]+:)?S:')) x
   where d.id = x.id
     and d.dropbox_path is distinct from x.to_path
     and not exists (select 1 from public.doc_backups o where o.dedupe_key = x.to_key and o.id <> d.id);
  get diagnostics m = row_count; n := n + m;

  -- (2) every file the rule wants that is not queued yet
  insert into public.doc_backups(entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, gen_kind, gen_ref, dedupe_key)
  select 'supplier', f.lead_id::text, f.doc_type, f.bucket, f.path, f.file_name, f.dropbox_path,
         case when f.gen_kind is null then 'storage' else 'generated' end, f.gen_kind, f.gen_ref, f.dedupe_key
    from public.fn_dbx_supplier_files() f
   where f.row_id is null
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- (3) THE CUSTOMER'S COPY of every quotation (review of #1997, D6), in his request's Quotes/ folder, as he was shown it
  insert into public.doc_backups(entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  select 'inquiry', c.inquiry_id::text, 'Quotation (as shown to the customer)', 'generated', 'quotation_customer', c.quote_id::text, c.dropbox_path, c.dedupe_key
    from public.fn_dbx_customer_quotation_files() c
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
  -- 13 Nov 2026 (ruling 1680): a registered supplier's correspondence goes in his ruled folder (fn_dbx_supplier_folders); the
  -- function runs only for a supplier's message (the one-time filter on v.party_kind), and for that supplier only (review D8)
  left join lateral (select f.lead_id as id, f.folder from public.fn_dbx_supplier_folders(case when v.party_id ~ '^[0-9]{1,18}$' then v.party_id::bigint else -1 end) f
                      where v.party_kind = 'supplier' and v.party_id ~ '^[0-9]{1,18}$') l on true
  cross join lateral (select
      case when c.id is not null then 'customer' when l.folder is not null then 'supplier' else 'company' end as entity,
      coalesce(c.id::text, case when l.folder is not null then l.id::text end, v.source_table || ':' || v.source_id) as entity_id,
      case when c.id is not null then
             '/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(c.full_name,'Customer')) || ' (' || left(c.id::text,8) || ')/'
             || case when i.id is not null then 'Inquiries/' || to_char(i.created_at,'YYYY-MM-DD') || ' ' || left(i.id::text,8)
                       || ' - ' || public.fn_dbx_safe(coalesce(i.status,'inquiry')) || '/' else '' end
             || 'Correspondence/'
           when l.folder is not null then l.folder || 'Correspondence/'
           else '/QuotesDone Backup/Company/Correspondence/' || to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
      end as base,
      to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM-DD HH24MI') || ' ' || v.direction || ' ' || v.channel || ' - '
        || public.fn_dbx_safe(left(coalesce(nullif(btrim(v.subject),''),'(no subject)'),80)) || ' #' || v.source_id || '.pdf' as fname) x
  -- a tagged sandbox run (fn_backup_sandbox_enqueue) lets its own demo messages through; trg_doc_backups_admit
  -- files them under _sandbox/<tag>/ and drops every other demo row exactly as before
  where (not v.is_demo or coalesce(current_setting('qd.backup_sandbox', true), '') <> '')
    -- a supplier not yet named by his licence waits: queued by the sweep after the name lands, under the name (ruling 1672);
    -- 13 Nov 2026: so does a registered supplier the model has not yet given a trade (no main category, no folder: ruling 1680)
    and not (v.party_kind = 'supplier' and exists (select 1 from public.leads b where b.id::text = v.party_id and coalesce(btrim(b.company_name), '') = ''))
    and not (v.party_kind = 'supplier' and l.id is not null and l.folder is null)
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

-- ── the admit trigger (live definition; the legacy anchor applies only to that supplier's own rows) ──────────────────────────
CREATE OR REPLACE FUNCTION public.trg_doc_backups_admit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- 13 Nov 2026 (ruling 1680): a folder named by the new rule carries no id; a company whose licensed name itself ends in
  -- "(<digits>)" must never be anchored to another supplier's folder, so the anchor applies only to that supplier's own rows
  if v_id is not null and new.entity = 'supplier' and new.entity_id = v_id then
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
end $function$
;

-- ── a case summary in a supplier's folder (live definition; the folder is his ruled one) ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_support_case_summary_backup_enqueue(p_case_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c public.support_case; p public.support_customer_profile; v_entity text; v_id text; v_base text;
begin
  -- a brake, not a gate: the text file needs no renderer (11 Nov 2026)
  if coalesce((select value from public.app_secrets where key = 'case_summary_backup_enabled'), '') = 'false' then return false; end if;
  select * into c from public.support_case where case_id = p_case_id;
  if c.case_id is null or c.summary is null then return false; end if;
  select * into p from public.support_customer_profile where id = c.customer_profile_id;
  -- the person's folder, as fn_enqueue_doc_backups names it; the admit trigger re-anchors it to their first named folder
  if p.customer_id is not null then
    select '/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(cu.full_name, 'Customer')) || ' (' || left(cu.id::text, 8) || ')/'
      into v_base from public.customers cu where cu.id = p.customer_id;
    v_entity := 'customer'; v_id := p.customer_id::text;
  elsif p.lead_id is not null then
    -- 13 Nov 2026 (ruling 1680): his ruled folder; none yet (no name or no main category) and the summary waits for its next version
    v_base := public.fn_dbx_supplier_folder(p.lead_id);
    v_entity := 'supplier'; v_id := p.lead_id::text;
  end if;
  if v_base is null then return false; end if;
  insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, file_name, dropbox_path, status, dedupe_key)
  values (v_entity, v_id, 'Case Summary', 'generated', 'case_summary', c.case_ref, c.case_ref || '.md',
          v_base || 'cases/' || c.case_ref || '.md', 'pending', 'CASE:' || c.case_ref)
  on conflict (dedupe_key) do update
     set status = 'pending', bucket = null, path = null, upload_state = null, error = null, attempts = 0,
         requeued_at = now(), claimed_at = null, claimed_by = null, last_attempt_at = null
   where doc_backups.status not in ('prune_pending', 'pruning', 'pruned');
  return found;
end $function$
;
