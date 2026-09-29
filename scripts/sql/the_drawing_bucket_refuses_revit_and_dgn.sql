-- THE DRAWING BUCKET REFUSES REVIT AND DGN.
-- Seat: it_engineer. 28 Sep 2026. Founder ruling 1000 (28 Sep 2026): a customer drawing is PDF or CAD
-- (DWG/DXF) only; Revit, IFC, DGN and every other model format are refused.
--
-- SUPERSEDES a_revit_or_dgn_original_is_kept_like_every_drawing.sql (22 Sep), which appended
-- application/vnd.autodesk.revit and image/vnd.dgn to the bucket. Re-applying that older file would put
-- them back; this file is the later MANIFEST entry and is the canonical one.
--
-- MEASURED (production, read-only, 28 Sep 2026): storage.buckets 'drawing-files' allowed_mime_types has
-- 28 entries, the last two application/vnd.autodesk.revit and image/vnd.dgn. The code side already
-- refuses both (supabase/functions/_shared/drawing_format.ts REFUSED_DRAWING_MIMES, PR #1022); the bucket
-- was the one place still accepting them.
--
-- WHAT THIS CHANGES: removes exactly those two types; every other entry keeps its place. WHAT IT DOES
-- NOT: no other type is touched (the bucket also stores non-drawing attachments such as spreadsheets and
-- mail, which are outside ruling 1000's drawing scope), no size limit, no policy, no existing object.
-- Rerunning changes nothing.
--
-- Prevented by: scripts/checks/the_drawing_bucket_refuses_revit_and_dgn.test.mjs.

update storage.buckets
   set allowed_mime_types = array(select t from unnest(allowed_mime_types) with ordinality u(t, n)
                                   where t not in ('application/vnd.autodesk.revit', 'image/vnd.dgn')
                                   order by n)
 where id = 'drawing-files'
   and allowed_mime_types && array['application/vnd.autodesk.revit', 'image/vnd.dgn'];

select case when (select not (allowed_mime_types && array['application/vnd.autodesk.revit', 'image/vnd.dgn'])
                         and allowed_mime_types @> array['application/pdf', 'image/vnd.dwg', 'image/vnd.dxf']
                    from storage.buckets where id = 'drawing-files')
       then 'PROBE OK' else 'PROBE FAILED: drawing-files still accepts Revit/DGN or lost PDF/DWG/DXF' end as verdict;
