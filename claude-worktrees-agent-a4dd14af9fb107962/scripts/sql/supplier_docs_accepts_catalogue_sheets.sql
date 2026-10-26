-- supplier-docs must accept the catalogue formats supplier_catalog_ingest exists to read.
-- 9 September 2026 — agent: sales_engineer
--
-- MEASURED, not assumed. Before this file:
--   storage.buckets['supplier-docs'].allowed_mime_types
--     = {application/pdf, image/jpeg, image/jpg, image/png, image/webp}
-- and supplier_catalog_ingest — whose whole subject is "csv / tsv / txt / xlsx / xls parsed here,
-- a price list is a table and needs no model" — uploaded those very files into that bucket. Storage
-- refused every one of them. The function could not see the refusal, because it wrote
--   .upload(path, bytes, { upsert: true }).catch(() => null)
-- and .upload() RESOLVES with { error } instead of rejecting, so that .catch() could never fire and
-- up.error was never read. supplier_catalog.source_document_path was then written pointing at an
-- object that does not exist. Silently. Every time.
--
-- Counted on production the same day: supplier_catalog 0 rows, supplier_product 0 rows, and 0
-- objects under catalog/ in the bucket. Nothing is being repaired here; a path that never once
-- worked is being made able to work, and the function now inspects up.error and fails loudly so a
-- future refusal is visible instead of invented.
--
-- WHY WIDENING THIS LIST IS NOT WIDENING THE CONTROL. allowed_mime_types matches the type the
-- CALLER DECLARES, which is one header edit away from anything — supabase/functions/_shared/
-- attachment.ts says so in its own opening comment, and it is right. The real control is
-- sanitizeUpload(), which decides the type from the MAGIC BYTES and refuses HTML, SVG, executables,
-- scripts and PDF polyglots by shape whatever they were named. As of this change supplier_catalog_
-- ingest routes through it like the other thirteen upload sites, and the three types added below
-- are only ever accepted where the CALLER passes SAFE_SHEET — which no other call site does.
-- The bucket stays PRIVATE and its 25 MB size limit is unchanged.

update storage.buckets
   set allowed_mime_types = array[
         'application/pdf',
         'image/jpeg', 'image/jpg', 'image/png', 'image/webp',
         -- catalogue sheets, added 9 Sep 2026
         'text/csv',
         'application/vnd.ms-excel',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
       ]
 where id = 'supplier-docs';

-- No SECURITY DEFINER routine is created or replaced here, so there is nothing to revoke.
