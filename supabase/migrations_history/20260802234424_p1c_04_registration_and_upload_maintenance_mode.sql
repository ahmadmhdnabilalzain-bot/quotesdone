-- Applied version: 20260802234424
-- Recovered from production, byte-for-byte as applied.

-- Phase 1 emergency containment, step 4 of 4 — MAINTENANCE MODE.
-- The product is not publicly launched (0 customers, 0 inquiries, 0 claimed suppliers), so supplier
-- registration, customer registration and sensitive document upload are placed in explicit
-- maintenance mode until the Phase 1 rework completes.
-- Enforced in the database rather than in six edge functions so it survives a redeploy and also
-- blocks direct service-role writes. Controlled by ONE switch: app_secrets.containment_maintenance.
-- NO DATA IS DELETED OR MODIFIED. Existing rows are untouched; only new writes are refused.

insert into public.app_secrets (key, value)
select 'containment_maintenance', 'true'
where not exists (select 1 from public.app_secrets where key='containment_maintenance');
update public.app_secrets set value='true' where key='containment_maintenance';

create or replace function public.fn_containment_maintenance()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((select lower(btrim(value))='true' from public.app_secrets
                    where key='containment_maintenance'), false);
$$;

-- Customer registration: covers customer_api, kyc and mobile_otp, which are the only three inserters.
create or replace function public.trg_containment_block_customer_registration()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if public.fn_containment_maintenance() then
    raise exception 'QUOTESDONE MAINTENANCE MODE: customer registration is temporarily closed pending Phase 1 rework (containment control D). No data has been changed.'
      using errcode = '57014', hint = 'Clear app_secrets.containment_maintenance to reopen.';
  end if;
  return new;
end $$;

drop trigger if exists zz_containment_customer_registration on public.customers;
create trigger zz_containment_customer_registration
  before insert on public.customers
  for each row execute function public.trg_containment_block_customer_registration();

-- Supplier registration: scoped to registration, approval, terms and document columns only, so
-- unrelated maintenance writes (e.g. cron job 120 backfill_invite_trades) are not affected.
create or replace function public.trg_containment_block_supplier_registration()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if public.fn_containment_maintenance()
     and (new.claimed                   is distinct from old.claimed
       or new.claimed_by                is distinct from old.claimed_by
       or new.accepted_terms_at         is distinct from old.accepted_terms_at
       or new.accepted_terms_version    is distinct from old.accepted_terms_version
       or new.accepted_terms_ip         is distinct from old.accepted_terms_ip
       or new.approval_status           is distinct from old.approval_status
       or new.verified                  is distinct from old.verified
       or new.owner_email_verified      is distinct from old.owner_email_verified
       or new.owner_phone_verified      is distinct from old.owner_phone_verified
       or new.registration_status       is distinct from old.registration_status
       or new.registration_fee_due      is distinct from old.registration_fee_due
       or new.registration_paid_at      is distinct from old.registration_paid_at
       or new.registration_submitted_at is distinct from old.registration_submitted_at
       or new.license_doc_path          is distinct from old.license_doc_path
       or new.iban_doc_path             is distinct from old.iban_doc_path
       or new.egr_doc_path              is distinct from old.egr_doc_path
       or new.company_profile_doc_path  is distinct from old.company_profile_doc_path
       or new.signed_terms_url          is distinct from old.signed_terms_url
       or new.signed_terms_path         is distinct from old.signed_terms_path
       or new.signed_terms_at           is distinct from old.signed_terms_at)
  then
    raise exception 'QUOTESDONE MAINTENANCE MODE: supplier registration, approval and document changes are temporarily closed pending Phase 1 rework (containment control D). No data has been changed.'
      using errcode = '57014', hint = 'Clear app_secrets.containment_maintenance to reopen.';
  end if;
  return new;
end $$;

drop trigger if exists zz_containment_supplier_registration on public.leads;
create trigger zz_containment_supplier_registration
  before update on public.leads
  for each row execute function public.trg_containment_block_supplier_registration();

-- Sensitive document upload. Buckets that receive user-supplied documents only; system buckets
-- (backups, site, brand, kb-import-assets, ...) are untouched so backup and monitoring keep working.
create or replace function public.trg_containment_block_sensitive_upload()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if public.fn_containment_maintenance()
     and new.bucket_id in ('supplier-docs','drawing-files','quote-files','finance-docs','compliance-docs','receipt-files')
  then
    raise exception 'QUOTESDONE MAINTENANCE MODE: document upload to % is temporarily closed pending Phase 1 rework (containment control D). No existing file has been changed.', new.bucket_id
      using errcode = '57014', hint = 'Clear app_secrets.containment_maintenance to reopen.';
  end if;
  return new;
end $$;

drop trigger if exists zz_containment_sensitive_upload on storage.objects;
create trigger zz_containment_sensitive_upload
  before insert on storage.objects
  for each row execute function public.trg_containment_block_sensitive_upload();

insert into containment.change_log (area, change, before_value, after_value, rollback_sql) values
 ('D_maintenance','app_secrets.containment_maintenance','(absent)','true',
  'update public.app_secrets set value=''false'' where key=''containment_maintenance'';'),
 ('D_maintenance','trigger zz_containment_customer_registration on public.customers','(none)','BEFORE INSERT -> refuse',
  'drop trigger if exists zz_containment_customer_registration on public.customers;'),
 ('D_maintenance','trigger zz_containment_supplier_registration on public.leads','(none)','BEFORE UPDATE (scoped) -> refuse',
  'drop trigger if exists zz_containment_supplier_registration on public.leads;'),
 ('D_maintenance','trigger zz_containment_sensitive_upload on storage.objects','(none)','BEFORE INSERT (6 buckets) -> refuse',
  'drop trigger if exists zz_containment_sensitive_upload on storage.objects;');;
