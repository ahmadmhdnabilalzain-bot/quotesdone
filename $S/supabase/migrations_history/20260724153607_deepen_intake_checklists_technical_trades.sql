-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724153607   name: deepen_intake_checklists_technical_trades
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Deepen intake (category_specs.fields) for the technical trades so the RFQ captures
-- everything a supplier needs to quote firm. Research-grounded (SIRA/DCD/ESMA/DM/DEWA) 2026.

update public.category_specs set fields = $j$[
 {"key":"system","type":"multiselect","required":true,"question":"Which system(s) do you need?","options":["CCTV cameras","Access control (doors)","Video intercom","Alarm system","Integrated (CCTV+access+alarm)"]},
 {"key":"num_cameras","type":"text","required":true,"question":"How many cameras in total, and roughly how are they split (entrances/exits, cash or counter areas, general interior, parking/perimeter)?","options":[]},
 {"key":"indoor_outdoor","type":"text","required":true,"question":"How many cameras are outdoor/weather-exposed vs indoor?","options":[]},
 {"key":"coverage_intent","type":"select","required":false,"question":"What must the cameras achieve in key areas?","options":["Detect only (general view)","Recognise people","Identify faces / license plates (needs higher resolution)"]},
 {"key":"retention","type":"select","required":true,"question":"How many days of recording do you need kept?","options":["31 days (SIRA standard for most businesses)","90 days (banks, jewellers, gold traders, high-security)","Other / not sure"]},
 {"key":"access_control","type":"select","required":false,"question":"Access control scope?","options":["None","Keypad only","Card/fob readers (state number of doors)","Biometric/face (state number of doors)"]},
 {"key":"intercom","type":"select","required":false,"question":"Video/audio intercom?","options":["None","Audio only","Video (state number of outdoor stations + indoor monitors)"]},
 {"key":"network_power","type":"select","required":false,"question":"Network & power?","options":["Supplier to provide PoE switch + cabling","Use existing network","Need full cabling run"]},
 {"key":"property_location","type":"text","required":true,"question":"Property type, emirate/area, and floor level?","options":[]},
 {"key":"scope","type":"select","required":true,"question":"What scope do you need?","options":["Supply and install","Supply only","Install only"]}
]$j$::jsonb, label='CCTV & Security Systems' where category='security';

update public.category_specs set fields = $j$[
 {"key":"system_type","type":"select","required":true,"question":"What type of AC system?","options":["Wall/floor split","Ducted (concealed) split","Cassette","VRF/VRV","Chiller (air/water-cooled)","Package unit","FAHU/AHU (fresh air)","Not sure - need site survey"]},
 {"key":"application_area","type":"text","required":true,"question":"What is the space used for (office, villa, retail, restaurant, server room, warehouse), and roughly what area in m² and ceiling height?","options":[]},
 {"key":"new_or_replace","type":"select","required":true,"question":"Is this new, replacement, or a service/repair?","options":["New installation","Replacement of existing","Extension of existing","Service / repair / maintenance"]},
 {"key":"load_basis","type":"select","required":false,"question":"Do you have a cooling-load calculation or MEP drawings?","options":["Yes, I have heat-load calc / MEP drawings","No - supplier to size it"]},
 {"key":"brand_tier","type":"select","required":false,"question":"Preferred brand tier / efficiency?","options":["Premium (Daikin/Mitsubishi/Trane/Carrier)","Mid (LG/Gree/O-General)","Economy","Best value - recommend"]},
 {"key":"electrical_supply","type":"select","required":false,"question":"Electrical supply available?","options":["Single-phase 230V","Three-phase 400V","Not sure"]},
 {"key":"scope","type":"select","required":true,"question":"Scope?","options":["Supply only","Supply and install","Turnkey (incl. ducting, MEP drawings, testing & commissioning)"]},
 {"key":"amc","type":"select","required":false,"question":"Include an annual maintenance contract (AMC)?","options":["Yes, include AMC","No","Not sure"]},
 {"key":"location","type":"text","required":true,"question":"Which emirate/area, floor level, and condenser location (roof/wall/ground)?","options":[]},
 {"key":"timeline","type":"select","required":false,"question":"When do you need it done?","options":["Within 2 weeks","2-4 weeks","1-2 months","Flexible"]}
]$j$::jsonb, label='HVAC / Air Conditioning' where category='hvac';

