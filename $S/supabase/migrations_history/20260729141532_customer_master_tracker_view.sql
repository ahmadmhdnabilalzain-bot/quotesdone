-- WHY: The founder's "one main Excel that tracks all customer data (name, mobile, email, document
-- number of the signed T&Cs)" does not exist anywhere - a Dropbox search for xlsx/csv returned zero
-- hits. The per-customer folders and signed T&C PDFs DO exist under /QuotesDone Backup/Customers/,
-- but nothing indexes them. This view is the single tabular source that an export job can render to
-- CSV/XLSX; SQL itself cannot write a workbook.
-- Document number: customers has no explicit T&C document number column, so we derive a stable,
-- human-quotable reference from the customer UUID (QD-TC-XXXXXXXX). It matches the folder suffix
-- fn_enqueue_doc_backups already uses (left(c.id::text,8)), so a row here maps 1:1 to a Dropbox folder.
create or replace view public.v_customer_master as
select
  c.id                                                   as customer_id,
  c.full_name                                            as name,
  c.phone                                                as mobile,
  c.email                                                as email,
  case when coalesce(btrim(c.signed_terms_path),'') <> ''
       then 'QD-TC-' || upper(left(replace(c.id::text,'-',''), 8))
       else null end                                     as tc_document_no,
  c.signed_terms_path                                    as tc_document_path,
  c.signed_terms_url                                     as tc_document_url,
  c.tos_version                                          as tc_version,
  coalesce(c.signed_terms_at, c.tos_accepted_at)         as tc_accepted_at,
  c.tos_ip                                               as tc_accepted_ip,
  '/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(c.full_name,'Customer'))
    || ' (' || left(c.id::text,8) || ')'                 as dropbox_folder,
  c.phone_verified,
  c.email_verified,
  c.created_at                                           as registered_at
from public.customers c
order by c.created_at desc nulls last;

comment on view public.v_customer_master is
  'Customer master tracker: name, mobile, email, signed T&C document number/path, accepted date and IP, plus the matching Dropbox folder. Intended as the source rowset for a CSV/XLSX export to Dropbox.';

grant select on public.v_customer_master to authenticated, service_role;