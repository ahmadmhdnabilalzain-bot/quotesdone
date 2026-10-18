-- supplier-docs must accept the Word and PowerPoint company profiles and catalogues process_docs reads.
-- 12 October 2026 — agent: sales_engineer
--
-- MEASURED the same day, before this file:
--   storage.buckets['supplier-docs'].allowed_mime_types
--     = {application/pdf, image/jpeg, image/jpg, image/png, image/webp, text/csv,
--        application/vnd.ms-excel, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet}
-- PR #1317 let process_docs accept a .docx/.pptx profile (SAFE_SUPPLIER_PAPERS); the re-run of the five
-- stage-2 f4294be8 suppliers then got HTTP 502 upload_failed on every one, because storage refused the
-- type. Same lesson as supplier_docs_accepts_catalogue_sheets.sql: the bucket list matches the DECLARED
-- type only; the control is sanitizeUpload(), which decides the type from the bytes and refuses
-- macro-bearing OOXML. The bucket stays PRIVATE and its 25 MB limit is unchanged.

update storage.buckets
   set allowed_mime_types = array[
         'application/pdf',
         'image/jpeg', 'image/jpg', 'image/png', 'image/webp',
         'text/csv',
         'application/vnd.ms-excel',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         -- company profiles and catalogues in Word and PowerPoint, added 12 Oct 2026
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.openxmlformats-officedocument.presentationml.presentation'
       ]
 where id = 'supplier-docs';

select case when (select allowed_mime_types @> array[
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.openxmlformats-officedocument.presentationml.presentation']::text[]
       and not public from storage.buckets where id = 'supplier-docs')
       then 'PROBE OK' else 'PROBE FAILED: supplier-docs does not accept docx/pptx' end as verdict;

-- No SECURITY DEFINER routine is created or replaced here, so there is nothing to revoke.
