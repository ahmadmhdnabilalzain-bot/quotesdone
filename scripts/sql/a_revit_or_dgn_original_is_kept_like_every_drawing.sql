-- A REVIT OR DGN ORIGINAL IS KEPT LIKE EVERY OTHER DRAWING.
--
-- Assigned: sales_engineer. 22 Sep 2026. Founder instructions 31/63/64/696.
--
-- MEASURED (production, 22 Sep 2026, read-only): storage.buckets 'drawing-files' allowed_mime_types
-- lists 26 types, including image/vnd.dwg and image/vnd.dxf, but NOT application/vnd.autodesk.revit or
-- image/vnd.dgn - the two types _shared/attachment.ts sniffs a .rvt and a DGN as, and SAFE_DOCS accepts.
-- customer_api storeOriginal therefore had the sanitizer accept a Revit model and storage refuse it,
-- returning null: the customer's .rvt was read for its version and preview, then lost - no
-- drawing_file_path on the request and nothing pdpl_erase could find.
--
-- WHAT THIS CHANGES: the two types are appended to the bucket's list (each only if absent, so a rerun
-- changes nothing). WHAT IT DOES NOT: no size limit, no other type, no policy on storage.objects.
-- A Revit or DGN drawing is still never shared with a supplier as a file: customer_api holds every CAD
-- original (drawing_held) unless it was pictured and redacted page by page.

update storage.buckets
   set allowed_mime_types = allowed_mime_types
       || array(select t from unnest(array['application/vnd.autodesk.revit', 'image/vnd.dgn']) t
                 where not t = any(allowed_mime_types))
 where id = 'drawing-files';

select case when (select allowed_mime_types @> array['application/vnd.autodesk.revit', 'image/vnd.dgn', 'image/vnd.dwg']
                    from storage.buckets where id = 'drawing-files')
       then 'PROBE OK' else 'PROBE FAILED' end as verdict;
