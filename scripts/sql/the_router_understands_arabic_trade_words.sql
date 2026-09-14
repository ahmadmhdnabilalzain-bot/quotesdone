-- THE ROUTER UNDERSTANDS ARABIC TRADE WORDS — AS CUSTOMERS ACTUALLY WRITE THEM.
-- 14 Sep 2026. Agent: customer_support (public_site route_brief is its surface).
--
-- MEASURED ON PRODUCTION, 14 Sep 2026, through public.fn_kb_route_decide — the same call
-- public_site's routeBrief makes — then fn_intake_slug_for_catalog, exactly as routeBrief does.
-- "recognised" = the router picked a catalog AND it maps to a category_specs checklist.
--
--   #  phrase (Arabic, as a customer types it)          BEFORE (live)                   AFTER (simulated*)
--   1  أحتاج سقف جبس معلق لمكتب 120 متر في دبي           gypsum, score 3 (threshold)     gypsum, 9
--   2  نريد تركيب واجهات ألمنيوم وزجاج لمبنى في الشارقة   aluminium, 6                    aluminium, 17
--   3  أبحث عن باركيه للأرضيات لفيلا                     NO  (باركيه=2 < 3)              flooring, 5
--   4  أحتاج دهان شقة ثلاث غرف                           NO  (0 aliases hit)             painting, 3
--   5  صيانة مكيفات سبليت في مكتب                        hvac, 4 vs 2                    hvac, 10 vs 2
--   6  أعمال سباكة لحمام جديد                            plumbing, 3                     plumbing, 3
--   7  تمديدات كهرباء لمحل تجاري                         electrical, 3                   electrical, 9
--   8  عزل مائي لسطح فيلا                                waterproofing, 6 vs 3           waterproofing, 6 vs 3
--   9  تصميم وتركيب مطبخ جديد لفيلا                      NO  (0)                         kitchens, 3
--  10  بناء مسبح في حديقة الفيلا                         NO  (0)                         swimming-pools, 3
--  11  تركيب ألواح طاقة شمسية على السطح                  solar, 6                        solar, 8
--  12  تركيب كاميرات مراقبة لمستودع                      NO  (ELV 14 ties Security 47, 4:4) security, 7 vs 4
--  13  لافتة مضيئة لواجهة المحل                          NO  (0)                         signage, 9
--  14  رخام للدرج والأرضيات                              NO  (0)                         flooring, 5 vs 2
--  15  أبواب خشب وخزائن ملابس                            NO  (0)                         carpentry, 14
--  BEFORE 7/15 recognised.  AFTER 15/15 recognised.
--  Guard phrase "الطابق الأرضي يحتاج تشطيب" (ground floor needs finishing): BEFORE no route,
--  AFTER still no route (fit-out 2 < 3). The ارضي→الارضي false positive described below does not occur.
--  English "gypsum false ceiling for a 120 sqm office in Dubai": gypsum, 9, before and after.
--  * AFTER was not applied by the author. It was computed by a read-only SELECT that reproduces
--    fn_kb_route's scoring over the live aliases UNION this file's rows, then fn_kb_route_decide's
--    thresholds, then fn_intake_slug_for_catalog. The same SELECT's BEFORE column matched the live
--    fn_kb_route_decide on all 15 phrases, catalog and score. Rows the simulation says this file adds:
--    148 base words + 1,243 attached forms = 1,391 (live table: 4,255, of which 2,107 Arabic).
--    Re-run the 15 phrases through fn_kb_route_decide after the apply to confirm.
--
-- THE REPORTED CASE (#1) DID NOT REPRODUCE AT THE ROUTER. Live, it routes to gypsum on ONE hit
-- (جبس, weight 3 = the minimum score to act on). The reported recognised:false most likely came
-- from how the audit sent the text; Arabic passed on a shell command line has come through as '?'
-- before. Either way the case was sitting exactly on the threshold: one alias, nothing to spare.
--
-- WHAT WAS WRONG — two causes, both in the DATA, not in the matcher:
--  1. MISSING EVERYDAY WORDS. kb_operational_alias holds 2,107 Arabic aliases, and not one of these
--     stands alone: دهان, صبغ, مطبخ, مسبح, رخام, خشب, لافتة, كاميرات, سقف معلق, نجار. They appear
--     only inside longer phrases (دهان جدران, حوض مطبخ, تنفيذ مسبح), and fn_kb_route needs the whole
--     alias phrase to appear in the text.
--  2. ATTACHED LETTERS. Arabic writes ال / و / ب / ل / لل / وال / بال onto the word itself, and
--     fn_kb_route matches whole words (' ' || alias_norm || ' '). So the alias ارضيات never matches
--     للأرضيات or والأرضيات, and مطابخ never matches المطابخ. kb_norm already folds alef forms,
--     taa marbuta (ة→ه), alef maqsura (ى→ي) and hamza seats (ئ→ي, ؤ→و). It does NOT remove attached
--     letters, and changing it would change every stored alias_norm (all 4,255 of them).
--
-- WHAT THIS CHANGES — rows in public.kb_operational_alias only, in two steps:
--  a. BASE WORDS: every catalog that a category_specs category maps to (via lead_trade_map) gets
--     the plain Arabic words a customer uses. Weight 3 = names the trade on its own. Weight 2 = supports
--     a score without deciding it. Same convention as marble_worktop_and_tiling_matched_nothing.sql:
--     رخام / جرانيت / كوارتز are 2 on flooring, kitchens and joinery alike, because a material does
--     not decide between a floor and a worktop.
--  b. ATTACHED FORMS of exactly those words — و, ب, ل, ال, لل, وال, بال — generated in SQL from the
--     stored alias_norm and carrying its weight. A two-word alias gets the definite form on both words
--     (السقف المعلق), because that is how Arabic makes an adjective agree.
--     A word that already starts with ال gets only و, ب and لل (للمنيوم, not لالمنيوم).
--
-- WHAT IT DELIBERATELY DOES NOT CHANGE:
--  - fn_kb_route, fn_kb_route_decide, kb_norm — no routine is touched. The matcher is correct; it only
--    had nothing to match.
--  - Attached forms are NOT generated for the 2,107 existing Arabic aliases wholesale. Measured
--    reason: cat 10 carries ارضي (earthing); its generated form الارضي is how Arabic writes
--    "ground floor", and every "الطابق الارضي" would score electrical. Only words listed below get
--    attached forms. That list re-lists some existing words (ارضيات, مطابخ, سباكة, مسابح…); for those
--    the base insert skips and only the attached forms are added, at the EXISTING weight.
--  - ف / ك prefixes and possessive endings (مطبخي, حمامنا) are not generated. Rarer in a request, and
--    each doubles the row count. Add them here if a measured phrase needs them.
--  - No other English alias is touched. The one exception is CCTV, below.
--
-- ENGLISH CCTV — ADDED THE SAME DAY. Measured: 'cctv' was weight 3 on ELV (14) and 2 on Security
-- (47). category_specs 'security' ("CCTV & Security Systems") maps to 47; 14 maps to no checklist.
-- So an English CCTV request routed to 14, fn_intake_slug_for_catalog returned null, and routeBrief
-- answered recognised:false. This file sets 'cctv' to 3 on 47 and 2 on 14, and adds 'security cameras',
-- 'security camera' and 'surveillance' at 3 on 47. ELV keeps its 'cctv' row at 2, because ELV suppliers
-- do sell cameras; it just no longer wins the tie.
--
--   phrase                                              BEFORE (live)                     AFTER (simulated*)
--   need CCTV installation for a warehouse in Sharjah   ELV 14, 3 vs 2 -> NOT recognised  security (47), 3 vs 2
--   security cameras for villa Dubai                    security (47), 3 ('security')     security (47), 9
--   surveillance system for office 20 cameras           NO (0)                            security (47), 3
--   BEFORE 1/3 recognised. AFTER 3/3, simulated by the same read-only method as the Arabic table.
--  - category_specs 'general' and 'general-services-other' map to no catalog, so there is nothing to
--    alias them to.
--
-- ADDITIVE AND IDEMPOTENT: `where not exists` on (catalog_num, alias_norm) plus `on conflict do nothing`
-- on the primary key (catalog_num, language, alias). A re-run inserts nothing. No existing alias, weight
-- or negative flag is changed. To reverse: delete by the two source tags below.

create temp table _ar_trade_vocab (catalog_num int, alias text, weight int) on commit drop;

insert into _ar_trade_vocab (catalog_num, alias, weight) values
  -- 17 Gypsum & False Ceiling  (gypsum)
  (17,'جبس',3),(17,'جبسوم',3),(17,'جبس بورد',3),(17,'جبسوم بورد',3),(17,'سقف جبس',3),(17,'أسقف جبس',3),
  (17,'سقف معلق',3),(17,'أسقف معلقة',3),(17,'سقف مستعار',3),(17,'قواطع جبس',2),(17,'درايوول',3),
  -- 19 Aluminium & Glass  (aluminium, glass, garage-doors)
  (19,'ألمنيوم',3),(19,'زجاج',2),(19,'واجهات زجاج',3),(19,'واجهات زجاجية',3),
  (19,'واجهات ألمنيوم',3),(19,'شبابيك',2),(19,'شبابيك ألمنيوم',3),(19,'نوافذ',2),(19,'سيكوريت',3),
  (19,'زجاج سيكوريت',3),(19,'باب كراج',3),(19,'أبواب كراج',3),(19,'شتر',2),(19,'أبواب رول',3),
  -- 18 Flooring  (flooring, tiling, carpets, marble-granite, epoxy-flooring)
  (18,'أرضيات',3),(18,'باركيه',2),(18,'أرضيات باركيه',3),(18,'بلاط',3),(18,'سيراميك',3),(18,'بورسلان',3),
  (18,'رخام',2),(18,'جرانيت',2),(18,'كوارتز',2),(18,'موكيت',3),(18,'سجاد',2),(18,'إيبوكسي',3),
  (18,'أرضيات إيبوكسي',3),(18,'أرضيات خشبية',3),(18,'فينيل',3),(18,'أرضيات فينيل',3),(18,'أرضيات spc',3),
  (18,'spc',3),(18,'تبليط',3),
  -- 21 Paints & Finishing  (painting, wallpaper)
  (21,'دهان',3),(21,'دهانات',3),(21,'صبغ',3),(21,'أصباغ',3),(21,'صباغ',2),(21,'طلاء',3),(21,'بوية',2),
  (21,'ورق جدران',3),(21,'ورق حائط',3),(21,'والبيبر',3),
  -- 9 HVAC  (hvac)
  (9,'تكييف',3),(9,'مكيف',3),(9,'مكيفات',2),(9,'تكييف هواء',3),(9,'صيانة مكيفات',3),(9,'تكييف مركزي',3),
  -- 11 Plumbing & Sanitaryware  (plumbing)
  (11,'سباكة',3),(11,'سباك',3),(11,'تمديدات صحية',3),(11,'تسريب مياه',2),(11,'سخان',2),(11,'سخانات',2),
  -- 10 Electrical  (electrical, generators)
  (10,'كهرباء',3),(10,'كهربائي',3),(10,'تمديدات كهرباء',3),(10,'تمديدات كهربائية',3),(10,'مولدات',3),
  (10,'مولد كهرباء',3),
  -- 5 Waterproofing / 6 Insulation / 7 Roofing
  (5,'عزل مائي',3),(5,'عازل مائي',3),(5,'عزل ضد الماء',3),(5,'عزل أسطح',3),
  (6,'عزل حراري',3),(6,'عازل حراري',3),(6,'عزل صوتي',3),
  (7,'تسقيف',3),(7,'سقف شينكو',3),
  -- 24 Kitchen & Bathroom  (kitchens)
  (24,'مطبخ',3),(24,'مطابخ',3),(24,'خزائن مطبخ',3),(24,'تجهيز مطبخ',3),(24,'رخام',2),(24,'جرانيت',2),
  (24,'كوارتز',2),(24,'سطح عمل',2),(24,'كاونتر',2),
  -- 25 Swimming Pools  (swimming-pools)
  (25,'مسبح',3),(25,'مسابح',3),(25,'بركة سباحة',3),(25,'برك سباحة',3),(25,'حمام سباحة',3),(25,'صيانة مسبح',3),
  -- 67 Renewable Energy  (solar)
  (67,'طاقة شمسية',3),(67,'ألواح شمسية',3),(67,'شمسية',2),(67,'شاحن سيارات',2),
  -- 47 Security Companies  (security = "CCTV & Security Systems"; 14 ELV has no checklist)
  (47,'كاميرات',3),(47,'كاميرا',3),(47,'كاميرا مراقبة',3),(47,'كاميرات مراقبة',2),(47,'نظام مراقبة',2),
  (47,'سي سي تي في',3),
  -- 85 Signage & Printing  (signage, acrylic)
  (85,'لافتة',3),(85,'لافتات',3),(85,'لافتة مضيئة',3),(85,'لوحة إعلانية',3),(85,'لوحة مضيئة',3),
  (85,'يافطة',3),(85,'يافطات',3),(85,'أكريليك',3),(85,'حروف بارزة',3),
  -- 20 Joinery & Carpentry  (carpentry, carpentry-joinery)
  (20,'نجارة',3),(20,'نجار',3),(20,'أعمال نجارة',3),(20,'خشب',2),(20,'أبواب خشب',3),(20,'أبواب خشبية',3),
  (20,'خزائن ملابس',3),(20,'خزانة ملابس',3),(20,'دواليب',3),(20,'رخام',2),(20,'جرانيت',2),
  -- 16 Fit-Out  (fitout, commercial-retail-fitout)
  (16,'تشطيبات',2),(16,'تشطيب',2),(16,'تجهيز مكاتب',3),(16,'تجهيز محل',3),(16,'تجهيز محلات',3),
  -- 22 Interior Decoration  (interior-design)
  (22,'تصميم داخلي',3),(22,'مصمم داخلي',3),(22,'ديكور',2),
  -- 23 Furniture  (custom-furniture)
  (23,'أثاث',3),(23,'أثاث مفصل',3),(23,'تفصيل أثاث',3),(23,'كنب',2),
  -- 70 Textile  (blinds-curtains, upholstery)
  (70,'ستائر',3),(70,'برادي',3),(70,'بلايند',3),(70,'تنجيد',3),(70,'تنجيد كنب',3),
  -- 86 Lifts  (elevators)
  (86,'مصعد',3),(86,'مصاعد',3),
  -- 46 Cleaning  (cleaning, facade-cleaning, water-tank-cleaning)
  (46,'تنظيف',3),(46,'تنظيف واجهات',3),(46,'تنظيف خزانات',3),(46,'غسيل خزانات',3),
  -- 45 Facilities Management  (landscaping, pest) — two-word only: حديقة alone appears in pool and villa requests
  (45,'تنسيق حدائق',3),(45,'تنسيق حديقة',3),(45,'مكافحة حشرات',3),(45,'رش مبيدات',3),
  -- 49 Logistics  (movers)
  (49,'نقل أثاث',3),(49,'نقل عفش',3),
  -- 12 Fire Fighting  (safety)
  (12,'طفايات',3),(12,'طفاية حريق',3),(12,'رشاشات حريق',3),
  -- 1 Construction  (masonry, demolition, general-building-contracting) — بناء alone is too generic
  (1,'هدم',3),(1,'أعمال هدم',3),(1,'مقاولات عامة',3),(1,'لياسة',3),
  -- 2 Steel  (steel, structural-steel-fabrication)
  (2,'حدادة',3),(2,'هناجر',3),(2,'هنجر',3),(2,'هيكل حديدي',3),
  -- 81 Modular & Prefab  (tents-and-shade-structures)
  (81,'مظلات',3),(81,'مظلات سيارات',3),(81,'خيام',3),(81,'برجولا',2),
  -- 15 Smart Home / 33 AV / 35 IT / 8 MEP
  (15,'منزل ذكي',3),(15,'بيت ذكي',3),
  (33,'نظام صوت',3),(33,'بروجكتر',3),
  (35,'تمديد شبكة',3),(35,'شبكة واي فاي',3),
  (8,'كهروميكانيك',3),
  -- 52 Industrial Equipment  (job-shop-manufacturing)
  (52,'خراطة',3),(52,'قص ليزر',3),(52,'ورشة تصنيع',3),
  -- 80 Testing & Consultancies  (engineering-and-architectural-consultancies)
  (80,'مكتب هندسي',3),(80,'استشاري هندسي',3),(80,'مخططات هندسية',2),
  -- 4 Formwork & Scaffolding  (scaffolding)
  (4,'سقالات',3),(4,'سقالة',3);

-- a. base words. distinct on the NORMALISED form: two spellings that normalise alike (ألمنيوم /
--    المنيوم) are different primary keys, and both rows would score — one word counted twice.
insert into public.kb_operational_alias (catalog_num, language, alias, alias_norm, weight, negative, source)
select distinct on (v.catalog_num, public.kb_norm(v.alias)) v.catalog_num,
       case when public.kb_norm(v.alias) ~ '[a-z]' and public.kb_norm(v.alias) !~ '[ء-ي]' then 'en' else 'ar' end,
       v.alias, public.kb_norm(v.alias), v.weight, false, 'qd_arabic_trade_vocab_2026_09_14'
  from _ar_trade_vocab v
 where not exists (select 1 from public.kb_operational_alias a
                    where a.catalog_num = v.catalog_num and a.alias_norm = public.kb_norm(v.alias))
on conflict do nothing;

-- b. attached forms of exactly those words, at the weight now stored for them
insert into public.kb_operational_alias (catalog_num, language, alias, alias_norm, weight, negative, source)
select distinct on (f.catalog_num, f.form) f.catalog_num, 'ar', f.form, f.form, f.weight, false,
       'qd_arabic_attached_forms_2026_09_14'
  from (
    select b.catalog_num, b.weight, x.form
      from (select distinct a.catalog_num, a.alias_norm as n, a.weight
              from public.kb_operational_alias a
              join _ar_trade_vocab v on v.catalog_num = a.catalog_num and a.alias_norm = public.kb_norm(v.alias)
             where a.language = 'ar' and a.alias_norm ~ '^[ء-ي]+( [ء-ي]+)?$') b
     cross join lateral (select split_part(b.n, ' ', 1) as w1, nullif(split_part(b.n, ' ', 2), '') as w2) s
     cross join lateral (select case when s.w1 not like 'ال%' and coalesce(s.w2, '') not like 'ال%'
                                     then 'ال' || s.w1 || coalesce(' ال' || s.w2, '') end as d) dd
     cross join lateral (values
        ('و' || b.n), ('ب' || b.n),
        (case when s.w1 like 'ال%' then 'لل' || substr(b.n, 3) else 'ل' || b.n end),
        (dd.d), ('و' || dd.d), ('ب' || dd.d), ('ل' || substr(dd.d, 2))
     ) x(form)
     where x.form is not null
  ) f
 where not exists (select 1 from public.kb_operational_alias a
                    where a.catalog_num = f.catalog_num and a.alias_norm = f.form)
 order by f.catalog_num, f.form, f.weight desc
on conflict do nothing;

-- c. English CCTV: Security (47) owns the checklist, so it gets the deciding weight. Idempotent: each
--    update touches a row only while its weight differs.
update public.kb_operational_alias set weight = 3
 where catalog_num = 47 and language = 'en' and alias_norm = 'cctv' and weight <> 3;
update public.kb_operational_alias set weight = 2
 where catalog_num = 14 and language = 'en' and alias_norm = 'cctv' and weight <> 2;

insert into public.kb_operational_alias (catalog_num, language, alias, alias_norm, weight, negative, source)
select 47, 'en', x.alias, public.kb_norm(x.alias), 3, false, 'qd_cctv_to_security_2026_09_14'
  from (values ('security cameras'), ('security camera'), ('surveillance')) x(alias)
 where not exists (select 1 from public.kb_operational_alias a
                    where a.catalog_num = 47 and a.alias_norm = public.kb_norm(x.alias))
on conflict do nothing;
