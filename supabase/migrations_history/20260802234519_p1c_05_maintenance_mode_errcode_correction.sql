-- Applied version: 20260802234519
-- Recovered from production, byte-for-byte as applied.

-- Correction to p1c_04. The maintenance refusals were raised with SQLSTATE 57014 (query_canceled).
-- PL/pgSQL's WHEN OTHERS deliberately does not catch that class, and connection pools can read it as
-- a timeout and retry. Replaced with the distinct, catchable custom SQLSTATE 'QDM01' so the refusal
-- is unambiguous, testable and never retried. Behaviour is otherwise identical: the write is refused.

create or replace function public.trg_containment_block_customer_registration()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if public.fn_containment_maintenance() then
    raise exception 'QUOTESDONE MAINTENANCE MODE: customer registration is temporarily closed pending Phase 1 rework (containment control D). No data has been changed.'
      using errcode = 'QDM01', hint = 'Set app_secrets.containment_maintenance to false to reopen.';
  end if;
  return new;
end $$;

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
      using errcode = 'QDM01', hint = 'Set app_secrets.containment_maintenance to false to reopen.';
  end if;
  return new;
end $$;

create or replace function public.trg_containment_block_sensitive_upload()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if public.fn_containment_maintenance()
     and new.bucket_id in ('supplier-docs','drawing-files','quote-files','finance-docs','compliance-docs','receipt-files')
  then
    raise exception 'QUOTESDONE MAINTENANCE MODE: document upload to % is temporarily closed pending Phase 1 rework (containment control D). No existing file has been changed.', new.bucket_id
      using errcode = 'QDM01', hint = 'Set app_secrets.containment_maintenance to false to reopen.';
  end if;
  return new;
end $$;

insert into containment.change_log (area, change, before_value, after_value, rollback_sql)
values ('D_maintenance','maintenance refusal SQLSTATE','57014 (query_canceled, uncatchable, retryable)','QDM01 (distinct, catchable, not retried)',
        '-- superseded by the p1c_04 trigger drops; no separate rollback needed');;
