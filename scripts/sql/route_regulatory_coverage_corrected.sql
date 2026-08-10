-- CORRECTION. My corpus evidence scan was too loose and I am reversing the part that was.
--
-- It counted module='uae_regulations' records for the route's mapped PACKAGE and called that
-- confirmed coverage. Ticket #205's own metric is stricter and it is the right one:
-- v_kb_route_regulatory_status counts DISTINCT NAMED AUTHORITIES on records joined by
-- SUBCATEGORY. Measured after my change: 39 of the 84 routes reading confirmed_covered have
-- ZERO named authorities. Having regulation text about a trade is not the same as knowing which
-- authority governs it, and activation on the looser test is exactly the fabrication the founder
-- forbids.
--
-- Only rows THIS session reviewed are touched (regulatory_reviewed_by = 'corpus_evidence_scan').
-- The 35 that were already confirmed before today keep whatever review put them there.
update public.kb_operational_route r
   set regulatory_coverage_status = 'requires_review',
       regulatory_coverage_note = 'Corpus evidence scan 2026-08-10 REVERSED: the package carries UAE regulation records, but no record on this route''s mapped subcategories NAMES an authority. Coverage needs a named authority, per spec_backlog#205.',
       regulatory_reviewed_by = 'corpus_evidence_scan_corrected',
       regulatory_reviewed_at = now()
 where r.regulatory_reviewed_by = 'corpus_evidence_scan'
   and (select count(distinct nullif(btrim(k.authority),''))
          from public.kb_operational_route_map m
          join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
         where m.catalog_num = r.catalog_num) = 0;

-- The ones that DO name an authority keep confirmed_covered, with the count that justified it.
update public.kb_operational_route r
   set regulatory_coverage_note = 'Corpus evidence scan 2026-08-10: ' ||
       (select count(distinct nullif(btrim(k.authority),''))
          from public.kb_operational_route_map m
          join kb_stage.records k on k.subcategory_slug = m.subcategory_slug
         where m.catalog_num = r.catalog_num)::text ||
       ' distinct named UAE authorit(ies) on this route''s mapped subcategories.'
 where r.regulatory_reviewed_by = 'corpus_evidence_scan';
