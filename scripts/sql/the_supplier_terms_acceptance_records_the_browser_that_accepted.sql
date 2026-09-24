-- A SUPPLIER'S TERMS ACCEPTANCE RECORDS THE BROWSER THAT ACCEPTED (sales_engineer, 24 Sep 2026).
--
-- Measured on production 24 Sep 2026: leads carries accepted_terms_at, accepted_terms_version,
-- accepted_terms_ip and accepted_terms_sha256, and no user-agent column at all, so neither the record
-- nor the signed certificate could say what device/browser gave the acceptance. The latest v13
-- registration (ZZ DEMO Interiors gypsum founderdemo, lead 126512) has time, v13, IP and hash, and no
-- user agent anywhere.
--
-- This adds the column only. _shared/supplier_terms.ts writes it (from the request's User-Agent) on
-- every acceptance path (supplier_api save_profile / accept_terms, kyc accept_terms), and
-- compliance_archive prints it on the certificate. ORDER: apply this BEFORE deploying those three
-- functions — an update naming a column that does not exist fails the whole acceptance write.
--
-- Not changed: existing rows stay null (the browser that accepted in the past was never captured and
-- is not invented); customers.* is untouched (customer terms are a different record).
alter table public.leads add column if not exists accepted_terms_user_agent text;

comment on column public.leads.accepted_terms_user_agent is
  'User-Agent header of the request that recorded accepted_terms_at (clipped to 500). Written by _shared/supplier_terms.ts; printed on the signed-terms certificate.';

select case when exists (select 1 from information_schema.columns where table_schema = 'public'
  and table_name = 'leads' and column_name = 'accepted_terms_user_agent')
  then 'PROBE OK' else 'PROBE FAILED: leads.accepted_terms_user_agent missing' end as verdict;
