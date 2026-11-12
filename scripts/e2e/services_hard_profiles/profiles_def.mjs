// THE HARD-PROFILE SET for supplier service profiling (sales_engineer, 12 Nov 2026; founder ruling 1647). Written for the analysis in
// docs/reports/2026-11-12-supplier-service-profiling.md (Part 2); make_profiles.mjs renders it, run.mjs reads it, score.mjs scores it.
// Twelve invented ZZ DEMO companies. Every company, licence number, partner and project here is fictional.
// Each profile carries its ANSWER KEY: what a sharp human sales engineer would list after reading it, and what he would ask.
//
// Answer-key fields (keys are public.taxonomy_trade / taxonomy_trade_service keys as they stand on 12 Nov 2026):
//   must_trades     trades the documents plainly state as the company's own business
//   ok_trades       neighbours that are not wrong
//   must_services   service keys the documents evidence in so many words (own team)
//   ok_services     keys that are a fair reading but not required
//   partner         service keys the documents say are delivered THROUGH A PARTNER / subcontractor
//   no_key          specific services the documents evidence that have NO key today (the supplier's own words)
//   umbrella        a broad word in the documents -> the specific candidates a human would ask about
//   questions       the questions he would ask (exact wording a supplier could answer with one tap)
//   vague           true when the profile is too vague to match on without asking
export const SYNTHETIC = 'QuotesDone synthetic fixture - not a real company or licence';

const P = (strings, ...v) => String.raw(strings, ...v);
const ul = (items) => `<ul>${items.map((s) => `<li>${s}</li>`).join('')}</ul>`;
const page = '<div class="brk"></div>';

