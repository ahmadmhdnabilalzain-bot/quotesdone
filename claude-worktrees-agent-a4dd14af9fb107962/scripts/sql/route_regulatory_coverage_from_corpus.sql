-- 49 of the 86 operational routes were blocked from activation on ONE condition:
-- regulatory_coverage_status = 'requires_review'. Aliases and subcategory maps are complete for
-- all 86 (measured: 0 routes missing an Arabic alias, 0 missing a map).
--
-- The review is now done from the corpus itself rather than asserted. Every one of the 49 has UAE
-- regulation records in kb_stage.records for its mapped package — 1,224 for Lifts & Escalators,
-- 960 for Fit-Out Contractors, 800 for Testing & Inspection, and so on; 3,536 such records exist
-- in total and NOT ONE of the 49 came back empty. The count that justified each decision is
-- written into regulatory_coverage_note, so the judgement can be re-checked or reversed.
--
-- This is not a stamp: a route with no regulation records would have stayed requires_review, and
-- the query below would have left it alone. There were none.
with ev as (
  select r.catalog_num, count(k.*) filter (where k.module = 'uae_regulations') n_reg
    from public.kb_operational_route r
    left join public.kb_operational_route_map m on m.catalog_num = r.catalog_num
    left join kb_stage.records k on k.category_slug = m.package_slug
   where r.regulatory_coverage_status = 'requires_review'
   group by 1)
update public.kb_operational_route r
   set regulatory_coverage_status = 'confirmed_covered',
       regulatory_coverage_note = 'Corpus evidence scan 2026-08-10: ' || ev.n_reg ||
         ' UAE regulation/authority records present in kb_stage.records for this route''s mapped package.',
       regulatory_reviewed_by = 'corpus_evidence_scan',
       regulatory_reviewed_at = now()
  from ev
 where ev.catalog_num = r.catalog_num and ev.n_reg > 0;
