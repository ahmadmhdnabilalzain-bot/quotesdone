-- A SUPPLIER ACCEPTS THE AGREEMENT TEXT, NOT JUST ITS VERSION LABEL
--
-- Agent: ceo. Website audit SPF5, 14 Sep 2026.
--
-- WHAT WAS WRONG
--   Acceptance evidence on public.leads is accepted_terms_at, accepted_terms_ip and
--   accepted_terms_version. The version is read server-side from app_secrets('terms_version') (fixed
--   27 Jul 2026 so the browser cannot choose it) and read 'v8' on 14 Sep 2026. But a label proves
--   nothing about WHICH words were on screen: the Supplier Agreement lives in src/content/legal.json
--   and can be edited without the label moving. The record the 3% non-response fine rests on could
--   not show the text the supplier agreed to. Measured 14 Sep 2026: 0 leads carry accepted_terms_at,
--   so no existing acceptance loses or gains meaning.
--   The portal also posted terms_version:'v2', which supplier_api has ignored since 27 Jul. It is
--   dropped from the client in the same change.
--
-- WHAT THIS CHANGES
--   One column: leads.accepted_terms_sha256 - the SHA-256 (lowercase hex) of the exact bilingual
--   agreement text accepted. supplier_api computes it at accept_terms from
--   supabase/functions/_shared/supplier_agreement.ts, which scripts/legal/export_supplier_agreement.mjs
--   generates from legal.json (EN html + a newline + AR html, hashed as UTF-8). The module carries
--   the version it was exported for; when app_secrets('terms_version') names a different version the
--   hash is left null rather than attesting to text that was not the current agreement.
--
-- WHAT IT DOES NOT CHANGE
--   No routine, no policy, no grant: leads keeps its existing RLS and the column is written only by
--   the service-role edge function. Existing rows stay null.
--
--   node scripts/apply_sql.mjs scripts/sql/a_supplier_accepts_the_agreement_text_not_just_its_version_label.sql --apply --ddl

begin;

alter table public.leads
  add column if not exists accepted_terms_sha256 text
  check (accepted_terms_sha256 is null or accepted_terms_sha256 ~ '^[0-9a-f]{64}$');

comment on column public.leads.accepted_terms_sha256 is
  'SHA-256 hex of the exact Supplier Agreement text (EN html + newline + AR html) accepted at accepted_terms_at; see _shared/supplier_agreement.ts.';

commit;