export const PROFILES = [
  // 1 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H01', slug: 'decoration_landscape_pools_partner', company: 'ZZ DEMO Rimal Decoration LLC', signup_trade: 'interior_fitout',
    licence: { key: 'dubai_det', licence_no: 'ZZ-880141', activities: ['Interior Decoration Works', 'Building Maintenance'] },
    tagline: 'Decoration - Outdoor living - Pools',
    body: `
<h2>About Rimal</h2><p>Since 2012 Rimal has been a decoration company for villas, majlis, apartments and boutique offices in Dubai, Sharjah and Ajman. From the front gate to the last cushion, our clients give us the whole home.</p>
<h2>Inside the home</h2>${ul(['Complete interior decoration of villas and apartments, from concept and 3D design to handover', 'Gypsum ceilings, cornices and feature walls', 'Wall painting, stucco and decorative paint finishes', 'Wallpaper and decorative wall panels', 'Parquet and SPC flooring', 'Curtains, blinds and upholstery of majlis seating', 'Custom wardrobes and TV units made in our own carpentry workshop in Al Quoz'])}
<h2>Outside the home</h2><p>Our gardens team turns the plot around the villa into a place to live in.</p>${ul(['Garden design and landscaping: planting, lawns and palm trees', 'Interlock paving, garden paths and boundary walls', 'Automatic irrigation systems', 'Pergolas, gazebos and outdoor seating areas', 'Garden lighting', 'Monthly garden maintenance contracts'])}
<h2>Swimming pools</h2><p>Swimming pools, jacuzzis and water features are designed and built through our specialist partner, ZZ DEMO Blue Lagoon Pools, under our supervision and under one contract with you. Pool maintenance is also arranged through them.</p>
${page}<h2>Recent work</h2>${ul(['Full decoration of a 6-bedroom villa, Al Barsha South (2025)', 'Garden, pergola and pool for a villa in Mirdif (2025)', 'Majlis and dining room, Al Khawaneej (2024)', 'Boutique office interior, 320 m2, Business Bay (2024)'])}
<h2>How we work</h2><p>One designer and one site supervisor stay with the project from the first visit to the handover. We give a fixed price after the site visit.</p>`,
    key: {
      must_trades: ['interior_fitout', 'landscaping'], ok_trades: ['gypsum', 'painting', 'wallpaper', 'flooring', 'curtains_blinds', 'upholstery', 'joinery', 'swimming_pools', 'design_consultancy', 'aluminium', 'road_works'],
      must_services: ['interior_fitout.decoration', 'interior_fitout.interior_design', 'gypsum.false_ceiling', 'painting.interior', 'painting.decorative', 'wallpaper.supply_install', 'wallpaper.wall_panels', 'flooring.parquet_vinyl', 'landscaping.softscape', 'landscaping.hardscape', 'landscaping.irrigation', 'landscaping.maintenance'],
      ok_services: ['gypsum.decorative', 'curtains_blinds.curtains', 'curtains_blinds.roller_blinds', 'upholstery.curtains', 'upholstery.blinds', 'upholstery.majlis', 'upholstery.sofa', 'joinery.wardrobes', 'joinery.custom_furniture', 'aluminium.pergolas_shades', 'road_works.interlock_paving', 'design_consultancy.interior_design', 'design_consultancy.visualisation_3d', 'interior_fitout.turnkey', 'interior_fitout.office', 'lighting_fixtures.outdoor_lighting'],
      partner: ['landscaping.pools', 'swimming_pools.pool_construction', 'swimming_pools.water_features', 'swimming_pools.pool_maintenance'],
      no_key: ['villa / residential decoration (segment)', 'garden design', 'pergolas & gazebos (timber/WPC, not aluminium)', 'garden lighting', 'jacuzzi'],
      umbrella: { 'decoration company': ['interior decoration', 'gypsum ceilings', 'painting', 'wallpaper', 'flooring', 'curtains', 'joinery', 'landscaping', 'pools'] },
      questions: ['Swimming pools: do you deliver these with your own team, or through a partner? (profile says partner: confirm)', 'Do you also take office or shop fit-out, or homes only?', 'Do you take a single item on its own (only painting, only curtains), or only as part of a decoration project?', 'Which emirates do you work in? (profile: Dubai, Sharjah, Ajman)'],
      vague: false } },

  // 2 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H02', slug: 'manpower_staff_and_similar', company: 'ZZ DEMO Al Wafa Manpower Supply Services LLC', signup_trade: 'labour_supply',
    licence: { key: 'dubai_det', licence_no: 'ZZ-431907', activities: ['On Demand Labors Supply', 'Human Resources Consultancy'] },
    tagline: 'Your people partner',
    body: `
<h2>Who we are</h2><p>ZZ DEMO Al Wafa is a UAE recruitment and manpower company established in 2015. We supply staff and similar services to companies across the Emirates. Whatever your requirement, we provide the right people at the right time.</p>
<h2>What we offer</h2><p>We supply staff to our clients on a temporary or permanent basis, and we take care of everything related to them so that you can focus on your business. Our clients include contractors, hotels, facilities companies, retailers, factories and hospitals.</p>
<h2>Why Al Wafa</h2>${ul(['A large database of candidates inside the UAE and abroad', 'Fast mobilisation, usually within 48 hours', 'All visas, insurance and accommodation handled by us', 'Replacement guarantee'])}
<h2>Our promise</h2><p>People are our business. We treat every worker with respect and every client as a partner.</p>`,
    key: {
      must_trades: ['labour_supply'], ok_trades: ['recruitment_executive_search', 'hr_outsourcing'],
      must_services: [], ok_services: ['recruitment_executive_search.permanent_recruitment', 'recruitment_executive_search.overseas_recruitment', 'labour_supply.project_manpower', 'labour_supply.hourly', 'labour_supply.general', 'labour_supply.skilled', 'hr_outsourcing.office_staff_outsourcing'],
      partner: [],
      no_key: ['temporary staffing (general)', 'drivers', 'cleaners / housekeeping staff', 'security guards', 'hospitality staff (waiters, stewards)', 'office / admin staff', 'engineers & professionals', 'nurses / medical staff', 'freelancers', 'factory / warehouse workers'],
      umbrella: { 'supply staff and similar services': ['general labourers & helpers', 'skilled trades (masons, electricians, plumbers, welders)', 'drivers & operators', 'cleaners & housekeeping', 'security guards', 'hospitality staff', 'office & admin staff', 'engineers & professionals', 'freelancers'] },
      questions: ['What sort of staff do you supply? (labourers and helpers / skilled tradesmen / drivers and operators / cleaners and housekeeping / security guards / hospitality staff / office and admin staff / engineers and professionals / freelancers)', 'How do you supply them? (by the hour or day / monthly contract / permanent placement for a fee / recruitment from abroad)', '"Similar services": what else do you provide? (visa and PRO services / payroll / staff accommodation / staff transport)'],
      vague: true } },

  // 3 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H03', slug: 'general_trading_building_materials_vague', company: 'ZZ DEMO Burj Star General Trading LLC', signup_trade: 'building_materials',
    licence: { key: 'dubai_det', licence_no: 'ZZ-507733', activities: ['General Trading'] },
    tagline: 'One stop for every site',
    body: `
<h2>Company profile</h2><p>ZZ DEMO Burj Star General Trading LLC is a leading general trading company in Deira, Dubai. We deal in all kinds of building materials, hardware, tools, sanitary and electrical items and much more. We are a one-stop shop for contractors, maintenance companies and facility managers.</p>
<h2>Why buy from us</h2>${ul(['Wide range always in stock', 'Direct import from China, India and Turkey', 'Competitive prices and credit facility for approved customers', 'Same-day delivery in Dubai and the Northern Emirates'])}
<h2>Our customers</h2><p>More than 600 contracting and maintenance companies buy from Burj Star every year.</p>`,
    key: {
      must_trades: ['building_materials'], ok_trades: ['hand_power_tools', 'electrical_wholesale', 'fasteners_fixings', 'plastics_pipes', 'safety_equipment', 'plumbing'],
      must_services: [], ok_services: ['building_materials.sanitary_ware', 'hand_power_tools.hand_tools', 'hand_power_tools.power_tools', 'electrical_wholesale.wiring_accessories', 'building_materials.cement_concrete', 'building_materials.blocks_bricks'],
      partner: [],
      no_key: ['hardware (general ironmongery, locks, hinges)', 'paints & painting tools supply', 'plumbing fittings supply (taps, valves, flexible hoses)', 'tiles supply', 'gypsum board & plaster supply', 'timber & plywood supply'],
      umbrella: { 'all kinds of building materials, hardware, tools, sanitary and electrical items': ['cement / blocks / aggregates', 'steel & rebar', 'tiles', 'sanitary ware', 'pipes & fittings', 'electrical accessories', 'cables', 'hand & power tools', 'fasteners', 'paints', 'safety / PPE', 'timber & plywood'] },
      questions: ['Which of these do you keep in stock? (cement, blocks and aggregates / steel and rebar / tiles / sanitary ware and taps / pipes and fittings / electrical accessories and cables / hand and power tools / fasteners and fixings / paints / safety equipment / timber and plywood)', 'Do you only supply, or do you also install?', 'Which brands are you a distributor for, if any?'],
      vague: true } },

  // 4 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H04', slug: 'facilities_management_long_list', company: 'ZZ DEMO Emirates Crest Facilities Management LLC', signup_trade: 'facilities_management',
    licence: { key: 'abu_dhabi_added', licence_no: 'CN-ZZ660218', activities: ['Facilities Management Services', 'Building Cleaning Services', 'Air Conditioning, Ventilation and Air Filtration Systems Installation and Maintenance'] },
    tagline: 'Integrated facilities management',
    body: `
<h2>About us</h2><p>ZZ DEMO Emirates Crest Facilities Management LLC looks after 140 buildings in Abu Dhabi, Al Ain and Dubai: residential towers, schools, clinics, malls and labour accommodation. We employ 620 people.</p>
<h2>Hard services</h2>${ul(['Integrated facilities management contracts', 'MEP annual maintenance contracts (AMC)', 'HVAC maintenance: chillers, FCUs, AHUs and split units', 'AC duct cleaning and disinfection', 'Electrical maintenance: DBs, lighting and emergency lighting', 'Plumbing and drainage maintenance, pump servicing', 'Fire alarm and fire fighting system maintenance (through our Civil Defence approved partner)', 'Lift and escalator maintenance (managed through the OEM)', 'BMS operation', 'Water tank cleaning and disinfection', 'Swimming pool maintenance and lifeguards', 'Civil and carpentry repairs, painting and handyman services', 'Kitchen exhaust hood and duct cleaning'])}
<h2>Soft services</h2>${ul(['Daily cleaning and housekeeping of offices, towers and schools', 'Deep cleaning', 'Facade and window cleaning by rope access and cradle', 'Pest control (subcontracted to a municipality-approved company)', 'Landscaping and irrigation maintenance', 'Waste collection and segregation', 'Security guards and concierge (provided by our sister company ZZ DEMO Crest Guard Security Services)', 'Reception, tea boys and office support staff', 'Move-in and move-out snagging and make-ready'])}
${page}<h2>Sectors</h2><p>Residential communities, commercial towers, schools and nurseries, healthcare, retail, labour camps.</p>
<h2>Helpdesk</h2><p>A 24/7 call centre and a CAFM system log every work order. Emergency response within 60 minutes in Abu Dhabi city.</p>
<h2>Selected contracts</h2>${ul(['Total FM, 3 residential towers, Al Reem Island (2023-2026)', 'Hard FM, 12 private schools, Abu Dhabi and Al Ain (2024-2027)', 'Soft services, community mall, Khalifa City (2025-2026)'])}`,
    key: {
      must_trades: ['facilities_management', 'cleaning', 'hvac'], ok_trades: ['plumbing', 'electrical', 'mep_general', 'landscaping', 'swimming_pools', 'water_treatment_services', 'water_treatment', 'waste_management', 'painting', 'pest_control', 'fire_fighting', 'elevators', 'security_guarding', 'home_automation', 'facade_access_maintenance', 'labour_supply', 'hr_outsourcing', 'real_estate_services', 'joinery'],
      must_services: ['facilities_management.integrated_fm', 'facilities_management.mep_amc', 'facilities_management.soft_services', 'facilities_management.building_maintenance', 'hvac.maintenance_amc', 'cleaning.deep_cleaning', 'cleaning.facade_windows', 'cleaning.ac_duct', 'cleaning.kitchen_exhaust', 'electrical.maintenance', 'plumbing.maintenance'],
      ok_services: ['cleaning.facility_management', 'mep_general.mep_maintenance', 'swimming_pools.pool_maintenance', 'landscaping.maintenance', 'landscaping.irrigation', 'water_treatment_services.water_tank_cleaning_disinfection', 'water_treatment.tank_cleaning_disinfection', 'waste_management.general_waste_collection', 'painting.repainting', 'painting.interior', 'home_automation.bms', 'real_estate_services.snagging_inspection', 'hr_outsourcing.office_staff_outsourcing', 'facade_access_maintenance.rope_access_repairs'],
      partner: ['fire_fighting.civil_defence', 'fire_fighting.fire_alarm', 'elevators.maintenance', 'cleaning.pest_control', 'pest_control.general_pest_control', 'security_guarding.manned_guarding', 'security_systems.guarding'],
      no_key: ['daily / contract cleaning & housekeeping', 'handyman services', 'lifeguards', 'concierge', 'reception & office support staff (tea boys)', 'make-ready / move-out works', 'pump servicing', '24/7 helpdesk / CAFM'],
      umbrella: {},
      questions: ['Fire systems, lifts, pest control and security: your profile says these go through a partner or sister company. Should we send you inquiries for them? (yes, through our partner / no)', 'Do you take one service on its own (only cleaning, only AC maintenance) or only full FM contracts?', 'Which emirates? (profile: Abu Dhabi, Al Ain, Dubai)'],
      vague: false } },

  // 5 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H05', slug: 'general_maintenance_one_page_vague', company: 'ZZ DEMO Noor Al Madina Technical Services LLC', signup_trade: 'facilities_management',
    licence: { key: 'sharjah_sedd', licence_no: 'ZZ-774502', activities: ['Technical Services', 'Building Maintenance'] },
    tagline: 'General maintenance and technical services',
    body: `
<h2>General maintenance and technical services</h2><p>ZZ DEMO Noor Al Madina Technical Services LLC carries out all kinds of maintenance works for villas, flats, offices and shops in Sharjah, Ajman and Dubai. A/C, plumbing, electrical, painting, carpentry, tiling, etc. No job is too small.</p>
<p>Call us any time. 24 hours, 7 days.</p>`,
    key: {
      must_trades: [], ok_trades: ['facilities_management', 'hvac', 'plumbing', 'electrical', 'painting', 'joinery', 'flooring', 'mep_general', 'cleaning'],
      must_services: [], ok_services: ['facilities_management.building_maintenance', 'hvac.maintenance_amc', 'plumbing.maintenance', 'electrical.maintenance', 'painting.repainting', 'painting.interior', 'flooring.tiling', 'mep_general.mep_maintenance'],
      partner: [],
      no_key: ['general maintenance / handyman (the trade itself)', 'A/C repair & servicing (callout, not AMC)', 'carpentry repairs', 'tile repair', '24/7 emergency callout'],
      umbrella: { 'all kinds of maintenance works': ['A/C servicing and repair', 'A/C installation', 'plumbing repairs', 'electrical repairs', 'painting', 'carpentry repairs', 'tiling', 'gypsum & false ceiling repairs', 'waterproofing', 'annual maintenance contracts'] },
      questions: ['A/C: which of these do you do? (servicing and repair / new installation / duct cleaning / annual contracts)', 'Do you take new installation and fit-out works, or repairs and maintenance only?', '"etc.": which of these as well? (gypsum and false ceilings / waterproofing / glass and aluminium / cleaning / pest control / none)', 'Do you offer annual maintenance contracts, or call-out jobs only?'],
      vague: true } },

  // 6 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H06', slug: 'mep_contractor_clear', company: 'ZZ DEMO Falcon Electromechanical Works LLC', signup_trade: 'mep_general',
    licence: { key: 'dubai_det', licence_no: 'ZZ-915560', activities: ['Electromechanical Equipment Installation and Maintenance', 'Air Conditioning, Ventilation and Air Filtration Systems Installation and Maintenance', 'Plumbing and Sanitary Installation', 'Fire Fighting and Alarm Systems Installation'] },
    tagline: 'MEP contracting since 2006',
    body: `
<h2>About Falcon</h2><p>ZZ DEMO Falcon Electromechanical Works LLC is an MEP contractor for buildings up to G+20, with 310 employees and its own duct fabrication workshop in Al Qusais. We are a Dubai Civil Defence approved fire contractor.</p>
<h2>Our services</h2>
<h3>HVAC</h3>${ul(['Supply and installation of split, ducted and package air conditioning units', 'VRF systems and air-cooled chillers', 'GI ducting, fabricated in house, and ventilation', 'Testing, balancing and commissioning'])}
<h3>Electrical</h3>${ul(['LV distribution boards, SMDBs and MCC panels', 'Cable trays, trunking and conduiting', 'Wiring, small power and lighting installation', 'Earthing and lightning protection'])}
<h3>Plumbing and drainage</h3>${ul(['Water supply piping (PPR, copper, PEX)', 'Drainage and sewerage', 'Sanitary fixtures installation', 'Water heaters, booster and transfer pumps'])}
<h3>Fire fighting</h3>${ul(['Sprinkler systems and hose reels', 'Fire pumps', 'Fire alarm systems', 'Civil Defence approvals and annual maintenance'])}
<h3>ELV and controls</h3>${ul(['BMS', 'CCTV and access control', 'Structured cabling'])}
<h3>After handover</h3>${ul(['Annual maintenance contracts for complete MEP', 'Shop drawings and as-built drawings', 'DEWA and Civil Defence authority approvals'])}
${page}<h2>Projects</h2>${ul(['MEP works, G+12 residential building, JVC (2025)', 'HVAC and fire fighting, private school, Al Warqa (2024)', 'MEP fit-out, 4 office floors, DIFC (2024)'])}`,
    key: {
      must_trades: ['mep_general', 'hvac', 'electrical', 'plumbing', 'fire_fighting'], ok_trades: ['home_automation', 'security_systems', 'it_services', 'av_it'],
      must_services: ['hvac.supply_install', 'hvac.vrf_chiller', 'hvac.ducting', 'hvac.testing_commissioning', 'electrical.db_panels', 'electrical.cable_tray', 'electrical.wiring_install', 'electrical.lighting', 'plumbing.water_supply', 'plumbing.drainage', 'plumbing.sanitary_fixtures', 'plumbing.heaters_pumps', 'fire_fighting.sprinklers', 'fire_fighting.fire_pumps', 'fire_fighting.fire_alarm', 'fire_fighting.civil_defence', 'mep_general.mep_install', 'mep_general.mep_maintenance', 'mep_general.shop_drawings', 'mep_general.authority_approvals'],
      ok_services: ['home_automation.bms', 'security_systems.cctv', 'security_systems.access_control', 'it_services.structured_cabling', 'av_it.data_cabling', 'hvac.maintenance_amc', 'mep_general.testing_commissioning'],
      partner: [], no_key: ['earthing & lightning protection', 'duct fabrication'],
      umbrella: {}, questions: ['Up to what building size or contract value do you take? (profile: buildings up to G+20)'], vague: false } },

  // 7 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H07', slug: 'two_unrelated_lines_signage_it', company: 'ZZ DEMO Pixel and Port LLC', signup_trade: 'signage',
    licence: { key: 'ajman_ded', licence_no: 'ZZ-338126', activities: ['Signboards Installation', 'Advertising Requisites Trading', 'Computer Network Installation and Maintenance'] },
    tagline: 'Signage Division - IT Networks Division',
    body: `
<h2>One company, two divisions</h2><p>ZZ DEMO Pixel and Port LLC started in 2011 as a sign maker in Ajman. In 2018 the owners added an IT networks division. Each division has its own manager, team and workshop.</p>
<h2>Signage Division</h2>${ul(['Shop front signs and fascia boards', '3D acrylic and stainless steel letters', 'LED light boxes and neon', 'Wayfinding and safety signs for buildings', 'Vehicle branding and fleet graphics', 'Large-format digital printing, banners and stickers', 'Municipality sign permits'])}
<h2>IT Networks Division</h2>${ul(['Structured cabling, Cat6 and fibre', 'Network installation: switches, routers, firewalls and Wi-Fi', 'Server rooms and racks', 'CCTV and access control', 'IP telephony and PABX', 'Annual IT support contracts for small offices'])}
<h2>Clients</h2><p>Retail chains, clinics, schools and SMEs in Ajman, Sharjah, Umm Al Quwain and Ras Al Khaimah.</p>`,
    key: {
      must_trades: ['signage', 'it_services'], ok_trades: ['security_systems', 'telecom_services', 'commercial_printing', 'av_it', 'marketing_advertising'],
      must_services: ['signage.shop_signs', 'signage.letters_3d', 'signage.lightbox', 'signage.wayfinding', 'signage.large_format', 'it_services.structured_cabling', 'it_services.network_install', 'it_services.it_support'],
      ok_services: ['it_services.servers_storage', 'it_services.cybersecurity', 'security_systems.cctv', 'security_systems.access_control', 'telecom_services.business_phone_systems_pbx_voip', 'av_it.data_cabling', 'av_it.telecom', 'safety_equipment.signs_barriers', 'marketing_advertising.advertising_permits', 'it_services.hardware_supply'],
      partner: [], no_key: ['vehicle branding & fleet graphics', 'neon signs', 'municipality sign permits', 'Wi-Fi installation'],
      umbrella: {}, questions: ['Which emirates do you install in? (profile: Ajman, Sharjah, UAQ, RAK)'], vague: false } },

  // 8 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H08', slug: 'arabic_only_cleaning_pest', company: 'ZZ DEMO Al Nukhba Cleaning and Pest Control Services LLC', signup_trade: 'cleaning', lang: 'ar',
    company_ar: 'زد زد ديمو النخبة لخدمات التنظيف ومكافحة الحشرات ذ.م.م',
    licence: { key: 'sharjah_sedd', licence_no: 'ZZ-209874', activities: ['Building Cleaning Services', 'Public Health Pests Control Services'] },
    tagline: 'الملف التعريفي للشركة',
    body: `
<h2>من نحن</h2><p>شركة زد زد ديمو النخبة لخدمات التنظيف ومكافحة الحشرات تأسست عام 2014 في الشارقة، وتخدم الفلل والشقق والمكاتب والمدارس والمطاعم في الشارقة وعجمان ودبي بفريق مكوّن من 85 عاملاً ومشرفاً.</p>
<h2>خدماتنا</h2>${ul(['التنظيف العميق للفلل والشقق', 'التنظيف بعد أعمال البناء والصيانة', 'تنظيف الواجهات الزجاجية والنوافذ', 'تنظيف وتعقيم خزانات المياه', 'تنظيف السجاد والكنب والستائر بالبخار', 'عقود التنظيف اليومية والشهرية للمكاتب والمدارس', 'تلميع وجلي الرخام', 'مكافحة الحشرات الزاحفة والطائرة', 'مكافحة القوارض', 'مكافحة النمل الأبيض قبل البناء وبعده', 'التعقيم والتطهير'])}
<h2>لماذا النخبة</h2>${ul(['مواد معتمدة من بلدية الشارقة', 'فنيون مرخّصون لمكافحة الآفات', 'خدمة في نفس اليوم'])}
<h2>عملاؤنا</h2><p>مدارس خاصة، عيادات، مطاعم، وشركات إدارة العقارات.</p>`,
    key: {
      must_trades: ['cleaning', 'pest_control'], ok_trades: ['water_treatment_services', 'water_treatment', 'marble_stone', 'facilities_management'],
      must_services: ['cleaning.deep_cleaning', 'cleaning.post_construction', 'cleaning.facade_windows', 'pest_control.general_pest_control', 'pest_control.rodent_control', 'pest_control.termite_treatment', 'pest_control.disinfection'],
      ok_services: ['cleaning.pest_control', 'water_treatment_services.water_tank_cleaning_disinfection', 'water_treatment.tank_cleaning_disinfection', 'marble_stone.stone_polishing', 'facilities_management.soft_services'],
      partner: [], no_key: ['carpet, sofa & curtain steam cleaning', 'daily / monthly contract cleaning for offices and schools'],
      umbrella: {}, questions: ['(none needed: the list is specific) Which emirates? (profile: Sharjah, Ajman, Dubai)'], vague: false } },

  // 9 ─────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H09', slug: 'glossy_30_pages_services_in_captions', company: 'ZZ DEMO Meridian Interiors LLC', signup_trade: 'interior_fitout', glossy: true,
    licence: { key: 'dubai_det', licence_no: 'ZZ-612045', activities: ['Interior Decoration Works', 'Carpentry and Flooring Contracting', 'False Ceiling and Light Partitions Installation'] },
    tagline: 'Crafting spaces. Building trust.',
    // body is generated (30 pages) by make_profiles.mjs from GLOSSY below
    key: {
      must_trades: ['interior_fitout', 'joinery'], ok_trades: ['flooring', 'marble_stone', 'gypsum', 'glazing', 'painting', 'hotel_furniture', 'office_furniture', 'wallpaper', 'design_consultancy', 'lighting_fixtures', 'doors', 'upholstery', 'curtains_blinds', 'mep_general', 'electrical', 'hvac', 'signage', 'commercial_kitchen', 'retail_shelving'],
      must_services: ['interior_fitout.turnkey', 'interior_fitout.office', 'interior_fitout.retail', 'joinery.custom_furniture', 'joinery.wood_panelling', 'joinery.kitchens', 'joinery.wardrobes'],
      ok_services: ['interior_fitout.refurbishment', 'interior_fitout.decoration', 'interior_fitout.interior_design', 'flooring.marble_granite', 'flooring.parquet_vinyl', 'flooring.carpet', 'gypsum.false_ceiling', 'gypsum.partitions', 'gypsum.acoustic_ceiling', 'glazing.partitions', 'joinery.wooden_doors', 'doors.wooden_doors', 'doors.fire_doors', 'hotel_furniture.casegoods_headboards', 'hotel_furniture.guestroom_furniture_packages', 'office_furniture.reception_counters', 'wallpaper.wall_panels', 'wallpaper.wall_cladding', 'marble_stone.worktops_vanities', 'painting.decorative'],
      partner: [], no_key: ['hospitality fit-out (hotels, restaurants, cafes)', 'clinic / healthcare fit-out', 'residential (villa, apartment) fit-out', 'own joinery factory (capacity 2,400 m2)', 'MEP modifications inside fit-out'],
      umbrella: { 'fit-out (from captions)': ['office fit-out', 'retail fit-out', 'restaurant / cafe fit-out', 'hotel refurbishment', 'clinic fit-out', 'villa interiors'] },
      questions: ['Joinery from your own factory: do you take joinery-only orders (doors, wardrobes, kitchens, reception counters) for other contractors, or only inside your own fit-out projects?', 'Marble, glass partitions and gypsum appear in your project captions: own team, or subcontracted?', 'Which sectors do you take? (offices / retail / restaurants and cafes / hotels / clinics / villas)'],
      vague: false } },

  // 10 ────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H10', slug: 'brands_and_distributorships', company: 'ZZ DEMO Gulf Horizon Technical Supplies LLC', signup_trade: 'hand_power_tools',
    licence: { key: 'jafza', licence_no: 'ZZ-150392', activities: ['Hand Tools Trading', 'Industrial Plant Equipment and Spare Parts Trading', 'Safety Equipment Trading'] },
    tagline: 'Authorised distributor - Stockist - Importer',
    body: `
<h2>About Gulf Horizon</h2><p>ZZ DEMO Gulf Horizon Technical Supplies LLC has supplied contractors, shipyards, factories and oil and gas service companies from its Jebel Ali warehouse since 2004.</p>
<h2>Our principals</h2><p>We are the authorised UAE distributor for:</p>${ul(['ZZ Kronwerk (Germany): cordless and corded power tools, rotary hammers, angle grinders', 'ZZ Tessaro (Italy): centrifugal and submersible pumps, booster sets', 'ZZ Northgard (Sweden): safety helmets, harnesses, lanyards and fall-arrest systems', 'ZZ Hanbit (Korea): welding machines, electrodes and MIG wire'])}
<h2>Brands we stock</h2><p>Makita, Bosch, DeWalt, Stanley, Hilti, Fischer, 3M, Honeywell, Karcher, Loctite, WD-40, Norton, Yale, Kito.</p>
<h2>Services</h2>${ul(['Tool repair and warranty service centre in Jebel Ali', 'Pump selection, commissioning and repair', 'Inspection and re-certification of harnesses', 'Same-day delivery in Dubai, next-day to Abu Dhabi'])}
<h2>Certifications</h2><p>ISO 9001:2015. Approved vendor of major contractors and shipyards.</p>`,
    key: {
      must_trades: ['hand_power_tools', 'industrial_pumps', 'safety_equipment', 'welding_equipment'], ok_trades: ['fasteners_fixings', 'abrasives_surface_finishing', 'chemicals', 'lubricants_industrial_oils', 'machinery_repair', 'material_handling', 'cleaning_chemicals', 'tool_equipment_rental', 'inspection_ndt', 'doors'],
      must_services: ['hand_power_tools.power_tools', 'industrial_pumps.centrifugal_pumps', 'industrial_pumps.submersible_sewage_pumps', 'industrial_pumps.booster_sets', 'safety_equipment.ppe', 'safety_equipment.fall_protection', 'welding_equipment.welding_machines', 'welding_equipment.electrodes_wires'],
      ok_services: ['hand_power_tools.hand_tools', 'hand_power_tools.cutting_drilling_accessories', 'industrial_pumps.pump_repair_rewinding', 'fasteners_fixings.anchors', 'abrasives_surface_finishing.grinding_cutting_discs', 'chemicals.adhesives_sealants', 'welding_equipment.machine_repair', 'machinery_repair.pump_compressor_overhaul', 'inspection_ndt.lifting_equipment_inspection'],
      partner: [], no_key: ['power tool repair & warranty service', 'harness inspection & re-certification', 'pressure washers (from the brand list)', 'chain hoists / lifting tackle (from the brand list)', 'the brands themselves: 4 distributorships + 14 stocked brands'],
      umbrella: { 'Brands we stock (names only)': ['power tools', 'hand tools', 'anchors & fixings', 'abrasives', 'PPE', 'adhesives & sealants', 'pressure washers', 'hoists'] },
      questions: ['Your stocked brands suggest you also sell these. Which do you keep? (hand tools / anchors and fixings / abrasives and cutting discs / adhesives and sealants / pressure washers / hoists and lifting tackle / locks)', 'Distributor or stockist: for which brands are you the authorised distributor? (shown: Kronwerk, Tessaro, Northgard, Hanbit)'],
      vague: false } },

  // 11 ────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H11', slug: 'licence_says_garments_profile_says_events', company: 'ZZ DEMO Silk Route Trading LLC', signup_trade: 'event_management',
    licence: { key: 'dubai_det', licence_no: 'ZZ-294418', activities: ['Readymade Garments Trading', 'Textile Trading'] },
    tagline: 'Events - Exhibitions - Brand activations',
    body: `
<h2>Who we are today</h2><p>ZZ DEMO Silk Route Trading LLC was founded in 2009 as a garments trader in Deira. Since 2019 our business has been events: we plan, build and run corporate events, exhibition stands and brand activations across the UAE.</p>
<h2>What we do</h2>${ul(['Corporate events, gala dinners and staff parties: planning and full management', 'Conferences and product launches', 'Exhibition stands: design, fabrication in our Al Quoz workshop, installation and dismantling', 'Mall kiosks and brand activations', 'Stage, truss, sound, lighting and LED screen rental', 'Event furniture rental', 'Hostesses, promoters and ushers', 'Event permits from DET and Dubai Police'])}
<h2>Recent events</h2>${ul(['Annual staff day for 1,200 employees, Dubai Parks (2025)', '9 x 12 m custom stand, Gulfood 2025, Dubai World Trade Centre', 'Mall roadshow in 6 malls for a telecom brand (2024)'])}`,
    key: {
      must_trades: ['event_management', 'exhibition_stands', 'event_equipment_rental'], ok_trades: ['marketing_advertising', 'event_entertainment', 'labour_supply', 'tents_shades'],
      must_services: ['event_management.corporate_events', 'event_management.conferences_seminars', 'event_management.product_launches', 'event_management.event_permits', 'event_management.event_staff_hostesses', 'exhibition_stands.custom_stands', 'exhibition_stands.kiosks_pop_ups', 'event_equipment_rental.led_screens', 'event_equipment_rental.sound_lighting', 'event_equipment_rental.staging_truss', 'event_equipment_rental.event_furniture'],
      ok_services: ['exhibition_stands.stand_graphics', 'marketing_advertising.campaign_management', 'exhibition_stands.modular_stands'],
      partner: [], no_key: ['brand activations / mall roadshows', 'gala dinners & staff parties'],
      must_not: ['apparel_fashion_wholesale', 'textiles_fabrics', 'uniforms_corporate_apparel'],
      licence_mismatch: true,
      umbrella: {}, questions: ['Your trade licence lists garments and textile trading, and your profile is about events. Do you still trade garments? (yes / no, events only)', 'Your licence does not list event activities. Do you have another licence or an added activity for events? (upload it / it is being added / no)'],
      vague: false } },

  // 12 ────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H12', slug: 'near_empty', company: 'ZZ DEMO Sahara Bright LLC', signup_trade: 'building_materials',
    licence: { key: 'dubai_det', licence_no: 'ZZ-701256', activities: ['General Trading'] },
    tagline: 'Company profile',
    body: `
<h2>Our vision</h2><p>To be the leading provider of quality solutions in the UAE and the region.</p>
<h2>Our mission</h2><p>Customer satisfaction through commitment, integrity and excellence. Your trusted partner for all your project needs.</p>
<h2>Our values</h2>${ul(['Quality', 'Trust', 'Teamwork'])}
<h2>Contact</h2><p>Dubai, United Arab Emirates.</p>`,
    key: {
      must_trades: [], ok_trades: [], must_services: [], ok_services: [], partner: [], no_key: [],
      must_be_empty: true,
      umbrella: {}, questions: ['Your profile does not say what your company does. What do you supply or do? (free text, or pick a trade)', 'Do you have a brochure, a catalogue or a past quotation we can read instead?'],
      vague: true } },

  // ── THREE NEW HARD PROFILES (12 Nov 2026, the build of branch sales_engineer-a-profile-is-read-first-and-mapped-second). Written,
  // with their answer keys, BEFORE the reader's prompts were tuned and before any reading of them: they were never seen by the tuning.
  // 13 ────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H13', slug: 'villa_contractor_prose_mep_subcontracted', company: 'ZZ DEMO Al Sabr Building Contracting LLC', signup_trade: 'general_contracting',
    licence: { key: 'dubai_det', licence_no: 'ZZ-482260', activities: ['Building Contracting', 'Swimming Pools Contracting'] },
    tagline: 'Homes built to last',
    body: `
<h2>About us</h2><p>ZZ DEMO Al Sabr has built private homes in Dubai and Sharjah since 2009. We build private villas from the foundation to the handover of the keys, and we add extensions, majlis annexes and new rooms to existing homes.</p>
<p>Our own crews carry out the concrete works and blockwork, plastering, floor and wall tiling, and the interior and exterior painting. Roof waterproofing is applied by our own team before every handover.</p>
<p>Electrical, plumbing and air-conditioning works are carried out by our approved MEP subcontractor, ZZ DEMO Volt Line Electromechanical, under our single contract with you.</p>
<p>Around the villa we lay interlock paving for driveways and walkways, and we build boundary walls and gates.</p>
<h2>Recent projects</h2>${ul(['G+1 villa, 5 bedrooms, Al Barsha South (2025)', 'Majlis annex and two rooms, Al Warqa (2025)', 'Twin villas, Al Rahmaniya, Sharjah (2024)'])}`,
    key: {
      must_trades: ['general_contracting'], ok_trades: ['civil_works', 'masonry_blockwork', 'flooring', 'painting', 'waterproofing', 'road_works', 'steel'],
      must_services: ['general_contracting.villa_construction', 'general_contracting.extensions_annexes', 'civil_works.concrete', 'masonry_blockwork.plastering', 'flooring.tiling', 'painting.interior', 'painting.exterior', 'waterproofing.roof', 'road_works.interlock_paving'],
      ok_services: ['civil_works.blockwork', 'masonry_blockwork.blockwork', 'civil_works.new_construction', 'general_contracting.building_construction', 'steel.gates_fencing', 'general_contracting.design_and_build'],
      partner: ['mep_general.mep_install', 'electrical.wiring_install', 'plumbing.water_supply', 'plumbing.drainage', 'plumbing.sanitary_fixtures', 'hvac.supply_install'],
      no_key: ['boundary walls'],
      umbrella: {},
      must_not: ['swimming_pools.pool_construction'],
      questions: ['Electrical, plumbing and air-conditioning: do you deliver these through your MEP subcontractor, or with your own team?', 'Do you also build commercial buildings, or homes only?', 'Your licence lists swimming pools: do you build pools? (the profile does not say so)'],
      vague: false } },

  // 14 ────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H14', slug: 'cleaning_chemicals_trader_services_by_sister', company: 'ZZ DEMO Crystal Hygiene Trading LLC', signup_trade: 'cleaning_chemicals',
    licence: { key: 'sharjah_sedd', licence_no: 'ZZ-337019', activities: ['Detergents and Cleaning Materials Trading', 'Janitorial Equipment Trading'] },
    tagline: 'Cleaning supplies for every building',
    body: `
<h2>Who we are</h2><p>ZZ DEMO Crystal Hygiene Trading supplies cleaning chemicals and janitorial products to hotels, hospitals, schools and facility management companies across the UAE, from our warehouse in Sharjah.</p>
<h2>Our products</h2>${ul(['Floor and surface cleaners, degreasers and glass cleaners', 'Disinfectants and hand sanitisers', 'Mops, buckets and janitorial trolleys', 'Garbage bags and waste bins', 'Floor scrubbers and vacuum cleaners'])}
<p>We also offer complete hygiene solutions and much more for your premises.</p>
<h2>Services</h2><p>Professional deep cleaning and pest control are provided by our sister company, ZZ DEMO Crystal Facility Services LLC.</p>
<h2>Why us</h2>${ul(['Free delivery in Sharjah, Dubai and Ajman', 'Monthly credit for approved customers', 'Product training for your cleaning staff'])}`,
    key: {
      must_trades: ['cleaning_chemicals'], ok_trades: ['chemicals'],
      must_services: ['cleaning_chemicals.floor_surface_cleaners', 'cleaning_chemicals.disinfectants_sanitisers', 'cleaning_chemicals.janitorial_trolleys_mops', 'cleaning_chemicals.waste_bins_liners', 'cleaning_chemicals.floor_cleaning_machines'],
      ok_services: [],
      partner: ['cleaning.deep_cleaning', 'pest_control.general_pest_control', 'cleaning.pest_control'],
      no_key: ['washroom paper products (tissue, hand towels)', 'air fresheners and dispensers'],
      umbrella: { 'complete hygiene solutions and much more': ['washroom paper products', 'soap and dispensers', 'air fresheners', 'hand dryers', 'laundry chemicals', 'kitchen chemicals'] },
      must_not: ['cleaning.deep_cleaning as his own', 'logistics_moving.site_delivery'],
      questions: ['"Complete hygiene solutions": which other products do you supply? (washroom paper / soap and dispensers / air fresheners / hand dryers / laundry chemicals / kitchen chemicals)', 'Deep cleaning and pest control: are these quoted by you, or by your sister company directly?'],
      vague: true } },

  // 15 ────────────────────────────────────────────────────────────────────────────────────────────
  { id: 'H15', slug: 'transport_heavy_equipment_logistics_solutions', company: 'ZZ DEMO Rakhaa Transport and Heavy Equipment Rental LLC', signup_trade: 'heavy_equipment',
    licence: { key: 'sharjah_sedd', licence_no: 'ZZ-905514', activities: ['Heavy Equipment Rental', 'Goods Land Transport', 'Passenger Transport by Buses'] },
    tagline: 'Moving your projects',
    body: `
<h2>Company overview</h2><p>ZZ DEMO Rakhaa Transport and Heavy Equipment Rental has served contractors in Sharjah, Dubai and the Northern Emirates since 2011 with a fleet of more than 120 units.</p>
<p>We rent mobile cranes from 25 to 100 tons with operator, and excavators, wheel loaders and forklifts on daily and monthly hire. Our flatbed trailers and tippers move steel, blocks and site materials to your project, and our 60-seater labour buses carry your workers on monthly contracts.</p>
<p>We also provide complete logistics solutions.</p>
<h2>Our fleet</h2>${ul(['Mobile cranes 25 t to 100 t', 'Excavators and wheel loaders', 'Forklifts 3 t to 10 t', 'Flatbed trailers and tippers', '60-seater buses'])}
<h2>Safety</h2><p>All operators hold valid third-party certificates. Our fleet is inspected every month.</p>`,
    key: {
      must_trades: ['heavy_equipment', 'staff_transport', 'logistics_moving'], ok_trades: ['material_handling', 'vehicle_leasing'],
      must_services: ['heavy_equipment.crane_hire', 'heavy_equipment.equipment_rental', 'heavy_equipment.with_operator', 'material_handling.forklifts_sale_rent', 'logistics_moving.site_delivery', 'staff_transport.labour_transport'],
      ok_services: ['heavy_equipment.earthmoving', 'staff_transport.bus_hire', 'vehicle_leasing.bus_van_hire_with_driver'],
      partner: [],
      no_key: ['trucks with driver (flatbed trailers, tippers)'],
      umbrella: { 'complete logistics solutions': ['storage and warehousing', 'freight forwarding', 'customs clearance', 'office and home moving', 'trucks with driver'] },
      questions: ['"Complete logistics solutions": which of these do you provide? (storage and warehousing / freight forwarding / customs clearance / moving / trucks with driver)'],
      vague: true } },
];

