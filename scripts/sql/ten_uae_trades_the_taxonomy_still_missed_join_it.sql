-- TEN UAE TRADES THE TAXONOMY STILL MISSED JOIN IT. Seat: sales_engineer. 19 Oct 2026.
-- Founder ledger 899 / 900 / 903: every category sold in the UAE except food & beverage; "first find which
-- trades are missing and add them to the platform taxonomy; then build knowledge for the complete trade list".
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 19 Oct 2026): taxonomy_trade 213 active codes in 12
-- groups, 1,047 active services. Each candidate below was checked against BOTH the trade labels and every active
-- service label (regex over label_en) before it was called missing. Candidates already held as a SERVICE of an
-- existing trade were NOT added as a trade (exact trade or none; a second home splits the supplier pool):
--   lifting gear -> material_handling "Hoists & lifting gear"; IT hardware, servers, cybersecurity, cloud ->
--   it_services; drone filming/mapping -> photo_video_production, land_survey; gate barriers -> security_systems;
--   workshop equipment -> hand_power_tools; kitchens and wardrobes -> joinery; carpet -> flooring;
--   luggage -> leather_footwear; weighing-scale CALIBRATION -> calibration_services (the SUPPLY of scales had no home).
-- What had no trade and no service anywhere, and is bought in the UAE by businesses or households:
--   apparel_fashion_wholesale, optical_eyewear, home_furniture, weighing_systems, drones_uav, occupational_health,
--   artwork_decor, bicycles_micromobility, baby_nursery_products, houseware_wholesale.
--
-- SAME RULES AS scripts/sql/the_missing_trades_join_the_taxonomy_under_twelve_groups.sql: aliases are the trade's
-- own two names and nothing else; every code is two words or more (fn_norm_trades reads the bare code word-start);
-- authority_required is left '{}' (a licence requirement is added when confirmed, never guessed); no supplier,
-- inquiry, tick or exclusion is rewritten. Idempotent: every insert is on conflict.

insert into public.taxonomy_trade (code, label, label_ar, aliases, sort, active, group_code)
select v.code, v.label, v.label_ar, v.aliases, v.sort, true, v.group_code
from (values
  ('apparel_fashion_wholesale','Garments & fashion wholesale','تجارة الملابس والأزياء بالجملة',array['garments & fashion wholesale','تجارة الملابس والأزياء بالجملة']::text[],480,'furniture_hospitality_consumer'),
  ('optical_eyewear','Optical & eyewear','البصريات والنظارات',array['optical & eyewear','البصريات والنظارات']::text[],481,'health_lab_safety'),
  ('home_furniture','Home furniture & mattresses','أثاث المنازل والمراتب',array['home furniture & mattresses','أثاث المنازل والمراتب']::text[],482,'furniture_hospitality_consumer'),
  ('weighing_systems','Weighing scales & weighbridges','موازين وجسور وزن',array['weighing scales & weighbridges','موازين وجسور وزن']::text[],483,'industrial_manufacturing'),
  ('drones_uav','Drones & unmanned aircraft','الطائرات بدون طيار (الدرون)',array['drones & unmanned aircraft','الطائرات بدون طيار (الدرون)']::text[],484,'technology_telecom'),
  ('occupational_health','Occupational health & onsite medical services','الصحة المهنية والخدمات الطبية في الموقع',array['occupational health & onsite medical services','الصحة المهنية والخدمات الطبية في الموقع']::text[],485,'health_lab_safety'),
  ('artwork_decor','Artwork, framing & decor','الأعمال الفنية والبراويز والديكور',array['artwork, framing & decor','الأعمال الفنية والبراويز والديكور']::text[],486,'furniture_hospitality_consumer'),
  ('bicycles_micromobility','Bicycles & e-scooters','الدراجات الهوائية والسكوترات الكهربائية',array['bicycles & e-scooters','الدراجات الهوائية والسكوترات الكهربائية']::text[],487,'transport_mobility'),
  ('baby_nursery_products','Baby & nursery products','منتجات الأطفال الرضع وغرف الأطفال',array['baby & nursery products','منتجات الأطفال الرضع وغرف الأطفال']::text[],488,'furniture_hospitality_consumer'),
  ('houseware_wholesale','Houseware & kitchenware wholesale','الأدوات المنزلية وأدوات المطبخ بالجملة',array['houseware & kitchenware wholesale','الأدوات المنزلية وأدوات المطبخ بالجملة']::text[],489,'furniture_hospitality_consumer')
) as v(code, label, label_ar, aliases, sort, group_code)
on conflict (code) do update
   set label = excluded.label, label_ar = excluded.label_ar,
       aliases = (select array_agg(distinct a) from unnest(public.taxonomy_trade.aliases || excluded.aliases) a),
       sort = excluded.sort,
       group_code = coalesce(public.taxonomy_trade.group_code, excluded.group_code);