update public.category_specs set fields = $j$[
 {"key":"element","type":"multiselect","required":true,"question":"What glass/aluminium element(s)?","options":["Curtain wall / facade","Shopfront / entrance","Windows","Internal glass partition","Balustrade / railing","Skylight / canopy","Glass doors (frameless/framed)"]},
 {"key":"dimensions_qty","type":"text","required":true,"question":"Opening sizes (W x H mm) per unit, quantity, and total m². Which floor level / building height?","options":[]},
 {"key":"glazing_performance","type":"select","required":true,"question":"Glass type / performance?","options":["Single glazed","Double / insulated (IGU)","Laminated (safety)","Tempered (toughened)","Low-E / solar-control","Not sure - recommend"]},
 {"key":"aluminium_system","type":"select","required":false,"question":"Aluminium system preference?","options":["Technal","Schuco","Gulf Extrusions","Alupco","Supplier to recommend","Not applicable (frameless)"]},
 {"key":"finish","type":"select","required":false,"question":"Finish?","options":["Powder-coated (state RAL colour)","Anodized","PVDF","Not sure"]},
 {"key":"safety_context","type":"select","required":false,"question":"Where is the glass located?","options":["Near a door / low level","Balustrade or barrier (needs load design)","Wet area (shower/bathroom)","Overhead / skylight","Standard vertical glazing"]},
 {"key":"scope","type":"select","required":true,"question":"Scope?","options":["Supply and install (incl. sealing)","Supply only"]},
 {"key":"location","type":"text","required":true,"question":"Property type, emirate/area, and access (scaffold/crane needed)?","options":[]},
 {"key":"timeline","type":"select","required":false,"question":"Timeline?","options":["Within 2 weeks","2-4 weeks","1-2 months","Flexible"]}
]$j$::jsonb, label='Glass & Glazing' where category='glass';

update public.category_specs set fields = $j$[
 {"key":"element","type":"multiselect","required":true,"question":"What aluminium work?","options":["Windows (sliding/casement)","Doors","Kitchen / wardrobe shutters","Cladding / composite panel (ACP)","Handrails / railing","Pergola / shade","Partitions"]},
 {"key":"dimensions_qty","type":"text","required":true,"question":"Sizes (W x H mm) per unit and quantity (or total m²)?","options":[]},
 {"key":"system_finish","type":"select","required":false,"question":"System & finish preference?","options":["Powder-coated (RAL)","Anodized","Thermal-break system","Supplier to recommend"]},
 {"key":"glazing","type":"select","required":false,"question":"Glass infill (if any)?","options":["Single glazed","Double glazed","Tinted / reflective","Frosted","No glass"]},
 {"key":"scope","type":"select","required":true,"question":"Scope?","options":["Supply and install","Supply only"]},
 {"key":"location","type":"text","required":true,"question":"Property type, emirate/area, floor, access?","options":[]},
 {"key":"timeline","type":"select","required":false,"question":"Timeline?","options":["Within 2 weeks","2-4 weeks","1-2 months","Flexible"]}
]$j$::jsonb, label='Aluminium Works' where category='aluminium';

update public.category_specs set fields = $j$[
 {"key":"scope","type":"multiselect","required":true,"question":"What electrical work?","options":["New wiring (first fix)","Rewiring","DB board supply & install","Lighting","Power sockets","Data & TV points","AC power points","DEWA new connection","DEWA load upgrade","Testing & certification only"]},
 {"key":"property_area","type":"text","required":true,"question":"Property type, built-up area (m²) and number of rooms/zones?","options":[]},
 {"key":"supply_phase","type":"select","required":true,"question":"Supply type?","options":["Single-phase","Three-phase","Not sure","Utility supply not yet available"]},
 {"key":"point_counts","type":"text","required":false,"question":"Roughly how many light points, power sockets, and high-load points (cooker/water heater/AC)?","options":[]},
 {"key":"load_additions","type":"text","required":false,"question":"Any major loads to add (central/split AC tonnage, water heaters kW, cooker, EV charger)?","options":[]},
 {"key":"dewa_works","type":"select","required":false,"question":"DEWA/utility works needed?","options":["New connection","Load increase","Meter relocation","None"]},
 {"key":"concealment","type":"select","required":false,"question":"Concealed or surface?","options":["Concealed (chased/conduit)","Surface trunking","Mixed"]},
 {"key":"certification","type":"select","required":false,"question":"Is a DEWA connection / inspection certificate required?","options":["Yes","No","Not sure"]},
 {"key":"location","type":"text","required":true,"question":"Which emirate/area?","options":[]},
 {"key":"timeline","type":"select","required":false,"question":"Timeline?","options":["Within 2 weeks","2-4 weeks","1-2 months","Flexible"]}
]$j$::jsonb, label='Electrical' where category='electrical';

