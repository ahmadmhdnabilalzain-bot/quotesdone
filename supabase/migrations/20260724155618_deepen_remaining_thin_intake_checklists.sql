-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724155618   name: deepen_remaining_thin_intake_checklists
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Deepen the 10 thin intake checklists. Required counts kept proportional (3-4):
-- ask only what a customer genuinely needs to compare, never an interrogation.

update category_specs set fields = $j$[
 {"key":"use","type":"select","required":true,"question":"What is the space mainly used for?","options":["Conference / meeting room","Auditorium / hall","Retail / digital signage","Home cinema / residential","Multiple"]},
 {"key":"rooms","type":"text","required":true,"question":"How many rooms/zones need AV, and their size or seating capacity?","options":[]},
 {"key":"display","type":"select","required":false,"question":"Display need?","options":["LED video wall","LCD video wall","Single large display","Projector + screen","Not sure"]},
 {"key":"audio_pa","type":"select","required":true,"question":"Audio / PA requirement?","options":["Integrated audio + PA","Voice evacuation tie-in","Basic speakers","None"]},
 {"key":"video_conf","type":"select","required":false,"question":"Video conferencing support?","options":["Microsoft Teams","Zoom","Both","None"]},
 {"key":"control","type":"select","required":false,"question":"Centralized control (single touch panel)?","options":["Yes","No","Not sure"]},
 {"key":"location","type":"text","required":true,"question":"Property type and emirate/area?","options":[]}
]$j$::jsonb, label='AV Systems' where category='av-systems';

update category_specs set fields = $j$[
 {"key":"type","type":"select","required":true,"question":"What do you need?","options":["Roller blinds","Blackout curtains","Sheer curtains","Roman blinds","Venetian blinds","Motorized blinds/curtains"]},
 {"key":"windows","type":"text","required":true,"question":"How many windows, and their sizes (W x H) if known?","options":[]},
 {"key":"operation","type":"select","required":false,"question":"Operation?","options":["Manual","Motorized / remote","Not sure"]},
 {"key":"fabric","type":"select","required":false,"question":"Fabric / light preference?","options":["Blackout","Dim-out","Sheer","No preference"]},
 {"key":"measurement","type":"select","required":false,"question":"Measurements?","options":["I have exact sizes","Need site measurement"]},
 {"key":"scope","type":"select","required":true,"question":"Scope?","options":["Supply and install","Supply only"]},
 {"key":"location","type":"text","required":true,"question":"Property type and emirate/area?","options":[]}
]$j$::jsonb, label='Curtains & Blinds' where category='blinds-curtains';

update category_specs set fields = $j$[
 {"key":"type","type":"select","required":true,"question":"Carpet tiles or broadloom (roll)?","options":["Carpet tiles","Broadloom roll","Not sure"]},
 {"key":"area","type":"text","required":true,"question":"Total area in sqm?","options":[]},
 {"key":"usage","type":"select","required":true,"question":"Usage / traffic level?","options":["Residential","Office","Heavy commercial","Hospitality"]},
 {"key":"fibre","type":"select","required":false,"question":"Fibre preference?","options":["Nylon","Polypropylene","Wool","No preference"]},
 {"key":"scope","type":"select","required":true,"question":"Scope?","options":["Supply and install","Supply only"]},
 {"key":"subfloor","type":"select","required":false,"question":"Subfloor?","options":["Tiles","Concrete","Raised floor","Needs leveling"]},
 {"key":"location","type":"text","required":false,"question":"Emirate/area?","options":[]}
]$j$::jsonb, label='Carpets' where category='carpets';

update category_specs set fields = $j$[
 {"key":"type","type":"select","required":true,"question":"Type of demolition?","options":["Full structure","Partial / structural","Soft strip-out (interior only)"]},
 {"key":"property","type":"select","required":true,"question":"Property type?","options":["Villa","Commercial unit","Warehouse / industrial","Building"]},
 {"key":"area","type":"text","required":true,"question":"Approximate area (sqft/sqm) and number of floors?","options":[]},
 {"key":"disposal","type":"select","required":true,"question":"Is debris removal & disposal included?","options":["Yes, include disposal","We will handle disposal","Not sure"]},
 {"key":"utilities","type":"select","required":false,"question":"Utility disconnections done (DEWA etc.)?","options":["Yes, disconnected","Need arranging","Unsure"]},
 {"key":"permit","type":"select","required":false,"question":"Who obtains the demolition permit?","options":["Contractor","Us","Not sure"]},
 {"key":"timeline","type":"select","required":false,"question":"Start date?","options":["Immediate","Within a month","Flexible"]}
]$j$::jsonb, label='Demolition' where category='demolition';

update category_specs set fields = $j$[
 {"key":"type","type":"select","required":true,"question":"Lift type?","options":["Passenger","Home lift","Freight / goods","Hospital","Panoramic / glass"]},
 {"key":"stops","type":"text","required":true,"question":"Number of floors / stops served?","options":[]},
 {"key":"capacity","type":"select","required":true,"question":"Required capacity?","options":["Up to 630 kg","630-1000 kg","1000 kg+","Not sure"]},
 {"key":"new_mod","type":"select","required":true,"question":"New building or modernization/replacement?","options":["New installation","Modernization / replacement"]},
 {"key":"mrl","type":"select","required":false,"question":"Machine-room or machine-room-less?","options":["MRL (no machine room)","With machine room","No preference"]},
 {"key":"brand","type":"select","required":false,"question":"Brand tier?","options":["Premium (Otis/KONE/Schindler)","Mid-range","No preference"]},
 {"key":"amc","type":"select","required":false,"question":"Annual maintenance contract?","options":["Yes","No","Not sure"]}
]$j$::jsonb, label='Elevators & Lifts' where category='elevators';

