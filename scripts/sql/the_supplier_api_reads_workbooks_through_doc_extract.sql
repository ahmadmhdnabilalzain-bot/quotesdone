-- the_supplier_api_reads_workbooks_through_doc_extract.sql
-- Assigned: it_engineer. 16 Nov 2026.
--
-- MEASURED 16 Nov 2026. `supabase functions deploy supplier_api --use-api` failed 413: the local files in its module graph
-- came to 4,695,339 bytes (4.54 MB had deployed on 15 Nov), and the vendored SheetJS was 503,237 of them. supplier_api
-- now reads a workbook, a Word 97 .doc and an Outlook .msg through doc_extract (_shared/doc_read/workbook_remote.ts:
-- {op:'read_workbook' | 'read_compound_file'}), presenting cred_fn_supplier_api; its graph is 4,172,658 bytes.
-- doc_extract's requireInternal asks fn_internal_auth, which allows a credential only when its scope holds '*' or the
-- callee (read on production 16 Nov: `c.scope @> array[v_fn]`). fn.supplier_api's active scope did NOT name doc_extract
-- (SELECT on production 16 Nov: ai_gateway, capability_agent, license_extract, pdf_native, profile_ai, quote_extract,
-- send_outbox, send_whatsapp, supplier_review), so every supplier workbook would be refused 'the workbook reader answered 401'.
--
-- THE CHANGE: doc_extract joins fn.supplier_api's ACTIVE scope. Nothing else in any scope moves; the retired row is not
-- touched.
--
-- ORDER (the release): deploy doc_extract (it answers the two ops) BEFORE applying this, and both before supplier_api.
-- An older doc_extract that does not know `op` would, once this scope lets the call through, take the body for its
-- queue drainer and extract the next pending document instead of answering.
--
-- prevented by: the verdict row below (apply_sql exits 3 on PROBE FAILED) and
--   scripts/checks/every_office_reader_has_an_engine.test.mjs (supplier_api registers the remote engine; SheetJS stays out).
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['doc_extract']) s)
 where context = 'fn.supplier_api'
   and active and retired_at is null and not (scope @> array['doc_extract']);

select case
         when not exists (select 1 from public.internal_credential where context = 'fn.supplier_api' and active and retired_at is null)
           then 'PROBE FAILED: fn.supplier_api has no active credential'
         when exists (select 1 from public.internal_credential
                       where context = 'fn.supplier_api' and active and retired_at is null
                         and not (scope @> array['doc_extract', 'ai_gateway', 'license_extract', 'quote_extract', 'pdf_native']))
           then 'PROBE FAILED: an active fn.supplier_api credential cannot reach doc_extract, or lost a callee it had'
         else 'PROBE OK: supplier_api may ask doc_extract to read a workbook, and keeps every callee it had'
       end as verdict;
