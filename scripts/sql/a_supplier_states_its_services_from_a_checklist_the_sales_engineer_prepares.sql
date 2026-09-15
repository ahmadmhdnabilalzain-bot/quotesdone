-- A SUPPLIER STATES ITS SERVICES FROM A CHECKLIST THE SALES ENGINEER PREPARES. Seat: sales_engineer.
-- 15 Sep 2026.
--
-- Founder, 15 Sep 2026: the Services checklist tab "will be our cross matching main source". The
-- supplier states the services it provides from a ready checklist the sales engineer prepares
-- (pre-ticked), adds anything missing as free text or by voice, and what is saved feeds matching.
-- And: "we cant use the browser built in. later this will be a mobile app as well. the structure
-- need to be built in already." -- so voice is a server action, not the browser's speech API.
--
-- MEASURED BEFORE THIS FILE (production, 15 Sep 2026):
--   * taxonomy_trade: 40 active codes, each with label + label_ar + aliases. Nothing listed the
--     SERVICES inside a trade, so the only checklist the portal could show was the 40 trade names.
--   * supplier_capabilities.services (text[]) exists and capability confirm writes it, but the
--     portal always sent back whatever the directory derivation held -- the supplier never chose it.
--   * decision_policy (key text PK, value jsonb) is where settled switches live; no voice flag existed.
--   * supabase/functions/transcribe is server-side speech-to-text through ai_gateway to an OpenRouter
--     audio model. OpenRouter is ON HOLD (founder), so voice ships switched OFF (flag below).
--
-- WHAT THIS CHANGES
--   1. taxonomy_trade_service -- the common services of each active trade, English and Arabic, five
--      per trade for all 40 codes, written by hand here (no model). Its key is trade_code + code; the
--      portal stores a ticked service in supplier_capabilities.services as '<trade_code>.<code>'.
--   2. supplier_voice_note -- one row per voice-to-text request: who, when, size, length, type and
--      outcome. It is the per-supplier rate limit's counter and the audit trail. NO AUDIO and NO TEXT
--      is stored; the recording is never kept anywhere.
--   3. decision_policy 'supplier_voice_input_enabled' = {"enabled": false}. supplier_api reads it on
--      every voice request and on every services_state, so web and a future mobile app see the same
--      switch. Turning it on is the founder's spend decision (OpenRouter audio model per request).
--
-- WHAT THIS DOES NOT CHANGE: fn_match_capability (still gates on trades + confirmed_at; a ticked
-- service implies its trade, so the trade gate is what the checklist feeds), fn_norm_trades (the
-- free-text resolver the save uses, exact alias or nothing), taxonomy_trade_proposal (a free-text
-- service no alias resolves becomes a pending proposal there, owned by sales_engineer).

create table if not exists public.taxonomy_trade_service (
  trade_code text not null references public.taxonomy_trade(code) on update cascade on delete cascade,
  code       text not null check (code ~ '^[a-z][a-z0-9_]*$'),
  label_en   text not null check (btrim(label_en) <> ''),
  label_ar   text not null check (label_ar ~ '[ء-ي]'),
  sort       integer not null default 100,
  active     boolean not null default true,
  primary key (trade_code, code)
);
comment on table public.taxonomy_trade_service is
  'Common services inside each taxonomy_trade, EN+AR, hand-written (no model). The supplier portal Services tab offers them as a checklist; a ticked one is stored in supplier_capabilities.services as trade_code.code. Seat: sales_engineer.';

alter table public.taxonomy_trade_service enable row level security;
drop policy if exists taxonomy_trade_service_service_role_only on public.taxonomy_trade_service;
create policy taxonomy_trade_service_service_role_only on public.taxonomy_trade_service
  as permissive for all to public using (false) with check (false);
revoke all on public.taxonomy_trade_service from anon, authenticated;

create table if not exists public.supplier_voice_note (
  id          bigint generated always as identity primary key,
  supplier_id bigint not null,
  created_at  timestamptz not null default now(),
  bytes       integer not null default 0 check (bytes >= 0),
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  mime        text,
  -- 'pending' is written first and counted by the rate limit, so parallel requests see each other.
  outcome     text not null check (outcome in ('pending','flag_off','rate_limited','refused','transcribed','empty','failed')),
  lang        text check (lang is null or lang in ('en','ar')),
  chars       integer check (chars is null or chars >= 0)
);
-- No foreign key to leads on purpose: this is an audit trail and must outlive a deleted supplier row.
create index if not exists supplier_voice_note_supplier_recent on public.supplier_voice_note (supplier_id, created_at desc);
comment on table public.supplier_voice_note is
  'One row per supplier voice-to-text request (supplier_api transcribe_service_note): size, length, type, outcome. Rate-limit counter and audit trail. Never holds audio or transcript text.';

