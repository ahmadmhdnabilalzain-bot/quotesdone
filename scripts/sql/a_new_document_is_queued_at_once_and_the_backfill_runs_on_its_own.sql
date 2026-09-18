-- A NEW DOCUMENT IS QUEUED AT ONCE, AND THE BACKFILL RUNS ON ITS OWN.
--
-- Assigned: it_engineer. 15 Sep 2026. URGENT: a live data-backup regression.
--
-- The founder's standing rule: "that data should never get lost no matter what".
--
-- MEASURED (15 Sep 2026, production):
--   * PR #716 (applied 09:24Z) added a STORAGE SWEEP section to fn_enqueue_doc_backups, and PR #720
--     (~09:43Z) a LEGACY EXPORTS section. dropbox_backup calls fn_enqueue_doc_backups through PostgREST,
--     whose role `authenticator` carries statement_timeout=8s. At 09:29:00Z agent_runs logged
--     dropbox_backup {stage:enqueue, signal:enqueue_failed} "canceling statement due to statement
--     timeout"; that log line is throttled to once an hour, so every later failure was silent. From
--     09:24Z doc_backups received ZERO new rows: not the backfill only, but every new customer and
--     supplier document stopped being queued for Dropbox. fn_conversation_archived and
--     fn_table_export_finish call the same routine through PostgREST and hit the same wall.
--   * One call as postgres (no 8 s limit), 10:10Z: 50.65 s, 400 rows (200 sweep + 200 legacy, 0 owner).
--   * Per section, read-only (clock_timestamp around each candidate SELECT): the owner rules are
--     20-30 ms each except CORRESPONDENCE at 2.8 s (the v_conversation_message view; 169 archive rows;
--     pre-filtering the archive by dedupe key does not help, 2.78 s); LEGACY EXPORTS candidates 18 ms,
--     the waiting count 3 ms; fn_backup_sweep_objects() 47,809 ms for 1,091 rows. The raw anti-join of
--     the swept buckets against doc_backups is 21 ms, so the cost was the sweep routine, not the data.
--   * WHY THE SWEEP TOOK 48 s: the planner flattened its LATERAL subqueries into the scan's filter. The
--     owner COALESCE (four correlated subqueries) was copied into every place x.entity, x.id and w.* are
--     used -- EXPLAIN shows 335 SubPlans -- and evaluated for every object of every swept bucket, the
--     8,369 files of 'backups' included, because the cheap path exclusions sat in the same filter.
--     ~5 ms x 9,352 rows.
--
-- WHAT CHANGES:
--   1. fn_backup_sweep_objects: the same rows, the same columns, the same exclusions, reordered. The
--      cheap filters (swept bucket, path shape, ZZ DEMO name, export and conversation folders, PDPL
--      erasure list) run first in a MATERIALIZED CTE, and the owner and demo/email LATERALs carry
--      OFFSET 0 so each is computed once per row. Measured: 47,809 ms -> 125 ms (EXPLAIN ANALYZE of
--      this body on production). The backup_gap duty and fn_it_backup_expected, which call it, speed
--      up the same way.
--   2. fn_enqueue_doc_backups keeps ONLY the owner rules for documents (SUPPLIERS, CUSTOMERS, INQUIRIES,
--      REVENUE INVOICES, CORRESPONDENCE, ACCOUNTING, TABLE EXPORTS): the MANIFEST-last body
--      (every_old_export_reaches_dropbox_and_no_export_is_pruned_without_a_verified_copy.sql) with its
--      last two sections removed and nothing else touched. Every caller (dropbox_backup,
--      fn_conversation_archived, fn_table_export_finish, fn_accountant_year_end_pack_attach,
--      fn_sales_engineer_refiles_backup) now gets a bounded call.
--   3. fn_enqueue_doc_backups_backfill(p_limit default 200) holds LEGACY EXPORTS and STORAGE SWEEP,
--      moved verbatim: the advisory lock, the legacy-day definition, the retention-recognised shape, at
--      most p_limit legacy rows waiting, at most p_limit swept files per call, oldest first, files over
--      an hour old, the sweep's exclusions and owners. Idempotent on (bucket, path) and on the dedupe key
--      (not exists + on conflict do nothing on both unique indexes), so rows the manual stopgap enqueue
--      already queued are skipped.
--   4. dropbox_backup calls the backfill as a SECOND statement after the new-document enqueue, so a slow
--      or failing backfill can no longer stop a new document being queued.
--   5. NEVER SILENT AGAIN, two ways:
--      * fn_backup_enqueue_outcome(stage, error): dropbox_backup reports each call's outcome; an error
--        raises it_engineer_finding 'duty:backup_enqueue_<stage>:failing' (deduped by issue key), a clean
--        call closes it. A throttled log line is no longer the only trace.
--      * fn_backup_enqueue_watch(), a stage of fn_it_backup_tick (every 15 minutes, from resilience_ping):
--        a stored supplier, customer, inquiry or invoice document older than an hour with no doc_backups
--        row, or a customer, registrant supplier or inquiry over an hour old without its generated PDF row,
--        raises 'duty:backup_enqueue_watch:unqueued_documents'; it closes when they are queued. This
--        catches a stopped enqueue even when dropbox_backup never runs. It is the 1-hour watch for the
--        owner rules; the backup_gap duty (swept files, 24 hours) and fn_backup_coverage (48 hours, to the
--        CEO) are unchanged.
--
-- WHAT THIS DOES NOT CHANGE: the owner rules' SQL, CORRESPONDENCE's 2.8 s (the largest remaining cost of
-- the new-document enqueue; a ceiling if conversations grow by orders of magnitude -- the fix then is the
-- view, not this routine), retention, the uploader, fn_backup_source_registry (its enqueue_rule texts say
-- "fn_enqueue_doc_backups: STORAGE SWEEP"; the sweep is found by that marker, not by routine name).
-- fn_sales_engineer_refiles_backup still calls fn_enqueue_doc_backups for a never-queued file; a swept
-- file is then filed by its own REFILE row rather than a SWEEP row, which fn_it_backup_expected_status
-- matches the same way (bucket, path).
--
-- APPLY ORDER: after PR #720's file. Then deploy dropbox_backup. The manual stopgap enqueue should then
-- call fn_enqueue_doc_backups_backfill() instead of fn_enqueue_doc_backups() (or stop: the edge does it).
--   node scripts/apply_sql.mjs scripts/sql/a_new_document_is_queued_at_once_and_the_backfill_runs_on_its_own.sql --apply --ddl
--   node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production dropbox_backup
-- Probe (aborted transaction under an 8 s statement_timeout, commits nothing):
--   node scripts/apply_sql.mjs scripts/checks/a_new_document_is_queued_at_once.probe.sql --apply --ddl

