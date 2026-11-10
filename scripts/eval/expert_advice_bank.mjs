// THE EXPERT-ADVICE EVAL BANK (10 Nov 2026, sales_engineer; founder ledger 1572, 1579, 1586). Pure data and graders, no
// network: scripts/eval/expert_advice_eval.mjs drives it; scripts/checks/the_expert_advice_eval_grades_what_it_claims.test.mjs
// proves each grader catches its bad turn offline.
//
// 27 openings across ALL TWELVE taxonomy groups (at least two each; ledger 1586: "never judge or test on the narrowest case"),
// each in five registers: English, Egyptian, Levantine (Lebanese), Gulf and Arabizi. Every conversation is three customer turns:
//   1. the opening (a problem or a need, not a chosen solution: the expert must diagnose and put options);
//   2. a size or quantity fact and "what do you recommend?" (the fact is planted: it must never be asked again);
//   3. "go with what you recommend" and a budget.
// `code` is the taxonomy trade the job must be placed in (any of them), `reask` the question turn 3 must NOT ask again.

export const REGISTERS = ['en', 'egyptian', 'levantine', 'gulf', 'arabizi'];
export const GROUPS = ['construction_building', 'mep_building_systems', 'facilities_property', 'furniture_hospitality_consumer', 'health_lab_safety',
  'industrial_manufacturing', 'marketing_media_events', 'materials_packaging', 'professional_business', 'technology_telecom', 'transport_mobility', 'energy_environment'];

const ASK_SIZE = /\b(size|dimensions?|how (big|large|wide|high|tall|long|many)|measurements?|area|square met|sqm|quantity|how much (area|space))\b|مقاس|قياس|أبعاد|ابعاد|مساحة|المساحة|كم (متر|عدد|قطعة|حبة|راكب|شخص)|عدد|طول|عرض|ارتفاع/i;
const ASK_BUDGET = /\bbudget\b|price range|ميزانية|الميزانية|budget-?ak|el budget/i;

