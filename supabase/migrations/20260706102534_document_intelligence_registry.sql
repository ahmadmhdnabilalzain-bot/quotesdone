-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706102534   name: document_intelligence_registry
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ DOCUMENT INTELLIGENCE: registry + auto-registration ============
create table if not exists public.documents(
  id bigserial primary key,
  bucket text not null,
  path text not null,
  file_name text,
  kind text not null,                 -- quote|drawing|licence|profile|catalog|egr|inbound|other
  ref_table text, ref_id text,
  mime text,
  status text not null default 'pending',   -- pending|processing|done|error|skipped
  extracted jsonb,                    -- {text,specifications,brands[],models[],dates[],quantities[],certifications[]}
  indexed boolean default false,
  error text,
  attempts int default 0,
  created_at timestamptz default now(),
  processed_at timestamptz,
  unique(bucket, path));
create index if not exists idx_documents_status on public.documents(status) where status='pending';
alter table public.documents enable row level security;
revoke all on public.documents from anon, authenticated;

-- upsert helper (service_role / triggers only)
create or replace function public.fn_register_document(
  p_bucket text, p_path text, p_kind text, p_ref_table text, p_ref_id text, p_file_name text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if p_path is null or p_path = '' then return; end if;
  insert into public.documents(bucket,path,kind,ref_table,ref_id,file_name)
  values (p_bucket,p_path,p_kind,p_ref_table,p_ref_id, coalesce(p_file_name, split_part(p_path,'/',array_length(string_to_array(p_path,'/'),1))))
  on conflict (bucket,path) do nothing;
end $$;

-- trigger: quotes.original_file_path
create or replace function public.trg_reg_quote_doc() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if NEW.original_file_path is not null and (TG_OP='INSERT' or NEW.original_file_path is distinct from OLD.original_file_path) then
     perform public.fn_register_document('quote-files', NEW.original_file_path, 'quote', 'quotes', NEW.id::text, NEW.original_file_name);
  end if;
  return NEW;
end $$;
drop trigger if exists reg_quote_doc on public.quotes;
create trigger reg_quote_doc after insert or update of original_file_path on public.quotes
  for each row execute function public.trg_reg_quote_doc();

-- trigger: inquiries.drawing_file_path
create or replace function public.trg_reg_inquiry_doc() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if NEW.drawing_file_path is not null and (TG_OP='INSERT' or NEW.drawing_file_path is distinct from OLD.drawing_file_path) then
     perform public.fn_register_document('drawing-files', NEW.drawing_file_path, 'drawing', 'inquiries', NEW.id::text, NEW.drawing_file_name);
  end if;
  return NEW;
end $$;
drop trigger if exists reg_inquiry_doc on public.inquiries;
create trigger reg_inquiry_doc after insert or update of drawing_file_path on public.inquiries
  for each row execute function public.trg_reg_inquiry_doc();

-- trigger: leads KYC/profile/catalog docs
create or replace function public.trg_reg_lead_docs() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare p text;
begin
  if NEW.license_doc_path is not null and (TG_OP='INSERT' or NEW.license_doc_path is distinct from OLD.license_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.license_doc_path, 'licence', 'leads', NEW.id::text, NEW.license_doc_name); end if;
  if NEW.company_profile_doc_path is not null and (TG_OP='INSERT' or NEW.company_profile_doc_path is distinct from OLD.company_profile_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.company_profile_doc_path, 'profile', 'leads', NEW.id::text, null); end if;
  if NEW.egr_doc_path is not null and (TG_OP='INSERT' or NEW.egr_doc_path is distinct from OLD.egr_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.egr_doc_path, 'egr', 'leads', NEW.id::text, NEW.egr_doc_name); end if;
  if NEW.catalog_doc_paths is not null then
     foreach p in array NEW.catalog_doc_paths loop
        perform public.fn_register_document('supplier-docs', p, 'catalog', 'leads', NEW.id::text, null); end loop; end if;
  return NEW;
end $$;
drop trigger if exists reg_lead_docs on public.leads;
create trigger reg_lead_docs after insert or update of license_doc_path, company_profile_doc_path, egr_doc_path, catalog_doc_paths on public.leads
  for each row execute function public.trg_reg_lead_docs();

-- ---- backfill existing uploads ----
select public.fn_register_document('quote-files', original_file_path,'quote','quotes',id::text,original_file_name)
  from public.quotes where original_file_path is not null;
select public.fn_register_document('drawing-files', drawing_file_path,'drawing','inquiries',id::text,drawing_file_name)
  from public.inquiries where drawing_file_path is not null;
select public.fn_register_document('supplier-docs', license_doc_path,'licence','leads',id::text,license_doc_name)
  from public.leads where license_doc_path is not null;
select public.fn_register_document('supplier-docs', company_profile_doc_path,'profile','leads',id::text,null)
  from public.leads where company_profile_doc_path is not null;
select public.fn_register_document('supplier-docs', egr_doc_path,'egr','leads',id::text,egr_doc_name)
  from public.leads where egr_doc_path is not null;

select count(*) as registered, string_agg(distinct kind,', ') as kinds from public.documents;