alter table public.supplier_voice_note enable row level security;
drop policy if exists supplier_voice_note_service_role_only on public.supplier_voice_note;
create policy supplier_voice_note_service_role_only on public.supplier_voice_note
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_voice_note from anon, authenticated;

insert into public.decision_policy (key, value, description, updated_at)
select 'supplier_voice_input_enabled', '{"enabled": false}'::jsonb,
       'Supplier portal voice-to-text (supplier_api transcribe_service_note -> transcribe -> OpenRouter audio model). OFF while the OpenRouter hold stands; switching it on is a spend decision for the founder.',
       now()
where not exists (select 1 from public.decision_policy where key = 'supplier_voice_input_enabled');

insert into public.taxonomy_trade_service (trade_code, code, label_en, label_ar, sort)
select v.trade_code, v.code, v.label_en, v.label_ar, v.sort
from (values
  ('hvac','supply_install','Supply & installation of AC units','توريد وتركيب وحدات التكييف',10),
  ('hvac','vrf_chiller','VRF & chiller systems','أنظمة VRF والتشيلر',20),
  ('hvac','ducting','Ducting & ventilation','مجاري الهواء والتهوية',30),
  ('hvac','maintenance_amc','Maintenance & annual contracts','الصيانة وعقود الصيانة السنوية',40),
  ('hvac','testing_commissioning','Testing & commissioning','الاختبار والتشغيل',50),
  ('electrical','wiring_install','Wiring & electrical installation','التمديدات والتركيبات الكهربائية',10),
  ('electrical','db_panels','Distribution boards & switchgear','لوحات التوزيع والمفاتيح الكهربائية',20),
  ('electrical','lighting','Lighting supply & installation','توريد وتركيب الإنارة',30),
  ('electrical','cable_tray','Cable trays & containment','حوامل الكابلات ومجاريها',40),
  ('electrical','maintenance','Electrical maintenance','الصيانة الكهربائية',50),
  ('building_materials','cement_concrete','Cement & ready-mix concrete','الإسمنت والخرسانة الجاهزة',10),
  ('building_materials','blocks_bricks','Blocks & bricks','الطابوق والبلوك',20),
  ('building_materials','aggregates','Sand & aggregates','الرمل والركام',30),
  ('building_materials','steel_rebar','Reinforcement steel','حديد التسليح',40),
  ('building_materials','sanitary_ware','Sanitary ware','الأدوات الصحية',50),
  ('engineering_consultancy','architectural_design','Architectural design','التصميم المعماري',10),
  ('engineering_consultancy','structural_design','Structural design','التصميم الإنشائي',20),
  ('engineering_consultancy','mep_design','MEP design','تصميم الأعمال الكهروميكانيكية',30),
  ('engineering_consultancy','supervision','Site supervision','الإشراف على التنفيذ',40),
  ('engineering_consultancy','authority_approvals','Authority approvals & permits','الموافقات والتصاريح الحكومية',50),
  ('power_generators','generator_supply','Generator supply','توريد المولدات',10),
  ('power_generators','generator_rental','Generator rental','تأجير المولدات',20),
  ('power_generators','ups','UPS systems','أنظمة الطاقة غير المنقطعة UPS',30),
  ('power_generators','generator_maintenance','Generator maintenance','صيانة المولدات',40),
  ('power_generators','ats_panels','Changeover & ATS panels','لوحات التحويل الأوتوماتيكي ATS',50),
  ('heavy_equipment','equipment_rental','Equipment rental','تأجير المعدات',10),
  ('heavy_equipment','crane_hire','Crane hire','تأجير الرافعات',20),
  ('heavy_equipment','earthmoving','Excavation & earthmoving','الحفر وتحريك التربة',30),
  ('heavy_equipment','equipment_sales','Equipment sales','بيع المعدات',40),
  ('heavy_equipment','with_operator','Equipment with operator','معدات مع مشغّل',50),
  ('plumbing','water_supply','Water supply piping','تمديدات إمدادات المياه',10),
  ('plumbing','drainage','Drainage & sewerage','الصرف الصحي',20),
  ('plumbing','sanitary_fixtures','Sanitary fixtures installation','تركيب الأدوات الصحية',30),
  ('plumbing','heaters_pumps','Water heaters & pumps','سخانات ومضخات المياه',40),
  ('plumbing','maintenance','Plumbing maintenance','صيانة السباكة',50),
  ('labour_supply','skilled','Skilled trades labour','عمالة فنية ماهرة',10),
  ('labour_supply','general','General labour','عمالة عامة',20),
  ('labour_supply','hourly','Hourly labour hire','تأجير عمالة بالساعة',30),
  ('labour_supply','project_manpower','Project manpower contracts','عقود توريد عمالة للمشاريع',40),
  ('labour_supply','supervisors','Foremen & supervisors','مراقبون ومشرفون',50),
  ('safety_equipment','ppe','PPE supply','توريد معدات الوقاية الشخصية',10),
  ('safety_equipment','fall_protection','Fall protection','معدات الحماية من السقوط',20),
  ('safety_equipment','signs_barriers','Safety signs & barriers','لافتات وحواجز السلامة',30),
  ('safety_equipment','first_aid','First aid supplies','مستلزمات الإسعافات الأولية',40),
  ('safety_equipment','workwear','Workwear & uniforms','ملابس العمل والزي الموحد',50),
  ('solar','pv_install','Solar PV installation','تركيب أنظمة الطاقة الشمسية الكهروضوئية',10),
  ('solar','water_heaters','Solar water heaters','سخانات المياه الشمسية',20),
  ('solar','battery_storage','Battery storage','أنظمة تخزين البطاريات',30),
  ('solar','grid_connection','Grid connection & approvals','الربط بالشبكة والموافقات',40),
  ('solar','maintenance','Solar maintenance & cleaning','صيانة وتنظيف الألواح الشمسية',50),
  ('chemicals','construction_chemicals','Construction chemicals','الكيماويات الإنشائية',10),
  ('chemicals','adhesives_sealants','Adhesives & sealants','المواد اللاصقة ومانعات التسرب',20),
  ('chemicals','coatings','Protective coatings','الطلاءات الواقية',30),
  ('chemicals','admixtures','Concrete admixtures','إضافات الخرسانة',40),
  ('chemicals','cleaning_chemicals','Industrial cleaning chemicals','كيماويات التنظيف الصناعي',50),
  ('plastics_pipes','pvc_pipes','PVC pipes & fittings','أنابيب ووصلات PVC',10),
  ('plastics_pipes','hdpe_pipes','HDPE pipes','أنابيب HDPE',20),
  ('plastics_pipes','ppr_pipes','PPR pipes','أنابيب PPR',30),
  ('plastics_pipes','water_tanks','Water tanks','خزانات المياه',40),
  ('plastics_pipes','custom_moulding','Custom plastic manufacturing','تصنيع بلاستيك حسب الطلب',50),
  ('oilfield','valves_fittings','Valves & fittings','الصمامات والوصلات',10),
  ('oilfield','pipes_flanges','Pipes & flanges','الأنابيب والشفاه',20),
  ('oilfield','instrumentation','Instrumentation','أجهزة القياس والتحكم',30),
  ('oilfield','consumables','Industrial consumables','المستهلكات الصناعية',40),
  ('oilfield','rotating_equipment','Pumps & rotating equipment','المضخات والمعدات الدوارة',50),
  ('home_automation','smart_home','Smart home systems','أنظمة المنزل الذكي',10),
  ('home_automation','bms','Building management systems','أنظمة إدارة المباني',20),
  ('home_automation','lighting_control','Lighting control','التحكم بالإنارة',30),
  ('home_automation','intercom','Intercom & door entry','الإنتركم وأنظمة الدخول',40),
  ('home_automation','integration','Programming & integration','البرمجة والتكامل',50),
  ('logistics_moving','moving','Office & home moving','نقل المكاتب والمنازل',10),
  ('logistics_moving','storage','Storage & warehousing','التخزين والمستودعات',20),
  ('logistics_moving','freight','Freight forwarding','الشحن',30),
  ('logistics_moving','customs','Customs clearance','التخليص الجمركي',40),
  ('logistics_moving','site_delivery','Site delivery & transport','التوصيل والنقل إلى الموقع',50),
  ('packaging','cartons','Cartons & boxes','الكراتين والصناديق',10),
  ('packaging','protective','Protective packaging','مواد التغليف الواقية',20),
  ('packaging','printing','Commercial printing','الطباعة التجارية',30),
  ('packaging','labels','Labels & stickers','الملصقات',40),
  ('packaging','pallets_wrapping','Pallets & wrapping','المنصات والتغليف',50),
  ('marine','ship_supply','Ship supply & chandlery','تموين السفن',10),
  ('marine','marine_equipment','Marine equipment','المعدات البحرية',20),
  ('marine','marine_works','Marine construction works','الأعمال الإنشائية البحرية',30),
  ('marine','diving','Diving & underwater services','الغوص والخدمات تحت الماء',40),
  ('marine','offshore','Offshore supply','الإمدادات البحرية للمنصات',50),
  ('it_services','network_install','Network installation','تركيب الشبكات',10),
  ('it_services','structured_cabling','Structured cabling','الكابلات المهيكلة',20),
  ('it_services','it_support','IT support & maintenance','الدعم والصيانة التقنية',30),
  ('it_services','cybersecurity','Cybersecurity','الأمن السيبراني',40),
  ('it_services','hardware_supply','Hardware supply','توريد الأجهزة',50),
  ('fire_fighting','fire_alarm','Fire alarm systems','أنظمة إنذار الحريق',10),
  ('fire_fighting','sprinklers','Sprinkler systems','أنظمة الرشاشات',20),
  ('fire_fighting','fire_pumps','Fire pumps','مضخات الحريق',30),
  ('fire_fighting','extinguishers','Fire extinguishers','طفايات الحريق',40),
  ('fire_fighting','civil_defence','Civil defence approvals & maintenance','موافقات وصيانة الدفاع المدني',50),
  ('joinery','kitchens','Kitchens','المطابخ',10),
  ('joinery','wardrobes','Wardrobes & closets','الخزائن والدواليب',20),
  ('joinery','wooden_doors','Wooden doors','الأبواب الخشبية',30),
  ('joinery','custom_furniture','Custom furniture','الأثاث حسب الطلب',40),
  ('joinery','wood_panelling','Wood panelling','التكسية الخشبية',50),
  ('glazing','tempered_laminated','Tempered & laminated glass','الزجاج المقسّى والمصفّح',10),
  ('glazing','partitions','Shower & glass partitions','فواصل الاستحمام والقواطع الزجاجية',20),
  ('glazing','mirrors','Mirrors','المرايا',30),
  ('glazing','frameless','Frameless glazing','الزجاج بدون إطار',40),
  ('glazing','glass_facades','Glass façades','الواجهات الزجاجية',50),
  ('aluminium','windows_doors','Aluminium windows & doors','نوافذ وأبواب الألمنيوم',10),
  ('aluminium','acp_cladding','ACP cladding','تكسية الألواح المركبة ACP',20),
  ('aluminium','curtain_wall','Curtain wall','الحوائط الستائرية',30),
  ('aluminium','louvres','Louvres','اللوفرات',40),
  ('aluminium','pergolas_shades','Pergolas & shades','البرجولات والمظلات',50),
  ('steel','structural_steel','Structural steel','الهياكل الفولاذية',10),
  ('steel','fabrication_welding','Metal fabrication & welding','تشكيل المعادن واللحام',20),
  ('steel','handrails','Handrails & balustrades','الدرابزين',30),
  ('steel','stainless','Stainless steel works','أعمال الستانلس ستيل',40),
  ('steel','gates_fencing','Gates & fencing','البوابات والأسوار',50),
  ('flooring','tiling','Tiling','التبليط',10),
  ('flooring','marble_granite','Marble & granite','الرخام والجرانيت',20),
  ('flooring','parquet_vinyl','Parquet & vinyl','الباركيه والفينيل',30),
  ('flooring','epoxy','Epoxy flooring','أرضيات الإيبوكسي',40),
  ('flooring','carpet','Carpet','السجاد والموكيت',50),
  ('painting','interior','Interior painting','الدهان الداخلي',10),
  ('painting','exterior','Exterior painting','الدهان الخارجي',20),
  ('painting','decorative','Decorative finishes','التشطيبات الديكورية',30),
  ('painting','protective_coating','Protective & industrial coatings','الطلاءات الواقية والصناعية',40),
  ('painting','repainting','Repainting & touch-up','إعادة الدهان والترميم',50),
  ('gypsum','false_ceiling','False ceilings','الأسقف المعلقة',10),
  ('gypsum','partitions','Gypsum partitions','قواطع الجبس',20),
  ('gypsum','plastering','Plastering','اللياسة',30),
  ('gypsum','decorative','Decorative gypsum','الجبس الديكوري',40),
  ('gypsum','acoustic_ceiling','Acoustic ceilings','الأسقف الصوتية',50),
  ('signage','shop_signs','Shop signs','لافتات المحلات',10),
  ('signage','letters_3d','3D & acrylic letters','الحروف البارزة والأكريليك',20),
  ('signage','wayfinding','Wayfinding signs','لافتات الإرشاد',30),
  ('signage','lightbox','Light boxes','الصناديق المضيئة',40),
  ('signage','large_format','Large-format printing','الطباعة كبيرة الحجم',50),
  ('landscaping','softscape','Softscape & planting','الزراعة والتشجير',10),
  ('landscaping','hardscape','Hardscape','الأعمال الصلبة للحدائق',20),
  ('landscaping','irrigation','Irrigation systems','أنظمة الري',30),
  ('landscaping','pools','Swimming pools','المسابح',40),
  ('landscaping','maintenance','Garden maintenance','صيانة الحدائق',50),
  ('security_systems','cctv','CCTV','كاميرات المراقبة',10),
  ('security_systems','access_control','Access control','أنظمة التحكم بالدخول',20),
  ('security_systems','barriers_turnstiles','Gate barriers & turnstiles','حواجز البوابات والبوابات الدوارة',30),
  ('security_systems','intruder_alarm','Intruder alarms','أنظمة إنذار السرقة',40),
  ('security_systems','guarding','Security guarding','خدمات الحراسة الأمنية',50),
  ('elevators','supply_install','Elevator supply & installation','توريد وتركيب المصاعد',10),
  ('elevators','escalators','Escalators & travelators','السلالم والممرات المتحركة',20),
  ('elevators','maintenance','Maintenance contracts','عقود الصيانة',30),
  ('elevators','modernisation','Modernisation','التحديث والتطوير',40),
  ('elevators','home_lifts','Home lifts','مصاعد المنازل',50),
  ('doors','wooden_doors','Wooden doors','الأبواب الخشبية',10),
  ('doors','fire_doors','Fire-rated doors','الأبواب المقاومة للحريق',20),
  ('doors','automatic_doors','Automatic doors','الأبواب الأوتوماتيكية',30),
  ('doors','shutters','Rolling shutters','الأبواب المعدنية الملفوفة',40),
  ('doors','ironmongery','Ironmongery','الإكسسوارات والمقابض المعدنية',50),
  ('waterproofing','roof','Roof waterproofing','العزل المائي للأسطح',10),
  ('waterproofing','basement','Basement & foundation waterproofing','عزل القبو والأساسات',20),
  ('waterproofing','wet_areas','Wet-area waterproofing','عزل المناطق الرطبة',30),
  ('waterproofing','thermal','Thermal insulation','العزل الحراري',40),
  ('waterproofing','acoustic','Acoustic insulation','العزل الصوتي',50),
  ('upholstery','curtains','Curtains','الستائر',10),
  ('upholstery','blinds','Blinds','الستائر الرول والشرائح',20),
  ('upholstery','sofa','Sofa & furniture upholstery','تنجيد الكنب والأثاث',30),
  ('upholstery','majlis','Majlis making','تفصيل المجالس',40),
  ('upholstery','fabric_supply','Fabric supply','توريد الأقمشة',50),
  ('wallpaper','supply_install','Wallpaper supply & installation','توريد وتركيب ورق الجدران',10),
  ('wallpaper','wall_panels','Wall panels','ألواح الجدران',20),
  ('wallpaper','wall_cladding','Wall cladding','تكسية الجدران',30),
  ('wallpaper','murals','Custom murals','الجداريات حسب الطلب',40),
  ('wallpaper','removal','Wallpaper removal','إزالة ورق الجدران',50),
  ('scaffolding','rental','Scaffolding rental','تأجير السقالات',10),
  ('scaffolding','erection','Erection & dismantling','التركيب والفك',20),
  ('scaffolding','formwork_shoring','Formwork & shoring','الشدات والدعامات',30),
  ('scaffolding','access_platforms','Access platforms','منصات الوصول',40),
  ('scaffolding','inspection','Scaffold inspection','فحص السقالات',50),
  ('cleaning','deep_cleaning','Deep cleaning','التنظيف العميق',10),
  ('cleaning','post_construction','Post-construction cleaning','التنظيف بعد البناء',20),
  ('cleaning','facade_windows','Façade & window cleaning','تنظيف الواجهات والنوافذ',30),
  ('cleaning','pest_control','Pest control','مكافحة الحشرات',40),
  ('cleaning','facility_management','Facility management','إدارة المرافق',50),
  ('av_it','audio_visual','Audio-visual systems','أنظمة الصوت والصورة',10),
  ('av_it','public_address','Public address','أنظمة الإذاعة الداخلية',20),
  ('av_it','data_cabling','Data cabling','كابلات البيانات',30),
  ('av_it','telecom','Telecom','الاتصالات',40),
  ('av_it','satellite_iptv','Satellite & IPTV','أنظمة الأقمار الصناعية وIPTV',50),
  ('interior_fitout','turnkey','Turnkey fit-out','التجهيز الداخلي المتكامل',10),
  ('interior_fitout','office','Office fit-out','تجهيز المكاتب',20),
  ('interior_fitout','retail','Retail fit-out','تجهيز المحلات',30),
  ('interior_fitout','interior_design','Interior design','التصميم الداخلي',40),
  ('interior_fitout','refurbishment','Refurbishment','الترميم والتجديد',50),
  ('civil_works','new_construction','New building construction','إنشاء المباني الجديدة',10),
  ('civil_works','concrete','Concrete works','أعمال الخرسانة',20),
  ('civil_works','blockwork','Blockwork & masonry','أعمال الطابوق والبناء',30),
  ('civil_works','demolition','Demolition','الهدم',40),
  ('civil_works','excavation','Excavation & backfilling','الحفر والردم',50),
  ('mep_general','mep_install','Full MEP installation','تنفيذ الأعمال الكهروميكانيكية المتكاملة',10),
  ('mep_general','mep_maintenance','MEP maintenance','صيانة الأعمال الكهروميكانيكية',20),
  ('mep_general','testing_commissioning','Testing & commissioning','الاختبار والتشغيل',30),
  ('mep_general','shop_drawings','Shop drawings','المخططات التنفيذية',40),
  ('mep_general','authority_approvals','Authority approvals','الموافقات الحكومية',50)
) v(trade_code, code, label_en, label_ar, sort)
where exists (select 1 from public.taxonomy_trade t where t.code = v.trade_code)
on conflict (trade_code, code) do update
  set label_en = excluded.label_en, label_ar = excluded.label_ar, sort = excluded.sort;

