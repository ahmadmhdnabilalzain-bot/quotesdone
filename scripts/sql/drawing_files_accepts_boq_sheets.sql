-- drawing-files must accept the BOQ spreadsheets the customer composer now takes.
-- 14 September 2026 — agent: ceo
--
-- Founder, 14 Sep 2026: "describe a job / drop a drawing is fine but add attach a BOQ also".
-- customer_api analyze_boq stores the customer's original BOQ beside their drawings, in drawing-files,
-- so pdpl_erase and retention_purge find it by owner exactly as they find a drawing.
--
-- MEASURED on production 14 Sep 2026, before this file:
--   storage.buckets['drawing-files'].allowed_mime_types
--     = {application/pdf, image/jpeg, image/jpg, image/png, image/webp, image/vnd.dwg, image/vnd.dxf}
-- so storage would refuse every CSV and XLSX. Until this is applied, analyze_boq still reads the BOQ
-- and returns it (the brief and the suppliers get it); only the original file is not kept, and the
-- response says so (stored:false, drawing_file_path null).
--
-- WHY WIDENING THIS LIST IS NOT WIDENING THE CONTROL. allowed_mime_types matches the DECLARED type.
-- The control is sanitizeUpload() in supabase/functions/_shared/attachment.ts, which decides the type
-- from the bytes, refuses HTML/SVG/executables/polyglots by shape and refuses a workbook carrying a VBA
-- project. customer_api passes SAFE_SHEET to it only on the analyze_boq path. The bucket stays PRIVATE
-- and its 25 MB size limit is unchanged. The same widening was made to supplier-docs on 9 Sep
-- (supplier_docs_accepts_catalogue_sheets.sql).

update storage.buckets
   set allowed_mime_types = array[
         'application/pdf',
         'image/jpeg', 'image/jpg', 'image/png', 'image/webp',
         'image/vnd.dwg', 'image/vnd.dxf',
         -- customer BOQ sheets, added 14 Sep 2026
         'text/csv',
         'application/vnd.ms-excel',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
       ]
 where id = 'drawing-files';

-- No SECURITY DEFINER routine is created or replaced here, so there is nothing to revoke.
