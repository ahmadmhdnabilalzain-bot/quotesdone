-- SUPPLIER CATEGORIES, RECONCILED TO THE SPECIFICATION EXACTLY.
--
-- "suppliers categories.txt" carries two lists: 66 grouped categories and a "Realistic Suppliers
-- Categories List (UAE)" of 84 numbered entries. Live carried 96 active trade agents.
--
-- MEASURED 11 Aug 2026, all 84 spec entries against category_agents:
--   spec entries missing from live ................ 0
--   live actives not in the 84 .................... 12
--   live actives with zero knowledge modules ...... 9
--
-- The two sets overlap almost exactly, and that is the finding. Eight of the twelve extras are the
-- SAME TRADE under a shorter slug, and every one of those eight has NO knowledge at all — zero of
-- the fourteen modules knowledge_module_standard requires — while its full-name twin has all
-- fourteen. They were never second desks; they were second names, and an inquiry that landed on one
-- reached an agent that knew nothing.
--
--   waterproofing          -> waterproofing-suppliers
--   solar                  -> renewable-energy-companies-solar-ev-battery
--   swimming-pools         -> swimming-pool-suppliers-and-contractors
--   smart-home             -> smart-home-and-home-automation-suppliers
--   custom-furniture       -> furniture-suppliers-ff-and-e-suppliers
--   combined-mep           -> mep-suppliers-electromechanical-suppliers
--   joinery-kitchens       -> joinery-and-carpentry-suppliers
--   interior-design        -> interior-decoration
--
-- The other four extras are NOT duplicates and are NOT removed. Each is a real trade named in the
-- spec's own 66-group list even though it is absent from the 84-entry short list, and each already
-- carries all fourteen modules:
--
--   general-building-contracting ............ group 1, construction and building
--   signage ................................. groups 8 and 58, signage and large-format graphics
--   job-shop-manufacturing .................. group 40, manufacturing by process
--   engineering-and-architectural-consultancies group 65, testing/inspection/technical services
--
-- signage is the one active category with no knowledge that is NOT a duplicate. It is left active
-- and handed to the daily generator rather than folded, because folding a real trade to make a
-- count come out even is the opposite of reconciling to the spec.
--
-- FOLD, NOT DELETE. category_agents already carries folded_into/folded_at and 23 rows use it. The
-- old slug keeps existing, keeps resolving through kb_category_aliases, and stops being a desk.
-- 79 supplier leads carry a folded slug in `sector` (solar 54, waterproofing 25) and are moved with
-- it — leaving them pointing at a deactivated category is how 79 suppliers would quietly stop
-- being matched.

begin;

-- 1. The eight duplicates, folded to their spec twin.
update public.category_agents c
   set active = false, folded_into = f.twin, folded_at = now()
  from (values
    ('waterproofing','waterproofing-suppliers'),
    ('solar','renewable-energy-companies-solar-ev-battery'),
    ('swimming-pools','swimming-pool-suppliers-and-contractors'),
    ('smart-home','smart-home-and-home-automation-suppliers'),
    ('custom-furniture','furniture-suppliers-ff-and-e-suppliers'),
    ('combined-mep','mep-suppliers-electromechanical-suppliers'),
    ('joinery-kitchens','joinery-and-carpentry-suppliers'),
    ('interior-design','interior-decoration')
  ) as f(dup, twin)
 where c.slug = f.dup and c.active;

-- 2. The suppliers on a folded slug move with it. Measured before: solar 54, waterproofing 25.
update public.leads l
   set sector = f.twin
  from (values
    ('waterproofing','waterproofing-suppliers'),
    ('solar','renewable-energy-companies-solar-ev-battery'),
    ('swimming-pools','swimming-pool-suppliers-and-contractors'),
    ('smart-home','smart-home-and-home-automation-suppliers'),
    ('custom-furniture','furniture-suppliers-ff-and-e-suppliers'),
    ('combined-mep','mep-suppliers-electromechanical-suppliers'),
    ('joinery-kitchens','joinery-and-carpentry-suppliers'),
    ('interior-design','interior-decoration')
  ) as f(dup, twin)
 where l.sector = f.dup;

-- 3. The old name keeps resolving. A customer, an invite or a scraped record that says "solar"
--    still reaches the renewable-energy desk instead of falling through to nothing.
insert into public.kb_category_aliases (category, maps_to, rationale)
select v.dup, v.twin,
       'Folded 11 Aug 2026: duplicate slug for the same trade. The spec''s 84-entry list names the target; this slug had zero of the fourteen required knowledge modules while the target had all fourteen.'
  from (values
    ('waterproofing','waterproofing-suppliers'),
    ('solar','renewable-energy-companies-solar-ev-battery'),
    ('swimming-pools','swimming-pool-suppliers-and-contractors'),
    ('smart-home','smart-home-and-home-automation-suppliers'),
    ('custom-furniture','furniture-suppliers-ff-and-e-suppliers'),
    ('combined-mep','mep-suppliers-electromechanical-suppliers'),
    ('joinery-kitchens','joinery-and-carpentry-suppliers'),
    ('interior-design','interior-decoration')
  ) as v(dup, twin)
 where not exists (select 1 from public.kb_category_aliases a where a.category = v.dup);

commit;
