-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710155830   name: doc_backups_structured_tree
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- allow generated rows (rendered later) + structured dedupe
alter table public.doc_backups
  add column if not exists source text not null default 'storage',
  add column if not exists gen_kind text,
  add column if not exists gen_ref text,
  add column if not exists dedupe_key text;
alter table public.doc_backups alter column bucket drop not null;
alter table public.doc_backups alter column path drop not null;
update public.doc_backups set dedupe_key = coalesce(dedupe_key, 'legacy:'||bucket||':'||path) where dedupe_key is null;
create unique index if not exists uq_doc_backups_dedupe on public.doc_backups(dedupe_key);

-- Dropbox-safe path segment
create or replace function public.fn_dbx_safe(x text) returns text language sql immutable set search_path to 'public','pg_catalog' as $$
  select btrim(regexp_replace(regexp_replace(coalesce(x,''),'[\\/:*?"<>|\r\n\t]+',' ','g'),'\s+',' ','g'))
$$;

-- Build the organized backup tree (idempotent). Suppliers scoped to REAL registrants (never the 20k directory leads).
create or replace function public.fn_enqueue_doc_backups()
returns integer language plpgsql security definer set search_path to 'public','pg_catalog' as $$
declare n integer := 0; m integer;
begin
  -- ============ SUPPLIERS ============
  with s as (
    select l.*,
      '/QuotesDone Backup/Suppliers/'
        || fn_dbx_safe(coalesce(nullif(btrim(split_part(coalesce(l.categories,''),',',1)),''), nullif(l.sector,''), 'Uncategorized'))
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)
  ),
  -- single-valued supplier docs
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
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- supplier catalogues (array)
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', s.id::text, 'Catalogue', 'supplier-docs', cat,
         regexp_replace(cat,'^.*/',''),
         s.base || 'Catalogue - ' || regexp_replace(cat,'^.*/',''),
         'storage', 'S:'||s.id||':cat:'||cat
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/'
        || fn_dbx_safe(coalesce(nullif(btrim(split_part(coalesce(l.categories,''),',',1)),''), nullif(l.sector,''), 'Uncategorized'))
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base,
      l.catalog_doc_paths
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false))
      and l.catalog_doc_paths is not null ) s,
    unnest(s.catalog_doc_paths) cat
  where cat is not null and length(cat)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- supplier generated "Company Details.pdf"
  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'supplier', s.id::text, 'Company Details','generated','supplier_details', s.id::text,
         s.base || 'Company Details.pdf', 'S:'||s.id||':details'
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/'
        || fn_dbx_safe(coalesce(nullif(btrim(split_part(coalesce(l.categories,''),',',1)),''), nullif(l.sector,''), 'Uncategorized'))
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false) ) s
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CUSTOMERS ============
  -- signed terms (storage)
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'customer', c.id::text, 'Signed Terms & Conditions','signed-terms', c.signed_terms_path,
         regexp_replace(c.signed_terms_path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Signed Terms & Conditions - '||regexp_replace(c.signed_terms_path,'^.*/',''),
         'storage', 'C:'||c.id||':terms:'||c.signed_terms_path
  from public.customers c where c.signed_terms_path is not null and length(c.signed_terms_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- customer generated "Customer Details.pdf"
  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ INQUIRIES (under their customer) ============
  -- drawings (storage)
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

  -- inquiry generated "Inquiry Summary.pdf"
  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf',
         'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $$;

