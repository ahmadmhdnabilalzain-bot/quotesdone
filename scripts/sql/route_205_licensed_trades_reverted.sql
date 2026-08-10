-- Routes 38, 39, 41, 61, 62 read confirmed_covered with ZERO named authorities in the corpus.
-- They are the exact five spec_backlog#205 names as MISSING authority mappings, and they are
-- Accounting & Audit, Tax Consultants, Law Firms, Medical Equipment and Pharmaceutical Suppliers
-- -- the most heavily licensed trades in the whole 86. Every one is governed by a named UAE
-- regulator and the corpus names none of them.
--
-- The confirmation predates today and is not mine, but leaving it standing would let those five
-- activate on a coverage claim the data does not support. A ticket that says these are missing and
-- a table that says they are covered cannot both be true; the corpus decides, and it sides with
-- the ticket. Reverted to requires_review, which keeps them out of activation until an authority
-- is actually named.
update public.kb_operational_route
   set regulatory_coverage_status = 'requires_review',
       regulatory_coverage_note = 'Reverted 2026-08-10: confirmed_covered with zero named authorities on the mapped subcategories. spec_backlog#205 names this route as missing its authority mapping, and a licensed trade cannot be covered by regulation text that names no regulator.',
       regulatory_reviewed_by = 'corpus_evidence_scan_corrected',
       regulatory_reviewed_at = now()
 where catalog_num in (38, 39, 41, 61, 62)
   and regulatory_coverage_status = 'confirmed_covered'
   and (select count(distinct nullif(btrim(k.authority),''))
          from public.kb_operational_route_map m
          join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
         where m.catalog_num = kb_operational_route.catalog_num) = 0;
