-- drawing-files and quote-files must accept every document the sales side can now read.
-- 14 September 2026 — agent: ceo
--
-- Founder, 14 Sep 2026: "the sales agent need to be extremely capable of reading all types of
-- document." supabase/functions/_shared/doc_read reads Word, PowerPoint, ODF, RTF, text, email
-- (.eml/.msg), DXF, IFC, GAEB XML, zip, TIFF/HEIC photos, PDF and spreadsheets with no model.
-- customer_api (analyze_document) stores the customer's original in drawing-files, and supplier_api
-- (extract_quote) stores the supplier's original quotation in quote-files, each with contentType set
-- to the SNIFFED type (sanitizeUpload decides it from the bytes).
--
-- MEASURED on production 14 Sep 2026, before this file:
--   drawing-files = {application/pdf, image/jpeg, image/jpg, image/png, image/webp, image/vnd.dwg,
--                    image/vnd.dxf, text/csv, application/vnd.ms-excel,
--                    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet}
--   quote-files   = {application/pdf, image/jpeg, image/jpg, image/png, image/webp}
-- so storage would refuse every other type after the reader had accepted it.
--
-- WHY WIDENING THIS LIST IS NOT WIDENING THE CONTROL. allowed_mime_types matches the DECLARED type.
-- The control is sanitizeUpload() in supabase/functions/_shared/attachment.ts: type from the bytes,
-- HTML/SVG/script/executables/PDF polyglots refused by shape, Office files carrying a VBA project
-- refused, and only callers passing SAFE_DOCS accept these types. The buckets stay PRIVATE and their
-- 25 MB size limits are unchanged. Nothing stored here is ever handed to a supplier as-is: suppliers
-- receive derived, anonymised copies (see _shared/anonymise.ts).

update storage.buckets
   set allowed_mime_types = array[
         'application/pdf', 'image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif', 'image/tiff', 'image/heic',
         'image/vnd.dwg', 'image/vnd.dxf',
         'text/csv', 'text/plain', 'application/rtf',
         'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.openxmlformats-officedocument.presentationml.presentation',
         'application/vnd.oasis.opendocument.text', 'application/vnd.oasis.opendocument.spreadsheet',
         'application/vnd.oasis.opendocument.presentation',
         'message/rfc822', 'application/vnd.ms-outlook',
         'application/x-step', 'application/x-gaeb+xml',
         'application/zip'
       ]
 where id in ('drawing-files', 'quote-files');

-- No SECURITY DEFINER routine is created or replaced here, so there is nothing to revoke.