// THE GLOSSY PROFILE (H09): 30 pages. No "Our services" list anywhere; what the company does is in the project captions.
export const GLOSSY = {
  front: [
    ['Chairman\'s message', 'Two decades ago we began with a small team and a simple belief: that every space tells a story. Today that belief still guides every decision we take. I thank our clients, our partners and above all our people for their trust. Together we look to the future with confidence and ambition.'],
    ['Our story', 'ZZ DEMO Meridian Interiors LLC was founded in Dubai in 2004. From a team of twelve we have grown to more than 400 people, a 2,400 m2 joinery factory in Dubai Investments Park and a portfolio of more than 600 completed projects across the Emirates.'],
    ['Vision, mission, values', 'Vision: to be the most trusted name in the region for spaces that inspire. Mission: to deliver on time, on budget and beyond expectation. Values: integrity, craftsmanship, safety, respect, innovation.'],
    ['Health, safety and environment', 'The safety of our people comes first. We work to an integrated management system, hold toolbox talks every morning and have recorded two million man-hours without a lost-time incident.'],
    ['Quality policy', 'We are committed to continual improvement. Our management system is certified to ISO 9001:2015, ISO 14001:2015 and ISO 45001:2018.'],
    ['Our people', 'Board of directors. Managing director. Projects director. Commercial manager. Design manager. Factory manager. HSE manager. 14 project managers, 22 site engineers, 31 foremen, 280 craftsmen.'],
    ['Our factory', 'CNC routers, edge banders, a spray booth and a polishing line. Capacity: 180 doors or 60 wardrobes a week.'],
    ['Our clients', 'Hotel operators, retail brands, banks, law firms, developers, clinics and private villa owners.'],
  ],
  projects: [
    ['The Harbour Club restaurant, Dubai Marina', '2025', 'Turnkey fit-out of a 640 m2 restaurant: joinery bar counter, banquette seating, marble flooring, feature ceiling, kitchen wall cladding.'],
    ['Law firm headquarters, DIFC Gate Village', '2025', 'Office fit-out, two floors, 2,100 m2: glass partitions, acoustic ceilings, carpet tiles, veneered wall panelling, reception counter, boardroom table.'],
    ['Flagship fashion store, Mall of the Emirates', '2025', 'Retail fit-out in 45 days: shopfront, display fixtures, gypsum ceilings, stone flooring, fitting rooms.'],
    ['Boutique hotel, 84 keys, Jumeirah', '2024', 'Refurbishment of guestrooms and corridors: wardrobes, headboards, vanity units, wooden doors, wallcovering, carpets.'],
    ['Private villa, Emirates Hills', '2024', 'Interior works to a 7-bedroom villa: walk-in wardrobes, kitchen, wood panelling, marble staircase, decorative painting.'],
    ['Dental clinic, Jumeirah Lakes Towers', '2024', 'Clinic fit-out, 380 m2: partitions, vinyl flooring, cabinetry, reception desk, DHA approvals.'],
    ['Bank branch roll-out, 6 branches', '2024', 'Fit-out and rebranding of six branches in Dubai and Sharjah: teller counters, partitions, ceilings, flooring, signage installation.'],
    ['Specialty coffee chain, 11 outlets', '2023-2025', 'Design and build of cafe interiors: counters, banquettes, wall cladding, lighting, MEP modifications.'],
    ['Co-working space, Dubai Design District', '2023', 'Office fit-out, 3,000 m2: phone booths, joinery lockers, raised flooring, glazed meeting rooms.'],
    ['Show apartments for a developer, Dubai Hills', '2023', 'Three show apartments, fully fitted and furnished in 30 days: kitchens, wardrobes, loose furniture, curtains.'],
    ['Fine-dining restaurant, Downtown Dubai', '2023', 'Turnkey fit-out: timber ceiling, brass screens, marble bar, banquette upholstery.'],
    ['Jewellery boutique, Gold Souk Extension', '2023', 'Retail fit-out: showcases, safes room joinery, feature ceiling, stone flooring.'],
    ['Corporate office, Abu Dhabi Global Market', '2022', 'Office fit-out, 1,400 m2: partitions, ceilings, carpets, joinery, AV-ready boardrooms.'],
    ['Paediatric clinic, Al Wasl Road', '2022', 'Clinic fit-out: curved joinery reception, vinyl flooring, wall protection, themed ceilings.'],
    ['Hotel lobby and all-day dining, Deira', '2022', 'Refurbishment during operation: marble flooring, timber wall panelling, feature lighting, buffet counters.'],
    ['Penthouse, Palm Jumeirah', '2022', 'Interior works: kitchen, wardrobes, wooden doors, parquet flooring, home cinema joinery.'],
    ['University library, Sharjah', '2021', 'Joinery package: 1,200 linear metres of shelving, study carrels, reading tables, acoustic wall panels.'],
    ['Perfume retail chain, 9 kiosks', '2021', 'Design, manufacture and installation of mall kiosks.'],
  ],
  back: [
    ['Awards', 'Commercial Interior Design Awards: Fit-out Firm of the Year, shortlisted 2023 and 2024. Best Restaurant Interior, 2025.'],
    ['Sustainability and community', 'FSC-certified timber on request. Low-VOC lacquers. We sponsor a vocational carpentry course and an annual beach clean-up.'],
    ['Testimonials', '"Meridian handed over our store four days early." - Regional projects manager, fashion retailer. "The joinery quality is the best we have seen in Dubai." - Hotel general manager.'],
    ['Contact', 'Dubai Investments Park, Dubai, United Arab Emirates. Contact details are shared through QuotesDone.'],
  ],
};