insert into public.taxonomy_trade_service (trade_code, code, label_en, label_ar, sort)
values
  ('apparel_fashion_wholesale','readymade_garments','Readymade garments','الملابس الجاهزة',10),
  ('apparel_fashion_wholesale','abayas_kanduras','Abayas, kanduras & modest wear','العبايات والكنادير والأزياء المحتشمة',20),
  ('apparel_fashion_wholesale','childrens_wear','Children''s wear','ملابس الأطفال',30),
  ('apparel_fashion_wholesale','sportswear_activewear','Sportswear & activewear','الملابس الرياضية',40),
  ('apparel_fashion_wholesale','private_label_garments','Private-label garment production','إنتاج الملابس بعلامة خاصة',50),
  ('optical_eyewear','spectacle_frames','Spectacle frames','إطارات النظارات',10),
  ('optical_eyewear','ophthalmic_lenses','Ophthalmic lenses','العدسات الطبية للنظارات',20),
  ('optical_eyewear','contact_lenses','Contact lenses & solutions','العدسات اللاصقة ومحاليلها',30),
  ('optical_eyewear','sunglasses','Sunglasses','النظارات الشمسية',40),
  ('optical_eyewear','safety_prescription_eyewear','Prescription safety eyewear','نظارات السلامة الطبية',50),
  ('optical_eyewear','optical_shop_equipment','Optical shop & lab equipment','معدات محلات ومختبرات البصريات',60),
  ('home_furniture','living_dining_furniture','Living & dining furniture','أثاث المعيشة والطعام',10),
  ('home_furniture','bedroom_furniture','Bedroom furniture','أثاث غرف النوم',20),
  ('home_furniture','mattresses_bedding','Mattresses & bedding','المراتب ومستلزمات السرير',30),
  ('home_furniture','majlis_seating','Majlis seating','جلسات المجلس',40),
  ('home_furniture','kids_furniture','Children''s furniture','أثاث الأطفال',50),
  ('home_furniture','furnished_unit_packages','Furnished apartment & villa packages','باقات تأثيث الشقق والفلل',60),
  ('weighing_systems','bench_platform_scales','Bench & platform scales','موازين طاولة ومنصات',10),
  ('weighing_systems','retail_label_scales','Retail & label-printing scales','موازين البيع بالتجزئة وطباعة الملصقات',20),
  ('weighing_systems','weighbridges','Truck weighbridges','جسور وزن الشاحنات',30),
  ('weighing_systems','crane_hook_scales','Crane & hook scales','موازين الرافعات والخطافات',40),
  ('weighing_systems','precision_lab_balances','Precision & laboratory balances','الموازين الدقيقة والمخبرية',50),
  ('weighing_systems','load_cells_indicators','Load cells & weighing indicators','خلايا الحمل ومؤشرات الوزن',60),
  ('drones_uav','camera_drones','Camera & photography drones','طائرات التصوير بدون طيار',10),
  ('drones_uav','survey_mapping_drones','Survey & mapping drones','طائرات المسح ورسم الخرائط',20),
  ('drones_uav','inspection_drones','Inspection & thermal drones','طائرات الفحص والتصوير الحراري',30),
  ('drones_uav','agricultural_spraying_drones','Agricultural spraying drones','طائرات الرش الزراعي',40),
  ('drones_uav','drone_parts_batteries','Drone parts & batteries','قطع غيار وبطاريات الدرون',50),
  ('drones_uav','counter_drone_systems','Counter-drone systems','أنظمة مكافحة الطائرات بدون طيار',60),
  ('occupational_health','pre_employment_medicals','Pre-employment & periodic medicals','الفحوص الطبية قبل التوظيف والدورية',10),
  ('occupational_health','onsite_clinic_nurse','Onsite clinic & nurse staffing','عيادة ميدانية وتوفير ممرضين',20),
  ('occupational_health','first_aid_supplies_kits','First-aid kits & refills','حقائب الإسعافات الأولية وتعبئتها',30),
  ('occupational_health','corporate_wellness_screening','Corporate wellness screening','الفحوص الصحية للشركات',40),
  ('occupational_health','event_medical_cover','Event & site medical cover','التغطية الطبية للفعاليات والمواقع',50),
  ('occupational_health','vaccination_programmes','Workplace vaccination programmes','برامج التطعيم في مكان العمل',60),
  ('artwork_decor','commissioned_artwork','Commissioned artwork','أعمال فنية حسب الطلب',10),
  ('artwork_decor','art_prints_framing','Art prints & framing','المطبوعات الفنية والبراويز',20),
  ('artwork_decor','mirrors_decor','Mirrors & decorative accessories','المرايا وإكسسوارات الديكور',30),
  ('artwork_decor','sculptures_installations','Sculptures & installations','المنحوتات والأعمال الفنية المجسمة',40),
  ('artwork_decor','hotel_art_packages','Hotel & office art packages','باقات الأعمال الفنية للفنادق والمكاتب',50),
  ('artwork_decor','calligraphy_art','Arabic calligraphy art','لوحات الخط العربي',60),
  ('bicycles_micromobility','bicycles','Bicycles','الدراجات الهوائية',10),
  ('bicycles_micromobility','e_bikes','E-bikes','الدراجات الكهربائية',20),
  ('bicycles_micromobility','e_scooters','E-scooters','السكوترات الكهربائية',30),
  ('bicycles_micromobility','cycling_accessories','Helmets, locks & cycling accessories','الخوذ والأقفال وإكسسوارات الدراجات',40),
  ('bicycles_micromobility','bike_racks_parking','Bike racks & parking','حوامل ومواقف الدراجات',50),
  ('bicycles_micromobility','bike_servicing','Bicycle & e-scooter servicing','صيانة الدراجات والسكوترات',60),
  ('baby_nursery_products','strollers_prams','Strollers & prams','عربات الأطفال',10),
  ('baby_nursery_products','child_car_seats','Child car seats','مقاعد الأطفال للسيارات',20),
  ('baby_nursery_products','cots_nursery_furniture','Cots & nursery furniture','أسرّة الأطفال وأثاث غرف الرضع',30),
  ('baby_nursery_products','feeding_accessories','Feeding bottles & accessories','رضاعات الأطفال ومستلزماتها',40),
  ('baby_nursery_products','diapers_wipes','Diapers & baby wipes','الحفاضات ومناديل الأطفال',50),
  ('baby_nursery_products','nursery_fitout_supplies','Nursery & daycare supplies','مستلزمات الحضانات ورياض الأطفال',60),
  ('houseware_wholesale','cookware','Cookware','أواني الطبخ',10),
  ('houseware_wholesale','tableware_glassware','Tableware & glassware','أدوات المائدة والأواني الزجاجية',20),
  ('houseware_wholesale','storage_organisation','Storage & organisation','أدوات التخزين والتنظيم',30),
  ('houseware_wholesale','plasticware_household','Household plasticware','الأدوات المنزلية البلاستيكية',40),
  ('houseware_wholesale','cleaning_tools','Household cleaning tools','أدوات التنظيف المنزلية',50),
  ('houseware_wholesale','home_textiles','Home textiles & towels','المفروشات المنزلية والمناشف',60)