// [id, group, codes (any), opening x5, fact {en, ar, arabizi}, budget, reask]
const O = (id, group, codes, open, fact, budget, reask = ASK_SIZE) => ({ id, group, codes, open, fact, budget, reask });
export const OPENINGS = [
  O('mdf_partition', 'construction_building', ['wallpaper', 'joinery', 'interior_fitout'], {
    en: 'I have a small customised MDF wall partition and want to cover it, thinking PVC panel or a wrap sticker',
    egyptian: 'عندي بارتشن خشب MDF صغير معمول مخصوص، عايز أكسيه، بفكر في PVC ولا استيكر',
    levantine: 'عندي قاطع MDF زغير معمول عالطلب، بدي لبّسو شي، عم فكّر بألواح PVC أو ستيكر',
    gulf: 'عندي قاطع خشب MDF صغير مسوّى تفصيل، أبي ألبسه بديكور PVC أو ستيكر',
    arabizi: '3andi partition MDF sgheer, abi albsa PVC aw sticker, shu ahsan?' },
    { en: 'It is about 2.4 m wide and 1.2 m high, both faces, in a kids room', ar: 'عرضه حوالي ٢٫٤ متر وارتفاعه ١٫٢ متر، من الوجهين، في غرفة أطفال', arabizi: 'el 3ard 2.4 m w el irtifa3 1.2 m, el wajhein, fi ghorfat el atfal' }, '3,000 AED'),
  O('villa_pool', 'construction_building', ['swimming_pools'], {
    en: 'We want to build a swimming pool in our villa garden in Dubai, what is allowed?',
    egyptian: 'عايزين نعمل حمام سباحة في جنينة الفيلا في دبي، إيه المسموح؟',
    levantine: 'بدنا نعمل مسبح بحديقة الفيلا بدبي، شو المسموح؟',
    gulf: 'نبي نسوي مسبح في حوش الفيلا في دبي، شو المسموح؟',
    arabizi: 'nabi nsawi pool fi 7oosh el villa fi Dubai, shu el masmoo7?' },
    { en: 'The space is about 10 by 4 metres, kids will use it', ar: 'المساحة تقريباً ١٠ في ٤ متر، والأطفال راح يستخدمونه', arabizi: 'el masa7a 10 x 4 m, w el 3iyal ra7 yesta5dmoona' }, '180,000 AED'),
  O('scaffolding_hire', 'construction_building', ['scaffolding'], {
    en: 'Need scaffolding to repaint the outside of a G+2 building',
    egyptian: 'محتاج سقالات عشان ندهن واجهة مبنى أرضي ودورين',
    levantine: 'بدي سقالات لندهن واجهة بناية أرضي وطابقين',
    gulf: 'أحتاج سقالات عشان نصبغ واجهة بناية أرضي وطابقين',
    arabizi: 'a7taj sa2alat 3ashan nasbogh wajhat binaya G+2' },
    { en: 'The facade is about 30 m long and 11 m high, for three weeks', ar: 'الواجهة طولها حوالي ٣٠ متر وارتفاعها ١١ متر، لمدة ثلاث أسابيع', arabizi: 'el wajha 30 m tool w 11 m irtifa3, la 3 asabee3' }, '20,000 AED'),
  O('bathroom_tiles', 'construction_building', ['flooring', 'tiling'], {
    en: 'Some of my bathroom floor tiles are cracked and a few sound hollow',
    egyptian: 'شوية بلاط في أرضية الحمام مكسور وفي حتت صوتها فاضي',
    levantine: 'في بلاط بأرض الحمام مكسور وكم وحدة صوتها فاضي',
    gulf: 'بعض بلاط أرضية الحمام مكسور وكم وحدة صوتها فاضي',
    arabizi: 'ba3d el balat fi 7ammam maksoor w kam wa7da sawtha fadi' },
    { en: 'The bathroom is about 2 by 3 metres', ar: 'الحمام تقريباً ٢ في ٣ متر', arabizi: 'el 7ammam ta2reeban 2 x 3 m' }, '6,000 AED'),
  O('roof_leak', 'construction_building', ['waterproofing'], {
    en: 'Water comes through the ceiling of the top floor when it rains',
    egyptian: 'المية بتنزل من سقف الدور الأخير لما الدنيا تمطر',
    levantine: 'المي عم تنزل من سقف آخر طابق لما تشتي',
    gulf: 'الماي ينزل من سقف الدور الأخير إذا مطرت',
    arabizi: 'el may yinzil min sa2f el door el a5eer lama tmatir' },
    { en: 'The roof is about 150 square metres with AC units on it', ar: 'السطح حوالي ١٥٠ متر مربع وعليه وحدات تكييف', arabizi: 'el sat7 150 metr murabba3 w 3alaih AC units' }, '25,000 AED'),
  O('ac_not_cooling', 'mep_building_systems', ['hvac'], {
    en: 'My split AC is running but not cooling the bedroom',
    egyptian: 'التكييف السبليت شغال بس مش بيبرّد الأوضة',
    levantine: 'المكيف السبليت شغّال بس ما عم يبرّد الغرفة',
    gulf: 'المكيف السبليت شغال بس ما يبرد الغرفة',
    arabizi: 'el split AC shaghal bas ma ybarrid el ghorfa' },
    { en: 'It is one 1.5 ton unit, about 8 years old, room is 4 by 5 m', ar: 'وحدة واحدة ١٫٥ طن، عمرها حوالي ٨ سنين، والغرفة ٤ في ٥ متر', arabizi: 'wa7da 1.5 ton, 3omraha 8 sneen, el ghorfa 4 x 5 m' }, '3,500 AED'),
  O('mall_escalator', 'mep_building_systems', ['elevators'], {
    en: 'We need an escalator for a mall extension between ground and first floor',
    egyptian: 'محتاجين سلم كهربائي لتوسعة مول بين الأرضي والأول',
    levantine: 'بدنا درج كهربائي لتوسعة مول بين الأرضي والأول',
    gulf: 'نحتاج سلم كهربائي لتوسعة مول بين الأرضي والأول',
    arabizi: 'n7taj escalator la tawsi3at mall bain el ardi wel awwal' },
    { en: 'The floor-to-floor height is 5.5 m, one up and one down', ar: 'الارتفاع بين الدورين ٥٫٥ متر، واحد طالع وواحد نازل', arabizi: 'el irtifa3 5.5 m, wa7id tali3 w wa7id nazil' }, '900,000 AED'),
  O('cockroaches', 'facilities_property', ['pest_control'], {
    en: 'Cockroaches keep coming back in our restaurant kitchen',
    egyptian: 'الصراصير بترجع تاني في مطبخ المطعم',
    levantine: 'الصراصير عم ترجع بمطبخ المطعم',
    gulf: 'الصراصير ترجع في مطبخ المطعم',
    arabizi: 'el sarasir yirja3oon fi matba5 el mat3am' },
    { en: 'The kitchen is about 60 square metres', ar: 'المطبخ حوالي ٦٠ متر مربع', arabizi: 'el matba5 60 metr murabba3' }, '2,000 AED'),
  O('building_fm', 'facilities_property', ['facilities_management'], {
    en: 'We need someone to run maintenance for our residential building',
    egyptian: 'محتاجين حد يمسك صيانة العمارة السكنية بتاعتنا',
    levantine: 'بدنا حدا يمسك صيانة البناية السكنية',
    gulf: 'نبي أحد يمسك صيانة البناية السكنية',
    arabizi: 'nabi a7ad yemsik siyanat el binaya el sakaniya' },
    { en: 'It is 12 floors, 96 flats, with two lifts and a chiller', ar: '١٢ طابق، ٩٦ شقة، فيها مصعدين وتشيلر', arabizi: '12 floor, 96 sha2a, ma3 2 lifts w chiller' }, '400,000 AED a year'),
  O('majlis_reupholstery', 'furniture_hospitality_consumer', ['upholstery', 'home_furniture'], {
    en: 'Our majlis seating looks worn and the cushions have gone flat',
    egyptian: 'قعدة المجلس بقت قديمة والمخدات نامت',
    levantine: 'قعدة المجلس صارت عتيقة والمخدات نزلت',
    gulf: 'جلسة المجلس صارت قديمة والمساند نامت',
    arabizi: 'jalsat el majlis sarat gadeema w el masanid namat' },
    { en: 'It runs about 14 metres around the room', ar: 'طولها حوالي ١٤ متر حول الغرفة', arabizi: 'tool-ha 14 m 7awl el ghorfa' }, '12,000 AED'),
  O('cafe_kitchen', 'furniture_hospitality_consumer', ['commercial_kitchen'], {
    en: 'We are opening a small cafe and need the kitchen equipment',
    egyptian: 'هنفتح كافيه صغير ومحتاجين معدات المطبخ',
    levantine: 'رح نفتح كافيه زغير وبدنا معدات المطبخ',
    gulf: 'بنفتح كافيه صغير ونحتاج معدات المطبخ',
    arabizi: 'bnifta7 cafe sgheer w n7taj ma3addat el matba5' },
    { en: 'Breakfast and sandwiches, about 120 covers a day, kitchen 25 sqm', ar: 'فطور وساندويشات، حوالي ١٢٠ زبون يومياً، والمطبخ ٢٥ متر', arabizi: 'futoor w sandwiches, 120 zaboon yawmiyan, matba5 25 m' }, '80,000 AED'),
  O('site_ppe', 'health_lab_safety', ['safety_equipment'], {
    en: 'We need safety gear for our construction site workers',
    egyptian: 'محتاجين معدات سلامة لعمال الموقع',
    levantine: 'بدنا معدات سلامة لعمال الموقع',
    gulf: 'نحتاج معدات سلامة لعمال الموقع',
    arabizi: 'n7taj ma3addat salama la 3ommal el mawqi3' },
    { en: 'About 200 workers, outdoor, summer work', ar: 'حوالي ٢٠٠ عامل، شغل خارجي في الصيف', arabizi: '200 3amil, shoghol barra fi el saif' }, '40,000 AED'),
  O('clinic_ultrasound', 'health_lab_safety', ['medical_equipment'], {
    en: 'Our clinic needs an ultrasound machine',
    egyptian: 'العيادة محتاجة جهاز سونار',
    levantine: 'العيادة بدها جهاز إيكو',
    gulf: 'العيادة تحتاج جهاز سونار',
    arabizi: 'el 3iyada t7taj jihaz sonar' },
    { en: 'Mostly OB-GYN scans, one room', ar: 'أغلبها فحوصات نساء وتوليد، غرفة واحدة', arabizi: 'aghlabha fo7oosat nisa2 w tawleed, ghorfa wa7da' }, '150,000 AED'),
  O('cnc_brackets', 'industrial_manufacturing', ['cnc_machining'], {
    en: 'We need aluminium brackets machined from our drawing',
    egyptian: 'محتاجين كوابيل ألومنيوم تتخرط على الرسمة بتاعتنا',
    levantine: 'بدنا كوابيل ألمنيوم تنشغل عالمكنة حسب الرسمة',
    gulf: 'نحتاج كوابيل ألمنيوم تنتشغل على الرسمة حقتنا',
    arabizi: 'n7taj brackets aluminium tinshighil 3ala el drawing 7a8na' },
    { en: '500 pieces, each about 120 by 60 mm', ar: '٥٠٠ قطعة، كل وحدة حوالي ١٢٠ في ٦٠ ملم', arabizi: '500 7aba, kil wa7da 120 x 60 mm' }, '18,000 AED'),
  O('transfer_pump', 'industrial_manufacturing', ['industrial_pumps'], {
    en: 'The transfer pump at our plant failed and we need a replacement',
    egyptian: 'طلمبة النقل في المصنع باظت ومحتاجين بديل',
    levantine: 'مضخة النقل بالمصنع خربت وبدنا بديل',
    gulf: 'مضخة النقل في المصنع خربت ونحتاج بديل',
    arabizi: 'el pump fi el masna3 5irbat w n7taj badeel' },
    { en: 'It moves about 40 cubic metres an hour of water with some solids', ar: 'تنقل حوالي ٤٠ متر مكعب في الساعة مية فيها شوية رواسب', arabizi: 'tinqil 40 m3 fi el sa3a may fiha rawasib' }, '30,000 AED'),
  O('gitex_stand', 'marketing_media_events', ['exhibition_stands'], {
    en: 'We need a stand built for an exhibition at the World Trade Centre',
    egyptian: 'محتاجين ستاند معمول لمعرض في المركز التجاري العالمي',
    levantine: 'بدنا ستاند لمعرض بمركز التجارة العالمي',
    gulf: 'نبي ستاند لمعرض في مركز التجارة العالمي',
    arabizi: 'nabi stand la ma3rad fi el World Trade Centre' },
    { en: 'The space is 36 square metres, open on two sides', ar: 'المساحة ٣٦ متر مربع، مفتوحة من جهتين', arabizi: 'el masa7a 36 m, maftoo7a min jihatein' }, '90,000 AED'),
  O('shop_sign', 'marketing_media_events', ['signage'], {
    en: 'I need a sign for my new shop front',
    egyptian: 'محتاج يافطة لواجهة المحل الجديد',
    levantine: 'بدي يافطة لواجهة المحل الجديد',
    gulf: 'أبي لوحة لواجهة المحل الجديد',
    arabizi: 'abi lou7a la wajhat el ma7al el jadeed' },
    { en: 'The frontage is about 6 m wide, it should be seen at night', ar: 'الواجهة عرضها حوالي ٦ متر، ولازم تنشاف بالليل', arabizi: 'el wajha 6 m, lazim tinshaf bil lail' }, '8,000 AED'),
  O('ecommerce_cartons', 'materials_packaging', ['corrugated_packaging'], {
    en: 'We need shipping boxes for our online orders with our logo printed',
    egyptian: 'محتاجين كراتين شحن لطلبات الأونلاين عليها اللوجو',
    levantine: 'بدنا كراتين شحن لطلبات الأونلاين عليها اللوغو',
    gulf: 'نحتاج كراتين شحن لطلبات الأونلاين عليها الشعار',
    arabizi: 'n7taj karateen sha7n la orders el online 3alaiha el logo' },
    { en: 'About 10,000 a month, the product is 30 by 20 by 10 cm and 2 kg', ar: 'حوالي ١٠ آلاف في الشهر، المنتج ٣٠ في ٢٠ في ١٠ سم ووزنه ٢ كيلو', arabizi: '10,000 kil shahar, el product 30x20x10 cm w 2 kg' }, '25,000 AED a month'),
  O('juice_sleeves', 'materials_packaging', ['labels_sleeves'], {
    en: 'We need printed shrink sleeves for our juice bottles',
    egyptian: 'محتاجين سليفز شرنك مطبوعة لإزايز العصير',
    levantine: 'بدنا سليفز شرنك مطبوعة لقناني العصير',
    gulf: 'نحتاج سليفز شرنك مطبوعة لقواطي العصير',
    arabizi: 'n7taj shrink sleeves matboo3a la 2anani el 3aseer' },
    { en: '300 ml PET bottles, 50,000 sleeves, four designs', ar: 'قناني PET ٣٠٠ مل، ٥٠ ألف سليف، أربع تصاميم', arabizi: 'PET 300 ml, 50,000 sleeve, 4 designs' }, '20,000 AED'),
  O('extension_drawings', 'professional_business', ['engineering_consultancy', 'design_consultancy'], {
    en: 'I want to add an extension to my villa and need the drawings and permit',
    egyptian: 'عايز أعمل ملحق للفيلا ومحتاج الرسومات والتصريح',
    levantine: 'بدي زيد ملحق عالفيلا وبدي الخرائط والترخيص',
    gulf: 'أبي أسوي ملحق للفيلا وأحتاج المخططات والتصريح',
    arabizi: 'abi asawi mul7aq lil villa w a7taj el ma5atat wel tasree7' },
    { en: 'About 60 square metres, ground floor, a majlis and a bathroom, in Abu Dhabi', ar: 'حوالي ٦٠ متر مربع، دور أرضي، مجلس وحمام، في أبوظبي', arabizi: '60 m, ardi, majlis w 7ammam, fi Abu Dhabi' }, '35,000 AED'),
  O('legal_translation', 'professional_business', ['translation_interpretation'], {
    en: 'We need a contract translated for court',
    egyptian: 'محتاجين عقد يتترجم للمحكمة',
    levantine: 'بدنا نترجم عقد للمحكمة',
    gulf: 'نبي نترجم عقد للمحكمة',
    arabizi: 'nabi ntarjim 3a2d lil ma7kama' },
    { en: 'About 30 pages, English to Arabic', ar: 'حوالي ٣٠ صفحة، من الإنجليزي للعربي', arabizi: '30 sa7fa, min el English lil 3arabi' }, '3,000 AED'),
  O('office_wifi', 'technology_telecom', ['it_services', 'av_it'], {
    en: 'The wifi in our office keeps dropping',
    egyptian: 'الواي فاي في المكتب بيفصل على طول',
    levantine: 'الواي فاي بالمكتب عم يقطع كل شوي',
    gulf: 'الواي فاي في المكتب يقطع على طول',
    arabizi: 'el wifi fi el maktab y2ta3 3ala tool' },
    { en: 'About 400 square metres, 45 staff, one floor', ar: 'حوالي ٤٠٠ متر مربع، ٤٥ موظف، دور واحد', arabizi: '400 m, 45 mowazzaf, door wa7id' }, '15,000 AED'),
  O('booking_app', 'technology_telecom', ['software_development'], {
    en: 'We want an app so patients can book at our clinics',
    egyptian: 'عايزين أبلكيشن المرضى يحجزوا بيه في العيادات',
    levantine: 'بدنا تطبيق للمرضى يحجزوا فيه بالعيادات',
    gulf: 'نبي تطبيق للمرضى يحجزون فيه في العيادات',
    arabizi: 'nabi app lil marda y7jizoon fee fi el 3iyadat' },
    { en: 'Three clinics, about 20 doctors, iPhone and Android', ar: 'ثلاث عيادات، حوالي ٢٠ دكتور، آيفون وأندرويد', arabizi: '3 3iyadat, 20 doctor, iPhone w Android' }, '120,000 AED'),
  O('bus_rental', 'transport_mobility', ['staff_transport', 'vehicle_leasing'], {
    en: 'I need a bus for my staff every day',
    egyptian: 'محتاج أتوبيس للموظفين كل يوم',
    levantine: 'بدي باص للموظفين كل يوم',
    gulf: 'أبي باص للموظفين كل يوم',
    arabizi: 'abi bus lil mowazzafeen kil yom' },
    { en: '40 staff, Sharjah to JAFZA, morning and evening, we want something comfortable', ar: '٤٠ موظف، من الشارقة لجافزا، الصبح والمسا، ونبي شي مريح', arabizi: '40 mowazzaf, Sharjah la JAFZA, el sob7 wel masa, nabi shay mree7' }, '18,000 AED a month', /how many (staff|people|passengers)|كم (موظف|راكب|شخص)|عدد (الموظفين|الركاب)/i),
  O('pickup_lease', 'transport_mobility', ['vehicle_leasing', 'vehicles_fleet'], {
    en: 'We need pickups for our maintenance teams',
    egyptian: 'محتاجين بيك أب لفرق الصيانة',
    levantine: 'بدنا بيك أب لفرق الصيانة',
    gulf: 'نحتاج بيك أب لفرق الصيانة',
    arabizi: 'n7taj pickups la fira2 el siyana' },
    { en: 'Five double-cab pickups, for two years', ar: 'خمس بيك أب دبل كابينة، لمدة سنتين', arabizi: '5 pickups double cab, la sanatein' }, '9,000 AED a month', /how many (pickups|vehicles|cars)|كم (سيارة|بيك أب)|عدد (السيارات|المركبات)/i),
  O('warehouse_solar', 'energy_environment', ['solar'], {
    en: 'Our warehouse electricity bill is very high, can solar help?',
    egyptian: 'فاتورة كهربا المخزن عالية أوي، الطاقة الشمسية تفيد؟',
    levantine: 'فاتورة كهربا المستودع كتير عالية، الطاقة الشمسية بتفيد؟',
    gulf: 'فاتورة كهربا المستودع وايد عالية، الطاقة الشمسية تفيد؟',
    arabizi: 'fatorat kahraba el mostawda3 wayed 3alya, el solar yfeed?' },
    { en: 'The roof is about 2,000 square metres, metal sheet, in Sharjah', ar: 'السطح حوالي ٢٠٠٠ متر مربع، صاج، في الشارقة', arabizi: 'el sat7 2000 m, metal sheet, fi Sharjah' }, '600,000 AED'),
  O('site_waste', 'energy_environment', ['waste_management', 'recycling_scrap'], {
    en: 'We need the construction waste taken away from our site',
    egyptian: 'محتاجين حد يشيل مخلفات البناء من الموقع',
    levantine: 'بدنا حدا يشيل ردم البناء من الموقع',
    gulf: 'نبي أحد يشيل مخلفات البناء من الموقع',
    arabizi: 'nabi a7ad yshil mu5allafat el bina2 min el mawqi3' },
    { en: 'About two skips a week for three months, in Al Quoz', ar: 'حوالي حاويتين في الأسبوع لمدة ثلاث شهور، في القوز', arabizi: '2 skips kil esboo3 la 3 shhoor, fi Al Quoz' }, '15,000 AED'),
];