-- PROBE (no raise exception: this file defines tables, and a raise would roll them back).
-- Asserts: every active trade has at least five services; every service has Arabic; the flag is
-- present; and the audit table takes and gives back a row for a supplier id no real company holds
-- (a negative id -- leads ids are positive), leaving nothing behind.
do $probe$
declare
  v_bare int; v_rows int; v_flag jsonb; v_left int;
begin
  select count(*) into v_bare from public.taxonomy_trade t
   where t.active and (select count(*) from public.taxonomy_trade_service s where s.trade_code = t.code and s.active) < 5;
  select count(*) into v_rows from public.taxonomy_trade_service;
  select value into v_flag from public.decision_policy where key = 'supplier_voice_input_enabled';
  if v_bare > 0 then raise warning 'CHK<<% active trade(s) have fewer than five services>>', v_bare; end if;
  if v_flag is null then raise warning 'CHK<<supplier_voice_input_enabled missing>>'; end if;

  insert into public.supplier_voice_note (supplier_id, bytes, duration_ms, mime, outcome)
  values (-900000001, 0, 0, 'audio/wav', 'flag_off');
  delete from public.supplier_voice_note where supplier_id = -900000001;
  select count(*) into v_left from public.supplier_voice_note where supplier_id < 0;
  if v_left <> 0 then raise warning 'CHK<<probe left % voice-note row(s)>>', v_left; end if;

  raise notice 'CHK<<services=% trades_short=% voice_flag=% probe_left=%>>', v_rows, v_bare, v_flag, v_left;
end
$probe$;
