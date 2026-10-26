-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724154839   name: universal_category_quote_gate_all_trades
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================================
-- UNIVERSAL category-aware quote gate (2026-07-24): extend from 7 trades to ALL.
-- Research-grounded (UAE: DM, DCD, DEWA, SIRA, ESMA, Al Safat, Shams Dubai, IRATA).
-- ============================================================================

-- Rewrite the mapper: ordered most-specific-first so e.g. ac-duct-cleaning->acduct
-- (not hvac), facade-cleaning->facade (not cleaning), water-tank-cleaning->watertank.
create or replace function public.fn_quote_spec_group(p_category text)
returns text language sql immutable as $fn$
  select case
    when p_category ~* 'duct.?clean|ac.?duct' then 'acduct'
    when p_category ~* 'facade.?clean|facade cleaning' then 'facade'
    when p_category ~* 'water.?tank' then 'watertank'
    when p_category ~* 'cctv|surveillance|security|access.?control|intercom|alarm' then 'security'
    when p_category ~* 'fire|safety|sprinkler|extinguisher|civil.?defen' then 'fire'
    when p_category ~* 'scaffold' then 'scaffolding'
    when p_category ~* 'demolition|strip.?out' then 'demolition'
    when p_category ~* 'garage.?door|shutter|rolling' then 'shutters'
    when p_category ~* 'elevator|escalator|^lift|lifts' then 'elevators'
    when p_category ~* 'generator' then 'generators'
    when p_category ~* 'solar|photovolt|shams' then 'solar'
    when p_category ~* 'swimming|pool' then 'pools'
    when p_category ~* 'tent|shade|pergola|awning|gazebo' then 'shade'
    when p_category ~* 'landscap|garden|softscape|hardscape|irrigation' then 'landscaping'
    when p_category ~* 'pest' then 'pestcontrol'
    when p_category ~* 'mover|moving|relocation|packing' then 'movers'
    when p_category ~* 'upholstery|curtain|blind|sofa' then 'upholstery'
    when p_category ~* 'wallpaper|wall covering' then 'wallpaper'
    when p_category ~* 'carpet' then 'carpet'
    when p_category ~* 'tiling|tile|marble|granite' then 'tiling'
    when p_category ~* 'floor|spc|vinyl|lvt|epoxy.?floor|parquet|laminate' then 'flooring'
    when p_category ~* 'paint' then 'painting'
    when p_category ~* 'gypsum|false.?ceiling|ceiling|drywall|plasterboard|partition' then 'gypsum'
    when p_category ~* 'waterproof' then 'waterproofing'
    when p_category ~* 'insulation' then 'insulation'
    when p_category ~* 'roofing|^roof|roof ' then 'roofing'
    when p_category ~* 'steel|fabrication' then 'steel'
    when p_category ~* 'masonry|block|^plaster' then 'masonry'
    when p_category ~* 'smart.?home|home.?automation|automation|knx' then 'smarthome'
    when p_category ~* 'av.?system|audio.?visual|audio visual' then 'avsystems'
    when p_category ~* 'network|structured.?cabl' then 'networking'
    when p_category ~* 'signage|sign.?board|3d letter' then 'signage'
    when p_category ~* 'acrylic|perspex|plexiglass' then 'acrylic'
    when p_category ~* 'interior.?design' then 'interiordesign'
    when p_category ~* 'fit.?out' then 'fitout'
    when p_category ~* 'combined.?mep|^mep$|mep' then 'mep'
    when p_category ~* 'glass|glaz|alumin|curtain.?wall|shopfront|balustrad' then 'glazing'
    when p_category ~* 'joinery|kitchen|furniture|carpentr|cabinet|wardrobe|cupboard' then 'joinery'
    when p_category ~* 'hvac|^ac-|air.?con|duct|chiller|cooling|ac.?maintenance' then 'hvac'
    when p_category ~* 'electric|wiring|dewa' then 'electrical'
    when p_category ~* 'plumb|sanitary|drainage' then 'plumbing'
    when p_category ~* 'facade' then 'glazing'
    when p_category ~* 'clean|housekeep' then 'cleaning'
    when p_category ~* 'handyman' then 'handyman'
    when p_category ~* 'general.?service|miscellaneous|^other|^general' then 'general'
    else null end;
$fn$;

