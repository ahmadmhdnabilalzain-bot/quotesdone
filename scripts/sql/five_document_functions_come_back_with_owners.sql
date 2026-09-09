-- FIVE DOCUMENT FUNCTIONS COME BACK, AND THIS IS WHO OWNS THEM.
--
-- Commit 182308b (PR #530, 8 Sep 2026) deleted 137 edge functions from the repository AND from
-- production without touching their callers. PR #532 already reversed eight of them because they
-- turned out to be the website. These five are the next reversal, and they are reversed for a
-- harder reason than provenance: LIVE CODE STILL CALLS THEM.
--
--   cad_convert     customer_api:581, supplier_catalog_ingest:150   DWG/DXF unreadable
--   drawing_redact  customer_api:615                                RFQ dispatched with NO drawing
--   drawing_boq     customer_api:618                                HTTP 200 ok:false, invisible
--   quote_extract   supplier_api:789                                supplier retypes the quote
--   doc_extract     (cron drainer)                                  the ONLY writer of
--                                                                   documents.extracted, and the
--                                                                   ONLY OCR path in the estate
--
-- every_deployed_function_has_an_owner.mjs fails in BOTH directions, so this file must be applied
-- BEFORE the deploy: a deployed function with no owner is exactly the orphan state the sweep
-- existed to end.
--
-- WHY EACH OWNER, deliberately and not by default:
--
--   cad_convert     website  — both of its callers are website functions (customer_api,
--                              supplier_catalog_ingest). It has no life outside their surfaces.
--   drawing_redact  website  — called only by customer_api, on the buyer's upload path. It is the
--                              privacy control on a page the website serves.
--   drawing_boq     website  — called only by customer_api, on the same upload. Its output is
--                              rendered straight back into the buyer's chat.
--   quote_extract   website  — called only by supplier_api, on the supplier portal's quote upload.
--   doc_extract     customer_support — the one that is NOT a website surface. No page calls it; a
--                              cron drains the documents queue and its output feeds kb_chunks, the
--                              knowledge the support agent answers from. Its siblings in that work
--                              (license_extract, extract_text, ai_gateway) are already
--                              customer_support, and the sales_engineer seat owns exactly one
--                              function — its own runtime — which this is not.
--
-- Nothing here is at risk: drawing_redaction_runs has 0 rows ever, inquiries with a
-- drawing_file_path is 0, supplier_catalog is 0. The pipeline is broken and has never carried a
-- real customer drawing.

insert into public.function_owner (function_slug, owner, note) values
  ('cad_convert', 'website',
   'Rasteriser for DWG/DXF via CloudConvert. Called by customer_api (buyer drawing upload) and supplier_catalog_ingest (catalogue upload) - both website functions. Raster preview only: no entities, layers, blocks, xrefs or dimensions, ever.'),
  ('drawing_redact', 'website',
   'Pixel overlay that blacks out identifying regions on rasterised drawing pages before they reach competing suppliers, with an independent verifier and one retry. Called by customer_api only. Fails closed: an unverified page is never shared.'),
  ('drawing_boq', 'website',
   'Draft bill of quantities read off drawing page images by a vision model, shown straight back to the buyer in customer_api''s chat. An estimate for briefing and matching, never a certified take-off.'),
  ('quote_extract', 'website',
   'Reads and anonymises a supplier''s uploaded quotation for supplier_api''s portal. Reports ok:false on an unreadable quotation so the supplier gets the manual form instead of a blank one.'),
  ('doc_extract', 'customer_support',
   'The only writer of documents.extracted and the only OCR path in the estate (scanned PDF -> CloudConvert PNG -> vision, pages 1-3). Drained by cron, not by any page; its output feeds kb_chunks, which is the knowledge the support agent answers from.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

-- ── AND THE CREDENTIAL THAT COULD NEVER HAVE REACHED IT ──────────────────────────────────────────
--
-- supplier_catalog_ingest:150 presents cred_db_internal to cad_convert. Measured 9 Sep 2026: the
-- ACTIVE db.internal credential (id 111) does not carry cad_convert in its scope, and
-- fn_internal_auth checks scope against the callee slug. So even once cad_convert is redeployed,
-- that caller would get 403 forbidden and report conversion_failed - the same symptom as before,
-- from a second, independent cause.
--
-- This is the narrowest possible widening: ONE slug added to ONE credential, for a call site that
-- already exists in deployed code. It grants nothing that was not already intended - the whole
-- point of that call site is to convert a CAD file - and supplier_catalog_ingest is owned by
-- another effort and is not edited.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['cad_convert']) s)
 where id = 111 and context = 'db.internal' and active
   and not (scope @> array['cad_convert']);

select function_slug, owner from public.function_owner
 where function_slug in ('cad_convert','drawing_redact','drawing_boq','quote_extract','doc_extract')
 order by function_slug;