-- ── 1. fn_backup_sweep_objects: the same list, computed once per file ────────────────────────────

create or replace function public.fn_backup_sweep_objects()
 RETURNS TABLE(bucket text, path text, bytes bigint, created_at timestamp with time zone, entity text, entity_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- The cheap filters first, once: without the fence the planner evaluated the owner lookups below for
  -- every object of every swept bucket, 8,369 export pages included (47.8 s measured; 125 ms with it).
  with o as materialized (
    select o.bucket_id, o.name, o.metadata, o.created_at
      from storage.objects o
     where o.bucket_id in (select r.bucket from public.fn_backup_source_registry() r
                            where r.kind = 'bucket' and r.backed_up and r.enqueue_rule like '%STORAGE SWEEP%')
       and right(o.name, 1) <> '/' and o.name !~ '(^|/)\.emptyFolderPlaceholder$'
       and o.name !~* 'zz[ _-]?demo'
       and not (o.bucket_id = 'backups' and o.name ~ '^(\d{4}-\d{2}-\d{2}|conversations)/')
       and not (o.bucket_id = 'signed-terms' and o.name like 'registers/%')
       and not exists (select 1 from public.pdpl_erase_files e where e.bucket = o.bucket_id and e.storage_path = o.name))
  select o.bucket_id, o.name, coalesce((o.metadata->>'size')::bigint, 0), o.created_at, x.entity, x.id
    from o
    cross join lateral (select
        (regexp_match(o.name, '^generated/\d+_(customer_details|inquiry_summary|comparison|supplier_details)_([0-9a-f_]{36}|\d{1,18})\.pdf$', 'i')) as gen,
        split_part(o.name, '/', 2) as seg2, split_part(o.name, '/', 3) as seg3) p
    -- OFFSET 0 keeps this a subquery computed once per row; flattened, it was copied into every reference.
    cross join lateral (select coalesce(
        (select case d.ref_table when 'customers' then 'customer' when 'inquiries' then 'inquiry'
                                 when 'quotes' then 'quote' when 'leads' then 'supplier' end || ':' || d.ref_id
           from public.documents d
          where d.bucket = o.bucket_id and d.path = o.name
            and d.ref_table in ('customers', 'inquiries', 'quotes', 'leads') and coalesce(d.ref_id, '') <> '' limit 1),
        (select 'customer:' || c.customer_id from public.quote_pdf_cache c
          where c.bucket = o.bucket_id and c.path = o.name and c.customer_id is not null limit 1),
        (select 'customer:' || t.customer_id from public.reveal_invoices ri join public.transactions t on t.id = ri.transaction_id
          where ri.bucket = o.bucket_id and ri.path = o.name and t.customer_id is not null limit 1),
        (select 'quote:' || q.id from public.quotes q where o.bucket_id = 'quote-files' and q.original_file_path = o.name limit 1),
        case when o.bucket_id = 'backups' and p.gen is not null then
               case lower(p.gen[1]) when 'customer_details' then 'customer' when 'supplier_details' then 'supplier' else 'inquiry' end
               || ':' || replace(lower(p.gen[2]), '_', '-') end,
        case when o.bucket_id = 'supplier-docs' and p.seg2 ~ '^\d{1,18}$' then 'supplier:' || p.seg2 end,
        case when o.bucket_id = 'drawing-files' and p.seg2 ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then 'inquiry:' || lower(p.seg2) end,
        case when o.bucket_id = 'quote-files' and p.seg3 ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then 'inquiry:' || lower(p.seg3) end,
        'company:storage/' || o.bucket_id) as owner
      offset 0) y
    cross join lateral (select split_part(y.owner, ':', 1) as entity, substr(y.owner, strpos(y.owner, ':') + 1) as id) x
    -- the owner row behind it: is it demo (null when the row is gone), and which customer email, for PDPL.
    -- Each cast is inside CASE behind the shape test that makes it safe.
    left join lateral (select
        case x.entity
          when 'supplier' then (select coalesce(l.is_demo, false) from public.leads l
                                 where l.id = case when x.id ~ '^\d{1,18}$' then x.id::bigint end)
          when 'customer' then (select coalesce(c.is_demo, false) from public.customers c
                                 where c.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'inquiry'  then (select coalesce(c.is_demo, false) from public.inquiries i left join public.customers c on c.id = i.customer_id
                                 where i.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'quote'    then (select coalesce(l.is_demo, false) or coalesce(c.is_demo, false)
                                  from public.quotes q left join public.leads l on l.id = q.supplier_id
                                  left join public.inquiries i on i.id = q.inquiry_id left join public.customers c on c.id = i.customer_id
                                 where q.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
        end as demo,
        case x.entity
          when 'customer' then (select c.email from public.customers c
                                 where c.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'inquiry'  then (select c.email from public.inquiries i join public.customers c on c.id = i.customer_id
                                 where i.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'quote'    then (select c.email from public.quotes q join public.inquiries i on i.id = q.inquiry_id
                                  join public.customers c on c.id = i.customer_id
                                 where q.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
        end as email
      offset 0) w on true
   where not coalesce(w.demo, false)
     and not (x.entity <> 'company' and w.demo is null
              and exists (select 1 from public.doc_backups z where z.entity = 'zz_demo' and z.entity_id = x.id))
     and not (w.email is not null and (w.email ~* '@removed\.invalid$'
              or exists (select 1 from public.pdpl_requests r
                          where r.kind = 'delete' and coalesce(r.status, '') not in ('rejected', 'withdrawn', 'cancelled')
                            and lower(r.email) = lower(w.email))));
$function$;
revoke execute on function public.fn_backup_sweep_objects() from public, anon, authenticated;

-- ── 2. fn_enqueue_doc_backups: the owner rules only ──────────────────────────────────────────────

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

  -- LEGACY EXPORTS and the STORAGE SWEEP are fn_enqueue_doc_backups_backfill (15 Sep 2026): together they
  -- took this call from milliseconds to 50 s, past PostgREST's 8 s, and every new document stopped.
  return n;
end $function$;
revoke execute on function public.fn_enqueue_doc_backups() from public, anon, authenticated;

-- ── 3. fn_enqueue_doc_backups_backfill: LEGACY EXPORTS and the STORAGE SWEEP, on their own call ────

create or replace function public.fn_enqueue_doc_backups_backfill(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare n integer := 0; m integer;
begin
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'fn_enqueue_doc_backups_backfill: p_limit is 1..1000 (got %)', p_limit;
  end if;

  -- ============ LEGACY EXPORTS (15 SEP 2026, it_engineer) ============
  -- The founder: "that data should never get lost no matter what". backup v1's dated folders (on or
  -- before 2026-09-07, no table_export_run row: the legacy-day definition fn_backup_prune_days uses) are
  -- filed exactly like a TABLE EXPORTS day, so retention recognises the copies. At most p_limit (200)
  -- legacy rows wait at a time, oldest day first: the uploader claims lowest id first, so a new customer
  -- or supplier document waits behind at most 200 export pages (measured median 2.6 MB). Refilled on
  -- every non-chained dropbox_backup run. One call at a time tops the queue up (review: a second scheduler
  -- and a kick can overlap, and each would read the same waiting count); a run that loses the lock skips
  -- only this section.
  if pg_try_advisory_xact_lock(hashtext('fn_enqueue_doc_backups:legacy_exports')) then
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
  limit greatest(0, p_limit - (select count(*) from public.doc_backups w
                                 where w.dedupe_key like 'EXPORT:%' and w.status in ('pending', 'processing', 'error', 'waiting_source')
                                   and w.bucket = 'backups' and split_part(w.path,'/',1) <= '2026-09-07'
                                   and not exists (select 1 from public.table_export_run r2 where r2.stamp::text = split_part(w.path,'/',1))))
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;
  end if;

  -- ============ STORAGE SWEEP (15 SEP 2026, it_engineer) ============
  -- The founder: "of course that data should never get lost no matter what". Every stored file no owner
  -- rule filed: fn_backup_sweep_objects() is the one list of what may be swept (the registry's swept
  -- buckets, without ZZ DEMO, demo owners, the export and conversation folders of backups, or any file
  -- of a customer PDPL is erasing; each row carries its real owner). Filed under Storage/<bucket>/<path> so the
  -- original path, which carries the supplier, inquiry or quote id, is kept. Only files over an hour
  -- old, so an owner rule that runs on the same upload files it first under its owner. At most p_limit
  -- (200) per call, oldest first: the backfill of existing files drains over successive runs.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select s.entity, s.entity_id, 'Stored file', s.bucket, s.path, regexp_replace(s.path,'^.*/',''),
         '/QuotesDone Backup/Storage/' || s.bucket || '/' || s.path,
         'storage', 'SWEEP:' || s.bucket || ':' || s.path
  from public.fn_backup_sweep_objects() s
  where s.created_at < now() - interval '1 hour'
    and not exists (select 1 from public.doc_backups d where d.bucket = s.bucket and d.path = s.path)
  order by s.created_at, s.bucket, s.path
  limit p_limit
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $function$;
-- created here, so EXECUTE went to PUBLIC: close it (service_role keeps its grant)
revoke execute on function public.fn_enqueue_doc_backups_backfill(integer) from public, anon, authenticated;

-- ── 4. NEVER SILENT: each enqueue call's outcome raises or closes a finding ───────────────────────

create or replace function public.fn_backup_enqueue_outcome(p_stage text, p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_stage is null or p_stage not in ('new_documents', 'backfill') then
    raise exception 'fn_backup_enqueue_outcome: stage is new_documents or backfill (got %)', p_stage;
  end if;
  -- One duty per stage, so a clean backfill never closes a failing new-document enqueue or the reverse.
  return public.fn_it_duty_settle('backup_enqueue_' || p_stage,
    case when p_error is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
      'item', 'failing', 'owner_seat', 'it_engineer', 'subject', 'dropbox_backup', 'blast', 'agent_facing', 'affected', 1,
      'title', case p_stage
                 when 'new_documents' then 'New documents are not being queued for Dropbox: fn_enqueue_doc_backups failed'
                 else 'The Dropbox backfill (storage sweep, pre-7-Sep exports) failed; new documents are still queued' end,
      'evidence', jsonb_build_object('error', left(p_error, 500), 'at', now(),
                    'routine', case p_stage when 'new_documents' then 'fn_enqueue_doc_backups' else 'fn_enqueue_doc_backups_backfill' end,
                    'caller', 'dropbox_backup')))
    end);
end $function$;
revoke execute on function public.fn_backup_enqueue_outcome(text, text) from public, anon, authenticated;

-- The 1-hour watch for the owner rules, independent of dropbox_backup running at all. The owner lists
-- are the SUPPLIERS / CUSTOMERS / INQUIRIES / REVENUE INVOICES rules of fn_enqueue_doc_backups: a file
-- they name that exists in storage, or a generated PDF row they create, missing after an hour is a
-- stopped enqueue. Demo owners and ZZ DEMO paths are left out (fn_it_backup_expected's filter).
create or replace function public.fn_backup_enqueue_watch()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
        ('supplier-docs', l.license_doc_path), ('supplier-docs', l.iban_doc_path), ('supplier-docs', l.egr_doc_path),
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
end $function$;
revoke execute on function public.fn_backup_enqueue_watch() from public, anon, authenticated;

-- fn_it_backup_tick: the MANIFEST-last body (an_export_day_reaches_dropbox_when_it_finishes.sql) with one
-- stage added, 'enqueue', FIRST: it is the cheapest stage (32 ms measured) and the one that tells a stopped
-- enqueue, so no slower stage runs ahead of it (review, 15 Sep 2026). A stage that throws is recorded by
-- fn_it_backup_stage_failed and the tick goes on.
create or replace function public.fn_it_backup_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o jsonb := '{}'::jsonb;
begin
  begin o := o || jsonb_build_object('enqueue', public.fn_backup_enqueue_watch());
  exception when others then o := o || jsonb_build_object('enqueue', public.fn_it_backup_stage_failed('enqueue', sqlerrm)); end;
  begin o := o || jsonb_build_object('recheck', public.fn_it_backup_recheck());
  exception when others then o := o || jsonb_build_object('recheck', public.fn_it_backup_stage_failed('recheck', sqlerrm)); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_backup_escalation_sweep());
  exception when others then o := o || jsonb_build_object('ceo', public.fn_it_backup_stage_failed('ceo', sqlerrm)); end;
  begin o := o || jsonb_build_object('watch', public.fn_backup_watch());
  exception when others then o := o || jsonb_build_object('watch', public.fn_it_backup_stage_failed('watch', sqlerrm)); end;
  begin o := o || jsonb_build_object('queue', public.fn_dropbox_queue_stale());
  exception when others then o := o || jsonb_build_object('queue', public.fn_it_backup_stage_failed('queue', sqlerrm)); end;
  begin o := o || jsonb_build_object('daily', public.fn_dropbox_backup_daily_report());
  exception when others then o := o || jsonb_build_object('daily', public.fn_it_backup_stage_failed('daily', sqlerrm)); end;
  return o || jsonb_build_object('reconcile', public.fn_dropbox_reconcile_due());
end $fn$;

-- ── PROBE: reads only, writes nothing (a file that defines routines must not raise). The timed fixture
-- probe is scripts/checks/a_new_document_is_queued_at_once.probe.sql. ──
do $probe$
declare v_bad int; v_body text;
begin
  select count(*) into v_bad from public.fn_backup_sweep_objects() s
   where s.path ~* 'zz[ _-]?demo'
      or (s.bucket = 'backups' and s.path ~ '^(\d{4}-\d{2}-\d{2}|conversations)/')
      or exists (select 1 from public.pdpl_erase_files e where e.bucket = s.bucket and e.storage_path = s.path);
  assert v_bad = 0, v_bad || ' swept file(s) the sweep must never offer';
  v_body := pg_get_functiondef('public.fn_enqueue_doc_backups()'::regprocedure);
  assert position('fn_backup_sweep_objects' in v_body) = 0 and position('advisory' in v_body) = 0,
    'fn_enqueue_doc_backups still carries a backfill section';
  raise notice 'sweep offers % file(s); fn_enqueue_doc_backups carries the owner rules only',
    (select count(*) from public.fn_backup_sweep_objects());
end $probe$;
