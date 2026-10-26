-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709112810   name: fn_entity_files
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Every openable file for a supplier / customer / rfq, each with its exact bucket+path
-- so the OS can open the real document via a signed URL. Read-only.
create or replace function public.fn_entity_files(p_entity text, p_id text)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog' as $$
declare out jsonb := '[]'::jsonb; l public.leads%rowtype;
begin
  if p_entity = 'supplier' then
    select * into l from public.leads where id = p_id::bigint;
    if l.id is not null then
      if l.license_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Trade licence','name',coalesce(l.license_doc_name,'trade licence'),'bucket','supplier-docs','path',l.license_doc_path); end if;
      if l.iban_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Bank / IBAN','name',coalesce(l.iban_doc_name,'iban letter'),'bucket','supplier-docs','path',l.iban_doc_path); end if;
      if l.egr_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Establishment card','name',coalesce(l.egr_doc_name,'establishment card'),'bucket','supplier-docs','path',l.egr_doc_path); end if;
      if l.insurance_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Insurance','name','insurance','bucket','supplier-docs','path',l.insurance_doc_path); end if;
      if l.vat_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','VAT certificate','name','vat certificate','bucket','supplier-docs','path',l.vat_doc_path); end if;
      if l.company_profile_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Company profile','name','company profile','bucket','supplier-docs','path',l.company_profile_doc_path); end if;
      if l.signed_terms_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Signed terms','name','signed terms','bucket','signed-terms','path',l.signed_terms_path); end if;
      if l.catalog_doc_paths is not null then
        out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Catalogues','type','Catalogue','name','catalogue','bucket','supplier-docs','path',x)) from unnest(l.catalog_doc_paths) x),'[]'::jsonb);
      end if;
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
end $$;
revoke all on function public.fn_entity_files(text,text) from anon, authenticated, public;