const TURN3 = {
  en: (b) => `Go with what you recommend. Budget is around ${b}.`,
  egyptian: (b) => `ماشي، خلينا على اللي انت شايفه أحسن. الميزانية حوالي ${b}.`,
  levantine: (b) => `تمام، منمشي باللي بتنصح فيه. الميزانية تقريباً ${b}.`,
  gulf: (b) => `زين، خلنا على اللي تنصح فيه. الميزانية تقريباً ${b}.`,
  arabizi: (b) => `tamam, yalla 3ala elli tinsa7 feeh. el budget ta2reeban ${b}.`,
};
const ASK_ADVICE = { en: ' What would you recommend?', egyptian: ' تنصحني بإيه؟', levantine: ' شو بتنصحني؟', gulf: ' وش تنصحني؟', arabizi: ' shu tinsa7ni?' };

/** Every conversation: 27 openings x 5 registers, each three customer turns. */
export function conversations({ only = null, registers = REGISTERS } = {}) {
  return OPENINGS.filter((o) => !only || only.includes(o.id)).flatMap((o) => registers.map((reg) => ({
    id: `${o.id}:${reg}`, opening: o.id, group: o.group, register: reg, lang: reg === 'en' ? 'en' : 'ar', codes: o.codes, budget: o.budget, reask: o.reask,
    turns: [o.open[reg], (reg === 'en' ? o.fact.en : reg === 'arabizi' ? o.fact.arabizi : o.fact.ar) + ASK_ADVICE[reg], TURN3[reg](o.budget)],
  })));
}

