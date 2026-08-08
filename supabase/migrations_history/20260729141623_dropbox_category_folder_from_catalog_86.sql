-- WHY: Supplier Dropbox folders are supposed to sit inside their category folder, one of the 86 in
-- public.catalog_supplier_categories. They did not. fn_enqueue_doc_backups derived the folder name as
--   fn_dbx_safe(coalesce(nullif(btrim(split_part(leads.categories,',',1)),''), nullif(leads.sector,''), 'Uncategorized'))
-- i.e. the first comma-separated token of leads.categories (free-text Yellow-Pages/Maps text such as
-- 'building material suppliers'), falling back to leads.sector (a legacy ~66-value enum, of which only
-- a handful appear among engaged suppliers). Neither is the catalog taxonomy: 0 of 20,464 leads have a
-- categories token that matches any catalog_supplier_categories.slug. That is why Dropbox grew ~18
-- legacy folders ('flooring', 'combined-mep', 'cctv-security') plus strays like 'Suppliers/dj zaino'
-- (a supplier whose free-text categories was its own trading name) and 'Uncategorized'.
-- FIX: derive from lead_category -> catalog_supplier_categories, which maps 12,566 leads onto 83 of
-- the 86 real categories via an is_primary row. Fall back to any non-primary catalog mapping, then to
-- an exact slug/name match on the legacy text, then 'Uncategorized'.
-- SAFETY: this only changes how NEW dropbox_path values are computed. doc_backups.dedupe_key does not
-- include the path and every insert is ON CONFLICT (dedupe_key) DO NOTHING, so already-enqueued and
-- already-uploaded rows keep their existing paths and nothing in Dropbox is moved, renamed or deleted.
create or replace function public.fn_dbx_category(p_lead_id bigint)
returns text
language sql
stable
set search_path to 'public', 'pg_catalog'
as $function$
  select public.fn_dbx_safe(coalesce(
    -- 1. the supplier's primary catalog category (the real 86-item taxonomy)
    (select c.name from public.lead_category lc
       join public.catalog_supplier_categories c on c.slug = lc.slug
      where lc.lead_id = p_lead_id and lc.is_primary
      order by lc.score desc nulls last limit 1),
    -- 2. any catalog category we managed to map, best score first
    (select c.name from public.lead_category lc
       join public.catalog_supplier_categories c on c.slug = lc.slug
      where lc.lead_id = p_lead_id
      order by lc.score desc nulls last limit 1),
    -- 3. legacy text, but only when it is literally a catalog slug or catalog name
    (select c.name from public.leads l
       join public.catalog_supplier_categories c
         on c.slug = btrim(split_part(coalesce(l.categories,''),',',1))
         or lower(c.name) = lower(btrim(split_part(coalesce(l.categories,''),',',1)))
         or c.slug = btrim(coalesce(l.sector,''))
      where l.id = p_lead_id limit 1),
    'Uncategorized'));
$function$;

comment on function public.fn_dbx_category(bigint) is
  'Resolves the Dropbox category folder name for a supplier from catalog_supplier_categories (the 86 real categories) via lead_category. Replaces the legacy leads.categories/leads.sector free-text derivation. Used by fn_enqueue_doc_backups for NEW backup paths only.';

create or replace function public.fn_enqueue_doc_backups()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
declare n integer := 0; m integer;
begin
  with s as (
    select l.*,
      '/QuotesDone Backup/Suppliers/'
        || public.fn_dbx_category(l.id)
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
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
  from sd on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', s.id::text, 'Catalogue', 'supplier-docs', cat,
         regexp_replace(cat,'^.*/',''), s.base || 'Catalogue - ' || regexp_replace(cat,'^.*/',''),
         'storage', 'S:'||s.id||':cat:'||cat
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/'
        || public.fn_dbx_category(l.id)
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base, l.catalog_doc_paths
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)) and l.catalog_doc_paths is not null ) s,
    unnest(s.catalog_doc_paths) cat
  where cat is not null and length(cat)>0 on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'supplier', s.id::text, 'Company Details','generated','supplier_details', s.id::text,
         s.base || 'Company Details.pdf', 'S:'||s.id||':details'
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/'
        || public.fn_dbx_category(l.id)
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false) ) s
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'customer', c.id::text, 'Signed Terms & Conditions','signed-terms', c.signed_terms_path,
         regexp_replace(c.signed_terms_path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Signed Terms & Conditions - '||regexp_replace(c.signed_terms_path,'^.*/',''),
         'storage', 'C:'||c.id||':terms:'||c.signed_terms_path
  from public.customers c where c.signed_terms_path is not null and length(c.signed_terms_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, 'RFQ drawing','drawing-files', i.drawing_file_path,
         coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Drawing - '||coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         'storage', 'I:'||i.id||':drawing:'||i.drawing_file_path
  from public.inquiries i join public.customers c on c.id=i.customer_id
  where i.drawing_file_path is not null and length(i.drawing_file_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf', 'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- Quote comparison reports: one PDF per distinct quote-set (>=2 live quotes). Anonymized A/B/C.
  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Quote Comparison','generated','comparison', i.id::text,
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Quote Comparison Report '||to_char(now(),'YYYY-MM-DD')||' '||left(sig.sig,8)||'.pdf',
         'CMP:'||i.id||':'||sig.sig
  from public.inquiries i
  join public.customers c on c.id=i.customer_id
  join lateral ( select md5(coalesce(string_agg(q.quote_amount::text||':'||coalesce(q.status,''),'|' order by q.quote_amount),'')) as sig,
                        count(*) as nq
                 from public.quotes q where q.inquiry_id=i.id and q.status<>'draft' ) sig on true
  where sig.nq >= 2
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $function$;