update category_specs set fields = $j$[
 {"key":"height","type":"select","required":true,"question":"Building height / number of floors?","options":["Low-rise (up to G+4)","Mid-rise","High-rise"]},
 {"key":"facade_type","type":"select","required":true,"question":"Facade type?","options":["Glass curtain wall","Cladding (ACP/stone)","Painted concrete","Mixed"]},
 {"key":"access","type":"select","required":false,"question":"Preferred access method?","options":["Rope access (IRATA)","BMU / cradle","No preference"]},
 {"key":"bmu","type":"select","required":true,"question":"Is a Building Maintenance Unit (BMU) already installed?","options":["Yes","No","Unknown"]},
 {"key":"frequency","type":"select","required":true,"question":"Frequency?","options":["One-time","Quarterly","Annual contract"]},
 {"key":"area","type":"text","required":false,"question":"Approximate facade area or dimensions (if known)?","options":[]},
 {"key":"location","type":"text","required":false,"question":"Emirate/area?","options":[]}
]$j$::jsonb, label='Facade / High-Rise Cleaning' where category='facade-cleaning';

update category_specs set fields = $j$[
 {"key":"type","type":"select","required":true,"question":"What do you need?","options":["Rolling shutter","Sectional garage door","Grille shutter","Fire-rated shutter"]},
 {"key":"dimensions","type":"text","required":true,"question":"Opening dimensions (width x height)?","options":[]},
 {"key":"operation","type":"select","required":true,"question":"Operation?","options":["Motorized + remote","Motorized","Manual"]},
 {"key":"material","type":"select","required":true,"question":"Material / finish?","options":["Galvanized steel","Aluminium","Stainless steel","Not sure"]},
 {"key":"units","type":"select","required":false,"question":"How many units?","options":["1","2-5","More than 5"]},
 {"key":"scope","type":"select","required":false,"question":"Scope?","options":["Supply and install","Supply only"]},
 {"key":"location","type":"text","required":false,"question":"Property type and emirate/area?","options":[]}
]$j$::jsonb, label='Garage Doors & Shutters' where category='garage-doors';

update category_specs set fields = $j$[
 {"key":"application","type":"select","required":true,"question":"Application?","options":["Standby / backup power","Prime / continuous","Temporary site power"]},
 {"key":"rating","type":"select","required":true,"question":"Required power rating (kVA)?","options":["Up to 100 kVA","100-500 kVA","500 kVA+","Not sure - advise"]},
 {"key":"enclosure","type":"select","required":true,"question":"Enclosure type?","options":["Soundproof canopy","Open type","Containerized"]},
 {"key":"ats","type":"select","required":true,"question":"Automatic mains failure (AMF/ATS) panel?","options":["Yes","No","Not sure"]},
 {"key":"fuel","type":"select","required":false,"question":"Fuel autonomy / runtime?","options":["8 hours","24 hours","Extended","Not sure"]},
 {"key":"scope","type":"select","required":false,"question":"Scope?","options":["Supply only","Supply and install","Full incl. commissioning + AMC"]},
 {"key":"location","type":"text","required":false,"question":"Property type and emirate/area?","options":[]}
]$j$::jsonb, label='Generators' where category='generators';

update category_specs set fields = $j$[
 {"key":"location","type":"select","required":true,"question":"Where is insulation being applied?","options":["External walls","Roof","HVAC ducts","Multiple areas"]},
 {"key":"area","type":"text","required":true,"question":"Approximate area to insulate (m²)?","options":[]},
 {"key":"target","type":"select","required":true,"question":"Target U-value or thickness?","options":["I have a specified value","Municipality minimum","Not sure - advise"]},
 {"key":"material","type":"select","required":false,"question":"Preferred material?","options":["XPS / EPS board","Polyurethane spray / PIR","Mineral / rockwool","No preference"]},
 {"key":"fire","type":"select","required":false,"question":"Fire-rated / non-combustible required?","options":["Yes","Standard","To be advised"]},
 {"key":"new_retro","type":"select","required":false,"question":"New build or retrofit?","options":["New construction","Retrofit / existing"]},
 {"key":"location_area","type":"text","required":false,"question":"Building type and emirate/area?","options":[]}
]$j$::jsonb, label='Thermal Insulation' where category='insulation';

update category_specs set fields = $j$[
 {"key":"tank_type","type":"select","required":true,"question":"Tank type?","options":["Overhead","Underground","Both"]},
 {"key":"capacity","type":"text","required":true,"question":"Tank capacity (gallons/litres) or number of tanks?","options":[]},
 {"key":"property","type":"select","required":true,"question":"Property type?","options":["Villa","Building","Commercial"]},
 {"key":"certificate","type":"select","required":true,"question":"Do you require a Dubai Municipality-approved cleaning certificate?","options":["Yes","No"]},
 {"key":"water_test","type":"select","required":false,"question":"Do you need a water quality lab test?","options":["Yes","No","Not sure"]},
 {"key":"frequency","type":"select","required":false,"question":"Frequency?","options":["One-time","6-monthly","Annual contract"]},
 {"key":"location","type":"text","required":false,"question":"Emirate/area?","options":[]}
]$j$::jsonb, label='Water Tank Cleaning' where category='water-tank-cleaning';

select category, jsonb_array_length(fields) n_fields,
 (select count(*) from jsonb_array_elements(fields) f where (f->>'required')::boolean) req
from category_specs where category in ('av-systems','blinds-curtains','carpets','demolition','elevators','facade-cleaning','garage-doors','generators','insulation','water-tank-cleaning') order by category;
