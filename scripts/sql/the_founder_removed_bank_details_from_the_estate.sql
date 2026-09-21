-- THE FOUNDER REMOVED BANK DETAILS FROM THE ESTATE (21 Sep 2026, it_engineer, founder instruction 527).
--
-- MEASURED, read-only on production at 2026-09-21 09:22 UTC, before anything here was written:
--   * public.leads: 22,266 rows. bank_name NOT NULL: 0. bank_iban NOT NULL: 0. bank_account_name NOT
--     NULL: 0. iban_doc_path NOT NULL: 0. iban_doc_name NOT NULL: 0. Any of the five: 0.
--   * storage.objects in bucket supplier-docs under an iban_doc_path: 0.
--   * Readers of bank_name / bank_iban / bank_account_name: 0 routines, 0 views, 0 triggers, 0 cron
--     (pg_proc.prosrc, pg_get_viewdef, pg_get_triggerdef, cron.job.command, all regex-swept). The only
--     text match was fn_supplier_certifications, which used 'bank_iban' as a LABEL KEY for the IBAN
--     letter, not as a column; that row is removed from scripts/sql/fn_supplier_certifications.sql.
--     pg_depend on the three attributes: 0 dependents.
--   * Readers of iban_doc_path / iban_doc_name: 7 routines (fn_enqueue_doc_backups,
--     fn_backup_enqueue_watch, fn_ws_supplier_360, fn_it_backup_expected, fn_supplier_certifications,
--     fn_entity_files, fn_backup_source_registry), 1 view (v_supplier_doc_score, which itself has 0
--     readers), 1 trigger (z70_document_landed_kicks_backup, UPDATE OF ... iban_doc_path ...).
--   * Edge functions reading any of the five: supplier_api (PROFILE_COLS allowlist, the aiReview
--     profile, the `me` select) and supplier_portal (DOC_KINDS 'iban'). Both edited in the same PR.
--   * Money path: customers pay the reveal fee through Stripe Checkout (stripe_checkout → stripe_confirm
--     → stripe_webhook); supplier dues are settled through Stripe the same way; the company's own
--     Mashreq statements reconcile against stripe_payout.bank_line_id. No path reads a supplier's bank
--     columns. The bank rails are Stripe's, not ours.
--
-- WHAT WAS WRONG. The supplier profile carried bank_name / bank_account_name / bank_iban and a "Bank
-- details (IBAN)" document type, and fn_supplier_certifications told suppliers "We cannot pay you without
-- it." None of that is true of how money moves here, and holding bank details we never use is a liability
-- with no counterpart. The founder, 21 Sep 2026: remove IBAN / bank details entirely.
--
-- WHAT THIS CHANGES.
--   1. Purges every stored value in the five columns (nulls them) and returns the row count purged.
--   2. Drops bank_name, bank_iban, bank_account_name from public.leads — 0 readers, 0 dependents.
--   3. Returns ONE verdict row: PROBE OK with the purged count, or PROBE FAILED if a bank column survived.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE.
--   * iban_doc_path and iban_doc_name are NULLED, NOT DROPPED. Nine database objects reference them (list
--     above); dropping the columns would need each rewritten and the z70 trigger's column list re-declared.
--     With no surface able to write them any more (DOC_KINDS 'iban' is gone) they stay empty. Dropping them
--     is a follow-up that rewrites those nine objects in their own files.
--   * storage.objects is not touched: 0 objects sit under an iban path today, and a storage delete belongs
--     to the storage API, not a metadata delete.
--   * v_supplier_doc_score still scores has_iban (10 points) and lists 'Bank IBAN letter' as missing. It
--     has 0 readers; it is left for the follow-up that drops the columns.

-- 1. Purge. Kept in a temp table so the count survives the ALTER below and reaches the verdict row.
create temp table bank_purge_result on commit drop as
with purged as (
  update public.leads
     set bank_name = null, bank_iban = null, bank_account_name = null,
         iban_doc_path = null, iban_doc_name = null
   where coalesce(nullif(btrim(bank_name), ''), nullif(btrim(bank_iban), ''),
                  nullif(btrim(bank_account_name), ''), nullif(btrim(iban_doc_path), ''),
                  nullif(btrim(iban_doc_name), '')) is not null
  returning id
)
select count(*)::int as purged_rows from purged;

-- 2. Drop the three bank columns. `if exists` so a re-apply is idempotent.
alter table public.leads
  drop column if exists bank_name,
  drop column if exists bank_iban,
  drop column if exists bank_account_name;

-- 3. The verdict row. The apply harness reads PROBE OK / PROBE FAILED off the result set.
select case
         when exists (select 1 from information_schema.columns
                       where table_schema = 'public' and table_name = 'leads'
                         and column_name in ('bank_name', 'bank_iban', 'bank_account_name'))
           then 'PROBE FAILED: a bank column survived the drop'
         else 'PROBE OK: purged ' || (select purged_rows from bank_purge_result)::text
              || ' lead row(s); bank_name, bank_iban, bank_account_name dropped; iban_doc_path/iban_doc_name nulled'
       end as verdict,
       (select purged_rows from bank_purge_result) as purged_rows;