update public.category_specs set fields = $j$[
 {"key":"scope","type":"multiselect","required":true,"question":"What plumbing work?","options":["Water supply piping","Drainage & waste","Sanitary fixture supply & install","Water tank","Water heater","Booster/pressure pump","Testing & connection only"]},
 {"key":"fixture_count","type":"text","required":true,"question":"How many bathrooms/WCs and kitchens, and total fixtures (WCs, basins, showers, baths, sinks)?","options":[]},
 {"key":"water_source","type":"select","required":false,"question":"Water source / connection?","options":["Mains available","Tank-fed (roof/ground)","New connection needed","Not sure"]},
 {"key":"hot_water","type":"select","required":false,"question":"Hot water system?","options":["Central","Individual electric heaters","Instant","Solar","Not sure"]},
 {"key":"fixtures_grade","type":"select","required":false,"question":"Fixtures supplied by whom, and grade?","options":["Premium (Grohe/Duravit/TOTO)","Mid (RAK/Geberit/American Standard)","Economy","Buyer will supply fixtures"]},
 {"key":"booster","type":"select","required":false,"question":"Is a booster/pressure pump needed?","options":["Yes","No","Not sure"]},
 {"key":"tank","type":"select","required":false,"question":"Water tank?","options":["New tank required (state capacity)","Reuse existing","None"]},
 {"key":"scope_mode","type":"select","required":true,"question":"Scope?","options":["Supply and install","Supply only","Install only"]},
 {"key":"location","type":"text","required":true,"question":"Property type and emirate/area?","options":[]},
 {"key":"timeline","type":"select","required":false,"question":"Timeline?","options":["Within 2 weeks","2-4 weeks","1-2 months","Flexible"]}
]$j$::jsonb, label='Plumbing & Sanitary' where category='plumbing';

update public.category_specs set fields = $j$[
 {"key":"occupancy","type":"select","required":true,"question":"Building occupancy type?","options":["Office / business","Retail / mercantile","Assembly (venue/mosque/hall)","Warehouse / storage","Industrial","Residential","Hospitality (hotel/restaurant)"]},
 {"key":"building","type":"text","required":true,"question":"Total built-up area (m²), number of floors/basements, building height, and approximate occupant count?","options":[]},
 {"key":"scope","type":"multiselect","required":true,"question":"What fire systems do you need?","options":["Fire alarm / detection","Sprinkler system","Fire pump set","Wet/dry risers & hydrants","Fire extinguishers","Kitchen suppression","Clean-agent (server/electrical room)","Emergency lighting & exit signage"]},
 {"key":"project_stage","type":"select","required":false,"question":"Project stage & approvals?","options":["New build","Fit-out","Retrofit / upgrade","DCD drawing approval already obtained","DCD approval needed as part of scope"]},
 {"key":"special_hazards","type":"multiselect","required":false,"question":"Any special hazard areas?","options":["Commercial kitchen","Server / UPS / switchgear room","Chemical / flammable storage","High-rack storage","None"]},
 {"key":"hassantuk","type":"select","required":false,"question":"Hassantuk (DCD smart monitoring) connection required? (Mandatory for Dubai commercial premises)","options":["Yes","Not sure"]},
 {"key":"amc","type":"select","required":false,"question":"Include an Annual Maintenance Contract? (DCD requires AMC before final inspection)","options":["Yes, include AMC","No","Not sure"]},
 {"key":"location","type":"text","required":true,"question":"Property type and emirate/area?","options":[]},
 {"key":"timeline","type":"select","required":false,"question":"Timeline?","options":["Urgent","Within 1 month","1-3 months","Flexible"]}
]$j$::jsonb, label='Fire Safety & Fire Fighting' where category='safety';

select category, jsonb_array_length(fields) n_fields,
 (select count(*) from jsonb_array_elements(fields) f where (f->>'required')::boolean) required
from public.category_specs where category in ('security','hvac','glass','aluminium','electrical','plumbing','safety') order by category;
