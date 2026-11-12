-- THE SAME WORK UNDER TWO KEYS MEETS AT THE SERVICE GATE (12 Nov 2026, sales_engineer; built by it_engineer).
-- Seat: sales_engineer. Founder rulings 1647 ("if this step is done wrong everything after it goes wrong") and 1628
-- (matching is code over confirmed keys). APPLY AFTER the_catalogue_can_name_what_suppliers_do.sql: four of its rows
-- name services that file adds.
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 12 Nov 2026; analysis services/REPORT.md 1.5, sql/dup.sql, and
-- the independent review of the same day): pairs of service keys name the same work in two trades and never met at the
-- service gate: a supplier holding one key was skipped by a request naming the other ("he was asked and does not hold
-- it"). Of the analysis's 13 pairs, 12 had no implication either way and the 13th (joinery.wooden_doors ->
-- doors.wooden_doors) one way; 6 sat in trades that are not curated neighbours, so even an implication would not have
-- helped (fn_match_capability considers only the request's trades, each named service's trade and their adjacent
-- trades). The review measured 4 more n -> n (tents_shades / fencing_shades x3, the two acoustic insulations), and
-- found that identity is ONE level deep: a civil contractor holding civil_works.new_construction matched
-- civil_works.blockwork (implied) but not its twin masonry_blockwork.blockwork.
--
-- WHAT THIS CHANGES:
--   1. service_implication.same boolean not null default false: same = true says the two keys are ONE piece of work
--      (identity), not that a firm doing the first usually does the second. A reader that asks the supplier about
--      implied services must not ask about a `same` row: confirming one key is confirming the other.
--   2. 18 pairs, one row each way, same = true (36 rows): the analysis's 13 except waterproofing.thermal /
--      thermal_insulation.roof_insulation (not identity: thermal insulation is roofs AND walls, so it is the plain
--      implication of 3), the review's 4, and the two staff keys the catalogue file adds under labour_supply
--      (office_admin_staff = hr_outsourcing.office_staff_outsourcing, receptionists = facilities_management.concierge_reception).
--   3. 10 plain implications (same = false): waterproofing.thermal -> roof and wall insulation; the 6 TWINS of curated
--      implications that end in a key of a pair (so an implied key reaches its twin: fn_services_effective follows one
--      level); aluminium.pergolas_shades -> landscaping.pergolas_gazebos and av_it.audio_visual -> signage.digital_signage
--      (decided as one-way: an aluminium pergola firm builds garden pergolas and an AV integrator installs digital
--      signage; a landscaper is not an aluminium shade firm and a sign maker is not an AV integrator).
--   4. 10 trade pairs become curated adjacent trades, each with its reason; adjacency is one level, is read only when a
--      request names a service, and a supplier reached through it must still hold a named service (the gate is
--      unchanged). The review measured that the analysis's 6 invite nobody unrelated.
-- No routine changes. The rows are listed one by one so the mirror supabase/functions/_shared/service_implications.json
-- can carry them exactly (scripts/checks/the_implication_map_has_one_seed.test.mjs reads this block).
-- Still open, for the sales engineer seat: packaging.labels / cartons vs labels_sleeves / corrugated_packaging.
--
-- prevented by: scripts/sql/the_same_work_under_two_keys_meets_at_the_service_gate_probe.sql (every same row both ways,
--               every plain row, through the live fn_match_capability in an aborted transaction, with a control service
--               that must NOT match) and scripts/checks/the_same_work_under_two_keys_meets_at_the_service_gate.test.mjs.

alter table public.service_implication add column if not exists same boolean not null default false;
comment on column public.service_implication.same is
  'sales_engineer: true = the two keys name the same work (identity), one row each way; confirming one is confirming the other, so it is never asked as an implied service.';

