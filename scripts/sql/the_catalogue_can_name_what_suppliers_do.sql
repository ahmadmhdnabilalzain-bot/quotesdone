-- THE CATALOGUE CAN NAME WHAT SUPPLIERS DO (12 Nov 2026, sales_engineer; built by it_engineer).
-- Seat: sales_engineer. Founder rulings 1647 (a broad word covers many services; a vague statement is asked about
-- specifically: a recruitment company is asked "labourers, professional experts, freelancers?"), 1627 and 1628 (services
-- are proposed from the documents, confirmed by the supplier, stored as keys; matching is code over confirmed keys).
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 12 Nov 2026; analysis scratchpad services/REPORT.md 1.2 and 3.6):
--   * 1,104 active services under 223 trades, 3 to 10 a trade. Of the founder's three kinds of staff (labourers,
--     professional experts, freelancers) only the first had a key; a manpower company could not say drivers, cleaners,
--     hospitality staff, engineers on secondment, warehouse workers or promoters. The designed reading, run on 12 hard
--     profiles, asked the recruitment company "What kinds of staff do you supply?" with 8 options and only 3 mapped to
--     a key. The same reading kept 60 phrases in the supplier's own words because no key existed (garden design,
--     jacuzzi, lifeguards, daily cleaning, move-out make-ready, vehicle branding, neon signs, earthing, clinic fit-out).
--   * "restaurant fit out" and "تجهيز مطاعم" were aliases of interior_fitout.retail (shops), so a restaurant fit-out
--     request could never reach a contractor who does restaurants, cafes and hotels.
--
-- WHAT THIS ADDS: 47 services under existing trades (no new trade), each with English and Arabic names, and 543 curated
-- aliases in both languages on them and on two existing services, filed as approved rows of the alias queue
-- (source curated, decided by sales_engineer) exactly as a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql
-- files its 427. Against the analysis's list of 43 (and the review of 12 Nov 2026):
--   * labour_supply.office_admin_staff IS added, and is the same work as hr_outsourcing.office_staff_outsourcing: a
--     manpower firm's checklist shows only his own trade's services, so without a key under labour_supply he could
--     never tick office staff. The `same` rows and the labour_supply / hr_outsourcing adjacency make the two meet
--     (the_same_work_under_two_keys_meets_at_the_service_gate.sql); the hr key gets the office-staff aliases here.
--   * NOT ADDED, linked: logistics_moving.trucking ("trucks with driver") is logistics_moving.site_delivery, whose
--     aliases already said trucking, lorry and شاحنات نقل; site_delivery gets the truck-with-driver and دينا aliases.
--   * ADDED, beyond the list: labour_supply.professional_staff (the founder's "professional experts": accountants, IT,
--     HR and sales staff on contract are not engineers on secondment); signage.neon_signs (kept in own words on a hard
--     profile; LED neon is a staple UAE sign line); labour_supply.office_boys, delivery_riders and receptionists (what a
--     UAE manpower firm also supplies; receptionists are the same work as facilities_management.concierge_reception).
--   * Staff kinds that already had a key in another trade are NOT duplicated: security guards are
--     security_guarding.manned_guarding, nurses occupational_health.onsite_clinic_nurse, event hostesses
--     event_management.event_staff_hostesses, safety officers hse_consultancy.site_safety_officers. Domestic workers
--     (housemaids on the household's visa) are not added: that is a licensed household service (Tadbeer), not B2B.
--     Catering is not added: food and beverage is outside the estate (founder ruling 1586).
--   * Names that sat on the wrong service move (section 2): "restaurant fit out" from interior_fitout.retail to the new
--     interior_fitout.hospitality; "paint supply" from chemicals.coatings (industrial coatings) to the new
--     building_materials.paints; "villa cleaning", "تنظيف فلل", "تنظيف شقق" from cleaning.deep_cleaning to the new
--     cleaning.residential (regular home cleaning).
--   * Too generic to be one service's name, so not used: "mixers" (industrial process mixers), "nails and screws" and
--     "عدد وأدوات" (fasteners, tools), "temporary staffing" / "contract staffing" (every kind of staff), "مضيفين".
--   * Gulf words: بلايوود (not the Egyptian أبلكاش), دريول (driver), أصباغ (paints), دينا (the small truck).
--   * landscaping.pergolas_gazebos is garden pergolas and gazebos (aluminium.pergolas_shades names "pergola"; the
--     aluminium firm reaches it by implication in the same-work file); building_materials.hardware avoids "ironmongery".
-- Every alias was checked against every name of every live service before it was written (none names another
-- service, 12 Nov 2026), and the guard below re-checks it at apply and refuses the file if one does.
--
-- WHAT THIS DOES NOT DO: no vectors are written here. The new services have none, and the five services whose aliases
-- change carry a stale sha. THE RELEASE BACKFILL RUNS AFTER THIS FILE:
--   node scripts/kb/embed_taxonomy_services.mjs --write    (free, in-region embed_ml; never OpenRouter)
--   node scripts/kb/embed_taxonomy_services.mjs            (must then print "0 stale vector(s)")
-- Until it has run, exact names and aliases work at once and the meaning layer skips the new keys.
-- No routine changes; no table is created (so no export-registry row); no trade is added (the sign-up mirror,
-- serverCopy.ts, and the quote hold lists do not move).
--
-- prevented by: scripts/checks/the_catalogue_can_name_what_suppliers_do.test.mjs (the founder's staff kinds, the broad
--               areas of the analysis, the links instead of duplicates, Arabic on every name, the guard, the readers'
--               limits) and the guard below.

-- ── 1. the services ─────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.taxonomy_trade_service (trade_code, code, label_en, label_ar, sort)
values
  ('labour_supply','drivers_operators','Drivers & equipment operators','سائقون ومشغّلو معدات',410),
  ('labour_supply','cleaners_housekeeping','Cleaners & housekeeping staff','عمال النظافة وطواقم التدبير المنزلي',420),
  ('labour_supply','hospitality_staff','Hospitality staff (waiters, stewards, kitchen helpers)','طواقم الضيافة (نُدُل ومضيفون ومساعدو مطابخ)',430),
  ('labour_supply','engineers_technicians','Engineers & technicians on secondment','مهندسون وفنيون بنظام الإعارة',440),
  ('labour_supply','professional_staff','Professional staff on contract (finance, IT, HR, sales)','كوادر مهنية بعقود مؤقتة (المالية وتقنية المعلومات والموارد البشرية والمبيعات)',450),
  ('labour_supply','warehouse_factory','Warehouse & factory workers','عمال المستودعات والمصانع',460),
  ('labour_supply','promoters_merchandisers','Promoters & merchandisers','المروّجون ومنسّقو المنتجات في المتاجر',470),
  ('labour_supply','freelancers','Freelancers & independent contractors','المستقلون والمتعاقدون الأفراد',480),
  ('labour_supply','office_admin_staff','Office & admin staff','الموظفون الإداريون والمكتبيون',490),
  ('labour_supply','office_boys','Office boys, tea boys & messengers','الأوفيس بوي وعمال البوفيه والمراسلون',500),
  ('labour_supply','delivery_riders','Delivery riders (motorbike)','مندوبو التوصيل بالدراجات النارية',510),
  ('labour_supply','receptionists','Receptionists & front-desk staff','موظفو الاستقبال والمكاتب الأمامية',520),
  ('interior_fitout','residential','Villa & apartment interiors','التجهيز الداخلي للفلل والشقق',410),
  ('interior_fitout','hospitality','Restaurant, cafe & hotel fit-out','تجهيز المطاعم والمقاهي والفنادق',420),
  ('interior_fitout','healthcare','Clinic & healthcare fit-out','تجهيز العيادات والمنشآت الصحية',430),
  ('landscaping','design','Landscape design','تصميم الحدائق والمساحات الخارجية',410),
  ('landscaping','lighting','Garden & landscape lighting','إنارة الحدائق والمساحات الخارجية',420),
  ('landscaping','pergolas_gazebos','Garden pergolas & gazebos','برجولات الحدائق والجلسات الخارجية',430),
  ('landscaping','plants_trees_supply','Plants, trees & palms supply','توريد النباتات والأشجار والنخيل',440),
  ('swimming_pools','pool_renovation','Pool renovation, retiling & leak repair','ترميم المسابح وتبليطها وإصلاح تسرّباتها',410),
  ('swimming_pools','heating_cooling','Pool heating & chillers','تدفئة المسابح وتبريدها',420),
  ('swimming_pools','jacuzzi_spa_sauna','Jacuzzi, spa, sauna & steam rooms','الجاكوزي والسبا وغرف الساونا والبخار',430),
  ('facilities_management','handyman','Handyman & minor repairs','الإصلاحات البسيطة وخدمات الهاندي مان',410),
  ('facilities_management','villa_amc','Annual maintenance contracts for villas & homes','عقود الصيانة السنوية للفلل والمنازل',420),
  ('facilities_management','concierge_reception','Concierge & reception staff','خدمات الكونسيرج وموظفو الاستقبال',430),
  ('facilities_management','lifeguards','Lifeguards & pool attendants','المنقذون ومراقبو المسابح',440),
  ('facilities_management','make_ready','Move-in & move-out make-ready','تجهيز الوحدات قبل التسليم وبعد الإخلاء',450),
  ('cleaning','contract_cleaning','Daily & contract cleaning (offices, buildings, schools)','التنظيف اليومي وعقود النظافة (المكاتب والمباني والمدارس)',410),
  ('cleaning','residential','Regular home cleaning (villas & apartments)','التنظيف المنزلي الدوري للفلل والشقق',420),
  ('cleaning','carpet_upholstery','Carpet, sofa & curtain cleaning','تنظيف السجاد والكنب والستائر',430),
  ('joinery','repairs','Carpentry & door repairs','إصلاح أعمال النجارة والأبواب',410),
  ('flooring','repairs','Tile & floor repairs','إصلاح البلاط والأرضيات',410),
  ('building_materials','tiles','Tiles (ceramic & porcelain)','البلاط (السيراميك والبورسلان)',410),
  ('building_materials','paints','Paints & painting materials','الدهانات ومواد الطلاء',420),
  ('building_materials','gypsum_boards','Gypsum boards & plaster','ألواح الجبس ومواد الجبس',430),
  ('building_materials','timber_plywood','Timber, plywood & MDF','الأخشاب والبلايوود وألواح MDF',440),
  ('building_materials','hardware','General building hardware','الخردوات ومستلزمات البناء العامة',450),
  ('building_materials','plumbing_fittings','Taps, valves & plumbing fittings','الخلاطات والمحابس ولوازم السباكة',460),
  ('building_materials','waterproofing_insulation','Waterproofing & insulation materials','مواد العزل المائي والحراري',470),
  ('electrical','earthing_lightning','Earthing & lightning protection','التأريض والحماية من الصواعق',410),
  ('logistics_moving','heavy_haulage','Heavy & abnormal load transport','نقل الأحمال الثقيلة والاستثنائية',410),
  ('event_management','brand_activations','Brand activations & roadshows','تفعيل العلامات التجارية والجولات الترويجية',410),
  ('event_management','weddings_private','Weddings & private events','حفلات الأعراس والمناسبات الخاصة',420),
  ('event_management','event_decor','Event decor & florals','ديكور الفعاليات وتنسيق الزهور',430),
  ('signage','vehicle_branding','Vehicle branding & fleet graphics','تغليف المركبات وإعلانات الأساطيل',410),
  ('signage','digital_signage','Digital signage & LED displays','اللافتات الرقمية وشاشات LED الإعلانية',420),
  ('signage','neon_signs','Neon & LED neon signs','لافتات النيون وإضاءة النيون',430)
on conflict (trade_code, code) do update set label_en = excluded.label_en, label_ar = excluded.label_ar, active = true;

-- ── 2. names that belong to another service leave the one they were on (they join the right one in 3) ─────────────────
-- a restaurant is not a shop; a paint shop is not an industrial coatings firm; a villa cleaned every week is not a deep clean
update public.taxonomy_trade_service t
   set aliases = array(select a from unnest(t.aliases) a where lower(btrim(a)) <> all (m.names))
  from (values ('interior_fitout', 'retail', array['restaurant fit out', 'تجهيز مطاعم']),
               ('chemicals', 'coatings', array['paint supply', 'توريد دهانات']),
               ('cleaning', 'deep_cleaning', array['villa cleaning', 'تنظيف فلل', 'تنظيف شقق'])) as m(trade_code, code, names)
 where t.trade_code = m.trade_code and t.code = m.code and t.aliases && m.names;

-- ── 3. the curated aliases, as approved rows of the queue; appended, never replacing what a service has ─────────────────
do $seed$
declare
  seed jsonb := $s$[
  ["labour_supply", "drivers_operators", ["drivers supply","driver supply","heavy duty drivers","light vehicle drivers","bus drivers supply","equipment operators","machine operators","forklift operators","توريد سائقين","سائقين","دريول","سائقي شاحنات","مشغلي معدات","مشغلي رافعات شوكية"]],
  ["labour_supply", "cleaners_housekeeping", ["cleaners supply","cleaning staff","cleaning labour","cleaning manpower","housekeeping staff","housekeepers","توريد عمال نظافة","عمال نظافة","عمالة نظافة","عاملات نظافة","طاقم تدبير منزلي"]],
  ["labour_supply", "hospitality_staff", ["waiters","waitresses","stewards","banquet staff","kitchen helpers","f&b staff","hospitality manpower","catering staff","baristas","جرسونات","عمال مطبخ","مساعدي طباخ","طاقم ضيافة","عمالة فندقية"]],
  ["labour_supply", "engineers_technicians", ["engineers supply","engineer supply","engineers on contract","technicians supply","technical staff supply","mep technicians supply","engineers on secondment","توريد مهندسين","توريد فنيين","مهندسين بعقود","فنيين بعقود","إعارة مهندسين"]],
  ["labour_supply", "professional_staff", ["professional staffing","contract professionals","accountants on contract","it contractors","specialist staff supply","كوادر مهنية","محاسبين بعقود","توريد كفاءات"]],
  ["labour_supply", "warehouse_factory", ["warehouse workers","warehouse staff","factory workers","production workers","pickers and packers","loading and unloading workers","عمال مستودعات","عمال مخازن","عمال مصانع","عمال تعبئة","عمال تحميل وتنزيل"]],
  ["labour_supply", "promoters_merchandisers", ["promoters","brand promoters","sales promoters","in-store promoters","merchandisers","brand ambassadors","مروجين","مروجات","مروجي مبيعات","منسقي رفوف","ميرشندايزر"]],
  ["labour_supply", "freelancers", ["freelancers","freelance professionals","freelance staff","independent contractors","freelancer supply","فريلانسر","مستقلين","متعاقدين مستقلين","عمل حر"]],
  ["labour_supply", "office_admin_staff", ["office assistants supply","clerical staff supply","admin assistants supply","office administrators supply","مساعدين إداريين","موظفي سكرتارية","موظفين مكتبيين"]],
  ["labour_supply", "office_boys", ["office boy","office boys","tea boy","tea boys","messenger","messengers","pantry boy","أوفيس بوي","عامل بوفيه","مراسل","مراسلين"]],
  ["labour_supply", "delivery_riders", ["delivery riders","delivery rider","bike riders","motorbike riders","rider supply","مندوب توصيل","مناديب توصيل","رايدر","سائقي دراجات توصيل"]],
  ["labour_supply", "receptionists", ["receptionist supply","front office staff","reception staff supply","front desk staff supply","توريد موظفي استقبال","موظفي مكتب أمامي","موظفات استقبال بعقود"]],
  ["interior_fitout", "residential", ["villa interiors","villa fit out","villa fitout","apartment fit out","apartment interiors","home interiors","residential fit out","villa renovation","ديكور فلل","تشطيب فلل","ديكور شقق","تشطيب شقق","تجهيز فلل"]],
  ["interior_fitout", "hospitality", ["restaurant fit out","restaurant fitout","cafe fit out","cafe fitout","hotel fit out","hotel fitout","f&b fit out","hospitality fit out","تجهيز مطاعم","تجهيز مقاهي","تجهيز كافيهات","تجهيز فنادق","ديكور مطاعم"]],
  ["interior_fitout", "healthcare", ["clinic fit out","clinic fitout","medical fit out","hospital fit out","dental clinic fit out","pharmacy fit out","healthcare fit out","تجهيز عيادات","ديكور عيادات","تجهيز مراكز طبية","تجهيز صيدليات"]],
  ["landscaping", "design", ["landscape design","garden design","landscape architecture","landscape designer","garden designer","تصميم حدائق","تصميم لاندسكيب","تصميم المساحات الخارجية"]],
  ["landscaping", "lighting", ["garden lighting","landscape lighting","garden lights","pathway lights","bollard lights","إنارة حدائق","إضاءة حدائق","إضاءة لاندسكيب"]],
  ["landscaping", "pergolas_gazebos", ["gazebo","gazebos","garden pergola","wooden pergola","wpc pergola","garden canopy","outdoor seating area","جازيبو","برجولة حديقة","برجولات خشبية","جلسات خارجية","مظلات حدائق"]],
  ["landscaping", "plants_trees_supply", ["plants supply","plant nursery","trees supply","palm trees","date palms","indoor plants","outdoor plants","nursery plants","مشتل","مشاتل","توريد نباتات","توريد أشجار","أشجار نخيل","فسائل نخيل"]],
  ["swimming_pools", "pool_renovation", ["pool renovation","pool refurbishment","pool retiling","pool leak repair","pool leak detection","pool resurfacing","pool plastering","ترميم مسابح","تجديد مسبح","تبليط مسبح","تسريب مسبح","إصلاح تسريب المسبح"]],
  ["swimming_pools", "heating_cooling", ["pool heating","pool heater","pool heat pump","pool chiller","pool cooling","swimming pool chiller","سخان مسبح","تدفئة مسبح","تبريد مسبح","تشيلر مسبح"]],
  ["swimming_pools", "jacuzzi_spa_sauna", ["jacuzzi","jacuzzis","hot tub","spa pool","sauna","sauna room","steam room","steam bath","جاكوزي","ساونا","غرفة بخار","حمام بخار","غرفة ساونا"]],
  ["facilities_management", "handyman", ["handyman","handyman services","minor repairs","small repairs","odd jobs","call out repairs","home repairs","هاندي مان","تصليحات بسيطة","إصلاحات منزلية","فني صيانة منزلية"]],
  ["facilities_management", "villa_amc", ["villa amc","villa maintenance contract","villa annual maintenance","home maintenance contract","home amc","villa maintenance","عقد صيانة فيلا","صيانة فلل سنوية","عقود صيانة الفلل","صيانة منازل"]],
  ["facilities_management", "concierge_reception", ["concierge","concierge services","reception staff","front desk staff","lobby attendants","كونسيرج","موظفي استقبال","موظفات استقبال","خدمات الاستقبال"]],
  ["facilities_management", "lifeguards", ["lifeguard","lifeguards","pool attendant","pool attendants","beach lifeguards","lifeguard services","منقذ","منقذين","منقذ سباحة","منقذي مسابح","مراقب مسبح"]],
  ["facilities_management", "make_ready", ["make ready","unit make ready","handover preparation","apartment turnover","vacated unit preparation","تجهيز شقق للتسليم","تجهيز وحدات بعد الإخلاء","تجهيز للتسليم"]],
  ["cleaning", "contract_cleaning", ["office cleaning","daily cleaning","contract cleaning","cleaning contract","building cleaning","school cleaning","janitorial services","cleaning amc","تنظيف مكاتب","تنظيف يومي","عقد نظافة","عقود تنظيف","تنظيف مباني","تنظيف مدارس"]],
  ["cleaning", "residential", ["villa cleaning","home cleaning","house cleaning","maid service","hourly maid","part time maid","maid by the hour","weekly home cleaning","تنظيف فلل","تنظيف شقق","تنظيف منزلي","عاملة تنظيف بالساعة","خادمة بالساعة","شغالة بالساعة","تنظيف بيوت"]],
  ["cleaning", "carpet_upholstery", ["carpet cleaning","sofa cleaning","upholstery cleaning","curtain cleaning","mattress cleaning","rug cleaning","carpet shampoo","تنظيف سجاد","تنظيف كنب","تنظيف موكيت","تنظيف ستائر","تنظيف مراتب","غسيل سجاد"]],
  ["joinery", "repairs", ["carpentry repair","carpentry repairs","door repair","door repairs","cabinet repair","wardrobe repair","hinge replacement","تصليح أبواب","إصلاح أبواب","تصليح خزائن","صيانة نجارة","تصليح نجارة"]],
  ["flooring", "repairs", ["tile repair","tile replacement","floor repair","floor repairs","broken tiles","floor tile repair","regrouting","تصليح بلاط","تغيير بلاط","إصلاح أرضيات","تبديل بلاط مكسور"]],
  ["building_materials", "tiles", ["tiles supply","ceramic tiles","porcelain tiles","floor tiles","wall tiles","tile showroom","tiles trading","توريد بلاط","بلاط سيراميك","بلاط بورسلان"]],
  ["building_materials", "paints", ["paint supply","paints supply","paint shop","emulsion paint","enamel paint","primers","paint trading","توريد دهانات","أصباغ","بيع دهانات","محل دهانات","دهانات بلاستيك"]],
  ["building_materials", "gypsum_boards", ["gypsum boards","plasterboard","drywall boards","gypsum powder","plaster of paris","ألواح جبس","ألواح جبسوم","بودرة جبس"]],
  ["building_materials", "timber_plywood", ["timber","timber supply","plywood","mdf boards","particle board","hardwood","softwood","marine plywood","wood trading","أخشاب","توريد أخشاب","بلايوود","بلاي وود","ألواح mdf"]],
  ["building_materials", "hardware", ["hardware store","hardware shop","hardware trading","general hardware","building hardware","خردوات","محل خردوات","مواد خردوات"]],
  ["building_materials", "plumbing_fittings", ["taps","bathroom taps","basin mixer tap","kitchen mixer tap","angle valves","brass fittings","plumbing materials","plumbing fittings","حنفيات","خلاطات مياه","لوازم سباكة","مواد سباكة"]],
  ["building_materials", "waterproofing_insulation", ["waterproofing materials","waterproofing membrane","bitumen membrane","insulation materials","insulation boards","rockwool","xps boards","glass wool","مواد عزل","لفائف عزل","رولات عزل","صوف صخري","ألواح عزل"]],
  ["electrical", "earthing_lightning", ["earthing","earthing system","grounding system","lightning protection","lightning arrester","earth pit","earthing testing","تأريض","مانعة صواعق","حماية من الصواعق","حفرة تأريض","نظام تأريض"]],
  ["logistics_moving", "heavy_haulage", ["heavy haulage","heavy transport","abnormal load","oversized cargo","lowbed trailer","low bed transport","heavy equipment transport","machinery transport","نقل ثقيل","نقل معدات ثقيلة","لوبد","نقل حمولات استثنائية"]],
  ["event_management", "brand_activations", ["brand activation","brand activations","roadshow","roadshows","mall activation","experiential marketing","sampling campaign","تفعيل علامة تجارية","فعاليات ترويجية","جولات ترويجية","تفعيل في المولات"]],
  ["event_management", "weddings_private", ["wedding planning","wedding planner","weddings","private party","birthday party","engagement party","private events","تنظيم حفلات زفاف","تنظيم أعراس","حفلات خاصة","حفلات أعياد ميلاد","حفلات خطوبة"]],
  ["event_management", "event_decor", ["event decor","event decoration","wedding decor","stage decor","floral arrangements","flower decoration","balloon decoration","kosha","ديكور حفلات","تنسيق زهور","تنسيق ورود","تزيين حفلات","كوشة","ديكور أعراس"]],
  ["signage", "vehicle_branding", ["vehicle branding","car branding","vehicle wrap","car wrap","fleet graphics","van branding","vehicle stickers","truck branding","تغليف سيارات","ستيكر سيارات","ملصقات سيارات","براندنج سيارات"]],
  ["signage", "digital_signage", ["digital signage","digital signs","led display","led signage","led billboard","outdoor led screen","advertising screens","شاشات إعلانية","لوحات رقمية","شاشات led إعلانية","شاشات led خارجية"]],
  ["signage", "neon_signs", ["neon sign","neon signs","led neon","neon flex","custom neon","نيون","لوحات نيون","لافتات نيون","نيون فليكس"]],
  ["hr_outsourcing", "office_staff_outsourcing", ["office staff supply","admin staff supply","temporary office staff","data entry staff","secretaries on contract","توريد موظفين إداريين","موظفين مكتبيين مؤقتين","موظفين إداريين بعقود"]],
  ["logistics_moving", "site_delivery", ["truck with driver","truck rental with driver","pickup with driver","flatbed truck","trailer transport","3 ton truck","10 ton truck","شاحنة مع سائق","بيك أب مع سائق","دينا","دينا مع سائق","تريلا","نقل بالتريلا"]]
]$s$::jsonb;
  v_missing text; v_owned text;
begin
  -- every key the seed names is a live service (a typo would silently curate nothing)
  select string_agg(x->>0 || '.' || (x->>1), ', ') into v_missing
    from jsonb_array_elements(seed) x
   where not exists (select 1 from public.taxonomy_trade_service s where s.active and s.trade_code = x->>0 and s.code = x->>1);
  if v_missing is not null then raise exception 'the catalogue seed names services that are not active: %', v_missing; end if;
  -- no alias is already a name of ANOTHER service (a name two services share names neither): refuse the whole file.
  -- The names are those fn_service_alias_owners compares (key, code, both labels, every alias), normalised ONCE: calling
  -- fn_service_alias_owners per alias normalises the whole catalogue 509 times and did not finish in 120 s (12 Nov 2026).
  with names as (
    select s.trade_code || '.' || s.code as k, public.fn_service_alias_norm(n) as n
      from public.taxonomy_trade_service s,
           unnest(array[s.trade_code || '.' || s.code, s.code, s.label_en, s.label_ar] || coalesce(s.aliases, '{}'::text[])) n
     where s.active
  ), p as (
    select distinct x->>0 || '.' || (x->>1) as k, lower(btrim(a)) as alias, public.fn_service_alias_norm(a) as n
      from jsonb_array_elements(seed) x, jsonb_array_elements_text(x->2) a
  )
  select string_agg(distinct p.alias || ' -> ' || nm.k, '; ') into v_owned
    from p join names nm on nm.n = p.n and nm.k <> p.k;
  if v_owned is not null then raise exception 'a curated alias already names another service: %', v_owned; end if;

  insert into public.service_alias_proposal (phrase, phrase_norm, trade_code, code, source, status, decided_by, decided_at, reason)
  select p.alias, public.fn_service_alias_norm(p.alias), p.trade_code, p.code, 'curated', 'approved', 'sales_engineer', now(),
         'curated 12 Nov 2026 (founder rulings 1647/1627/1628): the catalogue can name what suppliers do'
    from (select distinct x->>0 as trade_code, x->>1 as code, lower(btrim(a)) as alias
            from jsonb_array_elements(seed) x, jsonb_array_elements_text(x->2) a) p
  on conflict (phrase_norm, trade_code, code) do nothing;

  update public.taxonomy_trade_service t
     set aliases = coalesce(t.aliases, '{}'::text[])
                || array(select distinct lower(btrim(a)) from jsonb_array_elements(seed) x, jsonb_array_elements_text(x->2) a
                          where x->>0 = t.trade_code and x->>1 = t.code
                            and not (lower(btrim(a)) = any(coalesce(t.aliases, '{}'::text[])))
                          order by 1)
   where exists (select 1 from jsonb_array_elements(seed) x where x->>0 = t.trade_code and x->>1 = t.code);
end
$seed$;

-- ── 4. manpower and HR outsourcing firms do each other's work (the link for office staff; one level, the gate decides) ─
insert into public.taxonomy_trade_adjacent (a_code, b_code, reason_en, reason_ar)
values ('hr_outsourcing', 'labour_supply',
        'Manpower suppliers place office and admin staff, and HR outsourcing firms supply workers on their own visas.',
        'شركات توريد العمالة توفّر موظفين إداريين ومكتبيين، وشركات تعهيد الموارد البشرية توفّر عمالة على كفالتها.')
on conflict (a_code, b_code) do update set reason_en = excluded.reason_en, reason_ar = excluded.reason_ar, active = true;

-- Verdict row (a data file with a guard: the guard raises and refuses the apply; this row reports what landed).
select case
  when (select count(*) from public.taxonomy_trade_service where active and trade_code || '.' || code = any(array[
          'labour_supply.drivers_operators','labour_supply.professional_staff','labour_supply.freelancers','labour_supply.office_admin_staff',
          'labour_supply.office_boys','labour_supply.delivery_riders','labour_supply.receptionists','landscaping.design',
          'swimming_pools.jacuzzi_spa_sauna','cleaning.contract_cleaning','building_materials.tiles','signage.neon_signs'])) = 12
   and (select count(*) from public.taxonomy_trade_service where active) >= 1151
   and exists (select 1 from public.taxonomy_trade_service where trade_code = 'interior_fitout' and code = 'hospitality' and 'restaurant fit out' = any(aliases))
   and not exists (select 1 from public.taxonomy_trade_service where trade_code || '.' || code in ('interior_fitout.retail', 'chemicals.coatings', 'cleaning.deep_cleaning')
                     and aliases && array['restaurant fit out', 'paint supply', 'villa cleaning'])
   and exists (select 1 from public.taxonomy_trade_adjacent where active and a_code = 'hr_outsourcing' and b_code = 'labour_supply')
   and not exists (select 1 from public.taxonomy_trade_service where trade_code = 'logistics_moving' and code = 'trucking')
  then 'PROBE OK the catalogue names the 47 services, their aliases and the links'
  else 'PROBE FAILED: a catalogue service, alias or link is missing' end as verdict;
