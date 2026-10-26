-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710154511   name: doc_backups_table_and_enqueue
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists public.doc_backups(
  id bigserial primary key,
  entity text not null,
  entity_id text not null,
  doc_type text,
  bucket text not null,
  path text not null,
  file_name text,
  dropbox_path text,
  bytes bigint,
  status text not null default 'pending',   -- pending | done | error | skipped_large
  error text,
  attempts int not null default 0,
  created_at timestamptz not null default now(),
  backed_up_at timestamptz,
  unique(bucket, path)
);
create index if not exists ix_doc_backups_status on public.doc_backups(status) where status in ('pending','error');

-- Enumerate every stored supplier original and ensure a backup row exists (idempotent).
create or replace function public.fn_enqueue_doc_backups()
returns integer language plpgsql security definer set search_path to 'public','pg_catalog' as $$
declare n integer := 0;
begin
  with docs as (
    select l.id as sid,
           regexp_replace(coalesce(l.company_name,''),'[\\/:*?"<>|]','_','g') as co,
           v.doc_type, v.bucket, v.path
    from public.leads l
    cross join lateral (values
      ('Trade licence','supplier-docs', l.license_doc_path),
      ('Bank IBAN','supplier-docs', l.iban_doc_path),
      ('Establishment card','supplier-docs', l.egr_doc_path),
      ('Insurance','supplier-docs', l.insurance_doc_path),
      ('VAT certificate','supplier-docs', l.vat_doc_path),
      ('ISO certificate','supplier-docs', l.iso_doc_path),
      ('Manufacturer authorization','supplier-docs', l.manufacturer_auth_doc_path),
      ('Company profile','supplier-docs', l.company_profile_doc_path),
      ('Signed terms','signed-terms', l.signed_terms_path)
    ) as v(doc_type,bucket,path)
    where v.path is not null and length(v.path)>0
    union all
    -- catalogues (array)
    select l.id, regexp_replace(coalesce(l.company_name,''),'[\\/:*?"<>|]','_','g'),
           'Catalogue','supplier-docs', cat
    from public.leads l, unnest(coalesce(l.catalog_doc_paths,'{}')) cat
    where cat is not null and length(cat)>0
  )
  insert into public.doc_backups(entity, entity_id, doc_type, bucket, path, file_name, dropbox_path)
  select 'supplier', d.sid::text, d.doc_type, d.bucket, d.path,
         regexp_replace(d.path,'^.*/',''),
         '/QuotesDone Backup/Suppliers/'||d.sid||' '||left(d.co,60)||'/'||d.doc_type||' - '||regexp_replace(d.path,'^.*/','')
  from docs d
  on conflict (bucket, path) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