on conflict (trade_code, code) do nothing;

-- PROBE: one verdict row. The ten are active with EN + AR names, a group and at least four active services;
-- the 213 that existed are untouched in count; and a sentence naming another trade's work pulls in none of the ten.
select case
  when (select count(*) from public.taxonomy_trade t where t.active and t.code in ('apparel_fashion_wholesale','optical_eyewear','home_furniture','weighing_systems','drones_uav','occupational_health','artwork_decor','bicycles_micromobility','baby_nursery_products','houseware_wholesale')
          and t.group_code is not null and t.label_ar ~ '[ء-ي]'
          and (select count(*) from public.taxonomy_trade_service s where s.trade_code = t.code and s.active) >= 4) <> 10
    then 'PROBE FAILED: a new trade is missing, inactive, unnamed, ungrouped or has fewer than four services'
  when (select count(*) from public.taxonomy_trade where active) < 223
    then 'PROBE FAILED: fewer than 223 active trades'
  when public.fn_norm_trades('HVAC chiller replacement with calibration certificate, operator training and pumps') <> array['hvac']::text[]
    then 'PROBE FAILED: a bare word pulls a trade in: ' || array_to_string(public.fn_norm_trades('HVAC chiller replacement with calibration certificate, operator training and pumps'), ', ')
  else 'PROBE OK' end as verdict;
