-- A CUSTOMER ACCEPTANCE RECORDS THE HASH OF THE TERMS TEXT, AS A SUPPLIER'S DOES.
--
-- Assigned: it_engineer. 6 Oct 2026. Release review of #1240 (founder ledger 1122): "Store the Terms SHA on customer
-- acceptance, like suppliers." leads has accepted_terms_sha256 (_shared/supplier_terms.ts); customers recorded only
-- tos_version, tos_accepted_at and tos_ip, so a customer's record could not prove which text was accepted.
-- kyc accept_terms and customer_api accept_terms / create_inquiry write it (_shared/customer_terms.ts), as a separate
-- update, so the functions work before and after this column exists. Existing rows stay null: no hash is invented
-- for an acceptance nobody recorded one for.
--   node scripts/apply_sql.mjs scripts/sql/a_customer_acceptance_records_the_hash_of_the_terms_text.sql --apply --ddl

alter table public.customers add column if not exists tos_sha256 text;
comment on column public.customers.tos_sha256 is
  'SHA-256 of the customer Terms text accepted (app_secrets terms_sha256_customer when its pin is for tos_version). Null where none was recorded.';

select case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'customers' and column_name = 'tos_sha256')
            then 'PROBE OK: customers.tos_sha256 exists' else 'PROBE FAILED: no customers.tos_sha256' end as verdict;
