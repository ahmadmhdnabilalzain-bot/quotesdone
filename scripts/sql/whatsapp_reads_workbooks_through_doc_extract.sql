-- whatsapp_reads_workbooks_through_doc_extract.sql
-- Assigned: it_engineer. 16 Nov 2026 (simplification wave A, DUP item 1; founder ledgers 1714/1715).
--
-- MEASURED 16 Nov 2026. wa_inbound's local module graph (deno info --json wa_inbound/index.ts, every file under
-- supabase/functions/) was 4,345,532 bytes in 214 files, 503,237 of them the vendored SheetJS, reached through the one
-- side-effect import of _shared/doc_read/workbook_local.ts. supplier_api's upload failed 413 at 4,695,339 bytes the same
-- day. wa_inbound now registers the REMOTE workbook engine exactly as supplier_api does
-- (_shared/doc_read/workbook_remote.ts: {op:'read_workbook' | 'read_compound_file'} to doc_extract), presenting
-- cred_fn_wa_inbound; its graph is 3,816,914 bytes in 211 files (3,779,878 once its answer parsers left interview.ts).
-- doc_extract's requireInternal asks fn_internal_auth, which allows a credential only when its scope holds '*' or the
-- callee (`c.scope @> array[v_fn]`, as read for the supplier_api file of the same day). fn.wa_inbound's ACTIVE scope does
-- NOT name doc_extract (SELECT on production 16 Nov: one active row, scope {ai_gateway}; app_secrets.cred_fn_wa_inbound
-- present), so every WhatsApp workbook would be refused 'the workbook reader answered 401'.
--
-- THE CHANGE: doc_extract joins fn.wa_inbound's ACTIVE scope. Nothing else in any scope moves; no retired row is touched.
--
-- ORDER (the release): doc_extract already answers the two ops (it serves supplier_api's remote engine). Apply this
-- BEFORE deploying wa_inbound, or a WhatsApp workbook sent in between is refused as unreadable (the sender is told).
--
-- prevented by: the verdict row below (apply_sql exits 3 on PROBE FAILED) and
--   scripts/checks/every_office_reader_has_an_engine.test.mjs (wa_inbound registers the remote engine; SheetJS stays out).
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['doc_extract']) s)
 where context = 'fn.wa_inbound'
   and active and retired_at is null and not (scope @> array['doc_extract']);

select case
         when not exists (select 1 from public.internal_credential where context = 'fn.wa_inbound' and active and retired_at is null)
           then 'PROBE FAILED: fn.wa_inbound has no active credential'
         when exists (select 1 from public.internal_credential
                       where context = 'fn.wa_inbound' and active and retired_at is null
                         and not (scope @> array['doc_extract', 'ai_gateway']))
           then 'PROBE FAILED: an active fn.wa_inbound credential cannot reach doc_extract, or lost a callee it had'
         else 'PROBE OK: wa_inbound may ask doc_extract to read a workbook, and keeps every callee it had'
       end as verdict;
