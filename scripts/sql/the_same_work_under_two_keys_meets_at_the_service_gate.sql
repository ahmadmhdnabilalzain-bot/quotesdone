-- THE SAME WORK UNDER TWO KEYS MEETS AT THE SERVICE GATE (12 Nov 2026, sales_engineer; built by it_engineer).
-- Seat: sales_engineer. Founder rulings 1647 ("if this step is done wrong everything after it goes wrong") and 1628
-- (matching is code over confirmed keys).
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 12 Nov 2026; analysis services/REPORT.md 1.5, sql/dup.sql): 13
-- pairs of service keys name the same work in two trades. 12 of the 13 had no service_implication row either way, so a
-- supplier holding one key was skipped by a request naming the other ("he was asked and does not hold it"); the 13th
-- (joinery.wooden_doors -> doors.wooden_doors) met in one direction only. 6 of the 13 pairs are in trades that are not
-- curated neighbours, so even an implication would not have helped: fn_match_capability considers only the request's
-- trades, each named service's trade and their adjacent trades, and the supplier's trade was none of them.
--
-- WHAT THIS CHANGES:
--   1. service_implication.same boolean not null default false: a row with same = true says the two keys are ONE piece of
--      work (identity), not that a firm doing the first usually does the second. A reader that asks the supplier about
--      implied services (the question cards) must not ask about a `same` row: confirming one key is confirming the other.
--   2. one row each way, same = true, for all 13 pairs (the existing joinery -> doors row is marked same).
--   3. the 6 trade pairs those keys live in become curated adjacent trades, each with its reason; adjacency is one
--      level, is read only when a request names a service, and a supplier reached through it must still hold a named
--      service (fn_match_capability's gate is unchanged).
-- fn_services_effective already adds an active implication one level from what the supplier holds, so with 2 and 3 the
-- request naming either key reaches the supplier who holds the other. No routine changes.
-- Not here: further duplicates seen on the way (tents_shades and fencing_shades share car-park shades, tensile structures
-- and shade sails; waterproofing.acoustic and thermal_insulation.acoustic_insulation): the analysis did not measure them,
-- and they are reported for the sales engineer seat to decide.
--
-- prevented by: scripts/sql/the_same_work_under_two_keys_meets_at_the_service_gate_probe.sql (every pair, both ways,
--               through the live fn_match_capability in an aborted transaction, with a control service that must NOT
--               match) and scripts/checks/the_same_work_under_two_keys_meets_at_the_service_gate.test.mjs.

alter table public.service_implication add column if not exists same boolean not null default false;
comment on column public.service_implication.same is
  'sales_engineer: true = the two keys name the same work (identity), one row each way; confirming one is confirming the other, so it is never asked as an implied service.';

insert into public.service_implication (from_code, implies_trade, implies_code, reason_en, reason_ar, active, same)
select x.a, split_part(x.b, '.', 1), split_part(x.b, '.', 2),
       'The same work catalogued under two trades: holding one key is holding the other.',
       'العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.', true, true
  from (values
    ('landscaping.pools', 'swimming_pools.pool_construction'),
    ('cleaning.pest_control', 'pest_control.general_pest_control'),
    ('cleaning.facility_management', 'facilities_management.integrated_fm'),
    ('security_systems.guarding', 'security_guarding.manned_guarding'),
    ('upholstery.curtains', 'curtains_blinds.curtains'),
    ('water_treatment.tank_cleaning_disinfection', 'water_treatment_services.water_tank_cleaning_disinfection'),
    ('gypsum.plastering', 'masonry_blockwork.plastering'),
    ('civil_works.blockwork', 'masonry_blockwork.blockwork'),
    ('joinery.wooden_doors', 'doors.wooden_doors'),
    ('waterproofing.thermal', 'thermal_insulation.roof_insulation'),
    ('civil_works.demolition', 'demolition_works.building_demolition'),
    ('engineering_consultancy.architectural_design', 'design_consultancy.architectural_design'),
    ('interior_fitout.interior_design', 'design_consultancy.interior_design')
  ) p(k1, k2),
  lateral (values (p.k1, p.k2), (p.k2, p.k1)) x(a, b)
on conflict (from_code, implies_trade, implies_code) do update set same = true, active = true;

insert into public.taxonomy_trade_adjacent (a_code, b_code, reason_en, reason_ar)
select least(x.a, x.b), greatest(x.a, x.b), x.en, x.ar
from (values
  ('security_guarding', 'security_systems',
   'Security companies install the systems and supply the guards; one firm often does both.',
   'شركات الأمن تركّب الأنظمة وتوفّر الحراس، وكثير منها يقدّم الخدمتين.'),
  ('gypsum', 'masonry_blockwork',
   'Plastering is done by gypsum contractors and by masonry contractors alike.',
   'أعمال اللياسة ينفّذها مقاولو الجبس ومقاولو البناء على حدّ سواء.'),
  ('civil_works', 'masonry_blockwork',
   'Civil contractors build the blockwork and the plaster as part of the structure.',
   'مقاولو الأعمال المدنية ينفّذون البلوك واللياسة ضمن أعمال الهيكل.'),
  ('civil_works', 'demolition_works',
   'Civil contractors demolish before they build, and demolition firms work for them.',
   'مقاولو الأعمال المدنية يهدمون قبل البناء، وشركات الهدم تعمل لديهم.'),
  ('design_consultancy', 'engineering_consultancy',
   'Architectural design is offered by design studios and by engineering consultants.',
   'التصميم المعماري تقدّمه مكاتب التصميم ومكاتب الاستشارات الهندسية معًا.'),
  ('design_consultancy', 'interior_fitout',
   'Fit-out contractors design interiors, and interior designers deliver the fit-out.',
   'مقاولو التجهيز الداخلي يصمّمون الديكور، والمصمّمون ينفّذون التجهيز.')
) as x(a, b, en, ar)
on conflict (a_code, b_code) do update set reason_en = excluded.reason_en, reason_ar = excluded.reason_ar, active = true;

-- Verdict row (DDL file, so no raise): the column, the 26 identity rows and the 6 adjacent pairs are in place.
select case
  when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'service_implication'
                 and column_name = 'same' and data_type = 'boolean' and is_nullable = 'NO')
   and (select count(*) from public.service_implication where active and same) >= 26
   and (select count(*) from public.taxonomy_trade_adjacent where active and (a_code, b_code) in (
          ('security_guarding','security_systems'), ('gypsum','masonry_blockwork'), ('civil_works','masonry_blockwork'),
          ('civil_works','demolition_works'), ('design_consultancy','engineering_consultancy'), ('design_consultancy','interior_fitout'))) = 6
  then 'PROBE OK the 13 same-work pairs are identity rows both ways and their trades are adjacent'
  else 'PROBE FAILED: a same-work row, the column or an adjacent pair is missing' end as verdict;
