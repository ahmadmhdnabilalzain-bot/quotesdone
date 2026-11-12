# The catalogue knows the plain words suppliers use (12 Nov 2026, sales_engineer)

Founder ruling 1647: the reading of a supplier's profile must get his services right, because everything after it depends
on it. `scripts/sql/the_catalogue_knows_the_plain_words_suppliers_use.sql` gives the catalogue's services the plain names
a UAE supplier writes, so that the reading's code places his phrase on a key without asking a model. On 12 Nov 2026,
874 of the 1,151 active services had no name but their label.

**Status: written, rehearsed, NOT applied, and not to be applied before Monday** (coordinator's decision after the
independent review, `scratchpad/fixes/svc-aliases/REVIEW.md`). It is pending: `scripts/sql/pending/the_catalogue_knows_the_plain_words_suppliers_use.txt`.

## What the file holds now

- 3,501 curated names (2,858 English, 643 Arabic) on 907 services. Services with no name: 874 before, 19 after.
- Queue rows 205 and 206 ("تنظيف فلل", "تنظيف شقق" left approved under `cleaning.deep_cleaning`) rejected; `cleaning.residential` already holds both.
- Two plain implication rows: `thermal_insulation.roof_insulation` and `wall_insulation` -> `waterproofing.thermal`.
- The first version held 3,870 names. The review read every one against the live catalogue and found 213 bad (153 English,
  4.9 per 100; 60 Arabic, 8.1 per 100); they are removed. The guard was then made stronger (one name, one key, compared on a
  stem: plurals, a trailing supply / services / works / system(s), any trade's name, a part of another service's label in
  either language), and it refused 156 more. Bare profession words are not names ("professionals", "supervisors", "drivers",
  "electricians", "masons", "carpenters", "accountants"); specific forms are.

## What must be true before it is applied