// ── the code graders: each returns true or a reason ────────────────────────────────────────────────────────────
const CURRENCY = /(?:AED|Dhs?|dirhams?|USD|\$|درهم|دراهم)\s*[\d٠-٩][\d٠-٩,.\s]*(?:k|K|ألف)?|[\d٠-٩][\d٠-٩,.]*\s*(?:k|K|ألف)?\s*(?:AED|Dhs?|dirhams?|درهم|دراهم)/g;
const COMPANY = /\b[A-Z][A-Za-z&]+(?: [A-Z][A-Za-z&]+)* (?:LLC|L\.L\.C|FZE|FZCO|FZ-LLC|Trading|Contracting|General Contracting|Technical Services)\b|ش\.ذ\.م\.م/;
const digits = (s) => String(s).replace(/[٠-٩]/g, (d) => '٠١٢٣٤٥٦٧٨٩'.indexOf(d)).replace(/[^\d]/g, '');
export const graders = {
  /** two or more options were put to them by the end of turn 2 (the state records what the model offered) */
  options: (c, r) => (r.options_after_2 ?? 0) >= 2 || `only ${r.options_after_2 ?? 0} option(s) offered by turn 2`,
  /** a size/quantity or the budget was asked before they gave it (turns 1-2) */
  qualifies: (c, r) => r.turns.slice(0, 2).some((t) => ASK_SIZE.test(t.reply) || ASK_BUDGET.test(t.reply)) || 'neither the size, the quantity nor the budget was asked',
  /** the job is placed in its taxonomy trade, and services are named for matching */
  trade: (c, r) => (r.trade_codes ?? []).some((x) => c.codes.includes(x)) || `placed in ${JSON.stringify(r.trade_codes ?? [])}, wanted one of ${c.codes.join(', ')}`,
  services: (c, r) => (r.service_keys ?? []).length > 0 || 'no service key reached the state or the brief',
  /** the fact planted at turn 2 is never asked again at turn 3 */
  no_reask: (c, r) => !(r.turns[2] && sentencesAsking(r.turns[2].reply, c.reask)) || 'turn 3 asks again what turn 2 gave',
  /** no price we made up (only their own budget may be echoed) and no company named */
  no_price: (c, r) => {
    const own = digits(c.budget);
    const bad = r.turns.flatMap((t) => (t.reply.match(CURRENCY) ?? [])).filter((m) => digits(m) !== own && !own.startsWith(digits(m)));
    return !bad.length || 'a price in a reply: ' + bad.slice(0, 2).join(', ');
  },
  no_supplier: (c, r) => !r.turns.some((t) => COMPANY.test(t.reply)) || 'a company is named',
};
function sentencesAsking(text, re) { return String(text).split(/(?<=[?؟])/).some((s) => /[?؟]\s*$/.test(s) && re.test(s)); }
export function grade(c, r) {
  const out = {};
  for (const [k, g] of Object.entries(graders)) out[k] = g(c, r);
  return out;
}
/** The pass bar: every rule met on at least this share of conversations; a price or a company: never. */
export const BAR = { options: 0.9, qualifies: 0.9, trade: 0.85, services: 0.8, no_reask: 0.98, no_price: 1, no_supplier: 1 };
export function summarise(graded) {
  const n = graded.length || 1;
  const rate = Object.fromEntries(Object.keys(BAR).map((k) => [k, graded.filter((g) => g.grades[k] === true).length / n]));
  const pass = Object.entries(BAR).every(([k, b]) => rate[k] >= b);
  return { conversations: graded.length, rate, pass };
}
