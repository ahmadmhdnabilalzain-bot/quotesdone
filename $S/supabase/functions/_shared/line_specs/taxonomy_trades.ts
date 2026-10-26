// line_specs/taxonomy_trades.ts — the taxonomy_trade codes of 23 Sep 2026 (founder instructions 895/899/900,
// scripts/sql/the_missing_trades_join_the_taxonomy_under_twelve_groups.sql), as the quote hold reads them.
//
// tradeOfCategory (model.ts) matched a category by regular expressions written for the site's category
// slugs. A new taxonomy code would have fallen into those: hotel_furniture to joinery, cleaning_chemicals to
// cleaning — and been held on another trade's attributes. So an exact new code is decided here first:
//   * SAME_AS: the new code is the work an existing spec trade already reads (pest_control is pestcontrol,
//     with its termite warranty rule; shade structures are shade).
//   * BRANDED_GOODS: every line is a product named by make and model (a pump, a forklift, a phone). The
//     quote is held until each line states its brand and its model / product code (spec trade branded_goods).
//   * every other new code resolves to itself, which the catalogue does not hold: no line-level attribute is
//     asked (made-to-order goods and services need readers of their own, per trade — not written yet), and
//     the quote-level terms every quote carries (a concrete delivery date or lead time) still hold it.
// scripts/checks/every_trade_is_named_grouped_and_serviceable.test.mjs holds these lists equal to the SQL seed.

export const SAME_AS: Readonly<Record<string, string>> = {
  pest_control: 'pestcontrol',
  tents_shades: 'shade',
  fencing_shades: 'shade',
  demolition_works: 'demolition',
  general_contracting: 'general',
  masonry_blockwork: 'masonry',
  swimming_pools: 'pools',
  marble_stone: 'tiling',
  thermal_insulation: 'insulation',
  curtains_blinds: 'upholstery',
  removals_relocation: 'movers',
  design_consultancy: 'interiordesign',
};

export const BRANDED_GOODS: ReadonlySet<string> = new Set([
  'packaging_machinery', 'industrial_machinery', 'machinery_spare_parts', 'industrial_pumps', 'valves_actuators',
  'bearings_power_transmission', 'hand_power_tools', 'hydraulics_pneumatics', 'air_compressors', 'material_handling',
  'motors_drives', 'instrumentation_automation', 'commercial_kitchen', 'laundry_equipment', 'vending_machines',
  'water_dispensers', 'medical_equipment', 'electronics_wholesale', 'mobile_phones_wholesale', 'home_appliances',
  'vehicles_fleet', 'auto_parts', 'tyres_batteries', 'batteries_storage', 'fitness_equipment', 'salon_equipment',
  'musical_pro_audio', 'lighting_fixtures',
]);

export const NO_LINE_SPECS_YET: ReadonlySet<string> = new Set([
  'corrugated_packaging', 'flexible_packaging', 'rigid_plastic_packaging', 'glass_containers', 'metal_packaging',
  'pallets_wood_plastic', 'industrial_crating', 'fasteners_fixings', 'welding_equipment', 'racking_storage',
  'electrical_wholesale', 'cables_wires', 'steel_stock', 'non_ferrous_metals', 'polymers_resins', 'rubber_products',
  'industrial_gases', 'lubricants_industrial_oils', 'paper_board', 'abrasives_surface_finishing',
  'industrial_filters', 'industrial_textiles', 'castings_forgings', 'cnc_machining', 'additive_manufacturing',
  'mining_quarry_supplies', 'office_furniture', 'hotel_furniture', 'outdoor_furniture', 'school_furniture',
  'retail_shelving', 'mannequins_visual_merchandising', 'refrigeration_cold_rooms', 'hospitality_supplies',
  'cleaning_chemicals', 'tissue_disposables', 'medical_consumables', 'dental_supplies', 'laboratory_equipment',
  'pharma_wholesale', 'uniforms_corporate_apparel', 'textiles_fabrics', 'stationery_office_supplies',
  'promotional_gifts', 'books_educational', 'software_licensing', 'telecom_services', 'vehicle_leasing',
  'fuel_diesel', 'lpg_gas', 'water_treatment', 'sports_equipment', 'playground_equipment', 'cosmetics_wholesale',
  'perfumes_wholesale', 'toys_wholesale', 'jewellery_supplies', 'agri_inputs', 'veterinary_supplies',
  'legal_services', 'pro_government_services', 'accounting_bookkeeping', 'audit_assurance', 'tax_advisory',
  'insurance_brokerage', 'recruitment_executive_search', 'hr_outsourcing', 'corporate_training',
  'management_consultancy', 'marketing_advertising', 'digital_marketing', 'public_relations', 'market_research',
  'event_management', 'exhibition_stands', 'event_equipment_rental', 'photo_video_production',
  'translation_interpretation', 'commercial_printing', 'software_development', 'call_centre_bpo', 'debt_collection',
  'real_estate_services', 'business_centres', 'corporate_travel', 'staff_transport', 'courier_express',
  'cold_chain_logistics', 'records_management', 'security_guarding', 'iso_certification', 'hse_consultancy',
  'environmental_consultancy', 'energy_services', 'quantity_surveying', 'land_survey', 'testing_labs',
  'inspection_ndt', 'calibration_services', 'waste_management', 'recycling_scrap', 'hazardous_waste',
  'sewage_tanker', 'water_treatment_services', 'facade_access_maintenance', 'road_works', 'infrastructure_utilities',
  'prefab_buildings', 'corrosion_insulation', 'machinery_repair', 'fleet_maintenance', 'tool_equipment_rental',
  'laundry_services', 'ev_charging', 'aircraft_parts_mro', 'shipbuilding_repair', 'leather_footwear',
  'bitumen_petroleum_products', 'device_repair', 'event_entertainment', 'railway_equipment', 'furniture_repair',
  'investigation_screening', 'facilities_management', 'labels_sleeves', 'protective_packaging', 'bulk_bags_sacks', 'luxury_rigid_boxes', 'paper_bags', 'pharma_packaging', 'packaging_tapes_strapping',
]);
