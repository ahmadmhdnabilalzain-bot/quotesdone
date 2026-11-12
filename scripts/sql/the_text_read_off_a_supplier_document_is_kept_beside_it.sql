-- THE TEXT READ OFF A SUPPLIER DOCUMENT IS KEPT BESIDE IT (12 Nov 2026; seat: customer_support).
-- Final audit 12 Nov 2026, finding R4 (health F7, regcert_diagnosis F4); founder: "Proceed with fixes" (ledger 1642).
--
-- MEASURED ON PRODUCTION, 11-12 Nov 2026, before this file:
--   storage.buckets['supplier-docs'].allowed_mime_types = {application/pdf, image/jpeg, image/jpg, image/png, image/webp,
--     text/csv, application/vnd.ms-excel, ...spreadsheetml.sheet, ...wordprocessingml.document, ...presentationml.presentation}
--   235 edge errors "supplier_doc_trades.saveText ... mime type text/plain is not supported" since 10:23 UTC 11 Nov (23 of 23 in
--   the paid certification round); 0 objects named '%.read.txt' and 0 named '%.ocr.txt' in the bucket (12 Nov, SELECT).
--
-- WHAT THE TEXT IS FOR, AND WHO READS IT. Since ruling 1627 the model reads ALL of a supplier's documents together, so when he
-- uploads his profile after his licence, the licence's words are needed again. _shared/supplier_doc_trades.ts saveText keeps what
-- code (or the vision model, for a photo or a scan) read off each document as <path>.read.txt, and three readers load it:
-- proposeFromRead (the earlier documents of a read-together), supplier_docs_later.rereadTogether (the sweep's read-again after a
-- model outage) and readTexts (the next pages of a long PDF). supplier_catalog_ingest keeps a photographed catalogue's words as
-- <path>.ocr.txt the same way. With every save refused: a PDF is downloaded and parsed again on every later read (the licence was
-- parsed twice in each certification journey), and a photo's or a scan's words, which exist only in that file, are lost for the
-- read-together and for the sweep (proposeFromRead skips a 'photo_text' document with no kept text).
--
-- WHY THE BUCKET AND NOT THE UPLOAD'S TYPE. The file IS plain text, written by our own code from a string, and the upload says
-- so. Declaring it text/csv or application/pdf to get past the list would store a false type. The list matches the DECLARED type
-- only; the control on what a supplier sends is sanitizeUpload / sanitizeAndScan (_shared/attachment.ts, _shared/malware.ts),
-- which decides the type from the bytes, and supplier-docs has no storage policy for anon or authenticated (12 Nov: 0 policies on
-- storage.objects name it), so only the service role writes there. The bucket stays private; its size limit is unchanged.
-- The demo teardown already removes both sidecars (scripts/lib/demo_factory.mjs, the supplier-docs rule) and the purge by the
-- supplier's folder (demo_data_is_purged_by_its_marker_and_no_seat_duty_reads_it.sql) covers them, since they sit beside the file.

update storage.buckets
   set allowed_mime_types = allowed_mime_types || array['text/plain']
 where id = 'supplier-docs'
   and not (coalesce(allowed_mime_types, '{}'::text[]) @> array['text/plain']);

select case when (select allowed_mime_types @> array['text/plain', 'application/pdf', 'image/jpeg', 'text/csv']
                    from storage.buckets where id = 'supplier-docs')
            then 'PROBE OK' else 'PROBE FAILED: supplier-docs does not take text/plain beside its earlier types' end as verdict;

-- No routine is created or replaced here, so there is nothing to revoke.
