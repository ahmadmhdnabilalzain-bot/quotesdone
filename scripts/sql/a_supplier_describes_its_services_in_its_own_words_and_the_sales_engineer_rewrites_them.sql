-- A SUPPLIER DESCRIBES ITS SERVICES IN ITS OWN WORDS, AND THE SALES ENGINEER REWRITES THEM.
-- Seat: sales_engineer. 18 Sep 2026.
--
-- Founder, instruction 438: "for adding services its not a checkbox or drop down menu. i told you
-- its a voice to text or text box. once filled the sales engineer will rewrite that professionally
-- since he will cross match based on that."
-- Founder, instruction 439: "make sure the sales engineer is smart in cross matching. for example
-- someone who does decoration is definitely able to do flooring even through words cross matching
-- is not there."
--
-- MEASURED BEFORE THIS FILE (production, 17 Sep 2026 23:48 UTC, statement_timeout 8s):
--   * taxonomy_trade: 40 active. taxonomy_trade_service: 200 active rows, and NO aliases column --
--     the checklist could show a service but nothing could RECOGNISE one in a sentence.
--   * public.service_implication: does not exist (0 rows in information_schema.tables).
--   * supplier_capabilities: has `services`; has none of services_raw_text / services_implied /
--     services_removed.
--   * public.fn_services_effective: does not exist (0 rows in pg_proc).
--   * public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer): gates on
--     trades + confirmed_at + roles + authority + value. It has NO service-level gate.
--
-- WHAT THIS CHANGES
--   1. taxonomy_trade_service.aliases -- the exact EN+AR phrases that NAME each service, 201 rows
--      (interior_fitout.decoration is added below; the founder's own example needs it). The rewriter
--      (_shared/service_rewrite.ts) reads them through the trade matcher's own folding
--      (_shared/trade_words.ts termPattern + fn_ar_norm's Arabic normalisation), word-start anchored,
--      longest alias wins. EXACT OR NONE: no stemmer, no similarity, no nearest service. A phrase the
--      aliases do not name is KEPT in the supplier's own words and flagged for the sales engineer.
--   2. public.service_implication -- the curated, auditable capability-implication map. Each row says
--      one thing: a company that states `from_code` can also do `implies_trade.implies_code`, and why,
--      in English and Arabic. from_code is a taxonomy_trade code OR a '<trade>.<service>' key.
--      ONE LEVEL ONLY. Nothing here is transitive: what a STATED service implies is added, and what an
--      IMPLIED service would imply is not. That rule lives in the two readers (fn_services_effective
--      below, and impliedServices() in _shared/service_rewrite.ts) -- a chain in the data would be a
--      claim nobody curated. supabase/functions/_shared/service_implications.json is the same 113 rows
--      as the seed for the edge runtime, and scripts/checks/the_implication_map_has_one_seed.test.mjs
--      holds the two to each other.
--   3. supplier_capabilities.services_raw_text / services_implied / services_removed /
--      services_rewritten_at -- the supplier's own words as typed (audit), the implied services it
--      KEPT, the implied services it REMOVED, and when it confirmed the rewrite. `services` stays what
--      it always was: the confirmed list the supplier STATED.
--   4. public.fn_services_effective -- stated + implied - removed, one level, the one definition both
--      matching and the portal answer from.
--   5. public.fn_match_capability gains p_services and two output columns (service_hits,
--      via_implication). When an inquiry names no service the function behaves exactly as before.
--      The trade gate, the confirm gate, the role gate, the authority gate and the value gate are
--      untouched, and there is still no nearest/fuzzy mapping anywhere (founder, 14 Sep 2026).
--
-- WHAT THIS DOES NOT CHANGE: fn_norm_trades, taxonomy_trade_proposal, capabilityConfirm and the
-- versioned ledger in supplier_capability_confirmation, the voice flag
-- decision_policy.supplier_voice_input_enabled (still OFF -- OpenRouter is on hold).

-- ── 1. THE ALIASES THAT NAME A SERVICE ────────────────────────────────────────────────────────────
alter table public.taxonomy_trade_service
  add column if not exists aliases text[] not null default '{}'::text[];
comment on column public.taxonomy_trade_service.aliases is
  'Exact EN+AR phrases that NAME this service in a supplier''s own sentence. Read by _shared/service_rewrite.ts through the trade matcher''s folding (word-start anchored, Arabic normalised, longest alias wins). Exact or none -- never a stem, never a neighbour. Seat: sales_engineer.';

-- The founder''s own example ("someone who does decoration") needs a decoration service to state.
insert into public.taxonomy_trade_service (trade_code, code, label_en, label_ar, sort)
values ('interior_fitout','decoration','Interior decoration','الديكور الداخلي',25)
on conflict (trade_code, code) do nothing;

with seed(trade_code, code, aliases) as (values
  ('hvac','supply_install', array['ac installation','ac supply','air conditioning installation','air conditioner installation','split ac','ac unit','air conditioning unit','package unit','تركيب مكيف','توريد مكيف','تركيب تكييف','مكيف سبليت','مكيفات سبليت','وحدات تكييف','وحدة تكييف','مكيف سبلت']::text[]),
  ('hvac','vrf_chiller', array['vrf','vrv','chiller','chilled water system','تشيلر','شيلر','انظمة vrf','نظام vrf','تكييف مركزي']::text[]),
  ('hvac','ducting', array['ducting','ductwork','duct work','ventilation','exhaust fan','fresh air system','مجاري هواء','مجرى هواء','دكت','دكتات','تهوية','مراوح شفط']::text[]),
  ('hvac','maintenance_amc', array['ac maintenance','hvac maintenance','air conditioning maintenance','ac repair','ac servicing','ac amc','chiller maintenance','chiller overhaul','صيانة مكيف','صيانة تكييف','تصليح مكيف','صيانة تشيلر','عقد صيانة تكييف','عقود صيانة تكييف','تنظيف مكيفات','غسيل مكيفات']::text[]),
  ('hvac','testing_commissioning', array['hvac testing','hvac commissioning','air balancing','hvac balancing','اختبار وتشغيل تكييف','موازنة هواء','اختبار انظمة تكييف']::text[]),
  ('electrical','wiring_install', array['electrical installation','electrical wiring','wiring','electrical works','electrical fit out','تمديدات كهربائية','تمديدات كهرباء','تركيبات كهربائية','اعمال كهربائية','اعمال كهرباء','تمديد كهرباء']::text[]),
  ('electrical','db_panels', array['distribution board','db panel','switchgear','mdb','smdb','electrical panel','panel board','لوحات توزيع','لوحة توزيع','لوحات كهربائية','لوحة كهربائية','سويتش جير','لوحة كهرباء','لوحات كهرباء رئيسية']::text[]),
  ('electrical','lighting', array['lighting','light fitting','light fixture','led light','luminaire','انارة','اضاءة','كشافات','ثريات']::text[]),
  ('electrical','cable_tray', array['cable tray','cable trunking','trunking','cable ladder','containment','conduit','حوامل كابلات','حامل كابلات','مجاري كابلات','ترنك كابلات','مواسير كهرباء']::text[]),
  ('electrical','maintenance', array['electrical maintenance','electrical repair','صيانة كهربائية','صيانة كهرباء','تصليح كهرباء']::text[]),
  ('building_materials','cement_concrete', array['cement','ready mix','readymix','concrete supply','اسمنت','خرسانة جاهزة','باطون']::text[]),
  ('building_materials','blocks_bricks', array['block','brick','hollow block','solid block','طابوق','بلوك','طوب']::text[]),
  ('building_materials','aggregates', array['sand','aggregate','gravel','crushed stone','رمل','ركام','حصى','بحص']::text[]),
  ('building_materials','steel_rebar', array['rebar','reinforcement steel','reinforcing steel','steel bar','reinforcing bar','tmt bar','حديد تسليح','سيخ حديد','اسياخ حديد']::text[]),
  ('building_materials','sanitary_ware', array['sanitary ware','sanitaryware','sanitary supply','bathroom fittings','wash basin','ادوات صحية','مغاسل','كراسي حمام','اطقم حمام']::text[]),
  ('engineering_consultancy','architectural_design', array['architectural design','architecture','architect','تصميم معماري','تصاميم معمارية','هندسة معمارية','مخططات معمارية']::text[]),
  ('engineering_consultancy','structural_design', array['structural design','structural engineering','structural calculation','تصميم انشائي','تصاميم انشائية','هندسة انشائية','حسابات انشائية']::text[]),
  ('engineering_consultancy','mep_design', array['mep design','mep engineering','electromechanical design','تصميم كهروميكانيكي','تصميم اعمال كهروميكانيكية','تصميم كهروميكانيك']::text[]),
  ('engineering_consultancy','supervision', array['site supervision','construction supervision','project supervision','supervision consultant','اشراف على تنفيذ','اشراف هندسي','اشراف على مشاريع','اشراف موقع']::text[]),
  ('engineering_consultancy','authority_approvals', array['authority approval','building permit','municipality approval','permit drawing','رخصة بناء','رخص بناء','تصاريح بناء','موافقات بلدية','موافقات حكومية','تصاريح حكومية']::text[]),
  ('power_generators','generator_supply', array['generator supply','diesel generator','genset','generator sale','توريد مولد','مولد ديزل','مولدات ديزل','بيع مولد']::text[]),
  ('power_generators','generator_rental', array['generator rental','generator hire','rent generator','تأجير مولد','ايجار مولد','مولدات للايجار']::text[]),
  ('power_generators','ups', array['ups system','ups unit','ups battery','uninterruptible power','يو بي اس','طاقة غير منقطعة','مزود طاقة احتياطي','يوبي اس']::text[]),
  ('power_generators','generator_maintenance', array['generator maintenance','generator repair','generator service','صيانة مولد','تصليح مولد']::text[]),
  ('power_generators','ats_panels', array['ats panel','automatic transfer switch','changeover switch','changeover panel','synchronizing panel','لوحة تحويل','لوحات تحويل','مفتاح تحويل','تحويل اوتوماتيكي']::text[]),
  ('heavy_equipment','equipment_rental', array['equipment rental','equipment hire','plant hire','machinery rental','forklift','تأجير معدات','ايجار معدات','معدات للايجار','تأجير اليات','رافعة شوكية','رافعات شوكية']::text[]),
  ('heavy_equipment','crane_hire', array['crane','crane hire','crane rental','mobile crane','tower crane','رافعة','رافعات','كرين','كرينات','ونش']::text[]),
  ('heavy_equipment','earthmoving', array['earthmoving','earth moving','excavator','bulldozer','jcb','wheel loader','حفارات','حفارة','شيول','بلدوزر','جرافة','نقل اتربة','تسوية اراضي']::text[]),
  ('heavy_equipment','equipment_sales', array['equipment sales','equipment for sale','used equipment','machinery sales','بيع معدات','بيع اليات','معدات مستعملة']::text[]),
  ('heavy_equipment','with_operator', array['with operator','with driver','operated rental','wet hire','مع مشغل','مع سائق']::text[]),
  ('plumbing','water_supply', array['water supply piping','water piping','water line','water supply line','تمديدات مياه','مواسير مياه','تمديد مياه','امدادات مياه']::text[]),
  ('plumbing','drainage', array['drainage','sewerage','sewage','drain line','manhole','صرف صحي','مجاري','تصريف','غرف تفتيش','تسليك مجاري','بيارات']::text[]),
  ('plumbing','sanitary_fixtures', array['sanitary fixture','sanitary installation','toilet installation','bathroom installation','تركيب ادوات صحية','تركيب اطقم حمام','تركيب مغاسل','تركيب كراسي حمام']::text[]),
  ('plumbing','heaters_pumps', array['water heater','geyser','water pump','booster pump','transfer pump','سخان مياه','سخانات مياه','مضخة مياه','مضخات مياه','غطاس']::text[]),
  ('plumbing','maintenance', array['plumbing maintenance','plumbing repair','leak repair','leak detection','صيانة سباكة','صيانة صحية','تصليح تسريب','كشف تسريب']::text[]),
  ('labour_supply','skilled', array['skilled labour','skilled labor','skilled worker','skilled manpower','tradesmen','عمالة فنية','عمال فنيين','عمالة ماهرة']::text[]),
  ('labour_supply','general', array['general labour','general labor','helpers','unskilled labour','labourers','عمالة عامة','عمال عاديين','عمالة عادية']::text[]),
  ('labour_supply','hourly', array['hourly labour','hourly labor','hourly workers','hourly manpower','labour on hourly','عمالة بالساعة','عمال بالساعة','تأجير عمالة بالساعة','عمالة يومية']::text[]),
  ('labour_supply','project_manpower', array['manpower supply','manpower contract','project manpower','عقود عمالة','توريد قوى عاملة','قوى عاملة للمشاريع']::text[]),
  ('labour_supply','supervisors', array['foreman','foremen','site supervisor','labour supervisor','فورمن','مراقب عمال','مشرف موقع','مشرفين','مراقبين']::text[]),
  ('safety_equipment','ppe', array['ppe','personal protective','safety helmet','safety shoes','safety gloves','safety glasses','hard hat','معدات وقاية','خوذ','خوذة','احذية سلامة','قفازات']::text[]),
  ('safety_equipment','fall_protection', array['fall protection','safety harness','harness','lifeline','fall arrest','حماية من سقوط','حزام امان','احزمة امان']::text[]),
  ('safety_equipment','signs_barriers', array['safety sign','safety barrier','traffic cone','barricade','road barrier','warning sign','لافتات سلامة','لوحات سلامة','حواجز سلامة','اقماع مرور','حواجز طرق']::text[]),
  ('safety_equipment','first_aid', array['first aid','اسعافات اولية','اسعاف اولي','صندوق اسعاف']::text[]),
  ('safety_equipment','workwear', array['workwear','uniform','coverall','boiler suit','hi vis','high visibility','ملابس عمل','زي موحد','يونيفورم','افرول','اوفرول']::text[]),
  ('solar','pv_install', array['solar pv','solar panel','pv system','photovoltaic','solar installation','solar power system','ألواح شمسية','لوح شمسي','انظمة كهروضوئية','خلايا شمسية','تركيب طاقة شمسية']::text[]),
  ('solar','water_heaters', array['solar water heater','solar heater','solar hot water','سخان شمسي','سخانات شمسية','سخان مياه شمسي']::text[]),
  ('solar','battery_storage', array['battery storage','battery system','energy storage','lithium battery','bess','تخزين بطاريات','بطاريات تخزين','تخزين طاقة','بطاريات ليثيوم']::text[]),
  ('solar','grid_connection', array['grid connection','grid tie','net metering','shams dubai','ربط بالشبكة','ربط بشبكة','شمس دبي']::text[]),
  ('solar','maintenance', array['solar maintenance','solar panel cleaning','pv maintenance','pv cleaning','panel cleaning','صيانة ألواح شمسية','تنظيف ألواح شمسية','صيانة طاقة شمسية','تنظيف ألواح']::text[]),
  ('chemicals','construction_chemicals', array['construction chemical','grout','repair mortar','curing compound','bonding agent','كيماويات انشائية','كيماويات بناء','جراوت']::text[]),
  ('chemicals','adhesives_sealants', array['adhesive','sealant','silicone','tile adhesive','glue','مواد لاصقة','لاصق','غراء','سيليكون','مانع تسرب','مانعات تسرب']::text[]),
  ('chemicals','coatings', array['coating supply','coating material','paint supply','مواد طلاء','توريد طلاءات','توريد دهانات']::text[]),
  ('chemicals','admixtures', array['admixture','concrete additive','plasticizer','superplasticizer','اضافات خرسانة','ملدنات']::text[]),
  ('chemicals','cleaning_chemicals', array['cleaning chemical','industrial cleaner','detergent','degreaser','كيماويات تنظيف','مواد تنظيف','منظفات']::text[]),
  ('plastics_pipes','pvc_pipes', array['pvc pipe','upvc pipe','pvc fitting','upvc fitting','انابيب pvc','مواسير pvc','انابيب بي في سي']::text[]),
  ('plastics_pipes','hdpe_pipes', array['hdpe','انابيب hdpe','مواسير hdpe','بولي ايثيلين']::text[]),
  ('plastics_pipes','ppr_pipes', array['ppr','انابيب ppr','مواسير ppr']::text[]),
  ('plastics_pipes','water_tanks', array['water tank','grp tank','storage tank','plastic tank','خزان مياه','خزانات مياه','خزان ماء','تانكي']::text[]),
  ('plastics_pipes','custom_moulding', array['plastic manufacturing','injection moulding','injection molding','custom plastic','rotomoulding','تصنيع بلاستيك','قوالب بلاستيك','حقن بلاستيك']::text[]),
  ('oilfield','valves_fittings', array['valve','gate valve','ball valve','pipe fitting','صمامات','صمام','محابس','وصلات انابيب']::text[]),
  ('oilfield','pipes_flanges', array['flange','steel pipe','carbon steel pipe','seamless pipe','فلنجات','انابيب حديد','انابيب فولاذ','فلنج']::text[]),
  ('oilfield','instrumentation', array['instrumentation','pressure gauge','flow meter','transmitter','control instrument','اجهزة قياس','عدادات','حساسات']::text[]),
  ('oilfield','consumables', array['industrial consumable','consumables','welding rod','gasket','fastener','مستهلكات صناعية','مستهلكات','جوانات','مسامير وبراغي']::text[]),
  ('oilfield','rotating_equipment', array['rotating equipment','centrifugal pump','compressor','industrial pump','معدات دوارة','ضواغط','كمبروسر','مضخات صناعية','كومبريسر']::text[]),
  ('home_automation','smart_home', array['smart home','home automation','knx','smart system','منزل ذكي','منازل ذكية','بيت ذكي','اتمتة منزل','انظمة ذكية']::text[]),
  ('home_automation','bms', array['bms','building management system','building automation','ادارة مباني','نظام ادارة مبنى','اتمتة مباني']::text[]),
  ('home_automation','lighting_control', array['lighting control','dimming','lighting automation','تحكم بالانارة','تحكم بالاضاءة','تحكم في اضاءة','تحكم في انارة']::text[]),
  ('home_automation','intercom', array['intercom','door entry','video door phone','door phone','انتركم','جرس باب','هاتف باب']::text[]),
  ('home_automation','integration', array['system integration','av programming','control programming','crestron','control4','برمجة انظمة','تكامل انظمة','برمجة وتكامل']::text[]),
  ('logistics_moving','moving', array['moving','movers','relocation','house moving','office moving','packers','نقل اثاث','نقل عفش','نقل مكاتب','نقل منازل']::text[]),
  ('logistics_moving','storage', array['storage','warehousing','warehouse','self storage','تخزين','مستودعات','مستودع','مخازن']::text[]),
  ('logistics_moving','freight', array['freight','shipping','cargo','sea freight','air freight','شحن','شحن بحري','شحن جوي']::text[]),
  ('logistics_moving','customs', array['customs clearance','customs broker','clearance','تخليص جمركي','تخليص','جمارك']::text[]),
  ('logistics_moving','site_delivery', array['site delivery','delivery to site','transport','trucking','lorry','توصيل','نقل مواد','نقل الى موقع','شاحنات نقل']::text[]),
  ('packaging','cartons', array['carton','corrugated','cardboard','packaging box','shipping box','كراتين','كرتون','صناديق كرتون']::text[]),
  ('packaging','protective', array['protective packaging','bubble wrap','foam packaging','packing material','تغليف واقي','فقاعات تغليف','مواد تغليف']::text[]),
  ('packaging','printing', array['commercial printing','offset printing','printing press','brochure printing','business card','طباعة تجارية','طباعة اوفست','مطبعة','طباعة بروشورات']::text[]),
  ('packaging','labels', array['label','sticker','ملصقات','ستيكر','ليبل']::text[]),
  ('packaging','pallets_wrapping', array['pallet','stretch film','shrink wrap','strapping','طبليات','منصات خشبية','باليت','تغليف بالنايلون','ستريتش']::text[]),
  ('marine','ship_supply', array['ship supply','ship chandler','chandlery','ship provision','تموين سفن','مؤن سفن']::text[]),
  ('marine','marine_equipment', array['marine equipment','boat equipment','mooring equipment','navigation equipment','معدات بحرية','معدات قوارب','مراسي']::text[]),
  ('marine','marine_works', array['marine construction','marine works','jetty','quay wall','breakwater','dredging','اعمال بحرية','انشاءات بحرية','ارصفة بحرية','كاسر امواج','تجريف']::text[]),
  ('marine','diving', array['diving','underwater','subsea inspection','commercial diving','غوص','تحت ماء','غواصين']::text[]),
  ('marine','offshore', array['offshore','offshore supply','platform supply','rig supply','امدادات بحرية','منصات بحرية','امداد منصات','اوفشور']::text[]),
  ('it_services','network_install', array['network installation','networking','wifi','wi fi','wireless network','network setup','تركيب شبكات','شبكات حاسوب','شبكات كمبيوتر','شبكات انترنت','واي فاي','تمديد شبكات']::text[]),
  ('it_services','structured_cabling', array['structured cabling','cat6','cat 6','fiber optic','fibre optic','network cabling','كابلات مهيكلة','كوابل شبكات','ألياف ضوئية']::text[]),
  ('it_services','it_support', array['it support','it maintenance','helpdesk','computer repair','دعم فني','دعم تقني','صيانة كمبيوتر','صيانة حاسوب']::text[]),
  ('it_services','cybersecurity', array['cybersecurity','cyber security','firewall','penetration testing','information security','امن سيبراني','امن معلومات','جدار ناري','حماية شبكات']::text[]),
  ('it_services','hardware_supply', array['hardware supply','computer supply','laptop','server supply','it hardware','توريد اجهزة كمبيوتر','توريد حواسيب','اجهزة كمبيوتر','لابتوب']::text[]),
  ('fire_fighting','fire_alarm', array['fire alarm','smoke detector','fire detection','انذار حريق','كواشف دخان','كاشف دخان']::text[]),
  ('fire_fighting','sprinklers', array['fire sprinkler','sprinkler system','fm200','fm 200','suppression system','رشاشات حريق','مرشات حريق','اطفاء تلقائي','رشاشات']::text[]),
  ('fire_fighting','fire_pumps', array['fire pump','jockey pump','مضخات حريق','مضخة حريق']::text[]),
  ('fire_fighting','extinguishers', array['fire extinguisher','extinguisher','fire blanket','طفايات','طفاية','طفايات حريق']::text[]),
  ('fire_fighting','civil_defence', array['civil defence','civil defense','fire safety approval','fire system maintenance','دفاع مدني','موافقات دفاع مدني','صيانة انظمة حريق']::text[]),
  ('joinery','kitchens', array['kitchen','kitchen cabinet','مطابخ','مطبخ','تفصيل مطابخ']::text[]),
  ('joinery','wardrobes', array['wardrobe','closet','walk in closet','خزائن','دواليب','خزانة ملابس','كبت','كبتات']::text[]),
  ('joinery','wooden_doors', array['wooden door','wood door','timber door','ابواب خشب','باب خشب']::text[]),
  ('joinery','custom_furniture', array['custom furniture','furniture manufacturing','bespoke furniture','furniture','اثاث حسب طلب','تصنيع اثاث','اثاث','موبيليا']::text[]),
  ('joinery','wood_panelling', array['wood panelling','wood paneling','wooden cladding','timber cladding','تكسية خشبية','تكسيات خشب','تجاليد خشب','بانوهات خشب']::text[]),
  ('glazing','tempered_laminated', array['tempered glass','laminated glass','toughened glass','double glazing','glass supply','زجاج مقسى','زجاج سيكوريت','سكوريت','زجاج مصفح','زجاج مزدوج']::text[]),
  ('glazing','partitions', array['glass partition','shower glass','shower enclosure','shower screen','قواطع زجاج','فواصل زجاج','كابينة شاور','شاور زجاج','بارتيشن زجاج']::text[]),
  ('glazing','mirrors', array['mirror','مرايا','مراية','مرآة']::text[]),
  ('glazing','frameless', array['frameless glass','frameless glazing','frameless door','glass balustrade','زجاج بدون اطار','زجاج بدون برواز','درابزين زجاج']::text[]),
  ('glazing','glass_facades', array['glass facade','glass façade','glazed facade','structural glazing','واجهات زجاجية','واجهة زجاج','واجهات زجاج']::text[]),
  ('aluminium','windows_doors', array['aluminium window','aluminum window','aluminium door','aluminum door','نوافذ ألمنيوم','شبابيك ألمنيوم','ابواب ألمنيوم','باب ألمنيوم','نافذة ألمنيوم']::text[]),
  ('aluminium','acp_cladding', array['acp','acp cladding','aluminium composite','aluminum composite','composite panel','تكسية acp','ألواح مركبة','كلادينج']::text[]),
  ('aluminium','curtain_wall', array['curtain wall','curtain walling','unitized facade','حوائط ستائرية','حائط ستائري','كيرتن وول']::text[]),
  ('aluminium','louvres', array['louvre','louver','لوفر','لوفرات']::text[]),
  ('aluminium','pergolas_shades', array['pergola','shade structure','car park shade','car shade','sun shade','برجولات','برجولة','مظلات','مظلة','مظلات سيارات','سواتر']::text[]),
  ('steel','structural_steel', array['structural steel','steel structure','steel building','pre engineered building','steel frame','هياكل حديد','هياكل فولاذية','هيكل حديدي','منشآت حديدية','مباني حديد']::text[]),
  ('steel','fabrication_welding', array['fabrication','welding','metal fabrication','steel fabrication','metal works','blacksmith','لحام','حدادة','تشكيل معادن','اعمال حدادة','تصنيع معادن']::text[]),
  ('steel','handrails', array['handrail','balustrade','railing','درابزين','درابزينات','حاجز درج']::text[]),
  ('steel','stainless', array['stainless steel','stainless','ستانلس','ستانلس ستيل']::text[]),
  ('steel','gates_fencing', array['gate','fence','fencing','steel gate','بوابات','بوابة','اسوار','سياج','شبوك','سياج شبك']::text[]),
  ('flooring','tiling', array['tiling','tile','ceramic','porcelain','تبليط','بلاط','سيراميك','بورسلان','بورسلين']::text[]),
  ('flooring','marble_granite', array['marble','granite','natural stone','terrazzo','رخام','جرانيت','غرانيت','حجر طبيعي','تيرازو','تلميع رخام','جلي رخام']::text[]),
  ('flooring','parquet_vinyl', array['parquet','vinyl','laminate flooring','wooden flooring','wood flooring','spc flooring','باركيه','فينيل','ارضيات خشب','ارضيات خشبية']::text[]),
  ('flooring','epoxy', array['epoxy','epoxy flooring','epoxy floor','resin flooring','ايبوكسي','ارضيات ايبوكسي','ارضيات ريزن']::text[]),
  ('flooring','carpet', array['carpet','rug','سجاد','سجادة','موكيت']::text[]),
  ('painting','interior', array['interior painting','interior paint','wall painting','internal painting','دهان داخلي','دهانات داخلية','صبغ داخلي']::text[]),
  ('painting','exterior', array['exterior painting','external painting','facade painting','دهان خارجي','دهانات خارجية','دهان واجهات']::text[]),
  ('painting','decorative', array['decorative finish','decorative paint','texture paint','stucco','venetian plaster','دهانات ديكورية','دهان ديكوري','تشطيبات ديكور']::text[]),
  ('painting','protective_coating', array['protective coating','industrial coating','industrial painting','anti corrosion','epoxy coating','طلاءات واقية','طلاء واقي','دهانات صناعية','دهان صناعي','طلاء صناعي']::text[]),
  ('painting','repainting', array['repainting','repaint','touch up','اعادة دهان','ترميم دهان']::text[]),
  ('gypsum','false_ceiling', array['false ceiling','suspended ceiling','gypsum ceiling','drop ceiling','dropped ceiling','أسقف معلقة','سقف معلق','أسقف مستعارة','سقف مستعار','أسقف جبس','سقف جبس']::text[]),
  ('gypsum','partitions', array['gypsum partition','gypsum board partition','drywall','dry wall','gypsum board','stud partition','قواطع جبس','قواطع جبسية','جدران جبس','جبس بورد','جبسن بورد','جيبسوم بورد']::text[]),
  ('gypsum','plastering', array['plastering','plaster','لياسة','محارة']::text[]),
  ('gypsum','decorative', array['decorative gypsum','gypsum decoration','cornice','gypsum cornice','جبس ديكور','ديكور جبس','جبس ديكوري','كرانيش','كورنيش جبس']::text[]),
  ('gypsum','acoustic_ceiling', array['acoustic ceiling','acoustic tile','ceiling tile','mineral fiber ceiling','أسقف صوتية','سقف صوتي','بلاطات سقف']::text[]),
  ('signage','shop_signs', array['shop sign','signboard','sign board','storefront sign','لافتات محلات','لوحات محلات','لوحة محل','يافطات','يافطة']::text[]),
  ('signage','letters_3d', array['3d letter','acrylic letter','channel letter','3d sign','حروف بارزة','حروف اكريليك','حروف ثلاثية ابعاد','حروف مضيئة']::text[]),
  ('signage','wayfinding', array['wayfinding','directional sign','directory sign','لافتات ارشادية','لوحات ارشادية','لافتات ارشاد']::text[]),
  ('signage','lightbox', array['light box','lightbox','illuminated sign','صناديق مضيئة','صندوق مضيء','لوحات مضيئة']::text[]),
  ('signage','large_format', array['large format','banner printing','vinyl printing','flex printing','roll up','طباعة كبيرة','طباعة بنرات','بنرات','طباعة فلكس','طباعة فينيل']::text[]),
  ('landscaping','softscape', array['softscape','planting','plantation','tree planting','grass','lawn','زراعة','تشجير','عشب','نجيل']::text[]),
  ('landscaping','hardscape', array['hardscape','paving','interlock','kerb stone','pathway','انترلوك','بلاط حدائق','ممرات حدائق','رصف','تبليط حدائق']::text[]),
  ('landscaping','irrigation', array['irrigation','drip irrigation','garden sprinkler','sprinkler irrigation','انظمة ري','نظام ري','شبكات ري','ري بالتنقيط','رشاشات ري']::text[]),
  ('landscaping','pools', array['swimming pool','pool','مسابح','مسبح','حمامات سباحة','برك سباحة']::text[]),
  ('landscaping','maintenance', array['garden maintenance','landscape maintenance','gardening','gardener','صيانة حدائق','بستنة']::text[]),
  ('security_systems','cctv', array['cctv','camera','surveillance','security camera','كاميرات مراقبة','كاميرات','كاميرا','كاميرات أمنية']::text[]),
  ('security_systems','access_control', array['access control','biometric','card reader','door access','تحكم بالدخول','تحكم في دخول','بصمة','اكسس كنترول']::text[]),
  ('security_systems','barriers_turnstiles', array['gate barrier','boom barrier','turnstile','parking barrier','road blocker','بوابات دوارة','بوابة دوارة','حاجز سيارات','حواجز مواقف','بوم باريير','حاجز بوابة']::text[]),
  ('security_systems','intruder_alarm', array['intruder alarm','burglar alarm','security alarm','انذار سرقة','جرس انذار']::text[]),
  ('security_systems','guarding', array['security guard','guarding','watchman','security service','حراسة','حراس امن','حارس امن','خدمات امنية']::text[]),
  ('elevators','supply_install', array['elevator installation','lift installation','elevator supply','lift supply','passenger lift','تركيب مصاعد','توريد مصاعد','تركيب مصعد','مصاعد ركاب']::text[]),
  ('elevators','escalators', array['escalator','travelator','moving walkway','سلالم متحركة','سلم متحرك','ممرات متحركة']::text[]),
  ('elevators','maintenance', array['elevator maintenance','lift maintenance','elevator amc','lift repair','صيانة مصاعد','صيانة مصعد','عقود صيانة مصاعد']::text[]),
  ('elevators','modernisation', array['elevator modernisation','elevator modernization','lift modernisation','lift upgrade','تحديث مصاعد','تطوير مصاعد']::text[]),
  ('elevators','home_lifts', array['home lift','home elevator','villa lift','residential lift','مصاعد منازل','مصعد منزلي','مصاعد فلل','مصعد فيلا']::text[]),
  ('doors','wooden_doors', array['wooden door','wood door','timber door','ابواب خشب','باب خشب']::text[]),
  ('doors','fire_doors', array['fire door','fire rated door','أبواب مقاومة للحريق','باب مقاوم للحريق','ابواب حريق','ابواب ضد حريق']::text[]),
  ('doors','automatic_doors', array['automatic door','auto door','sensor door','sliding door operator','ابواب اوتوماتيكية','ابواب اوتوماتيك','باب اوتوماتيك','ابواب سنسور']::text[]),
  ('doors','shutters', array['rolling shutter','roller shutter','shutter','شتر','شترات','رول شتر','ابواب رول']::text[]),
  ('doors','ironmongery', array['ironmongery','door hardware','door handle','hinge','door lock','اكسسوارات ابواب','مقابض ابواب','مفصلات','اقفال ابواب','كوالين']::text[]),
  ('waterproofing','roof', array['roof waterproofing','roof insulation','roofing membrane','عزل اسطح','عزل سطح','عزل مائي للاسطح','عزل فوم']::text[]),
  ('waterproofing','basement', array['basement waterproofing','foundation waterproofing','tanking','عزل قبو','عزل اساسات','عزل بدروم']::text[]),
  ('waterproofing','wet_areas', array['wet area waterproofing','bathroom waterproofing','shower waterproofing','عزل حمامات','عزل مناطق رطبة']::text[]),
  ('waterproofing','thermal', array['thermal insulation','heat insulation','عزل حراري','عزل حرارة']::text[]),
  ('waterproofing','acoustic', array['acoustic insulation','sound insulation','soundproofing','عزل صوتي','عزل صوت']::text[]),
  ('upholstery','curtains', array['curtain','ستائر','ستارة','برادي']::text[]),
  ('upholstery','blinds', array['blind','roller blind','ستائر رول','رول بلايند','ستائر شرائح','بلايند']::text[]),
  ('upholstery','sofa', array['sofa','furniture upholstery','reupholstery','couch','تنجيد كنب','تنجيد اثاث','كنب']::text[]),
  ('upholstery','majlis', array['majlis','arabic seating','مجالس','مجلس عربي','تفصيل مجالس','تنجيد مجالس']::text[]),
  ('upholstery','fabric_supply', array['fabric','textile','upholstery fabric','اقمشة','قماش','اقمشة تنجيد']::text[]),
  ('wallpaper','supply_install', array['wallpaper','wall paper','ورق جدران','ورق حائط','ورق جدار','خلفيات جدران']::text[]),
  ('wallpaper','wall_panels', array['wall panel','wpc panel','3d panel','decorative panel','ألواح جدران','ألواح حائط','بانوهات']::text[]),
  ('wallpaper','wall_cladding', array['wall cladding','pvc cladding','تكسية جدران','تكسيات جدران','تكسية حوائط']::text[]),
  ('wallpaper','murals', array['mural','wall art','جداريات','جدارية','رسم جداري']::text[]),
  ('wallpaper','removal', array['wallpaper removal','remove wallpaper','ازالة ورق جدران']::text[]),
  ('scaffolding','rental', array['scaffolding rental','scaffolding hire','scaffold hire','scaffold rental','تأجير سقالات','ايجار سقالات','سقالات للايجار']::text[]),
  ('scaffolding','erection', array['scaffold erection','scaffolding erection','scaffolding installation','scaffold dismantling','تركيب سقالات','فك وتركيب سقالات','تركيب وفك سقالات']::text[]),
  ('scaffolding','formwork_shoring', array['formwork','shoring','shuttering','شدات','طوبار','دعامات','قوالب خرسانة']::text[]),
  ('scaffolding','access_platforms', array['access platform','scissor lift','boom lift','manlift','cradle','رافعة مقصية','سلة رفع','منصة عمل','مان لفت','بوم لفت']::text[]),
  ('scaffolding','inspection', array['scaffold inspection','scaffolding inspection','scaffold tagging','فحص سقالات','تفتيش سقالات']::text[]),
  ('cleaning','deep_cleaning', array['deep cleaning','deep clean','villa cleaning','sanitization','تنظيف عميق','تعقيم','تنظيف فلل']::text[]),
  ('cleaning','post_construction', array['post construction cleaning','after construction cleaning','builders clean','تنظيف بعد بناء','تنظيف بعد تشطيب','تنظيف ما بعد بناء']::text[]),
  ('cleaning','facade_windows', array['facade cleaning','window cleaning','glass cleaning','rope access cleaning','تنظيف واجهات','تنظيف نوافذ','تنظيف زجاج']::text[]),
  ('cleaning','pest_control', array['pest control','fumigation','termite','مكافحة حشرات','مكافحة افات','رش مبيدات','مكافحة قوارض','بق الفراش']::text[]),
  ('cleaning','facility_management', array['facility management','facilities management','fm services','ادارة مرافق']::text[]),
  ('av_it','audio_visual', array['audio visual','av system','sound system','projector','video wall','انظمة صوت','صوتيات','شاشات عرض','بروجكتر']::text[]),
  ('av_it','public_address', array['public address','pa system','background music','paging system','اذاعة داخلية','نظام اذاعة','سماعات سقف']::text[]),
  ('av_it','data_cabling', array['data cabling','data cable','utp cabling','كابلات بيانات','كابلات داتا']::text[]),
  ('av_it','telecom', array['telecom','telephone system','pabx','ip phone','اتصالات','سنترال','بدالة']::text[]),
  ('av_it','satellite_iptv', array['satellite','iptv','smatv','ستلايت','ساتلايت','تلفزيون مركزي','اطباق ستلايت','دش ستلايت']::text[]),
  ('interior_fitout','decoration', array['interior decoration','decoration','decor','interior decor','interior decorator','ديكور داخلي','ديكور','ديكورات','اعمال ديكور']::text[]),
  ('interior_fitout','turnkey', array['turnkey','turn key','complete fit out','full fit out','تسليم مفتاح','تجهيز متكامل','تشطيب متكامل']::text[]),
  ('interior_fitout','office', array['office fit out','office fitout','office interior','office renovation','تجهيز مكاتب','تشطيب مكاتب','ديكور مكاتب']::text[]),
  ('interior_fitout','retail', array['retail fit out','retail fitout','shop fit out','shop fitout','restaurant fit out','تجهيز محلات','تشطيب محلات','ديكور محلات','تجهيز مطاعم']::text[]),
  ('interior_fitout','interior_design', array['interior design','interior designer','تصميم داخلي','تصميم ديكور','تصاميم داخلية']::text[]),
  ('interior_fitout','refurbishment', array['refurbishment','renovation','remodeling','remodelling','ترميم','تجديد','اعادة تأهيل']::text[]),
  ('civil_works','new_construction', array['new construction','building construction','villa construction','general contracting','main contractor','انشاء مباني','بناء فلل','مقاولات بناء','مقاولات عامة','بناء مباني']::text[]),
  ('civil_works','concrete', array['concrete works','concrete work','concrete casting','rcc','اعمال خرسانة','اعمال خرسانية','صب خرسانة','خرسانة مسلحة']::text[]),
  ('civil_works','blockwork', array['blockwork','block work','masonry','brickwork','اعمال طابوق','اعمال بلوك','بناء طابوق','بناء بلوك']::text[]),
  ('civil_works','demolition', array['demolition','strip out','هدم','تكسير']::text[]),
  ('civil_works','excavation', array['excavation','backfilling','backfill','earthworks','حفر وردم','حفريات','ردم','اعمال حفر']::text[]),
  ('mep_general','mep_install', array['mep installation','mep works','mep contracting','mep contractor','electromechanical works','اعمال كهروميكانيكية','تنفيذ كهروميكانيك','مقاولات كهروميكانيك']::text[]),
  ('mep_general','mep_maintenance', array['mep maintenance','building maintenance','electromechanical maintenance','صيانة كهروميكانيكية','صيانة مباني','صيانة كهروميكانيك']::text[]),
  ('mep_general','testing_commissioning', array['mep testing','mep commissioning','testing and commissioning','testing & commissioning','اختبار وتشغيل','اختبار وتشغيل انظمة']::text[]),
  ('mep_general','shop_drawings', array['shop drawing','shop drawings','as built drawing','as-built','مخططات تنفيذية','رسومات تنفيذية','مخططات شوب']::text[]),
  ('mep_general','authority_approvals', array['mep approval','dewa approval','electricity authority approval','موافقات هيئة كهرباء','موافقات ديوا']::text[])
)
update public.taxonomy_trade_service t
   set aliases = s.aliases
  from seed s
 where t.trade_code = s.trade_code and t.code = s.code
   and t.aliases is distinct from s.aliases;

-- Every seeded key must be a live service, or the rewrite would quietly name something that is not
-- on the platform. This raises rather than skipping.
do $$
declare v_missing text;
begin
  select string_agg(k, ', ') into v_missing from (values
    ('hvac.supply_install'),
    ('hvac.vrf_chiller'),
    ('hvac.ducting'),
    ('hvac.maintenance_amc'),
    ('hvac.testing_commissioning'),
    ('electrical.wiring_install'),
    ('electrical.db_panels'),
    ('electrical.lighting'),
    ('electrical.cable_tray'),
    ('electrical.maintenance'),
    ('building_materials.cement_concrete'),
    ('building_materials.blocks_bricks'),
    ('building_materials.aggregates'),
    ('building_materials.steel_rebar'),
    ('building_materials.sanitary_ware'),
    ('engineering_consultancy.architectural_design'),
    ('engineering_consultancy.structural_design'),
    ('engineering_consultancy.mep_design'),
    ('engineering_consultancy.supervision'),
    ('engineering_consultancy.authority_approvals'),
    ('power_generators.generator_supply'),
    ('power_generators.generator_rental'),
    ('power_generators.ups'),
    ('power_generators.generator_maintenance'),
    ('power_generators.ats_panels'),
    ('heavy_equipment.equipment_rental'),
    ('heavy_equipment.crane_hire'),
    ('heavy_equipment.earthmoving'),
    ('heavy_equipment.equipment_sales'),
    ('heavy_equipment.with_operator'),
    ('plumbing.water_supply'),
    ('plumbing.drainage'),
    ('plumbing.sanitary_fixtures'),
    ('plumbing.heaters_pumps'),
    ('plumbing.maintenance'),
    ('labour_supply.skilled'),
    ('labour_supply.general'),
    ('labour_supply.hourly'),
    ('labour_supply.project_manpower'),
    ('labour_supply.supervisors'),
    ('safety_equipment.ppe'),
    ('safety_equipment.fall_protection'),
    ('safety_equipment.signs_barriers'),
    ('safety_equipment.first_aid'),
    ('safety_equipment.workwear'),
    ('solar.pv_install'),
    ('solar.water_heaters'),
    ('solar.battery_storage'),
    ('solar.grid_connection'),
    ('solar.maintenance'),
    ('chemicals.construction_chemicals'),
    ('chemicals.adhesives_sealants'),
    ('chemicals.coatings'),
    ('chemicals.admixtures'),
    ('chemicals.cleaning_chemicals'),
    ('plastics_pipes.pvc_pipes'),
    ('plastics_pipes.hdpe_pipes'),
    ('plastics_pipes.ppr_pipes'),
    ('plastics_pipes.water_tanks'),
    ('plastics_pipes.custom_moulding'),
    ('oilfield.valves_fittings'),
    ('oilfield.pipes_flanges'),
    ('oilfield.instrumentation'),
    ('oilfield.consumables'),
    ('oilfield.rotating_equipment'),
    ('home_automation.smart_home'),
    ('home_automation.bms'),
    ('home_automation.lighting_control'),
    ('home_automation.intercom'),
    ('home_automation.integration'),
    ('logistics_moving.moving'),
    ('logistics_moving.storage'),
    ('logistics_moving.freight'),
    ('logistics_moving.customs'),
    ('logistics_moving.site_delivery'),
    ('packaging.cartons'),
    ('packaging.protective'),
    ('packaging.printing'),
    ('packaging.labels'),
    ('packaging.pallets_wrapping'),
    ('marine.ship_supply'),
    ('marine.marine_equipment'),
    ('marine.marine_works'),
    ('marine.diving'),
    ('marine.offshore'),
    ('it_services.network_install'),
    ('it_services.structured_cabling'),
    ('it_services.it_support'),
    ('it_services.cybersecurity'),
    ('it_services.hardware_supply'),
    ('fire_fighting.fire_alarm'),
    ('fire_fighting.sprinklers'),
    ('fire_fighting.fire_pumps'),
    ('fire_fighting.extinguishers'),
    ('fire_fighting.civil_defence'),
    ('joinery.kitchens'),
    ('joinery.wardrobes'),
    ('joinery.wooden_doors'),
    ('joinery.custom_furniture'),
    ('joinery.wood_panelling'),
    ('glazing.tempered_laminated'),
    ('glazing.partitions'),
    ('glazing.mirrors'),
    ('glazing.frameless'),
    ('glazing.glass_facades'),
    ('aluminium.windows_doors'),
    ('aluminium.acp_cladding'),
    ('aluminium.curtain_wall'),
    ('aluminium.louvres'),
    ('aluminium.pergolas_shades'),
    ('steel.structural_steel'),
    ('steel.fabrication_welding'),
    ('steel.handrails'),
    ('steel.stainless'),
    ('steel.gates_fencing'),
    ('flooring.tiling'),
    ('flooring.marble_granite'),
    ('flooring.parquet_vinyl'),
    ('flooring.epoxy'),
    ('flooring.carpet'),
    ('painting.interior'),
    ('painting.exterior'),
    ('painting.decorative'),
    ('painting.protective_coating'),
    ('painting.repainting'),
    ('gypsum.false_ceiling'),
    ('gypsum.partitions'),
    ('gypsum.plastering'),
    ('gypsum.decorative'),
    ('gypsum.acoustic_ceiling'),
    ('signage.shop_signs'),
    ('signage.letters_3d'),
    ('signage.wayfinding'),
    ('signage.lightbox'),
    ('signage.large_format'),
    ('landscaping.softscape'),
    ('landscaping.hardscape'),
    ('landscaping.irrigation'),
    ('landscaping.pools'),
    ('landscaping.maintenance'),
    ('security_systems.cctv'),
    ('security_systems.access_control'),
    ('security_systems.barriers_turnstiles'),
    ('security_systems.intruder_alarm'),
    ('security_systems.guarding'),
    ('elevators.supply_install'),
    ('elevators.escalators'),
    ('elevators.maintenance'),
    ('elevators.modernisation'),
    ('elevators.home_lifts'),
    ('doors.wooden_doors'),
    ('doors.fire_doors'),
    ('doors.automatic_doors'),
    ('doors.shutters'),
    ('doors.ironmongery'),
    ('waterproofing.roof'),
    ('waterproofing.basement'),
    ('waterproofing.wet_areas'),
    ('waterproofing.thermal'),
    ('waterproofing.acoustic'),
    ('upholstery.curtains'),
    ('upholstery.blinds'),
    ('upholstery.sofa'),
    ('upholstery.majlis'),
    ('upholstery.fabric_supply'),
    ('wallpaper.supply_install'),
    ('wallpaper.wall_panels'),
    ('wallpaper.wall_cladding'),
    ('wallpaper.murals'),
    ('wallpaper.removal'),
    ('scaffolding.rental'),
    ('scaffolding.erection'),
    ('scaffolding.formwork_shoring'),
    ('scaffolding.access_platforms'),
    ('scaffolding.inspection'),
    ('cleaning.deep_cleaning'),
    ('cleaning.post_construction'),
    ('cleaning.facade_windows'),
    ('cleaning.pest_control'),
    ('cleaning.facility_management'),
    ('av_it.audio_visual'),
    ('av_it.public_address'),
    ('av_it.data_cabling'),
    ('av_it.telecom'),
    ('av_it.satellite_iptv'),
    ('interior_fitout.decoration'),
    ('interior_fitout.turnkey'),
    ('interior_fitout.office'),
    ('interior_fitout.retail'),
    ('interior_fitout.interior_design'),
    ('interior_fitout.refurbishment'),
    ('civil_works.new_construction'),
    ('civil_works.concrete'),
    ('civil_works.blockwork'),
    ('civil_works.demolition'),
    ('civil_works.excavation'),
    ('mep_general.mep_install'),
    ('mep_general.mep_maintenance'),
    ('mep_general.testing_commissioning'),
    ('mep_general.shop_drawings'),
    ('mep_general.authority_approvals')
  ) as want(k)
  where not exists (
    select 1 from public.taxonomy_trade_service s
    where s.trade_code || '.' || s.code = want.k and s.active
  );
  if v_missing is not null then
    raise exception 'service_aliases.json names services that are not active in taxonomy_trade_service: %', v_missing;
  end if;
end $$;

-- ── 2. THE CAPABILITY-IMPLICATION MAP ─────────────────────────────────────────────────────────────
-- Founder, instruction 439. Curated by the sales engineer, never derived, never inferred by a model.
-- One row = one relation + its reason. ONE LEVEL: the readers never follow a chain.
create table if not exists public.service_implication (
  from_code     text not null check (from_code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)?$'),
  implies_trade text not null,
  implies_code  text not null,
  reason_en     text not null check (btrim(reason_en) <> ''),
  reason_ar     text not null check (reason_ar ~ '[ء-ي]'),
  active        boolean not null default true,
  primary key (from_code, implies_trade, implies_code),
  foreign key (implies_trade, implies_code)
    references public.taxonomy_trade_service(trade_code, code) on update cascade on delete cascade,
  constraint service_implication_not_itself check (from_code <> implies_trade || '.' || implies_code)
);
comment on table public.service_implication is
  'What a stated capability ALSO covers, curated by the sales engineer with a reason in EN and AR (founder instruction 439, 15 Sep 2026). from_code is a taxonomy_trade code or a trade.service key. Applied ONE LEVEL ONLY by fn_services_effective and by impliedServices() in _shared/service_rewrite.ts -- an implied service never implies anything further. Seat: sales_engineer.';
comment on column public.service_implication.from_code is
  'A taxonomy_trade code (the supplier stated the trade) or a <trade>.<service> key (it stated the service).';

alter table public.service_implication enable row level security;
drop policy if exists service_implication_service_role_only on public.service_implication;
create policy service_implication_service_role_only on public.service_implication
  as permissive for all to public using (false) with check (false);
revoke all on public.service_implication from anon, authenticated;

insert into public.service_implication (from_code, implies_trade, implies_code, reason_en, reason_ar) values
  ('interior_fitout.decoration','flooring','tiling','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','flooring','parquet_vinyl','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','flooring','carpet','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','painting','interior','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','painting','decorative','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','gypsum','partitions','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','gypsum','false_ceiling','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','gypsum','decorative','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','wallpaper','supply_install','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','wallpaper','wall_panels','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','joinery','wood_panelling','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.decoration','upholstery','curtains','Interior decoration companies deliver these finishes as part of the work.','شركات الديكور الداخلي تنفّذ هذه التشطيبات ضمن أعمالها.'),
  ('interior_fitout.turnkey','flooring','tiling','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.turnkey','flooring','parquet_vinyl','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.turnkey','flooring','carpet','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.turnkey','painting','interior','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.turnkey','gypsum','partitions','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.turnkey','gypsum','false_ceiling','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.turnkey','wallpaper','supply_install','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.turnkey','joinery','wooden_doors','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.turnkey','joinery','custom_furniture','A turnkey fit-out contractor delivers every interior finish.','مقاول التجهيز المتكامل ينفّذ جميع التشطيبات الداخلية.'),
  ('interior_fitout.office','flooring','carpet','Office fit-out includes partitions, ceilings, flooring and painting.','تجهيز المكاتب يشمل القواطع والأسقف والأرضيات والدهان.'),
  ('interior_fitout.office','flooring','parquet_vinyl','Office fit-out includes partitions, ceilings, flooring and painting.','تجهيز المكاتب يشمل القواطع والأسقف والأرضيات والدهان.'),
  ('interior_fitout.office','painting','interior','Office fit-out includes partitions, ceilings, flooring and painting.','تجهيز المكاتب يشمل القواطع والأسقف والأرضيات والدهان.'),
  ('interior_fitout.office','gypsum','partitions','Office fit-out includes partitions, ceilings, flooring and painting.','تجهيز المكاتب يشمل القواطع والأسقف والأرضيات والدهان.'),
  ('interior_fitout.office','gypsum','false_ceiling','Office fit-out includes partitions, ceilings, flooring and painting.','تجهيز المكاتب يشمل القواطع والأسقف والأرضيات والدهان.'),
  ('interior_fitout.office','gypsum','acoustic_ceiling','Office fit-out includes partitions, ceilings, flooring and painting.','تجهيز المكاتب يشمل القواطع والأسقف والأرضيات والدهان.'),
  ('interior_fitout.office','glazing','partitions','Office fit-out includes partitions, ceilings, flooring and painting.','تجهيز المكاتب يشمل القواطع والأسقف والأرضيات والدهان.'),
  ('interior_fitout.retail','flooring','tiling','Retail fit-out includes flooring, partitions, ceilings, painting and shop joinery.','تجهيز المحلات يشمل الأرضيات والقواطع والأسقف والدهان وأعمال النجارة.'),
  ('interior_fitout.retail','painting','interior','Retail fit-out includes flooring, partitions, ceilings, painting and shop joinery.','تجهيز المحلات يشمل الأرضيات والقواطع والأسقف والدهان وأعمال النجارة.'),
  ('interior_fitout.retail','gypsum','partitions','Retail fit-out includes flooring, partitions, ceilings, painting and shop joinery.','تجهيز المحلات يشمل الأرضيات والقواطع والأسقف والدهان وأعمال النجارة.'),
  ('interior_fitout.retail','gypsum','false_ceiling','Retail fit-out includes flooring, partitions, ceilings, painting and shop joinery.','تجهيز المحلات يشمل الأرضيات والقواطع والأسقف والدهان وأعمال النجارة.'),
  ('interior_fitout.retail','joinery','custom_furniture','Retail fit-out includes flooring, partitions, ceilings, painting and shop joinery.','تجهيز المحلات يشمل الأرضيات والقواطع والأسقف والدهان وأعمال النجارة.'),
  ('interior_fitout','flooring','tiling','Fit-out contractors carry out these interior finishes.','مقاولو التجهيز الداخلي ينفّذون هذه التشطيبات الداخلية.'),
  ('interior_fitout','painting','interior','Fit-out contractors carry out these interior finishes.','مقاولو التجهيز الداخلي ينفّذون هذه التشطيبات الداخلية.'),
  ('interior_fitout','gypsum','partitions','Fit-out contractors carry out these interior finishes.','مقاولو التجهيز الداخلي ينفّذون هذه التشطيبات الداخلية.'),
  ('interior_fitout','gypsum','false_ceiling','Fit-out contractors carry out these interior finishes.','مقاولو التجهيز الداخلي ينفّذون هذه التشطيبات الداخلية.'),
  ('civil_works.new_construction','civil_works','concrete','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.'),
  ('civil_works.new_construction','civil_works','blockwork','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.'),
  ('civil_works.new_construction','civil_works','excavation','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.'),
  ('civil_works.new_construction','gypsum','plastering','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.'),
  ('civil_works.new_construction','flooring','tiling','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.'),
  ('civil_works.new_construction','painting','interior','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.'),
  ('civil_works.new_construction','painting','exterior','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.'),
  ('civil_works.new_construction','waterproofing','roof','A main contractor builds the structure and finishes the building.','المقاول الرئيسي ينفّذ الهيكل ويُكمل تشطيب المبنى.'),
  ('civil_works','civil_works','concrete','Civil contractors carry out concrete, blockwork and plastering.','مقاولو الأعمال المدنية ينفّذون أعمال الخرسانة والطابوق واللياسة.'),
  ('civil_works','civil_works','blockwork','Civil contractors carry out concrete, blockwork and plastering.','مقاولو الأعمال المدنية ينفّذون أعمال الخرسانة والطابوق واللياسة.'),
  ('civil_works','gypsum','plastering','Civil contractors carry out concrete, blockwork and plastering.','مقاولو الأعمال المدنية ينفّذون أعمال الخرسانة والطابوق واللياسة.'),
  ('mep_general.mep_install','electrical','wiring_install','An MEP contractor installs the electrical, plumbing and air-conditioning services.','مقاول الأعمال الكهروميكانيكية يركّب أنظمة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_install','electrical','db_panels','An MEP contractor installs the electrical, plumbing and air-conditioning services.','مقاول الأعمال الكهروميكانيكية يركّب أنظمة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_install','electrical','lighting','An MEP contractor installs the electrical, plumbing and air-conditioning services.','مقاول الأعمال الكهروميكانيكية يركّب أنظمة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_install','plumbing','water_supply','An MEP contractor installs the electrical, plumbing and air-conditioning services.','مقاول الأعمال الكهروميكانيكية يركّب أنظمة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_install','plumbing','drainage','An MEP contractor installs the electrical, plumbing and air-conditioning services.','مقاول الأعمال الكهروميكانيكية يركّب أنظمة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_install','plumbing','sanitary_fixtures','An MEP contractor installs the electrical, plumbing and air-conditioning services.','مقاول الأعمال الكهروميكانيكية يركّب أنظمة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_install','hvac','supply_install','An MEP contractor installs the electrical, plumbing and air-conditioning services.','مقاول الأعمال الكهروميكانيكية يركّب أنظمة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_install','hvac','ducting','An MEP contractor installs the electrical, plumbing and air-conditioning services.','مقاول الأعمال الكهروميكانيكية يركّب أنظمة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_maintenance','electrical','maintenance','MEP maintenance covers electrical, plumbing and air-conditioning maintenance.','صيانة الأعمال الكهروميكانيكية تشمل صيانة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_maintenance','plumbing','maintenance','MEP maintenance covers electrical, plumbing and air-conditioning maintenance.','صيانة الأعمال الكهروميكانيكية تشمل صيانة الكهرباء والسباكة والتكييف.'),
  ('mep_general.mep_maintenance','hvac','maintenance_amc','MEP maintenance covers electrical, plumbing and air-conditioning maintenance.','صيانة الأعمال الكهروميكانيكية تشمل صيانة الكهرباء والسباكة والتكييف.'),
  ('mep_general.testing_commissioning','hvac','testing_commissioning','MEP testing and commissioning includes the air-conditioning systems.','اختبار وتشغيل الأعمال الكهروميكانيكية يشمل أنظمة التكييف.'),
  ('mep_general','electrical','wiring_install','MEP contractors install electrical, plumbing and air-conditioning work.','مقاولو الأعمال الكهروميكانيكية ينفّذون أعمال الكهرباء والسباكة والتكييف.'),
  ('mep_general','plumbing','water_supply','MEP contractors install electrical, plumbing and air-conditioning work.','مقاولو الأعمال الكهروميكانيكية ينفّذون أعمال الكهرباء والسباكة والتكييف.'),
  ('mep_general','plumbing','drainage','MEP contractors install electrical, plumbing and air-conditioning work.','مقاولو الأعمال الكهروميكانيكية ينفّذون أعمال الكهرباء والسباكة والتكييف.'),
  ('mep_general','hvac','supply_install','MEP contractors install electrical, plumbing and air-conditioning work.','مقاولو الأعمال الكهروميكانيكية ينفّذون أعمال الكهرباء والسباكة والتكييف.'),
  ('electrical.wiring_install','electrical','lighting','Electrical installation includes lighting points and cable containment.','التمديدات الكهربائية تشمل نقاط الإنارة وحوامل الكابلات.'),
  ('electrical.wiring_install','electrical','cable_tray','Electrical installation includes lighting points and cable containment.','التمديدات الكهربائية تشمل نقاط الإنارة وحوامل الكابلات.'),
  ('plumbing.water_supply','plumbing','drainage','Plumbing contractors lay drainage and fix sanitary fittings with the water lines.','مقاولو السباكة ينفّذون الصرف ويركّبون الأدوات الصحية مع تمديدات المياه.'),
  ('plumbing.water_supply','plumbing','sanitary_fixtures','Plumbing contractors lay drainage and fix sanitary fittings with the water lines.','مقاولو السباكة ينفّذون الصرف ويركّبون الأدوات الصحية مع تمديدات المياه.'),
  ('hvac.supply_install','hvac','maintenance_amc','Air-conditioning installers service the units they install.','من يركّب وحدات التكييف يتولّى صيانتها.'),
  ('gypsum.false_ceiling','gypsum','acoustic_ceiling','Ceiling contractors install acoustic ceilings and gypsum partitions too.','مقاولو الأسقف يركّبون الأسقف الصوتية وقواطع الجبس أيضًا.'),
  ('gypsum.false_ceiling','gypsum','partitions','Ceiling contractors install acoustic ceilings and gypsum partitions too.','مقاولو الأسقف يركّبون الأسقف الصوتية وقواطع الجبس أيضًا.'),
  ('gypsum.partitions','gypsum','false_ceiling','Gypsum board installers build false ceilings with the same system.','من يركّب ألواح الجبس ينفّذ الأسقف المعلّقة بالنظام نفسه.'),
  ('painting.interior','painting','repainting','Painters take on repainting and touch-up work.','شركات الدهان تتولّى إعادة الدهان وأعمال الترقيع.'),
  ('painting.exterior','painting','repainting','Painters take on repainting and touch-up work.','شركات الدهان تتولّى إعادة الدهان وأعمال الترقيع.'),
  ('flooring.marble_granite','flooring','tiling','Stone fixers lay tiles with the same skills and tools.','من يركّب الرخام والجرانيت يركّب البلاط بالمهارة والأدوات نفسها.'),
  ('glazing.glass_facades','aluminium','curtain_wall','Façade contractors build glass façades as curtain walls.','مقاولو الواجهات ينفّذون الواجهات الزجاجية بنظام الحوائط الستائرية.'),
  ('aluminium.curtain_wall','glazing','glass_facades','Curtain wall contractors glaze the façade they build.','مقاولو الحوائط الستائرية يركّبون زجاج الواجهة التي ينفّذونها.'),
  ('aluminium.windows_doors','glazing','tempered_laminated','Aluminium and glass works supply the glass and louvres with the frames.','أعمال الألمنيوم والزجاج تورّد الزجاج واللوفرات مع الإطارات.'),
  ('aluminium.windows_doors','aluminium','louvres','Aluminium and glass works supply the glass and louvres with the frames.','أعمال الألمنيوم والزجاج تورّد الزجاج واللوفرات مع الإطارات.'),
  ('steel.fabrication_welding','steel','handrails','Metal fabricators make handrails, gates and fences.','ورش تشكيل المعادن تصنع الدرابزين والبوابات والأسوار.'),
  ('steel.fabrication_welding','steel','gates_fencing','Metal fabricators make handrails, gates and fences.','ورش تشكيل المعادن تصنع الدرابزين والبوابات والأسوار.'),
  ('steel.structural_steel','steel','fabrication_welding','Structural steel contractors fabricate and weld.','مقاولو الهياكل الفولاذية ينفّذون التشكيل واللحام.'),
  ('joinery.kitchens','joinery','wardrobes','Kitchen joiners make wardrobes with the same workshop.','ورش المطابخ تصنع الخزائن والدواليب بالورشة نفسها.'),
  ('joinery.custom_furniture','joinery','wardrobes','Furniture makers build wardrobes and closets.','صانعو الأثاث يصنعون الخزائن والدواليب.'),
  ('joinery.wooden_doors','doors','wooden_doors','The same service is listed under Joinery and under Doors.','الخدمة نفسها مدرجة تحت النجارة وتحت الأبواب.'),
  ('doors.wooden_doors','joinery','wooden_doors','The same service is listed under Doors and under Joinery.','الخدمة نفسها مدرجة تحت الأبواب وتحت النجارة.'),
  ('security_systems.cctv','security_systems','intruder_alarm','CCTV installers fit intruder alarms on the same systems.','من يركّب كاميرات المراقبة يركّب أنظمة إنذار السرقة على الأنظمة نفسها.'),
  ('it_services.network_install','it_services','structured_cabling','Network installers run the cabling the network needs.','من يركّب الشبكات يمدّ الكابلات التي تحتاجها الشبكة.'),
  ('it_services.network_install','av_it','data_cabling','Network installers run the cabling the network needs.','من يركّب الشبكات يمدّ الكابلات التي تحتاجها الشبكة.'),
  ('it_services.structured_cabling','av_it','data_cabling','The same cabling is listed under IT and under AV & IT.','الكابلات نفسها مدرجة تحت خدمات تقنية المعلومات وتحت الأنظمة الصوتية والمرئية.'),
  ('av_it.data_cabling','it_services','structured_cabling','The same cabling is listed under AV & IT and under IT.','الكابلات نفسها مدرجة تحت الصوتيات وتقنية المعلومات وتحت تقنية المعلومات.'),
  ('home_automation.smart_home','home_automation','lighting_control','Smart home integrators install lighting control and door entry.','شركات المنزل الذكي تركّب التحكم بالإنارة وأنظمة الاتصال الداخلي (الإنتركم).'),
  ('home_automation.smart_home','home_automation','intercom','Smart home integrators install lighting control and door entry.','شركات المنزل الذكي تركّب التحكم بالإنارة وأنظمة الاتصال الداخلي (الإنتركم).'),
  ('fire_fighting.sprinklers','fire_fighting','fire_pumps','Sprinkler contractors install the fire pumps that feed them.','مقاولو الرشاشات يركّبون مضخات الحريق التي تغذّيها.'),
  ('fire_fighting','fire_fighting','extinguishers','Fire-fighting contractors supply and service extinguishers.','مقاولو مكافحة الحريق يورّدون الطفايات ويصونونها.'),
  ('landscaping.softscape','landscaping','irrigation','Planting contractors install irrigation and maintain gardens.','مقاولو الزراعة يركّبون أنظمة الري ويصونون الحدائق.'),
  ('landscaping.softscape','landscaping','maintenance','Planting contractors install irrigation and maintain gardens.','مقاولو الزراعة يركّبون أنظمة الري ويصونون الحدائق.'),
  ('waterproofing.roof','waterproofing','thermal','Roof waterproofing systems are laid with thermal insulation.','أنظمة العزل المائي للأسطح تُنفَّذ مع العزل الحراري.'),
  ('solar.pv_install','solar','maintenance','Solar installers connect, maintain and clean the systems they install.','من يركّب أنظمة الطاقة الشمسية يربطها بالشبكة ويصونها وينظّفها.'),
  ('solar.pv_install','solar','grid_connection','Solar installers connect, maintain and clean the systems they install.','من يركّب أنظمة الطاقة الشمسية يربطها بالشبكة ويصونها وينظّفها.'),
  ('elevators.supply_install','elevators','maintenance','Elevator installers maintain the lifts they install.','من يركّب المصاعد يتولّى صيانتها.'),
  ('power_generators.generator_supply','power_generators','generator_maintenance','Generator suppliers service generators and supply the changeover panels.','مورّدو المولدات يصونونها ويورّدون لوحات التحويل.'),
  ('power_generators.generator_supply','power_generators','ats_panels','Generator suppliers service generators and supply the changeover panels.','مورّدو المولدات يصونونها ويورّدون لوحات التحويل.'),
  ('heavy_equipment.equipment_rental','heavy_equipment','with_operator','Equipment rental companies supply operators with the machines.','شركات تأجير المعدات توفّر المشغّلين مع الآليات.'),
  ('scaffolding.rental','scaffolding','erection','Scaffolding rental companies erect and dismantle what they rent.','شركات تأجير السقالات تركّب ما تؤجّره وتفكّه.'),
  ('cleaning.deep_cleaning','cleaning','post_construction','Deep-cleaning companies take on post-construction cleaning.','شركات التنظيف العميق تتولّى التنظيف بعد البناء.'),
  ('cleaning.facility_management','cleaning','deep_cleaning','Facility management companies provide cleaning services.','شركات إدارة المرافق تقدّم خدمات التنظيف.'),
  ('upholstery.curtains','upholstery','blinds','Curtain makers supply and fit blinds.','من يفصّل الستائر يورّد ستائر الرول والشرائح ويركّبها.'),
  ('upholstery.sofa','upholstery','majlis','Upholsterers make majlis seating.','المنجّدون يفصّلون المجالس.'),
  ('wallpaper.supply_install','wallpaper','removal','Wallpaper installers remove old wallpaper first.','من يركّب ورق الجدران يزيل الورق القديم أولًا.'),
  ('signage.shop_signs','signage','letters_3d','Sign makers produce 3D letters and light boxes.','صانعو اللافتات يصنعون الحروف البارزة والصناديق المضيئة.'),
  ('signage.shop_signs','signage','lightbox','Sign makers produce 3D letters and light boxes.','صانعو اللافتات يصنعون الحروف البارزة والصناديق المضيئة.'),
  ('logistics_moving.moving','logistics_moving','storage','Moving companies store goods between moves.','شركات نقل الأثاث تخزّن الأغراض بين عمليات النقل.')
on conflict (from_code, implies_trade, implies_code) do update
  set reason_en = excluded.reason_en, reason_ar = excluded.reason_ar, active = true;

-- from_code must name something real: a live trade, or a live service.
do $$
declare v_bad text;
begin
  select string_agg(distinct i.from_code, ', ') into v_bad
  from public.service_implication i
  where i.active
    and not exists (select 1 from public.taxonomy_trade t where t.code = i.from_code and t.active)
    and not exists (select 1 from public.taxonomy_trade_service s
                    where s.trade_code || '.' || s.code = i.from_code and s.active);
  if v_bad is not null then
    raise exception 'service_implication.from_code names no active trade or service: %', v_bad;
  end if;
end $$;

-- ── 3. WHAT THE SUPPLIER TYPED, AND WHAT IT CONFIRMED ─────────────────────────────────────────────
-- `services` keeps its meaning: the confirmed list the supplier STATED (service keys, plus any of its
-- own words the aliases do not name). The three columns below are what instruction 438 asks to keep
-- separately -- the raw input for audit, and the implied half split into kept and removed.
alter table public.supplier_capabilities
  add column if not exists services_raw_text   text,
  add column if not exists services_implied    text[] not null default '{}'::text[],
  add column if not exists services_removed    text[] not null default '{}'::text[],
  add column if not exists services_rewritten_at timestamptz;
comment on column public.supplier_capabilities.services_raw_text is
  'The supplier''s own words about its services, exactly as typed or dictated, before the sales engineer''s rewrite. Audit only -- matching never reads it. Seat: sales_engineer.';
comment on column public.supplier_capabilities.services_implied is
  'Service keys the supplier KEPT from the implication map (service_implication), as shown to it with their reason. Audit of the confirmation; fn_services_effective recomputes from the live map so a retired rule stops matching.';
comment on column public.supplier_capabilities.services_removed is
  'Service keys the supplier REMOVED from the implied list. fn_services_effective subtracts these, so removing flooring means flooring inquiries stop reaching it.';
comment on column public.supplier_capabilities.services_rewritten_at is
  'When the supplier confirmed a sales engineer rewrite of its own words. Null means it never did -- matching then applies the implication map to its confirmed trades and checklist services instead.';

-- ── 4. STATED + IMPLIED - REMOVED, ONE LEVEL ──────────────────────────────────────────────────────
-- The ONE definition of what a supplier can be matched on at service level. Both readers (matching
-- below, and the portal preview) answer from it.
--
-- ONE LEVEL, AND WHY IT IS A JOIN AND NOT A RECURSION: the map is read exactly once, against what the
-- supplier STATED. An implied service is never fed back in. Decoration implies false ceilings; false
-- ceilings imply acoustic ceilings; decoration does NOT imply acoustic ceilings, because no-one
-- curated that step and a chain of plausible steps is how a matcher starts inventing capability.
create or replace function public.fn_services_effective(
  p_stated  text[],
  p_trades  text[] default '{}'::text[],
  p_removed text[] default '{}'::text[]
) returns text[]
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
  with stated as (
    select distinct s.trade_code || '.' || s.code as key
    from public.taxonomy_trade_service s
    where s.active and s.trade_code || '.' || s.code = any(coalesce(p_stated, '{}'::text[]))
  ),
  src as (
    select key from stated
    union
    select t from unnest(coalesce(p_trades, '{}'::text[])) t
  ),
  implied as (
    select distinct i.implies_trade || '.' || i.implies_code as key
    from public.service_implication i
    join src on src.key = i.from_code
    where i.active
  )
  select coalesce(array_agg(distinct key order by key), '{}'::text[])
  from (select key from stated union select key from implied) all_keys
  where key <> all (coalesce(p_removed, '{}'::text[]));
$function$;
revoke all on function public.fn_services_effective(text[], text[], text[]) from public, anon, authenticated;
comment on function public.fn_services_effective(text[], text[], text[]) is
  'The service keys a supplier can be matched on: what it STATED, plus one level of service_implication from its stated services and trades, minus what it REMOVED. Founder instructions 438-439. Seat: sales_engineer.';

-- Why each implied key is there, for the portal preview and for the match record.
create or replace function public.fn_service_implications(p_sources text[])
 returns table(implies_key text, from_code text, reason_en text, reason_ar text)
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
  select i.implies_trade || '.' || i.implies_code, i.from_code, i.reason_en, i.reason_ar
  from public.service_implication i
  where i.active and i.from_code = any(coalesce(p_sources, '{}'::text[]))
  order by 1, 2;
$function$;
revoke all on function public.fn_service_implications(text[]) from public, anon, authenticated;
comment on function public.fn_service_implications(text[]) is
  'One level of service_implication out of the given stated services and trades, each with the sales engineer''s reason in EN and AR. Seat: sales_engineer.';

-- ── 5. MATCHING AT SERVICE LEVEL ──────────────────────────────────────────────────────────────────
-- fn_match_capability keeps every gate it had. It gains ONE: when the inquiry names services
-- (p_services), a candidate must cover at least one of them -- covered meaning fn_services_effective,
-- so a decoration company reaches a flooring inquiry, and stops reaching it the moment it removes
-- flooring. An inquiry that names no service (p_services empty) is matched exactly as before.
--
-- EVERY MATCH RECORDS WHICH RULE PRODUCED IT (founder instruction 439): via_implication carries
-- 'from_code -> implied_key' for each matched service the supplier did not state itself, and `why`
-- names them, so a shortlist can always be read back to the curated row that put a supplier on it.
--
-- The signature changes, so the old one is DROPPED rather than replaced -- two overloads would let a
-- caller silently keep the service-blind one. `or replace` here does NOT preserve an ACL (there is no
-- function at this signature to preserve one from): the new signature is created fresh and EXECUTE is
-- granted to PUBLIC, so the revoke below is part of the same file. It is written `or replace` so that
-- scripts/apply_sql.mjs recognises it as a routine this file defines and reads its definition back.
drop function if exists public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer);

create or replace function public.fn_match_capability(
  p_trades text[],
  p_need text default 'executes'::text,
  p_products text[] default '{}'::text[],
  p_brands text[] default '{}'::text[],
  p_project_type text default null::text,
  p_value numeric default null::numeric,
  p_emirate text default null::text,
  p_limit integer default 12,
  p_services text[] default '{}'::text[]
)
 returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[],
               product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text,
               service_hits text[], via_implication text[])
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size
),
req_auth as (
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades)
),
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value, sc.coverage_emirates,
         sc.services, sc.services_removed,
         l.company_name, l.emirate as lead_emirate,
         least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0))) as track,
         -- TIE-BREAK ONLY. Every UAE supplier covers the whole country (founder, 14 Sep 2026), so the
         -- job's emirate never removes a candidate; it only orders two equal scores.
         (p_emirate is not null and (
              exists (select 1 from unnest(sc.coverage_emirates) ce where ce ilike p_emirate)
           or l.emirate ilike p_emirate
           or l.license_city ilike p_emirate)) as in_emirate
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null                        -- GATE: supplier confirmed their own scope
    and sc.trades && p_trades                              -- GATE: trade intersection
    and not (sc.excluded_trades && p_trades)               -- GATE: declared negative scope
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    and exists (                                            -- GATE: role can actually do this kind of work
      select 1 from public.taxonomy_role r
      where r.code = any(sc.roles)
        and case p_need when 'supplies'    then r.supplies
                        when 'whole_scope' then r.whole_scope
                        else r.executes end
    )
    and not exists (                                        -- GATE: every mandatory authority held
      select 1 from unnest((select codes from req_auth)) a
      where not (sc.authority_approvals ? a)
    )
    and (p_value is null or (                               -- GATE: job size inside their range
          (sc.min_project_value is null or p_value >= sc.min_project_value)
      and (sc.max_project_value is null or p_value <= sc.max_project_value)))
),
-- GATE: the services the inquiry names, at SERVICE level. Stated + one level of the curated
-- implication map - what the supplier removed. Empty p_services leaves every candidate through.
--
-- ONE DEFINITION OF COVERAGE. eff_services is computed once per candidate by fn_services_effective,
-- and BOTH the hit list and the attribution are derived from it. An earlier draft re-derived the
-- attribution from c.services directly (database review, 18 Sep 2026): a service code the supplier
-- still stores but taxonomy_trade_service no longer marks active was rejected by fn_services_effective
-- and accepted by the attribution, so `why` could name a curated rule that never actually fired.
eff as (
  select c.*,
         case when cardinality(p_services) = 0 then '{}'::text[]
              else public.fn_services_effective(c.services, c.trades, c.services_removed) end as eff_services
  from cand c
),
svc as (
  select e.*,
    array(select unnest(e.eff_services) intersect select unnest(p_services)) as service_hits,
    -- ponytail: one scan of service_implication per candidate. At 113 curated rows against a
    -- candidate set the gates above have already cut down, this is not measurable; batch it with a
    -- single unnest+join if the map or the candidate count grows an order of magnitude.
    array(
      select distinct i.from_code || ' -> ' || i.implies_trade || '.' || i.implies_code
      from public.service_implication i
      where i.active
        and (i.implies_trade || '.' || i.implies_code) = any(e.eff_services)   -- it really is covered
        and (i.implies_trade || '.' || i.implies_code) = any(p_services)       -- and the inquiry asked
        and not ((i.implies_trade || '.' || i.implies_code) = any(coalesce(e.services, '{}'::text[])))
        and (i.from_code = any(coalesce(e.trades, '{}'::text[]))
          or i.from_code = any(coalesce(e.services, '{}'::text[])))
      order by 1) as via_implication
  from eff e
),
scored as (
  select c.*,
    (select count(distinct pq) from unnest(p_products) pq
      where exists (select 1 from unnest(c.products_norm) pp
                    where pp ilike '%'||pq||'%' or pq ilike '%'||pp||'%'))::int as product_hits,
    (cardinality(p_brands) > 0 and exists (
       select 1 from unnest(p_brands) bq join unnest(c.brands) bb on bb ilike '%'||bq||'%' or bq ilike '%'||bb||'%'
     )) as brand_hit,
    (p_project_type is not null and exists (
       select 1 from unnest(c.project_types) pt
       where pt ilike '%'||p_project_type||'%' or p_project_type ilike '%'||pt||'%'
     )) as ptype_hit,
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known
  from svc c
  where cardinality(p_services) = 0 or cardinality(c.service_hits) > 0
),
ranked as (
  select s.*,
    round(
        w.w_prod  * (case when cardinality(p_products) > 0
                          then s.product_hits::numeric / cardinality(p_products) else 0 end)
      + w.w_brand * (case when s.brand_hit then 1 else 0 end)
      + w.w_ptype * (case when s.ptype_hit then 1 else 0 end)
      + w.w_track * s.track
      + w.w_size  * (case when s.size_known then 1 else 0.5 end)
    , 1) as score_v
  from scored s, w
)
select r.supplier_id, r.company_name, r.score_v as score,
  r.trades, r.roles, r.product_hits, r.brand_hit, r.ptype_hit, round(r.track,3) as track,
  concat_ws(' · ',
    'trades ' || array_to_string(array(select unnest(r.trades) intersect select unnest(p_trades)), '+'),
    case when cardinality(r.service_hits) > 0 then cardinality(r.service_hits)||'/'||cardinality(p_services)||' services' end,
    case when cardinality(r.via_implication) > 0 then 'implied: ' || array_to_string(r.via_implication, ', ') end,
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality(p_products)||' products' end,
    case when r.brand_hit then 'brand match' end,
    case when r.ptype_hit then 'project type' end,
    case when p_emirate is not null then
      case when r.in_emirate then 'in ' || p_emirate else 'UAE-wide' end end
  ) as why,
  r.service_hits, r.via_implication
from ranked r
order by r.score_v desc, cardinality(r.service_hits) desc, r.in_emirate desc, r.track desc, r.supplier_id
limit greatest(1, p_limit);
$function$;
revoke all on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) from public, anon, authenticated;
comment on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) is
  'The structured matcher. Gates: confirmed scope, trade intersection, negative scope, matchability, role, mandatory authority, job value, and -- when the inquiry names services -- service coverage through fn_services_effective. service_hits and via_implication say which services matched and which curated implication rule produced each one the supplier did not state itself. Exact codes only; no nearest, no fuzzy (founder, 14 Sep 2026).';