insert into public.service_implication (from_code, implies_trade, implies_code, reason_en, reason_ar, same) values
  ('landscaping.pools','swimming_pools','pool_construction','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('swimming_pools.pool_construction','landscaping','pools','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('cleaning.pest_control','pest_control','general_pest_control','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('pest_control.general_pest_control','cleaning','pest_control','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('cleaning.facility_management','facilities_management','integrated_fm','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('facilities_management.integrated_fm','cleaning','facility_management','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('security_systems.guarding','security_guarding','manned_guarding','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('security_guarding.manned_guarding','security_systems','guarding','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('upholstery.curtains','curtains_blinds','curtains','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('curtains_blinds.curtains','upholstery','curtains','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('water_treatment.tank_cleaning_disinfection','water_treatment_services','water_tank_cleaning_disinfection','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('water_treatment_services.water_tank_cleaning_disinfection','water_treatment','tank_cleaning_disinfection','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('gypsum.plastering','masonry_blockwork','plastering','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('masonry_blockwork.plastering','gypsum','plastering','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('civil_works.blockwork','masonry_blockwork','blockwork','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('masonry_blockwork.blockwork','civil_works','blockwork','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('joinery.wooden_doors','doors','wooden_doors','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('doors.wooden_doors','joinery','wooden_doors','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('civil_works.demolition','demolition_works','building_demolition','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('demolition_works.building_demolition','civil_works','demolition','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('engineering_consultancy.architectural_design','design_consultancy','architectural_design','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('design_consultancy.architectural_design','engineering_consultancy','architectural_design','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('interior_fitout.interior_design','design_consultancy','interior_design','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('design_consultancy.interior_design','interior_fitout','interior_design','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('tents_shades.car_park_shades','fencing_shades','car_park_shades','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('fencing_shades.car_park_shades','tents_shades','car_park_shades','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('tents_shades.tensile_structures','fencing_shades','tensile_structures','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('fencing_shades.tensile_structures','tents_shades','tensile_structures','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('tents_shades.shade_sails','fencing_shades','sail_shades','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('fencing_shades.sail_shades','tents_shades','shade_sails','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('waterproofing.acoustic','thermal_insulation','acoustic_insulation','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('thermal_insulation.acoustic_insulation','waterproofing','acoustic','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('labour_supply.office_admin_staff','hr_outsourcing','office_staff_outsourcing','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('hr_outsourcing.office_staff_outsourcing','labour_supply','office_admin_staff','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('labour_supply.receptionists','facilities_management','concierge_reception','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('facilities_management.concierge_reception','labour_supply','receptionists','The same work catalogued under two trades: holding one key is holding the other.','العمل نفسه مُدرج تحت مهنتين، ومن يقدّم أحدهما يقدّم الآخر.',true),
  ('waterproofing.thermal','thermal_insulation','roof_insulation','A waterproofing contractor who does thermal insulation insulates roofs and walls.','مقاول العزل المائي الذي يقدّم العزل الحراري يعزل الأسطح والجدران.',false),
  ('waterproofing.thermal','thermal_insulation','wall_insulation','A waterproofing contractor who does thermal insulation insulates roofs and walls.','مقاول العزل المائي الذي يقدّم العزل الحراري يعزل الأسطح والجدران.',false),
  ('civil_works','masonry_blockwork','blockwork','Civil contractors carry out concrete, blockwork and plastering.','مقاولو الأعمال المدنية ينفّذون أعمال الخرسانة والطابوق واللياسة.',false),
  ('civil_works','masonry_blockwork','plastering','Civil contractors carry out concrete, blockwork and plastering.','مقاولو الأعمال المدنية ينفّذون أعمال الخرسانة والطابوق واللياسة.',false),
  ('civil_works.new_construction','masonry_blockwork','blockwork','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.',false),
  ('civil_works.new_construction','masonry_blockwork','plastering','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.',false),
  ('interior_fitout.decoration','curtains_blinds','curtains','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.',false),
  ('interior_fitout.turnkey','doors','wooden_doors','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.',false),
  ('aluminium.pergolas_shades','landscaping','pergolas_gazebos','Aluminium pergola makers also build garden pergolas and gazebos.','مصنّعو البرجولات الألمنيوم ينفّذون كذلك برجولات الحدائق والجلسات الخارجية.',false),
  ('av_it.audio_visual','signage','digital_signage','Audio-visual integrators supply and install digital signage and LED displays.','شركات أنظمة الصوت والصورة تورّد اللافتات الرقمية وشاشات LED وتركّبها.',false)
on conflict (from_code, implies_trade, implies_code) do update set same = excluded.same, active = true;

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
   'مقاولو التجهيز الداخلي يصمّمون الديكور، والمصمّمون ينفّذون التجهيز.'),
  ('facilities_management', 'labour_supply',
   'Facilities managers and manpower suppliers both place reception and front-desk staff.',
   'شركات إدارة المرافق وشركات توريد العمالة توفّر كلتاهما موظفي الاستقبال.'),
  ('doors', 'interior_fitout',
   'Fit-out contractors supply and hang the doors of the interiors they build.',
   'مقاولو التجهيز الداخلي يورّدون الأبواب ويركّبونها في المساحات التي ينفّذونها.'),
  ('aluminium', 'landscaping',
   'Aluminium pergola makers and landscapers both build garden pergolas and gazebos.',
   'مصنّعو الألمنيوم وشركات تنسيق الحدائق ينفّذون كلاهما برجولات الحدائق والجلسات الخارجية.'),
  ('av_it', 'signage',
   'Audio-visual integrators and sign makers both install digital signage and LED displays.',
   'شركات الصوت والصورة وشركات اللافتات تركّب كلتاهما اللافتات الرقمية وشاشات LED.')
) as x(a, b, en, ar)
on conflict (a_code, b_code) do update set reason_en = excluded.reason_en, reason_ar = excluded.reason_ar, active = true;

-- Verdict row (DDL file, so no raise): the column, the 36 identity rows, the 10 plain rows and the 10 adjacent pairs.
select case
  when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'service_implication'
                 and column_name = 'same' and data_type = 'boolean' and is_nullable = 'NO')
   and (select count(*) from public.service_implication where active and same) >= 36
   and not exists (select 1 from public.service_implication where same and from_code = 'waterproofing.thermal')
   and (select count(*) from public.taxonomy_trade_adjacent where active and (a_code, b_code) in (
          ('security_guarding','security_systems'), ('gypsum','masonry_blockwork'), ('civil_works','masonry_blockwork'),
          ('civil_works','demolition_works'), ('design_consultancy','engineering_consultancy'), ('design_consultancy','interior_fitout'),
          ('facilities_management','labour_supply'), ('doors','interior_fitout'), ('aluminium','landscaping'), ('av_it','signage'))) = 10
  then 'PROBE OK the same-work pairs are identity rows both ways, their twins and links are in place, their trades adjacent'
  else 'PROBE FAILED: a same-work row, the column or an adjacent pair is missing' end as verdict;