-- Seed the ~30 new trade groups (3 mandatory domain aspects each; regex-safe, no \b).
insert into public.category_quote_specs (spec_group, aspect, label, match_regex, mandatory, note) values
('flooring','material','Flooring material','spc|vinyl|lvt|epoxy|laminate|parquet|engineered wood|porcelain|ceramic',true,null),
('flooring','area','Area (sqm)','sqm|m2|square met|area|linear',true,null),
('flooring','thickness','Thickness / wear layer','\d+\s*mm|wear layer|micron|thickness',true,null),
('tiling','material','Tile/stone type','porcelain|ceramic|marble|granite|quartz|natural stone|vitrified',true,null),
('tiling','area','Area (sqm)','sqm|m2|square met|area',true,null),
('tiling','size','Tile/slab size & thickness','\d+\s*mm|slab|thickness|\d+x\d+|size',true,null),
('painting','type','Paint type & spec','emulsion|acrylic|enamel|primer|texture|epoxy|weathershield|paint',true,null),
('painting','area_coats','Area & coats','sqm|m2|coats|\d+\s*coat',true,null),
('painting','surface','Surface / location','interior|exterior|ceiling|wall|wood|metal',true,null),
('gypsum','system','Ceiling/partition system','gypsum|false ceiling|suspended|drywall|partition|grid|gyproc|board',true,null),
('gypsum','area','Area (sqm)','sqm|m2|square met|area',true,null),
('gypsum','board','Board type & thickness','9\s*mm|12\.5\s*mm|moisture resist|fire rated|acoustic|thickness',true,null),
('waterproofing','system','Waterproofing system','membrane|liquid applied|cementitious|bituminous|polyurethane|torch|coating',true,null),
('waterproofing','area','Area (sqm)','sqm|m2|square met|area',true,null),
('waterproofing','location','Application location','roof|wet area|bathroom|basement|water tank|balcony|toilet|planter',true,null),
('wallpaper','material','Wallpaper type','vinyl|non-woven|fabric|3d|pvc|textured|mural|adhesive|wallpaper',true,null),
('wallpaper','area','Area / rolls','sqm|m2|roll|square met|area',true,null),
('wallpaper','location','Location / surface','interior|feature wall|wall|ceiling|room',true,null),
('carpet','material','Carpet type & fibre','carpet tile|broadloom|nylon|polypropylene|wool|loop pile|cut pile|carpet',true,null),
('carpet','area','Area (sqm)','sqm|m2|square met|area',true,null),
('carpet','pile','Pile / weight / backing','pile|gsm|weight|backing|density|thickness',true,null),
('landscaping','area','Area & scope (m2)','m2|sqm|square met|softscape|hardscape|planting area|area',true,null),
('landscaping','planting','Planting schedule','plant|tree|shrub|turf|grass|groundcover|topsoil|species',true,null),
('landscaping','irrigation','Irrigation system','irrigation|drip|sprinkler|emitter|controller|tse|treated sewage',true,'TSE water where network exists (DM)'),
('pools','dimensions','Pool size / depth / type','\d+\s*m2|dimension|depth|length|width|skimmer|overflow|infinity|shell|pool',true,null),
('pools','construction','Construction type','concrete|gunite|shotcrete|rebar|fibreglass|liner|waterproofing|membrane',true,null),
('pools','filtration','Filtration & circulation','filter|pump|circulation|sand filter|skimmer|balance tank|turnover',true,null),
('solar','size','System size (kWp)','kwp|kilowatt|\d+\s*panel|panel|capacity|\d+\s*kw',true,null),
('solar','panel','Panel & inverter','panel|inverter|monocrystalline|watt|mppt|string|module',true,null),
('solar','mounting','Mounting / structure','mounting|rail|ballast|roof|ground mount|tilt|structure',true,'DEWA Shams Dubai for grid-tied'),
('shade','area','Coverage area','\d+\s*m2|sqm|span|dimension|length|width|coverage',true,null),
('shade','frame','Frame / structure','steel|aluminium|galvanis|frame|column|section|powder coat',true,null),
('shade','fabric','Fabric / covering','pvc|pvdf|hdpe|membrane|tensile|shade cloth|fabric|polycarbonate',true,null),
('roofing','area','Roof area & type','\d+\s*m2|sqm|roof area|flat roof|pitched|slope',true,null),
('roofing','waterproofing','Waterproofing system','waterproof|membrane|bituminous|torch|liquid applied|sbs|\bpu\b|polyurethane',true,null),
('roofing','buildup','Insulation & build-up','insulation|xps|screed|vapour barrier|protection board|layer|thickness',true,null),
('insulation','material','Insulation material','xps|eps|polyurethane|rockwool|mineral wool|glasswool|pir|foam|insulation',true,null),
('insulation','thickness','Thickness & thermal value','thickness|\d+\s*mm|r.?value|u.?value|k.?value|thermal conductivity|lambda',true,null),
('insulation','area','Application area','wall|roof|soffit|duct|external|cavity|m2|sqm',true,null),
('steel','tonnage','Tonnage & sections','tonne|\d+\s*ton|\d+\s*kg|section|beam|column|shs|rhs|plate',true,null),
('steel','grade','Steel grade','grade|s275|s355|astm|a36|en 10025|yield|mill cert',true,null),
('steel','fabrication','Fabrication & connections','weld|bolt|connection|gusset|baseplate|fabrication|shop drawing',true,null),
('masonry','block','Block type & size','block|hollow|solid|thermal block|aac|autoclaved|density',true,null),
('masonry','area','Wall area & thickness','\d+\s*m2|sqm|wall area|thickness|linear met|height',true,null),
('masonry','plaster','Plaster / render','plaster|render|cement|coat|screed',true,null),
('smarthome','protocol','Control protocol / system','knx|zigbee|z-wave|lutron|control4|crestron|dali|bacnet|automation',true,null),
('smarthome','scope','Controlled loads / points','lighting|shades|curtain|hvac|thermostat|scene|points|circuits',true,null),
('smarthome','panel','Control panels / UI','touch panel|keypad|gateway|server|app|tablet',true,null),
('avsystems','scope','AV scope & rooms','display|projector|video wall|led screen|meeting room|auditorium|boardroom|\bav\b',true,null),
('avsystems','audio','Audio system','speaker|amplifier|watt|dsp|line array|ceiling speaker|microphone|pa system',true,null),
('avsystems','display','Display spec','inch|4k|nits|pixel pitch|led|lcd|brightness|resolution',true,null),
('networking','cable','Cable category / type','cat6|cat6a|cat7|fiber|fibre|om3|om4|os2|utp|stp|backbone',true,null),
('networking','points','Data points / coverage','data point|outlet|node|drop|floor|rack|points',true,null),
('networking','equipment','Active/passive equipment','switch|router|patch panel|access point|firewall|poe|rack|cabinet',true,null),
('elevators','capacity','Capacity & stops','person|\d+\s*kg|\d+\s*stop|floor|landing|capacity',true,null),
('elevators','type','Lift type & speed','traction|hydraulic|mrl|machine.?room|m/s|speed',true,null),
('elevators','shaft','Shaft / pit / headroom','shaft|pit|headroom|hoistway|travel|door opening|dimensions',true,null),
('generators','rating','Power rating (kVA/kW)','kva|prime|standby|rating|output|continuous|\d+\s*kw',true,null),
('generators','engine','Engine & alternator','engine|alternator|perkins|cummins|stamford|diesel',true,null),
('generators','enclosure','Enclosure & config','canopy|soundproof|acoustic|open type|containerized|weatherproof',true,null),
('interiordesign','deliverables','Scope & deliverables','concept|design|drawings|3d|render|moodboard|layout|deliverables',true,null),
('interiordesign','area','Area & stages','sqm|sq.?ft|area|schematic|detailed design|boq|stages',true,null),
('interiordesign','fees','Fee basis & schedule','fee|lump sum|per sqft|percentage|payment schedule|milestone',true,null),
('signage','type','Sign type & construction','3d letter|channel letter|acrylic|led|neon|billboard|pylon|fascia|lightbox|sign',true,null),
('signage','dimensions','Dimensions','height|width|\d+\s*mm|\d+\s*m\b|size|dimension|area',true,null),
('signage','illumination','Illumination & material','led|backlit|front.?lit|acrylic|stainless|aluminium|composite',true,null),
('acrylic','product','Product type','acrylic|perspex|plexiglass|display|stand|holder|partition|enclosure|sheet',true,null),
('acrylic','dimensions','Dimensions & thickness','\d+\s*mm|thickness|size|height|width|dimension',true,null),
('acrylic','material','Material grade & finish','cast|extruded|clear|frosted|opal|colour|polished|matte|edge',true,null),
('cleaning','scope','Scope & areas','general|deep|kitchen|bathroom|bedroom|balcony|sqft|area|floor',true,null),
('cleaning','frequency','Frequency / visits','one.?time|weekly|monthly|per visit|visits|hours|man.?hour|cleaners',true,null),
('cleaning','materials','Materials & equipment','supplies|chemicals|detergent|equipment|steam|machine|materials',true,null),
('facade','surface','Surface & height','facade|glass|cladding|external|floors|height|storeys|elevation|sqm',true,null),
('facade','access','Access method & safety','rope access|irata|bmu|cradle|scaffold|permit|harness|fall arrest',true,'IRATA + work-at-height permit'),
('facade','frequency','Frequency / cycle','one.?time|quarterly|annual|cycle|cleans|schedule',true,null),
('watertank','scope','Tank scope & size','water tank|gallon|litre|underground|overhead|capacity|tanks',true,null),
('watertank','method','Cleaning & disinfection','drain|scrub|vacuum|disinfect|chlorine|sanitize|antibacterial|flush',true,null),
('watertank','certificate','Certificate & water test','certificate|dm approved|water test|lab report|potability|clearance',true,'DM-approved certificate mandatory'),
('pestcontrol','pests','Pests & areas','cockroach|termite|rodent|bed bug|ant|mosquito|bird|pest|area',true,null),
('pestcontrol','method','Method & chemicals','spray|gel|fumigation|fogging|bait|approved|chemical|treatment',true,'DM-approved pesticides'),
('pestcontrol','frequency','Frequency / visits','visit|monthly|quarterly|one.?time|contract|warranty|follow.?up',true,null),
('movers','scope','Move scope & services','packing|unpacking|loading|dismantle|assemble|move|relocation|boxes|labour',true,null),
('movers','inventory','Inventory / volume','studio|bhk|villa|truck|items|volume|movers',true,null),
('movers','transport','Route, floors & access','pickup|drop|floor|lift|elevator|distance|emirate|\d+\s*km',true,null),
('upholstery','items','Items & service type','sofa|seater|mattress|carpet|curtain|blind|upholstery|shampoo',true,null),
('upholstery','method','Method / treatment','steam|shampoo|dry clean|deep clean|stain|sanitize|fabrication|measurement',true,null),
('upholstery','quantity','Quantity / measurement','seater|per piece|sqm|per curtain|per window|linear|units',true,null),
('handyman','tasks','Tasks & trades','plumbing|electrical|carpentry|painting|tiling|fixing|installation|repair|task',true,null),
('handyman','labour','Labour basis','hourly|per hour|half day|full day|per task|man.?hour|call.?out|visit',true,null),
('handyman','materials','Materials & parts','materials|parts|spares|supply|excluded|included',true,null),
('acduct','scope','System & scope','duct|coil|grille|diffuser|fcu|ahu|split|central|filter|blower',true,null),
('acduct','method','Method & process','brush|vacuum|negative pressure|sanitize|disinfect|antimicrobial|inspection|camera',true,null),
('acduct','quantity','Quantity / units','per unit|per duct|per outlet|sqft|units|tonnage',true,null),
('fitout','scope','Scope / BOQ breakdown','boq|scope|civil|partition|ceiling|flooring|joinery|mep|line item',true,null),
('fitout','area','Area (sqft/sqm)','sqft|sq.?ft|sqm|m2|square',true,null),
('fitout','finishes','Finish specifications','finish|material|specification|brand|grade|laminate',true,null),
('mep','scope','MEP scope (M/E/P)','mechanical|electrical|plumbing|hvac|ducting|wiring|piping|drainage',true,null),
('mep','loads','Loads / capacity','\d+\s*kw|\d+\s*amp|load|tonnage|btu|cfm|gpm|capacity',true,null),
('mep','equipment','Equipment make/model','make|model|brand|rating|panel|chiller|pump',true,null),
('scaffolding','type','Scaffold type / height / area','scaffold|frame|cuplock|tube|height|\d+\s*m\b|sqm|bay',true,null),
('scaffolding','duration','Duration / rental','duration|rental|hire|per month|per week|period|days',true,null),
('scaffolding','supply','Supply, erect & dismantle','supply|erect|dismantle|install|remove|labour',true,null),
('demolition','scope','Demolition scope','demolition|strip out|soft strip|full|partial|structure|slab',true,null),
('demolition','area','Area / volume','sqft|sqm|m2|volume|floors|storeys|cubic',true,null),
('demolition','disposal','Debris removal & disposal','debris|disposal|haul|tipping|removal|waste|dumping',true,null),
('shutters','type','Type & dimensions','rolling|sectional|shutter|garage door|width|height|opening|\d+\s*mm',true,null),
('shutters','material','Material / gauge / finish','material|steel|aluminium|galvanized|gauge|slat|finish|powder coat',true,null),
('shutters','operation','Operation','manual|motor|motorized|automatic|remote|chain',true,null),
('general','scope','Scope description','scope|work|service|description|task|deliverable',true,null),
('general','quantity','Quantity / units','quantity|qty|units|nos|sqm|sqft|hours|lumpsum',true,null),
('general','timeline','Timeline / duration','timeline|duration|days|weeks|completion|delivery|schedule',true,null);