Three conditions, all of them (the coordinator's decision of 12 Nov 2026):

(a) A GOLDEN SET FOR MATCHING EXISTS and is run before and after the apply plus re-embed. It holds 100 real request texts (production inquiries, the customer's own words, no ZZ DEMO) each with the service key(s) the sales engineer agrees is right, and 100 real supplier phrases (from listed companies' and confirmed suppliers' own text: not the hard profiles' phrases, which this file added and so cannot test it) each with its key. It is scored three ways: exact names (supplier_profile_reading.ts nameIndex/codeKeysOf and service_rewrite.ts exactService), the meaning layer (service_meaning.ts proposeByMeaning over the stored vectors), and fn_lead_reclassify_tick's trade shortlist. Top-1 and top-3 per way, before and after: no way may fall, and no phrase that was right may turn wrong. The repository has no such set today: the two checks that measured the meaning layer were retired on 11 Nov 2026 (customer_support) with their subjects, scripts/checks/retired/a_catalogue_line_is_understood_by_meaning.RETIRED.mjs (catalogue_read.readCatalogue deleted) and scripts/checks/retired/a_suppliers_documents_name_trades_by_exact_code_or_meaning_never_by_words.RETIRED.mjs (trade_resolve.tradesOfText deleted), both under founder ruling 1627; scripts/checks/services_are_named_by_exact_name_or_meaning_never_by_alias_words.test.mjs keeps a small live leg of ZZ DEMO sentences, which is not a labelled set.

(b) ONE PAID RE-MEASUREMENT of the 16 hard profiles after the apply and re-embed (scripts/e2e/services_hard_profiles/run.mjs, then record.mjs; about USD 0.18 and about 56 calls, as run c0afdde7 cost USD 0.1813; cap USD 0.40). The pass bar, set before the run: not below today's 97 of 111 stated services listed or asked; no more than 2 wrong trades of 65; no wrong service listed beyond the three known (H06 industrial_pumps.booster_sets, H07 packaging.labels, H04 labour_supply.general). The recording then replaces recorded.json, so the offline check replays the state after the apply.

(c) THE SALES ENGINEER DECIDES THE PAIRS FIRST, because a name given to one key of a pair is a decision about the pair. Recommendations:
  the nine keys in seven duplicate pairs (left without a name here):
   - machinery_repair.motor_rewinding / motors_drives.motor_rewinding: same work, `same` both ways.
   - flexible_packaging.bubble_wrap_air_cushions / protective_packaging.bubble_wrap (packaging.protective holds "bubble wrap"): same work, `same` both ways between the two.
   - packaging.shrink_sleeves / labels_sleeves.shrink_sleeves: same work, `same` both ways.
   - packaging.strapping (PP, PET & steel) / packaging_tapes_strapping.pet_pp_strapping and steel_strapping: not identity (one is wider); plain rows both ways.
   - packaging.woven_sacks / bulk_bags_sacks.pp_woven_sacks: same work, `same` both ways.
   - packaging.fibc_bags / bulk_bags_sacks.jumbo_bags: same work, `same` both ways.
   - playground_equipment.shade_sails / tents_shades.shade_sails (= fencing_shades.sail_shades): same work, `same` rows to both (`same` is one level).
  the twelve same-work pairs with no `same` row (this file split their synonyms between the two keys):
   - logistics_moving.moving / removals_relocation.home_moving and office_relocation: moving is wider; plain rows both ways.
   - accounting_bookkeeping.payroll_processing / hr_outsourcing.payroll_wps: same work, `same` both ways.
   - staff_transport.chauffeur_limousine / vehicle_leasing.chauffeur_services: same work, `same` both ways.
   - testing_labs.water_environmental_testing / water_treatment.water_testing: the lab is wider; plain rows both ways.
   - waste_management.construction_debris_removal / demolition_works.debris_removal: same work, `same` both ways.
   - calibration_services.laboratory_equipment / laboratory_equipment.calibration_services: same work, `same` both ways.
   - investigation_screening.employee_background_check / recruitment_executive_search.background_screening: same work, `same` both ways.
   - event_equipment_rental.tents_marquees / tents_shades.event_tents: hire versus supply and install; plain rows both ways.
   - civil_works.new_construction / general_contracting.building_construction: same work, `same` both ways.
   - mep_general.mep_maintenance / facilities_management.building_maintenance: building maintenance is wider; plain row building_maintenance -> mep_maintenance.
   - batteries_storage.battery_energy_storage_systems / solar.battery_storage: same work, `same` both ways.
   - fuel_diesel.lubricants / lubricants_industrial_oils.engine_oils and hydraulic_gear_oils: plain rows from the two specialist keys to fuel_diesel.lubricants.

## At merge, once the three hold

Apply with `--seat sales_engineer` (data only), the probe through `rehearse_sql.mjs`, the MANIFEST line in the same commit
as the deleted note, then the re-embed. Run it only from the main checkout, where `@huggingface/transformers` resolves.
Elsewhere `scripts/lib/service_vectors.mjs` makes about 909 `embed_ml` calls, and its header records 107 GB of egress in
two hours from such a run. The exact steps are in the pending note.

## Candidates for the other key (removed here, not moved; for the sales engineer to decide)

Each phrase was on the review's list of bad rows because it names another key better, and that other key does not hold it today. Moving one is a decision about two keys, so none is moved by this file.

| phrase | was given to | candidate key |
|---|---|---|
| ball valves | `valves_actuators.ball_butterfly_valves` | `oilfield.valves_fittings` |
| gate valves | `valves_actuators.gate_globe_check_valves` | `oilfield.valves_fittings` |
| steel pipes | `steel_stock.pipes_hollow_sections` | `oilfield.pipes_flanges` |
| ip phones | `telecom_services.business_phone_systems_pbx_voip` | `av_it.telecom` |
| kerb stones | `road_works.kerbs_road_marking` | `landscaping.hardscape` |
| kerbstones | `road_works.kerbs_road_marking` | `landscaping.hardscape` |
| interlock tiles | `road_works.interlock_paving` | `landscaping.hardscape` |
| interlocking tiles | `road_works.interlock_paving` | `landscaping.hardscape` |
| بروشورات | `commercial_printing.promotional_printing` | `commercial_printing.brochures_catalogues` |
| marble polishing | `marble_stone.stone_polishing` | `flooring.marble_granite` |
| chandeliers | `lighting_fixtures.decorative_lighting` | `electrical.lighting` |
| chandelier | `lighting_fixtures.decorative_lighting` | `electrical.lighting` |
| نجف | `lighting_fixtures.decorative_lighting` | `electrical.lighting` |
| lighting control system | `lighting_fixtures.lighting_controls` | `home_automation.lighting_control` |
| dimming systems | `lighting_fixtures.lighting_controls` | `home_automation.lighting_control` |
| ro system | `water_treatment.water_softeners_filters` | `water_treatment.ro_plants` |
| drinking water testing | `testing_labs.water_environmental_testing` | `water_treatment.water_testing` |
| potable water testing | `water_treatment.water_testing` | `testing_labs.water_environmental_testing` |
| تبخير | `pest_control.fumigation_of_cargo` | `cleaning.pest_control` |
| مخارط | `industrial_machinery.machine_tools_lathes_mills` | `cnc_machining.cnc_turning_milling` |
| building maintenance services | `facilities_management.building_maintenance` | `mep_general.mep_maintenance` |
| home movers | `removals_relocation.home_moving` | `logistics_moving.moving` |
| office movers | `removals_relocation.office_relocation` | `logistics_moving.moving` |
| office shifting | `removals_relocation.office_relocation` | `logistics_moving.moving` |
| packers and movers | `removals_relocation.packing_crating` | `logistics_moving.moving` |
| packing and moving | `removals_relocation.packing_crating` | `logistics_moving.moving` |
| payroll outsourcing | `accounting_bookkeeping.payroll_processing` | `hr_outsourcing.payroll_wps` |
| payroll services | `accounting_bookkeeping.payroll_processing` | `hr_outsourcing.payroll_wps` |
| payroll management | `hr_outsourcing.payroll_wps` | `accounting_bookkeeping.payroll_processing` |
| chauffeur | `vehicle_leasing.chauffeur_services` | `staff_transport.chauffeur_limousine` |
| chauffeur service | `vehicle_leasing.chauffeur_services` | `staff_transport.chauffeur_limousine` |
| lab instrument calibration | `laboratory_equipment.calibration_services` | `calibration_services.laboratory_equipment` |
| lv switchgear | `electrical_wholesale.switchgear_components` | `electrical.db_panels` |
| laser cutting steel | `steel_stock.cut_to_size_service` | `cnc_machining.laser_waterjet_cutting` |
| cnc plasma cutting | `steel_stock.cut_to_size_service` | `cnc_machining.laser_waterjet_cutting` |
| glass cleaners | `cleaning_chemicals.floor_surface_cleaners` | `cleaning.facade_windows` |
| candidate background checks | `recruitment_executive_search.background_screening` | `investigation_screening.employee_background_check` |
| debris disposal | `demolition_works.debris_removal` | `waste_management.construction_debris_removal` |
| servers | `it_services.servers_storage` | `it_services.hardware_supply` |
| سيرفرات | `it_services.servers_storage` | `it_services.hardware_supply` |
| tent rental | `event_equipment_rental.tents_marquees` | `tents_shades.event_tents` |
| تأجير خيام | `event_equipment_rental.tents_marquees` | `tents_shades.event_tents` |
| cable glands | `electrical_wholesale.conduits_glands` | `cables_wires.cable_accessories` |
| cable glands supply | `cables_wires.cable_accessories` | `electrical_wholesale.conduits_glands` |
| pabx systems | `telecom_services.business_phone_systems_pbx_voip` | `av_it.telecom` |
| sprinklers supply | `agri_inputs.irrigation_equipment` | `fire_fighting.sprinklers` |
| energy storage system | `batteries_storage.battery_energy_storage_systems` | `solar.battery_storage` |
| wall panelling | `joinery.wood_panelling` | `wallpaper.wall_panels` |
| building contractor | `general_contracting.building_construction` | `civil_works.new_construction` |
| لوحات إعلانية | `marketing_advertising.outdoor_billboards` | `signage.shop_signs` |
| chiller repair | `refrigeration_cold_rooms.refrigeration_maintenance` | `hvac.maintenance_amc` |
| sheet metal fabrication | `cnc_machining.sheet_metal_bending` | `steel.fabrication_welding` |
| building management | `real_estate_services.property_management` | `home_automation.bms` |
| breakers | `electrical_wholesale.breakers_contactors` | `tool_equipment_rental.power_tools` |
| 1000 litre tank | `metal_packaging.ibc_tanks` | `plastics_pipes.water_tanks` |
| سيور | `bearings_power_transmission.v_belts_pulleys` | `rubber_products.conveyor_belts` |
| rubber flooring | `playground_equipment.rubber_safety_flooring` | `fitness_equipment.gym_flooring` |
| rubber tiles | `playground_equipment.rubber_safety_flooring` | `fitness_equipment.gym_flooring` |
| أرضيات مطاطية | `playground_equipment.rubber_safety_flooring` | `fitness_equipment.gym_flooring` |
| t-shirt printing | `uniforms_corporate_apparel.embroidery_logo_branding` | `promotional_gifts.custom_printing_engraving` |
| tshirt printing | `uniforms_corporate_apparel.embroidery_logo_branding` | `promotional_gifts.custom_printing_engraving` |
| glass printing | `glass_containers.decoration_printing_on_glass` | `doors.window_film` |
| glass decoration | `glass_containers.decoration_printing_on_glass` | `doors.window_film` |
| glass frosting | `glass_containers.decoration_printing_on_glass` | `doors.window_film` |
| a4 paper | `paper_board.printing_paper` | `stationery_office_supplies.paper_notebooks` |
| copy paper | `paper_board.printing_paper` | `stationery_office_supplies.paper_notebooks` |
| ورق a4 | `paper_board.printing_paper` | `stationery_office_supplies.paper_notebooks` |
| ورق تصوير | `paper_board.printing_paper` | `stationery_office_supplies.paper_notebooks` |
| water fountains | `swimming_pools.water_features` | `water_dispensers.drinking_fountains` |
| dubai municipality approval | `design_consultancy.design_approvals` | `engineering_consultancy.authority_approvals` |
| office plants | `landscaping.plant_rental` | `landscaping.plants_trees_supply` |
| supervisor | `labour_supply.supervisors` | `engineering_consultancy.supervision` |
| supervisors | `labour_supply.supervisors` | `engineering_consultancy.supervision` |
| balloons | `toys_wholesale.seasonal_party_toys` | `event_management.event_decor` |
| بالونات | `toys_wholesale.seasonal_party_toys` | `event_management.event_decor` |

## What the stronger guard refused beyond the review's 213

| name | service | why |
|---|---|---|
| bookkeeping | `accounting_bookkeeping.monthly_bookkeeping` | (c) a trade's name: accounting_bookkeeping |
| bookkeeping services | `accounting_bookkeeping.monthly_bookkeeping` | (c) a trade's name: accounting_bookkeeping |
| مسك دفاتر | `accounting_bookkeeping.monthly_bookkeeping` | (c) a trade's name: accounting_bookkeeping |
| rapid prototyping | `additive_manufacturing.prototype_models` | (c) a trade's name: additive_manufacturing |
| compressor service | `air_compressors.compressor_maintenance` | (a/b) a stemmed name of oilfield.rotating_equipment+tool_equipment_rental.compressors_welders |
| aircraft parts | `aircraft_parts_mro.aircraft_spare_parts` | (c) a trade's name: aircraft_parts_mro |
| قطع غيار طائرات | `aircraft_parts_mro.aircraft_spare_parts` | (c) a trade's name: aircraft_parts_mro |
| abaya | `apparel_fashion_wholesale.abayas_kanduras` | (d) a part of the label of textiles_fabrics.abaya_kandura_fabric |
| abayas | `apparel_fashion_wholesale.abayas_kanduras` | (d) a part of the label of textiles_fabrics.abaya_kandura_fabric |
| كنادير | `apparel_fashion_wholesale.abayas_kanduras` | (d) a part of the label of textiles_fabrics.abaya_kandura_fabric |
| براويز | `artwork_decor.art_prints_framing` | (c) a trade's name: artwork_decor |
| bearing supply | `bearings_power_transmission.bearings` | (c) a trade's name: bearings_power_transmission |
| bicycle | `bicycles_micromobility.bicycles` | (c) a trade's name: bicycles_micromobility |
| دراجات هوائية | `bicycles_micromobility.bicycles` | (c) a trade's name: bicycles_micromobility |
| e scooter | `bicycles_micromobility.e_scooters` | (c) a trade's name: bicycles_micromobility |
| bitumen | `bitumen_petroleum_products.bitumen_supply` | (c) a trade's name: bitumen_petroleum_products |
| بيتومين | `bitumen_petroleum_products.bitumen_supply` | (c) a trade's name: bitumen_petroleum_products |
| وسائل تعليمية | `books_educational.teaching_aids` | (c) a trade's name: books_educational |
| fibc | `bulk_bags_sacks.jumbo_bags` | (c) a trade's name: bulk_bags_sacks |
| bulk bags | `bulk_bags_sacks.jumbo_bags` | (c) a trade's name: bulk_bags_sacks |
| أكياس منسوجة | `bulk_bags_sacks.pp_woven_sacks` | (c) a trade's name: bulk_bags_sacks |
| coworking | `business_centres.coworking_desks` | (c) a trade's name: business_centres |
| virtual office | `business_centres.virtual_office_ejari` | (c) a trade's name: business_centres |
| forging | `castings_forgings.forgings` | (c) a trade's name: castings_forgings |
| janitorial supplies | `cleaning_chemicals.janitorial_trolleys_mops` | (c) a trade's name: cleaning_chemicals |
| cnc machining | `cnc_machining.cnc_turning_milling` | (c) a trade's name: cnc_machining |
| cp system | `corrosion_insulation.cathodic_protection` | nothing left after the stem |
| debt collection | `debt_collection.commercial_collection` | (c) a trade's name: debt_collection |
| تحصيل ديون | `debt_collection.commercial_collection` | (c) a trade's name: debt_collection |
| credit reports | `debt_collection.company_credit_reports` | (c) a trade's name: debt_collection |
| تقارير ائتمانية | `debt_collection.company_credit_reports` | (c) a trade's name: debt_collection |
| strip-out works | `demolition_works.interior_strip_out` | (c) a trade's name: demolition_works |
| interior design services | `design_consultancy.interior_design` | (c) a trade's name: interior_fitout+design_consultancy |
| phone repair | `device_repair.mobile_phone_repair` | (c) a trade's name: device_repair |
| seo services | `digital_marketing.seo` | (c) a trade's name: digital_marketing |
| cable trays | `electrical.cable_tray` | (c) a trade's name: electrical |
| distribution boards | `electrical.db_panels` | (c) a trade's name: electrical |
| energy audit | `energy_services.energy_audits` | (c) a trade's name: energy_services |
| تدقيق الطاقة | `energy_services.energy_audits` | (c) a trade's name: energy_services |
| esco | `energy_services.performance_contracts` | (c) a trade's name: energy_services |
| kiosk | `exhibition_stands.kiosks_pop_ups` | (d) a part of the label of vending_machines.smart_lockers_kiosks |
| kiosks | `exhibition_stands.kiosks_pop_ups` | (d) a part of the label of vending_machines.smart_lockers_kiosks |
| rope access | `facade_access_maintenance.rope_access_repairs` | (c) a trade's name: facade_access_maintenance |
| rope access services | `facade_access_maintenance.rope_access_repairs` | (c) a trade's name: facade_access_maintenance |
| soft fm | `facilities_management.soft_services` | (c) a trade's name: facilities_management |
| soft fm services | `facilities_management.soft_services` | (c) a trade's name: facilities_management |
| housekeeping services | `facilities_management.soft_services` | (c) a trade's name: cleaning |
| براغي | `fasteners_fixings.bolts_nuts_washers` | (c) a trade's name: fasteners_fixings |
| fire pump systems | `fire_fighting.fire_pumps` | (c) a trade's name: fire_fighting |
| tiling works | `flooring.tiling` | (c) a trade's name: flooring |
| diesel supply | `fuel_diesel.diesel_delivery_to_site` | (c) a trade's name: fuel_diesel |
| توريد ديزل | `fuel_diesel.diesel_delivery_to_site` | (c) a trade's name: fuel_diesel |
| furniture dismantling | `furniture_repair.furniture_dismantle_reassemble` | (d) a part of the label of removals_relocation.furniture_assembly |
| glass bottle | `glass_containers.glass_bottles` | (c) a trade's name: glass_containers |
| عدد يدوية | `hand_power_tools.hand_tools` | (c) a trade's name: hand_power_tools |
| عدد كهربائية | `hand_power_tools.power_tools` | (a/b) a stemmed name of tool_equipment_rental.power_tools |
| bms systems | `home_automation.bms` | (c) a trade's name: home_automation |
| mattresses | `home_furniture.mattresses_bedding` | (c) a trade's name: home_furniture |
| mattress | `home_furniture.mattresses_bedding` | (c) a trade's name: home_furniture |
| مراتب | `home_furniture.mattresses_bedding` | (c) a trade's name: home_furniture |
| plasticware | `houseware_wholesale.plasticware_household` | (d) a part of the label of laboratory_equipment.lab_glassware_plasticware |
| eor | `hr_outsourcing.employer_of_record` | (c) a trade's name: hr_outsourcing |
| vrf systems | `hvac.vrf_chiller` | (c) a trade's name: hvac |
| hydraulic service | `hydraulics_pneumatics.hydraulic_repair` | (c) a trade's name: hydraulics_pneumatics |
| industrial packing | `industrial_crating.machinery_packing` | (c) a trade's name: industrial_crating |
| machine installation | `industrial_machinery.installation_commissioning` | (d) a part of the label of machinery_repair.machine_installation_alignment |
| tarpaulin | `industrial_textiles.tarpaulins_canvas` | (d) a part of the label of tents_shades.awnings_tarpaulins |
| tarpaulins | `industrial_textiles.tarpaulins_canvas` | (d) a part of the label of tents_shades.awnings_tarpaulins |
| خطوط أنابيب | `infrastructure_utilities.pipelines` | (c) a trade's name: infrastructure_utilities |
| plc | `instrumentation_automation.plc_hmi` | (c) a trade's name: instrumentation_automation |
| automation systems | `instrumentation_automation.plc_hmi` | (c) a trade's name: instrumentation_automation |
| jewellery boxes | `jewellery_supplies.jewellery_display_packaging` | (d) a part of the label of luxury_rigid_boxes.perfume_jewellery_boxes |
| built in wardrobes | `joinery.wardrobes` | (c) a trade's name: joinery |
| carpenters supply | `labour_supply.skilled` | (c) a trade's name: joinery |
| plumbers supply | `labour_supply.skilled` | (c) a trade's name: plumbing |
| welders supply | `labour_supply.skilled` | (d) a part of the label of tool_equipment_rental.compressors_welders |
| عشب صناعي | `landscaping.artificial_grass` | (c) a trade's name: landscaping |
| نجيل صناعي | `landscaping.artificial_grass` | (c) a trade's name: landscaping |
| laundry equipment service | `laundry_equipment.laundry_equipment_maintenance` | (c) a trade's name: laundry_equipment |
| linen hire | `laundry_services.linen_rental` | (c) a trade's name: laundry_services |
| gift boxes | `luxury_rigid_boxes.rigid_gift_boxes` | (c) a trade's name: luxury_rigid_boxes |
| علب هدايا | `luxury_rigid_boxes.rigid_gift_boxes` | (c) a trade's name: luxury_rigid_boxes |
| mannequins | `mannequins_visual_merchandising.full_body_mannequins` | (c) a trade's name: mannequins_visual_merchandising |
| mannequin | `mannequins_visual_merchandising.full_body_mannequins` | (c) a trade's name: mannequins_visual_merchandising |
| استبيانات | `market_research.consumer_surveys` | (c) a trade's name: market_research |
| forklift service | `material_handling.forklift_servicing` | (c) a trade's name: material_handling+heavy_equipment |
| mobile phones | `mobile_phones_wholesale.smartphones` | (c) a trade's name: mobile_phones_wholesale |
| electric motor | `motors_drives.electric_motors` | (c) a trade's name: motors_drives |
| musical instruments | `musical_pro_audio.musical_instruments` | (c) a trade's name: musical_pro_audio |
| pro audio | `musical_pro_audio.pro_audio_equipment` | (c) a trade's name: musical_pro_audio |
| outdoor furniture | `outdoor_furniture.garden_terrace_furniture` | (c) a trade's name: outdoor_furniture |
| أثاث خارجي | `outdoor_furniture.garden_terrace_furniture` | (c) a trade's name: outdoor_furniture |
| filling machine | `packaging_machinery.filling_machines` | (a/b) the same stem given here to packaging_machinery.machine_servicing |
| filling machine service | `packaging_machinery.machine_servicing` | (a/b) a stemmed name of packaging_machinery.filling_machines |
| carrier bags | `paper_bags.printed_carrier_bags` | (c) a trade's name: paper_bags |
| أكياس تسوق | `paper_bags.printed_carrier_bags` | (c) a trade's name: paper_bags |
| عود | `perfumes_wholesale.oud_bakhoor` | (c) a trade's name: perfumes_wholesale |
| disinfection services | `pest_control.disinfection` | (d) a part of the label of water_treatment.tank_cleaning_disinfection+water_treatment_services.water_tank_cleaning_disinfection |
| pest control services | `pest_control.general_pest_control` | (c) a trade's name: pest_control |
| مكافحة القوارض | `pest_control.rodent_control` | (c) a trade's name: pest_control |
| video production | `photo_video_production.corporate_video` | (c) a trade's name: photo_video_production |
| إنتاج فيديو | `photo_video_production.corporate_video` | (c) a trade's name: photo_video_production |
| playground equipment | `playground_equipment.outdoor_play_structures` | (c) a trade's name: playground_equipment |
| drainage systems | `plumbing.drainage` | (c) a trade's name: plumbing |
| drainage works | `plumbing.drainage` | (c) a trade's name: plumbing |
| prefab buildings | `prefab_buildings.modular_steel_buildings` | (c) a trade's name: prefab_buildings |
| modular buildings | `prefab_buildings.modular_steel_buildings` | (c) a trade's name: prefab_buildings |
| مباني جاهزة | `prefab_buildings.modular_steel_buildings` | (c) a trade's name: prefab_buildings |
| pr services | `public_relations.media_relations` | nothing left after the stem |
| علاقات عامة | `public_relations.media_relations` | (c) a trade's name: public_relations |
| إدارة عقارات | `real_estate_services.property_management` | (c) a trade's name: real_estate_services |
| records storage | `records_management.off_site_archiving` | (c) a trade's name: records_management |
| recruitment services | `recruitment_executive_search.permanent_recruitment` | (c) a trade's name: recruitment_executive_search |
| cold room | `refrigeration_cold_rooms.cold_rooms_freezer_rooms` | (c) a trade's name: refrigeration_cold_rooms |
| cold rooms | `refrigeration_cold_rooms.cold_rooms_freezer_rooms` | (c) a trade's name: refrigeration_cold_rooms |
| غرف تبريد | `refrigeration_cold_rooms.cold_rooms_freezer_rooms` | (c) a trade's name: refrigeration_cold_rooms |
| فك وتركيب أثاث | `removals_relocation.furniture_assembly` | (a/b) a stemmed name of furniture_repair.furniture_dismantle_reassemble |
| تركيب أثاث | `removals_relocation.furniture_assembly` | (d) a part of the label of furniture_repair.furniture_dismantle_reassemble |
| asphalt works | `road_works.asphalt_paving` | (c) a trade's name: road_works |
| نقل الأموال | `security_guarding.cash_in_transit` | (c) a trade's name: security_guarding |
| security guards | `security_guarding.manned_guarding` | (c) a trade's name: security_systems |
| security guard services | `security_guarding.manned_guarding` | (c) a trade's name: security_systems |
| security guards supply | `security_guarding.manned_guarding` | (c) a trade's name: security_systems |
| sewage tanker | `sewage_tanker.septic_emptying` | (c) a trade's name: sewage_tanker |
| water tanker | `sewage_tanker.water_tanker_delivery` | (c) a trade's name: sewage_tanker |
| water tankers | `sewage_tanker.water_tanker_delivery` | (c) a trade's name: sewage_tanker |
| ship repair | `shipbuilding_repair.ship_drydocking` | (c) a trade's name: shipbuilding_repair |
| shipbuilding | `shipbuilding_repair.vessel_newbuild` | (c) a trade's name: shipbuilding_repair |
| بناء سفن | `shipbuilding_repair.vessel_newbuild` | (c) a trade's name: shipbuilding_repair |
| acrylic letters | `signage.letters_3d` | (c) a trade's name: signage |
| software development | `software_development.custom_software` | (c) a trade's name: software_development |
| app development | `software_development.mobile_apps` | (c) a trade's name: software_development |
| bus rental | `staff_transport.bus_hire` | (c) a trade's name: staff_transport |
| تأجير حافلات | `staff_transport.bus_hire` | (c) a trade's name: staff_transport |
| نقل موظفين | `staff_transport.staff_shuttles` | (c) a trade's name: staff_transport |
| water feature | `swimming_pools.water_features` | (c) a trade's name: swimming_pools |
| ضريبة الشركات | `tax_advisory.corporate_tax_registration_filing` | (c) a trade's name: tax_advisory |
| خيام | `tents_shades.event_tents` | (c) a trade's name: tents_shades |
| تأجير عدد | `tool_equipment_rental.power_tools` | (c) a trade's name: tool_equipment_rental |
| interpretation services | `translation_interpretation.simultaneous_interpretation` | (c) a trade's name: translation_interpretation |
| actuator | `valves_actuators.actuators` | (c) a trade's name: valves_actuators |
| valve actuators | `valves_actuators.actuators` | (c) a trade's name: valves_actuators |
| تأجير سيارات | `vehicle_leasing.short_term_rental` | (c) a trade's name: vehicle_leasing |
| coffee machines | `vending_machines.office_coffee_machines` | (c) a trade's name: vending_machines |
| coffee machine | `vending_machines.office_coffee_machines` | (c) a trade's name: vending_machines |
| vending machine | `vending_machines.snack_drink_vending_machines` | (c) a trade's name: vending_machines |
| vending machines | `vending_machines.snack_drink_vending_machines` | (c) a trade's name: vending_machines |
| vending service | `vending_machines.vending_placement_servicing` | (c) a trade's name: vending_machines |
| skip hire | `waste_management.skip_container_hire` | (c) a trade's name: waste_management |
| water dispenser | `water_dispensers.bottled_water_dispensers` | (c) a trade's name: water_dispensers |
| water dispensers | `water_dispensers.bottled_water_dispensers` | (c) a trade's name: water_dispensers |
| water cooler | `water_dispensers.bottled_water_dispensers` | (a/b) the same stem given here to water_dispensers.dispenser_sanitising_service |
| water cooler service | `water_dispensers.dispenser_sanitising_service` | (a/b) the same stem given here to water_dispensers.bottled_water_dispensers |
| stp | `water_treatment.wastewater_treatment_plants` | (d) a part of the label of water_treatment_services.stp_wtp_operation_maintenance |
| تنظيف خزانات | `water_treatment_services.water_tank_cleaning_disinfection` | (c) a trade's name: water_treatment_services |
| weighbridge | `weighing_systems.weighbridges` | (c) a trade's name: weighing_systems |
