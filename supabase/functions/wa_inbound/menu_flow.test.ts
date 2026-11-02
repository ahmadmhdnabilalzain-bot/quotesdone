// The WhatsApp welcome and menu, driven through the real routing with fakes for the database and
// Twilio (founder_instruction 759, 22 Sep 2026). Prevents "said hi, got no response" from coming back
// for any reason inside the routing: a greeting, a first message, every option, each audience, and a
// conversation that continues past the first reply all get an answer.
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/wa_inbound/menu_flow.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { answerFromFaq, type Content, founderUnanswered, type MenuDeps, type MenuInput, type MenuMeaning, menuTurn, reofferMenu, type Turn, unanswered, welcomeFirstContact } from './menu_flow.ts';
import { type Figures, isFiguresCommand } from './founder_queries.ts';
import { HELD_NOTICE } from './model_says.ts';
import { coverageReply, groupedTrades, type Trade } from './coverage.ts';
import {
  type Audience, caseConfirm, cleanName, contentKey, founderCommand, greetLine, HOURS, humanAlert, type Lang, MENU_BUTTON, sorryLead,
  MENU_IDS, menuChoice, type MenuContext, type MenuId, menuItems, optionReply, WELCOME_TAIL, welcomeText, withinHours,
} from './menu.ts';

const FROM = 'whatsapp:+971500000021'; // reserved ZZ DEMO fixture block

// public.taxonomy_trade, the 42 active rows read from production on 22 Sep 2026, in sort order as wa_inbound reads
// them (sort, code). The coverage answer is built from whatever the table holds; this snapshot proves it fits.
export const TRADES: Trade[] = [
  {"code":"hvac","label":"HVAC & air conditioning","label_ar":"التكييف والتهوية","aliases":["hvac","air conditioning","air-conditioning","a/c unit","vrf","chiller","ducting","ductwork","ventilation","fcu","ahu","تكييف","مكيف","تهوية","مجاري هواء","تشيلر","شيلر","وحدات مناولة هواء"]},
  {"code":"electrical","label":"Electrical","label_ar":"الأعمال الكهربائية","aliases":["electrical","electric","wiring","switchgear","db panel","distribution board","cable tray","lighting","busbar","أعمال كهرب","تمديدات كهرب","تركيبات كهرب","مقاولات كهرب","صيانة كهرب","لوحات كهرب","كابلات كهرب","أسلاك كهرب","فني كهرب","إنارة","إنارات","لوحات توزيع","لوحة توزيع","حوامل كابلات"]},
  {"code":"building_materials","label":"Building & Construction Materials","label_ar":"مواد البناء والتشييد","aliases":["building material","building materials","construction material","construction materials","cement","aggregate","ready mix","blocks and bricks","sanitary ware","مواد بناء","مواد إنشائية","إسمنت","خرسانة جاهزة","طابوق","ركام"]},
  {"code":"engineering_consultancy","label":"Engineering Consultancy & Architecture","label_ar":"الاستشارات الهندسية والعمارة","aliases":["consultants engineers","consulting engineer","engineering consultant","engineers contractors","architect","architects","architectural","design consultancy","structural engineer","استشارات هندسية","مكتب هندسي","مكاتب هندسية","مكتب استشاري","استشاري هندسي","إشراف هندسي","مهندس معماري","هندسة معمارية","تصميم معماري","مهندس إنشائي"]},
  {"code":"power_generators","label":"Generators & Power Equipment","label_ar":"المولدات ومعدات الطاقة","aliases":["generator","generators","genset","gen set","power generation","diesel generator","ups system","مولد","جنريتر","جنرتر","توليد طاقة","توليد كهرباء"]},
  {"code":"heavy_equipment","label":"Heavy Equipment & Plant","label_ar":"المعدات الثقيلة والآليات","aliases":["heavy duty equipment","heavy equipment","earthmoving","excavator","crane hire","forklift","construction equipment","plant hire","معدات ثقيلة","آليات ثقيلة","حفارات","حفارة","رافعات","رافعة","كرين","شيول","بوكلين","جرافة","جرافات","بلدوزر","قلاب","تأجير معدات"]},
  {"code":"labour_supply","label":"Manpower & Labour Supply","label_ar":"توريد العمالة","aliases":["labour supply","labor supply","manpower supply","manpower service","staffing supply","توريد عمالة","توفير عمالة","تأجير عمالة","توريد أيدي عاملة","توفير أيدي عاملة","تأجير أيدي عاملة","خدمات عمالة"]},
  {"code":"plumbing","label":"Plumbing & sanitary","label_ar":"السباكة والأدوات الصحية","aliases":["plumbing","plumber","sanitary","sanitaryware","drainage","pipework","water supply","سباك","أدوات صحية","تمديدات صحية","صرف صحي","إمدادات مياه","تمديدات مياه","سخانات مياه","سخان مياه"]},
  {"code":"safety_equipment","label":"Safety Equipment & PPE","label_ar":"معدات السلامة والوقاية الشخصية","aliases":["safety equipment","personal protective","ppe supplier","safety clothing","fall protection","معدات سلامة","مستلزمات سلامة","معدات وقاية","معدات حماية شخصية","ملابس واقية","ملابس سلامة","أحذية سلامة","حماية من سقوط"]},
  {"code":"solar","label":"Solar & Renewable Energy","label_ar":"الطاقة الشمسية والمتجددة","aliases":["solar energy","solar panel","solar power","photovoltaic","solar water heater","طاقة شمسية","ألواح شمسية","ألواح طاقة شمسية","خلايا شمسية","سخانات شمسية","سخان شمسي","كهروضوئي"]},
  {"code":"chemicals","label":"Industrial & Construction Chemicals","label_ar":"الكيماويات الصناعية والإنشائية","aliases":["chemical products","industrial chemical","construction chemical","adhesive and sealant","coating chemical","كيماوي","مواد كيميائية","مواد لاصقة"]},
  {"code":"plastics_pipes","label":"Plastics, Pipes & Fittings","label_ar":"البلاستيك والأنابيب والتجهيزات","aliases":["plastic products","pipe fitting","pipes and fittings","pvc pipe","hdpe","plastic manufactur","منتجات بلاستيك","أنابيب بلاستيك","مواسير بلاستيك","أنابيب ووصلات","وصلات أنابيب","تصنيع بلاستيك"]},
  {"code":"oilfield","label":"Oilfield & Industrial Supplies","label_ar":"مستلزمات حقول النفط والصناعة","aliases":["oil field suppl","oilfield","oil and gas suppl","petrochemical suppl","حقول نفط","حقل نفط","نفط وغاز","بترول وغاز","بتروكيماوي"]},
  {"code":"home_automation","label":"Home & Building Automation","label_ar":"أتمتة المنازل والمباني","aliases":["home automation","building automation","smart home","building management system","bms system","منزل ذكي","منازل ذكية","بيت ذكي","بيوت ذكية","أتمتة منزل","أتمتة منازل","أتمتة مباني","نظام إدارة مباني","أنظمة إدارة مباني"]},
  {"code":"logistics_moving","label":"Logistics, Movers & Storage","label_ar":"النقل والتخزين والخدمات اللوجستية","aliases":["moving and storage","movers and packers","relocation service","freight forwarding","warehousing service","نقل أثاث","نقل عفش","نقل وتخزين","نقل بضائع","شحن بضائع","وكيل شحن","تخليص جمركي","خدمات لوجستية","لوجستي"]},
  {"code":"packaging","label":"Packaging & Printing Supplies","label_ar":"مستلزمات التغليف والطباعة","aliases":["packaging company","packaging material","corrugated","printing press","تغليف","مطبعة","مطابع","كرتون مقوى","كرتون مضلع"]},
  {"code":"marine","label":"Marine & Offshore Supplies","label_ar":"المستلزمات والأعمال البحرية","aliases":["marine supply","marine equipment","ship chandler","offshore supply","معدات بحرية","مستلزمات بحرية","تموين سفن","خدمات بحرية","أعمال بحرية"]},
  {"code":"fire_fighting","label":"Fire fighting & life safety","label_ar":"مكافحة الحريق وأنظمة السلامة","aliases":["fire fighting","firefighting","fire alarm","fire pump","sprinkler","fire suppression","life safety","fire protection","مكافحة حريق","مكافحة حرائق","إطفاء حريق","إطفاء حرائق","أنظمة إطفاء","إنذار حريق","إنذار حرائق","رشاشات حريق","مضخات حريق","مضخة حريق","حماية من حريق","طفايات","طفاية","كاشف دخان","كواشف دخان","سبرنكلر"]},
  {"code":"it_services","label":"IT & Network Services","label_ar":"خدمات تقنية المعلومات والشبكات","aliases":["computer support","it services","network support","structured cabling","computer security service","تقنية معلومات","تكنولوجيا معلومات","أمن معلومات","أمن سيبراني","شبكات حاسوب","شبكات حاسب","شبكات كمبيوتر"]},
  {"code":"office_equipment","label":"Office equipment & printing","label_ar":"المعدات المكتبية والطباعة","aliases":["office equipment","office automation","office machines","photocopier","copier machine","printer","toner","معدات مكتبية","أجهزة مكتبية","طابعات","آلات تصوير","أحبار طابعات"]},
  {"code":"pos_retail","label":"Point-of-sale & retail technology","label_ar":"أنظمة نقاط البيع وتقنيات التجزئة","aliases":["point of sale","pos system","pos terminal","cash register","barcode scanner","receipt printer","retail technology","نقاط بيع","نقطة بيع","أجهزة كاشير","باركود"]},
  {"code":"joinery","label":"Joinery & carpentry","label_ar":"النجارة والأعمال الخشبية","aliases":["built in wardrobe","cabinet","carpenter","carpentry","closet","counter top","countertop","countertops","fitted kitchen","joinery","kitchen","kitchen fitting","kitchen unit","kitchens","millwork","vanity","vanity unit","wardrobe","wooden","woodwork","work top","worktop","worktops","نجار","أعمال خشب","خشبي","تفصيل مطابخ","تصنيع مطابخ","تركيب مطابخ","خزائن","خزانة","دواليب","دولاب","كبتات","سطح عمل","أسطح عمل","تصنيع أثاث"]},
  {"code":"glazing","label":"Glass & glazing","label_ar":"الزجاج والواجهات الزجاجية","aliases":["glass","glazing","glazed","mirror","tempered glass","laminated glass","frameless","زجاج","مرايا","سكوريت","سيكوريت"]},
  {"code":"aluminium","label":"Aluminium & cladding","label_ar":"الألمنيوم والتكسية","aliases":["aluminium","aluminum","cladding","facade","curtain wall","acp panel","louvre","ألمنيوم","ألومنيوم","ألمونيوم","ألومينيوم","كلادينج","كلادنج","كلادينغ","تكسية واجهات","لوفرات"]},
  {"code":"steel","label":"Steel & metal fabrication","label_ar":"الحديد وتشكيل المعادن","aliases":["steel","metal fabrication","welding","welded","stainless","mild steel","structural steel","handrail","حديد","فولاذ","ستانلس","ستانليس","استانلس","ستيل","تشكيل معادن","هياكل معدنية","لحام","درابزين","حدادة"]},
  {"code":"flooring","label":"Flooring","label_ar":"الأرضيات","aliases":["flooring","floor tiles","tiling","vinyl","epoxy floor","carpet","parquet","marble","skirting","أرضيات","تبليط","بلاط أرضيات","بلاط سيراميك","بلاط بورسلين","بلاط رخام","بلاط جدران","فينيل","سجاد","موكيت","باركيه","باركيت","رخام","سيراميك","بورسلين","بورسلان","جرانيت"]},
  {"code":"painting","label":"Painting & finishes","label_ar":"الدهانات والتشطيبات","aliases":["painting","painter","paint work","coating","protective coating","decoration","دهان","طلاء","بوية","بويات"]},
  {"code":"gypsum","label":"Gypsum, partitions & ceilings","label_ar":"الجبس والقواطع والأسقف","aliases":["gypsum","partition","partitions","false ceiling","drywall","plasterboard","plastering","bulkhead","جبس","أسقف معلقة","سقف معلق","أسقف مستعارة","سقف مستعار","قواطع جبس","لياسة"]},
  {"code":"signage","label":"Signage & printing","label_ar":"اللافتات والطباعة","aliases":["signage","signboard","sign board","3d letters","acrylic letters","lightbox","wayfinding","لافتات","لافتة","يافطات","يافطة","لوحات إعلان","لوحات إرشاد","حروف بارزة","حروف أكريليك"]},
  {"code":"landscaping","label":"Landscaping & pools","label_ar":"تنسيق الحدائق والمسابح","aliases":["landscaping","landscape","softscape","hardscape","irrigation","swimming pool","garden","تنسيق حدائق","صيانة حدائق","تجميل حدائق","زراعة حدائق","لاندسكيب","مشاتل","مشتل","عشب صناعي","نجيل صناعي","أنظمة ري","شبكات ري","مسابح","مسبح","حمامات سباحة"]},
  {"code":"security_systems","label":"Security systems","label_ar":"الأنظمة الأمنية","aliases":["access control","cctv","gate barrier","intruder alarm","security control equipment","security guard service","security system","surveillance","turnstile","كاميرات مراقبة","أنظمة مراقبة","أنظمة أمن","تحكم بالدخول","تحكم في دخول","إنذار سرقة","حراسة أمنية","خدمات حراسة","بوابات دوارة"]},
  {"code":"elevators","label":"Elevators & escalators","label_ar":"المصاعد والسلالم المتحركة","aliases":["elevator","elevators","lift installation","escalator","travelator","dumbwaiter","مصعد","مصاعد","سلالم متحركة","سلم متحرك","سلالم كهربائية","سلم كهربائي"]},
  {"code":"doors","label":"Doors & windows","label_ar":"الأبواب والنوافذ","aliases":["door","doors","window","windows","shutter","automatic door","fire door","ironmongery","أبواب","نوافذ","شبابيك","دريش"]},
  {"code":"waterproofing","label":"Waterproofing & insulation","label_ar":"العزل المائي والحراري","aliases":["waterproofing","waterproof","insulation","membrane","thermal insulation","acoustic insulation","عزل","عازل","عوازل","ممبرين"]},
  {"code":"upholstery","label":"Upholstery & soft furnishing","label_ar":"التنجيد والمفروشات","aliases":["upholstery","upholstered","curtain","curtains","blinds","soft furnishing","sofa","تنجيد","منجد","ستائر","ستارة","برادي","مفروشات","كنب","تفصيل مجالس"]},
  {"code":"wallpaper","label":"Wallpaper & wall finishes","label_ar":"ورق الجدران والتشطيبات الجدارية","aliases":["wallpaper","wall covering","wall panelling","wall cladding","ورق جدران","ورق حائط","ورق حيطان","تكسية جدران","تكسيات جدران"]},
  {"code":"scaffolding","label":"Scaffolding & access","label_ar":"السقالات ومعدات الوصول","aliases":["scaffolding","scaffold","formwork","shoring","access platform","سقال","سقايل","شدات","قوالب صب"]},
  {"code":"cleaning","label":"Cleaning & facility services","label_ar":"التنظيف وخدمات المرافق","aliases":["cleaning","facilities management","facility management","handyman","housekeeping","janitorial","pest control","property maintenance","تنظيف","إدارة مرافق","مكافحة حشرات","مكافحة آفات","مكافحة قوارض","رش مبيدات","صيانة عقارات","صيانة مباني"]},
  {"code":"av_it","label":"AV, IT & low current","label_ar":"الصوت والصورة والتيار الخفيف","aliases":["audio visual","audio-visual","low current","structured cabling","networking","telecom","data cabling","public address","تيار خفيف","صوت وصورة","صوتيات","أنظمة صوتية","كابلات بيانات","إذاعة داخلية"]},
  {"code":"interior_fitout","label":"Interior fit-out","label_ar":"التشطيبات والتجهيزات الداخلية","aliases":["fit out","fit out contractor","fit-out","fitout","interior decorator","interior design","interior works","refurbishment","turnkey fitout","turnkey interior","تشطيبات داخلية","تشطيب داخلي","تصميم داخلي","ديكور","فيت أوت","فت أوت","تجهيزات داخلية","ترميم"]},
  {"code":"civil_works","label":"Civil & construction works","label_ar":"الأعمال المدنية والإنشائية","aliases":["blockwork","building contractor","civil","civil contracting","civil work","civil works","concrete","construction","construction company","contracting company","contractors general","demolition","general contracting","masonry","screed","structural","أعمال مدنية","مقاولات عامة","مقاولات بناء","مقاول بناء","إنشاءات","أعمال إنشائية","أعمال خرسان","صب خرسان","أعمال هدم"]},
  {"code":"mep_general","label":"MEP (combined)","label_ar":"الأعمال الكهروميكانيكية المتكاملة (MEP)","aliases":["building services","contractors electro mechanical","electro mechanical","electromechanical","mechanical electrical plumbing","mep","mep works","كهروميكانيك","إلكتروميكانيك","أعمال ميكانيكية وكهربائية"]},
];

// The twelve live groups (public.taxonomy_trade_group) and each fixture trade's group, as
// scripts/sql/the_missing_trades_join_the_taxonomy_under_twelve_groups.sql (#881) writes them. wa_inbound
// reads them with the trade rows; the answer is grouped by whatever the table says.
const G: Record<string, [string, string, number]> = {
  construction_building: ['Construction & Building', 'البناء والتشييد', 10],
  mep_building_systems: ['MEP & Building Systems', 'الأعمال الكهروميكانيكية وأنظمة المباني', 20],
  industrial_manufacturing: ['Industrial Equipment & Manufacturing', 'المعدات الصناعية والتصنيع', 30],
  materials_packaging: ['Materials, Chemicals & Packaging', 'المواد الخام والكيماويات والتغليف', 40],
  energy_environment: ['Energy, Environment & Agriculture', 'الطاقة والبيئة والزراعة', 50],
  transport_mobility: ['Transport, Vehicles, Marine & Aviation', 'النقل والمركبات والبحرية والطيران', 60],
  technology_telecom: ['Technology & Telecom', 'التقنية والاتصالات', 70],
  facilities_property: ['Facilities & Property Services', 'خدمات المرافق والعقارات', 80],
  professional_business: ['Professional & Business Services', 'الخدمات المهنية وخدمات الأعمال', 90],
  marketing_media_events: ['Marketing, Media & Events', 'التسويق والإعلام والفعاليات', 100],
  health_lab_safety: ['Health, Laboratory & Safety', 'الصحة والمختبرات والسلامة', 110],
  furniture_hospitality_consumer: ['Furniture, Hospitality & Consumer Goods', 'الأثاث والضيافة والسلع الاستهلاكية', 120],
};
const GROUP_OF: Record<string, string> = {
  aluminium: 'construction_building', building_materials: 'construction_building', civil_works: 'construction_building', doors: 'construction_building',
  flooring: 'construction_building', glazing: 'construction_building', gypsum: 'construction_building', interior_fitout: 'construction_building',
  joinery: 'construction_building', painting: 'construction_building', scaffolding: 'construction_building', steel: 'construction_building',
  wallpaper: 'construction_building', waterproofing: 'construction_building', landscaping: 'construction_building', heavy_equipment: 'construction_building',
  electrical: 'mep_building_systems', elevators: 'mep_building_systems', fire_fighting: 'mep_building_systems', home_automation: 'mep_building_systems',
  hvac: 'mep_building_systems', mep_general: 'mep_building_systems', plumbing: 'mep_building_systems', security_systems: 'mep_building_systems', av_it: 'mep_building_systems',
  oilfield: 'industrial_manufacturing', chemicals: 'materials_packaging', packaging: 'materials_packaging', plastics_pipes: 'materials_packaging',
  solar: 'energy_environment', power_generators: 'energy_environment', logistics_moving: 'transport_mobility', marine: 'transport_mobility',
  it_services: 'technology_telecom', office_equipment: 'technology_telecom', pos_retail: 'technology_telecom', cleaning: 'facilities_property',
  engineering_consultancy: 'professional_business', labour_supply: 'professional_business', signage: 'marketing_media_events',
  safety_equipment: 'health_lab_safety', upholstery: 'furniture_hospitality_consumer',
};
function accountsForEveryTrade(body: string, lang: 'en' | 'ar') {
  let counted = 0;
  for (const [code, [en, ar]] of Object.entries(G)) {
    const members = TRADES.filter((t) => t.group?.code === code);
    if (!members.length) continue;
    const line = body.split('\n').find((l) => l.startsWith('• ' + (lang === 'ar' ? ar : en) + ': '));
    assert(line, 'group missing: ' + en);
    const named = members.filter((t) => line.includes(lang === 'ar' ? t.label_ar! : t.label)).length;
    const more = Number((line.match(lang === 'ar' ? / و(\d+) أخرى$/ : / and (\d+) more$/) ?? [])[1] ?? 0);
    assertEquals(named + more, members.length, en + ': every trade named or counted');
    counted += members.length;
  }
  assertEquals(counted, TRADES.length);
}
for (const t of TRADES) { const g = GROUP_OF[t.code]; if (g) t.group = { code: g, label_en: G[g][0], label_ar: G[g][1], sort: G[g][2] }; }

type Sent = { to: string; body: string; content?: Content };
// THE REASONED MEANING, MOCKED (the real one is think(): _shared/reasoned_menus.ts, tested in reasoned_menus.test.ts).
// These are the readings a model returns for the fixtures below; the routing is what this file proves.
const READ: Record<string, MenuMeaning | MenuId> = { 'Follow up my request': 'qd_follow', 'Report a problem': 'qd_problem', 'Hi': 'greeting', 'Hello': 'greeting', 'hello': 'greeting', 'menu': 'greeting', 'MENU': 'greeting', 'السلام عليكم': 'salam' };
function harness(o: { ctx?: Partial<MenuContext>; sids?: Record<string, string>; contentFails?: boolean; faq?: string | null;
                      enabled?: boolean; history?: Turn[]; weWrote?: boolean; held?: boolean; appended?: boolean; gapOk?: boolean;
                      reasoningHeld?: boolean; noModel?: boolean;
                      /** The reasoned INTENT think() would return (reasoned_channels.ts); null = held. Default 'none'. */
                      meaning?: string | null } = {}) {
  const sent: Sent[] = []; const rows: Array<Record<string, unknown>> = []; const cases: string[] = []; const notified: string[] = []; const closed: string[] = []; const gaps: string[] = [];
  const history: Turn[] = [...(o.history || [])];
  const meanings: Array<[string, boolean]> = []; const offered: boolean[] = [];
  const reasoned: string[] = []; const queued: string[] = [];
  // THE MODEL, faked: it writes the reply from the situation; every text it wrote this turn is kept, so a test can
  // prove a sent conversation reply is one of them (rulings 1195-1197). o.noModel: no model answers.
  const written: string[] = [];
  const d: MenuDeps = {
    // the held notice (model_says.ts HELD_NOTICE), sent as index.ts sends it
    held: (r) => { const notice = HELD_NOTICE[r.audience === 'supplier' ? 'en' : r.lang]; sent.push({ to: FROM, body: notice }); return Promise.resolve({ notice, sent: true, err: null }); },
    write: (r) => { if (o.noModel) return Promise.resolve(''); const t = r.situation; written.push(t); return Promise.resolve(t); },
    // o.noModel is OpenRouter DOWN (no call reached a model): the only case a code-written line may go out (1339)
    outage: () => !!o.noModel,
    meaning: (text, awaitingProblem, offerMenu) => {
      meanings.push([text, awaitingProblem]);
      offered.push(offerMenu);
      if (o.reasoningHeld) return Promise.resolve(null);
      return Promise.resolve(READ[text] ?? (awaitingProblem ? 'problem' : 'other'));
    },
    intent: (text) => { reasoned.push(text); return Promise.resolve(o.meaning === undefined ? 'none' : o.meaning); },
    queueIntent: (text) => { queued.push(text); return Promise.resolve(); },
    autoreplyEnabled: () => Promise.resolve(o.enabled ?? true),
    recentTurns: () => Promise.resolve([...history]),
    weWroteRecently: () => Promise.resolve(o.weWrote ?? false),
    context: () => Promise.resolve({ audience: 'unknown', name: null, ...(o.ctx || {}) } as MenuContext),
    faq: () => Promise.resolve(o.faq ?? null),
    trades: () => Promise.resolve(TRADES),
    founderFigures: () => Promise.resolve({ ok: false } as Figures),
    recordGap: (text, reason) => { gaps.push(reason + ':' + text); return Promise.resolve(o.gapOk ?? true); },
    openCase: (_f, text) => { cases.push(text); return Promise.resolve({ ref: 'QD-S-ZZ' + cases.length, appended: o.appended ?? false, slaHours: 24 }); },
    humanHold: () => Promise.resolve(o.held ?? false),
    closeCase: (ref, reason) => { closed.push(ref + ':' + reason); return Promise.resolve({ ok: true, phone: '971500000041', lang: 'ar' as Lang, reason }); },
    closeHuman: (phone) => { closed.push('human:' + phone); return Promise.resolve(1); },
    notifyHuman: (from) => { notified.push(from); return Promise.resolve(true); },
    contentSid: (key) => Promise.resolve(o.sids?.[key] ?? null),
    send: (to, body, content) => {
      sent.push({ to, body, content });
      return Promise.resolve(content && o.contentFails ? { ok: false, err: '63xxx list not allowed' } : { ok: true });
    },
    record: (row) => {
      rows.push(row as unknown as Record<string, unknown>);
      history.unshift({ route: row.route, await: row.await, lang: row.lang });
      return Promise.resolve();
    },
  };
  return { d, sent, rows, cases, notified, closed, gaps, meanings, offered, reasoned, queued, written };
}
const msg = (body: string, audience: Audience = 'unknown', extra: Partial<MenuInput> = {}): MenuInput => ({ from: FROM, body, audience, ...extra });

Deno.test('the list fits WhatsApp: 6 items, titles <= 24, descriptions <= 72, button <= 20, both languages', () => {
  for (const lang of ['en', 'ar'] as Lang[]) {
    assert(MENU_BUTTON[lang].length <= 20);
    for (const aud of ['unknown', 'customer', 'supplier'] as Audience[]) {
      const items = menuItems(lang, aud);
      assertEquals(items.map((i) => i.id), [...MENU_IDS]);
      for (const i of items) {
        assert(i.item.length <= 24, lang + ' title too long: ' + i.item);
        assert(i.description.length <= 72, lang + ' description too long: ' + i.description);
      }
    }
  }
});

Deno.test('greeting_state: the menu opens only on a REASONED hello; held, nothing is guessed and the other handlers answer', async () => {
  // reasoned 'other' (a question beside the hello): not taken as a greeting
  const q = harness({ history: [{ route: 'deterministic', await: null, lang: 'en' }] });
  assertEquals((await menuTurn(q.d, msg('hi, what are your fees?'))).handled, false);
  assertEquals(q.meanings, [['hi, what are your fees?', false]]);
  // held: even a bare "Hi" mid-conversation is left to the handlers, whose last word is the menu (reofferMenu)
  const h = harness({ reasoningHeld: true, history: [{ route: 'deterministic', await: null, lang: 'en' }] });
  assertEquals((await menuTurn(h.d, msg('Hi'))).handled, false);
  assertEquals(h.sent.length, 0);
  // a list reply is structured: no reasoning is asked for at all
  const l = harness();
  await menuTurn(l.d, msg('x', 'unknown', { listId: 'qd_general' }));
  assertEquals(l.meanings, []);
});

Deno.test('problem_state: after "Report a problem" a reasoned hello is not filed; held, the words are kept as the case', async () => {
  const at = [{ route: 'menu_qd_problem', await: 'problem', lang: 'en' as Lang }];
  const g = harness({ history: at });
  assertEquals((await menuTurn(g.d, msg('Hi'))).route, 'menu_welcome');
  assertEquals(g.cases, []);
  assertEquals(g.meanings, [['Hi', true]]);
  const o = harness({ history: at, reasoningHeld: true });
  const r = await menuTurn(o.d, msg('the supplier never came'));
  assertEquals(r.route, 'menu_case');
  assertEquals(o.cases, ['the supplier never came']);
  assertEquals((o.rows[0].extra as Record<string, unknown>).meaning, 'held');
  // reasoned 'other' in the problem state (not a problem, not a hello) goes to its own handler
  const x = harness({ history: at });
  x.d.meaning = () => Promise.resolve('other');
  assertEquals((await menuTurn(x.d, msg('what are your fees?'))).handled, false);
  assertEquals(x.cases, []);
});

Deno.test('first "Hi" from an unknown number: English welcome signed QuotesDone, sent as the interactive list', async () => {
  const h = harness({ sids: { menu_en_general: 'HX' + '0'.repeat(32) } });
  const r = await menuTurn(h.d, msg('Hi'));
  assertEquals(r.route, 'menu_welcome');
  assertEquals(h.sent.length, 1);
  assertEquals(h.sent[0].content?.sid, 'HX' + '0'.repeat(32));
  // The {{1}} line is the model's (rulings 1195-1197), written for this turn; one line, as a Content variable must be.
  assertEquals(h.sent[0].content!.variables['1'], h.written[0].replace(/\s*\n+\s*/g, ' '));
  assert(!h.sent[0].content!.variables['1'].includes('\n'), 'a Content variable carries no line break');
  assertMatch(h.rows[0].reply as string, /Kind regards,\nQuotesDone Customer Support$/);
});

Deno.test('first "السلام عليكم": Arabic welcome that returns the salam, numbered when no Content SID exists', async () => {
  const h = harness();
  await menuTurn(h.d, msg('السلام عليكم'));
  assertEquals(h.sent.length, 1);
  assertEquals(h.sent[0].content, undefined);
  assertMatch(h.written[0], /returning the salam/); // the model is told to return the salam; the words are its own
  assert(h.sent[0].body.startsWith(h.written[0].replace(/\s*\n+\s*/g, ' ')));
  assertMatch(h.sent[0].body, /1\. طلب عرض سعر جديد/);
  assertMatch(h.sent[0].body, /فريق خدمة العملاء في QuotesDone/);
  assertEquals(h.rows[0].lang, 'ar');
});

Deno.test('a confirmed customer is greeted by name; a supplier sees "My supplier account"', async () => {
  const c = harness({ ctx: { audience: 'customer', name: 'ZZ DEMO Customer' }, sids: { menu_en_general: 'HX' + '1'.repeat(32) } });
  await menuTurn(c.d, msg('hello', 'customer'));
  assertMatch(c.written[0], /ZZ DEMO Customer/);
  assertEquals(c.sent[0].content?.variables['1'], c.written[0].replace(/\s*\n+\s*/g, ' '));
  assertEquals(contentKey('en', 'customer'), 'menu_en_general');

  const s = harness({ ctx: { audience: 'supplier', name: 'ZZ DEMO Trading LLC', approved: false } });
  await menuTurn(s.d, msg('menu', 'supplier'));
  assertMatch(s.sent[0].body, /3\. My supplier account/);
  assertEquals(contentKey('en', 'supplier'), 'menu_en_supplier');
});

Deno.test('the interactive list is refused: the numbered menu goes instead, nobody is left unanswered', async () => {
  const h = harness({ sids: { menu_en_general: 'HX' + '2'.repeat(32) }, contentFails: true });
  await menuTurn(h.d, msg('Hi'));
  assertEquals(h.sent.length, 2);
  assertMatch(h.sent[1].body, /1\. Request a quotation[\s\S]*6\. Talk to a person/);
  assertEquals(h.rows[0].sent, true);
  assertEquals((h.rows[0].extra as Record<string, unknown>).via, 'text_fallback');
});

Deno.test('a list reply (ListId), a button and a bare number after the menu select the option structurally; a typed title is not matched', () => {
  assertEquals(menuChoice({ listId: 'qd_follow' }), 'qd_follow');
  assertEquals(menuChoice({ buttonPayload: 'qd_person' }), 'qd_person');
  // menu_choice (point 75): a TYPED title is free text — never matched here, its meaning is reasoned (next test)
  assertEquals(menuChoice({ body: 'Report a problem' }), null);
  assertEquals(menuChoice({ body: 'الإبلاغ عن مشكلة' }), null);
  assertEquals(menuChoice({ body: '2', numbers: true }), 'qd_follow');
  assertEquals(menuChoice({ body: '٥', numbers: true }), 'qd_problem');
  assertEquals(menuChoice({ body: '2' }), null, 'a bare number means nothing unless we just offered the menu');
  assertEquals(menuChoice({ listId: 'qd_drop_tables' }), null);
});

Deno.test('menu_choice: a typed option is REASONED to that option; held, it is not picked on a word and the handlers answer', async () => {
  const h = harness({ history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
  assertEquals((await menuTurn(h.d, msg('Report a problem'))).route, 'menu_qd_problem');
  assertEquals(h.meanings, [['Report a problem', false]]);
  const held = harness({ reasoningHeld: true, history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
  assertEquals((await menuTurn(held.d, msg('Report a problem'))).handled, false);
  assertEquals(held.sent.length, 0);
  // Mid-conversation (no menu just shown) the options are not offered, and a reading of "qd_person" pages nobody.
  const mid = harness({ history: [{ route: 'deterministic', await: null, lang: 'en' }] });
  mid.d.meaning = (_t, _p, offer) => { mid.offered.push(offer); return Promise.resolve(offer ? 'qd_person' : 'other'); };
  assertEquals((await menuTurn(mid.d, msg('can someone call me about my quote'))).handled, false);
  assertEquals([mid.offered, mid.notified], [[false], []]);
  // While a problem is being described, the menu is not offered either: the description is filed.
  const pr = harness({ history: [{ route: 'menu_qd_problem', await: 'problem', lang: 'en' }] });
  // (menuMeaning only ever returns an option it offered: without the menu the reading is 'problem')
  pr.d.meaning = (_t, _p, offer) => { pr.offered.push(offer); return Promise.resolve(offer ? 'qd_follow' : 'problem'); };
  assertEquals((await menuTurn(pr.d, msg('I followed up twice and nobody answered'))).route, 'menu_case');
  assertEquals(pr.offered, [false]);
  // The founder is never offered the menu options, even right after it.
  const f = harness({ history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
  f.d.meaning = (_t, _p, offer) => { f.offered.push(offer); return Promise.resolve('qd_person'); };
  await menuTurn(f.d, msg('Talk to a person', 'founder'));
  assertEquals([f.offered, f.notified], [[false], []]);
});

Deno.test('every option routes to its own flow', async () => {
  const cases: Array<[string, RegExp, Partial<MenuContext>]> = [
    ['qd_new', /quotesdone\.com\/me\?new=1/, {}],
    ['qd_follow', /Request 1042: Quotes received/, { audience: 'customer', name: 'ZZ DEMO', requests: [{ rfq_no: 1042, status: 'quoted', created_at: '2026-09-20T10:00:00Z' }] }],
    ['qd_supplier', /register|Register/, {}],
    ['qd_general', /type your question/, {}],
    ['qd_problem', /describe the problem/, {}],
    ['qd_person', /a member of the team will reply to you on this number/, {}],
  ];
  for (const [id, expect, ctx] of cases) {
    const h = harness({ ctx, history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
    const r = await menuTurn(h.d, msg('x', (ctx.audience as Audience) || 'unknown', { listId: id }));
    assertEquals(r.route, 'menu_' + id);
    assertMatch(h.sent[0].body, expect, id);
    if (id === 'qd_person') assertEquals(h.notified, [FROM]);
    else assertEquals(h.notified, []);
  }
});

Deno.test('follow-up: an unknown number is told plainly nothing is registered on it, never shown anyone\'s requests', async () => {
  // fn_wa_menu_context lists requests only for a CONFIRMED customer number; the reply trusts that.
  const h = harness({ ctx: { audience: 'unknown', requests: [] }, history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
  await menuTurn(h.d, msg('Follow up my request'));
  assertMatch(h.sent[0].body, /There is no request registered under this mobile number \(or its email\)/);
  assertMatch(h.sent[0].body, /https:\/\/quotesdone\.com\/me\?new=1/);
  assert(!h.sent[0].body.includes('9'));
});

Deno.test('supplier option: a verified supplier gets the portal, an unverified one the remaining steps', async () => {
  const ok = harness({ ctx: { audience: 'supplier', name: 'ZZ DEMO Co', approved: true } });
  await menuTurn(ok.d, msg('x', 'supplier', { listId: 'qd_supplier' }));
  assertMatch(ok.sent[0].body, /is verified/);
  const no = harness({ ctx: { audience: 'supplier', name: 'ZZ DEMO Co', approved: false } });
  await menuTurn(no.d, msg('x', 'supplier', { listId: 'qd_supplier' }));
  assertMatch(no.sent[0].body, /not verified yet/);
});

Deno.test('report a problem: the next message becomes a case and the reference is confirmed', async () => {
  const h = harness({ history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
  await menuTurn(h.d, msg('5'));
  assertEquals(h.rows[0].await, 'problem');
  const r = await menuTurn(h.d, msg('My quote for request 1042 disappeared'));
  assertEquals(r.route, 'menu_case');
  assertEquals(h.cases, ['My quote for request 1042 disappeared']);
  assertMatch(h.sent[1].body, /Your case reference is QD-S-ZZ1/);
});

Deno.test('the caps do not stop a conversation: every turn of a five-message session is answered', async () => {
  // wa_per_recipient_24h = 1 governs the outbox's business-initiated notices, not replies in a session.
  const h = harness();
  for (const b of ['Hi', '4', 'what are your fees', 'menu', '6']) await menuTurn(h.d, msg(b));
  // 'what are your fees' has no FAQ answer in this fake, so it is left to the normal route (not sent here).
  assertEquals(h.sent.length, 4);
  assert(h.rows.every((r) => r.sent === true));
});

Deno.test('the caps really are absent from wa_inbound: it never reads them and never queues a reply in the outbox', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(!src.includes("'wa_per_recipient_24h'") && !src.includes("'wa_daily_cap'"));
  assert(!/from\('notifications'\)\s*\.insert/.test(src));
});

Deno.test('wa_autoreply_enabled off: nothing is sent, the turn is still recorded', async () => {
  const h = harness({ enabled: false });
  await menuTurn(h.d, msg('Hi'));
  assertEquals(h.sent.length, 0);
  assertEquals(h.rows[0].sent, false);
});

Deno.test('the founder: "Hi" opens the menu, but a command is left to his command channel', async () => {
  const h = harness({ ctx: { audience: 'founder', name: 'ZZ DEMO Founder' } });
  assertEquals((await menuTurn(h.d, msg('Hi', 'founder'))).handled, true);
  const g = harness({ ctx: { audience: 'founder' } });
  assertEquals((await menuTurn(g.d, msg('send me the weekly report', 'founder'))).handled, false);
});

Deno.test('first contact with a real question: left to the handlers first, then the FAQ answer and the menu', async () => {
  const h = harness({ faq: 'Posting a job is free.' });
  assertEquals((await menuTurn(h.d, msg('Is posting a job free?'))).handled, false);
  assertEquals(h.sent.length, 0);
  assertEquals(await welcomeFirstContact(h.d, msg('Is posting a job free?')), true);
  assertEquals(h.sent[0].body, h.written[0]);
  assert(h.written[0].includes('Posting a job is free.'));
  assertEquals(h.rows.map((r) => r.route), ['menu_first_answer', 'menu_welcome']);
});

// Review of #841 (HIGH): a supplier replying to a price request we sent through the outbox was welcomed
// with the menu instead of reaching fn_supplier_apply_change.
Deno.test('a supplier replying "12500" to our price request is in-flow: no menu, the price-change handler gets it', async () => {
  const h = harness({ ctx: { audience: 'supplier' }, weWrote: true });
  for (const b of ['12500', 'yes, reduce to 9000']) {
    assertEquals((await menuTurn(h.d, msg(b, 'supplier'))).handled, false, b);
    assertEquals(await welcomeFirstContact(h.d, msg(b, 'supplier')), false, b);
  }
  assertEquals(h.sent.length, 0);
});

Deno.test('a first message with a document goes to document intake, never the menu', async () => {
  const h = harness();
  assertEquals((await menuTurn(h.d, msg('my trade licence', 'unknown', { hasMedia: true }))).handled, false);
  assertEquals((await menuTurn(h.d, msg('Hi', 'unknown', { hasMedia: true }))).handled, false);
  assertEquals(await welcomeFirstContact(h.d, msg('', 'unknown', { hasMedia: true })), false);
  assertEquals(h.sent.length, 0);
});

Deno.test('an explicit hello after one of our notices still gets the welcome', async () => {
  const h = harness({ weWrote: true, history: [{ route: 'deterministic', await: null, lang: 'en' }] });
  assertEquals((await menuTurn(h.d, msg('Hello'))).route, 'menu_welcome');
  assertEquals(h.sent.length, 1);
});

// 1195-1197: the stored first-contact welcome is gone; the composed (model-written) reply is the one that must come last.
Deno.test('in wa_inbound the composed reply runs only after every handler that could claim the message', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const at = src.indexOf('await say(situation)');
  assert(at > 0);
  for (const handler of ["admin.rpc('fn_supplier_apply_change'", "admin.rpc('fn_wa_route'", 'if (media.length) {', "if (audience === 'founder') {"]) {
    const h = src.indexOf(handler);
    assert(h > 0 && h < at, handler + ' must come before the composed reply');
  }
});

Deno.test('later free text: a confident FAQ answer is sent; with none, the menu is offered again', async () => {
  const yes = harness({ faq: 'Suppliers pay no commission.', history: [{ route: 'menu_qd_general', await: 'question', lang: 'en' }] });
  assertEquals(await answerFromFaq(yes.d, msg('do suppliers pay commission')), true);
  assertMatch(yes.sent[0].body, /Suppliers pay no commission\.[\s\S]*reply MENU/);
  const no = harness({ history: [{ route: 'faq_answer', await: null, lang: 'en' }] });
  assertEquals((await menuTurn(no.d, msg('blah blah'))).handled, false);
  assertEquals(await answerFromFaq(no.d, msg('blah blah')), false);
  await reofferMenu(no.d, msg('blah blah'), 'Sorry, I could not match that to an answer.');
  assertMatch(no.sent[0].body, /Sorry, I could not match[\s\S]*1\. Request a quotation/);
  assertEquals(no.rows[0].route, 'menu_reoffer');
});

// ---- Founder instruction 763 (22 Sep 2026): the five defects he found testing the live menu ----------

Deno.test('763/1 the welcome never greets with an address, and sounds like a senior support lead', () => {
  // wa_messages 252: "Good day management@quotesdone.com" -- fn_identify_contact returns the admin email.
  assertEquals(cleanName('management@quotesdone.com'), null);
  assertEquals(cleanName('+971 50 000 0021'), null);
  assertEquals(cleanName('  ZZ DEMO  Person '), 'ZZ DEMO Person');
  assertEquals(greetLine('en', 'founder', 'management@quotesdone.com'), 'Good day, and thank you for contacting QuotesDone.');
  assert(!greetLine('ar', 'founder', 'management@quotesdone.com').includes('@'));
  for (const lang of ['en', 'ar'] as Lang[]) {
    const w = welcomeText(lang, 'unknown', null);
    assert(w.length <= 1024, lang + ' welcome exceeds the list-picker body limit: ' + w.length);
    assert(w.includes(HOURS[lang]), lang + ' welcome states the working hours');
    assert(w.includes('QuotesDone'));
  }
  // 22 Sep 2026 (documents-language audit, DL-11): this pinned "construction procurement platform",
  // which named a sector the product does not confine itself to — every trade is welcome except food
  // and beverage. The assertion now pins the corrected sentence, and refuses the old one by name.
  assertMatch(WELCOME_TAIL.en, /sourcing marketplace for every trade except food and beverage: request quotations and compare verified suppliers/);
  assert(!/construction procurement/.test(WELCOME_TAIL.en + WELCOME_TAIL.ar));
  assertMatch(WELCOME_TAIL.ar, /فريق خدمة العملاء في QuotesDone$/);
});

Deno.test('763/1 the working hours are the company\'s published hours (src/content/company.json), not copy', async () => {
  const company = JSON.parse(await Deno.readTextFile(new URL('../../../src/content/company.json', import.meta.url)));
  assertEquals(HOURS.en, company.hours.en);
  assertEquals(HOURS.ar, company.hours.ar);
  assertEquals(withinHours(new Date('2026-09-22T06:00:00Z')), true);   // Tuesday 10:00 Dubai
  assertEquals(withinHours(new Date('2026-09-22T15:00:00Z')), false);  // Tuesday 19:00 Dubai
  // 22 Sep 2026 (WEB-04): the working week is Monday to Friday everywhere on the estate, so Friday
  // is inside the hours and Sunday is outside. This line pinned the old Sunday-to-Thursday week.
  assertEquals(withinHours(new Date('2026-09-25T06:00:00Z')), true);   // Friday 10:00 Dubai
  assertEquals(withinHours(new Date('2026-09-27T06:00:00Z')), false);  // Sunday 10:00 Dubai
});

Deno.test('763/2 links go to the right portal: customers and strangers to /me, only suppliers to /portal', () => {
  const none: MenuContext = { audience: 'founder', name: 'ZZ DEMO', requests: [] };
  const cases: Array<[typeof MENU_IDS[number], MenuContext]> = [
    ['qd_new', { audience: 'unknown', name: null }], ['qd_follow', none], ['qd_follow', { audience: 'customer', name: null, requests: [] }]];
  for (const [id, ctx] of cases) {
    for (const lang of ['en', 'ar'] as Lang[]) {
      const t = optionReply(id, lang, ctx);
      assert(!t.includes('/portal'), id + ' ' + lang + ' must not send a customer to the supplier portal: ' + t);
      assert(t.includes(lang === 'ar' ? 'https://quotesdone.com/ar/me?new=1' : 'https://quotesdone.com/me?new=1'), id + ' ' + lang);
    }
  }
  const listed = optionReply('qd_follow', 'en', { audience: 'customer', name: 'ZZ DEMO', requests: [
    { id: '00000000-0000-4000-8000-000000000001', rfq_no: 1042, status: 'quoted', created_at: '2026-09-20T10:00:00Z' }] });
  assertMatch(listed, /Request 1042: Quotes received \(opened 2026-09-20\)\nhttps:\/\/quotesdone\.com\/me\?request=00000000-0000-4000-8000-000000000001/);
  assertMatch(optionReply('qd_supplier', 'en', { audience: 'supplier', name: 'ZZ DEMO Co', approved: true }), /https:\/\/quotesdone\.com\/portal$/);
  assertMatch(optionReply('qd_follow', 'en', { audience: 'supplier', name: 'ZZ DEMO Co', approved: true }), /\/portal$/);
});

Deno.test('763/3 a second report while a case is open is added to it; the reporter is told the reference and the clock', async () => {
  assertMatch(caseConfirm('en', { ref: 'QD-S-ZZ1', appended: true, slaHours: 24 }), /already have an open case, QD-S-ZZ1.*within 24 hours/);
  assertMatch(caseConfirm('ar', { ref: 'QD-S-ZZ1', appended: false, slaHours: 24 }), /QD-S-ZZ1.*خلال 24 ساعة/);
  const h = harness({ appended: true, history: [{ route: 'menu_qd_problem', await: 'problem', lang: 'en' }] });
  await menuTurn(h.d, msg('still broken'));
  assertEquals((h.rows[0].extra as Record<string, unknown>).case_appended, true);
});

Deno.test('763/3 the founder closes a case by WhatsApp and the reporter is told, in their language', async () => {
  assertEquals(founderCommand('close QD-S-ABC234 fixed the upload'), { kind: 'close_case', ref: 'QD-S-ABC234', reason: 'fixed the upload' });
  assertEquals(founderCommand('DONE +971 50 000 0041'), { kind: 'close_human', phone: '971500000041' });
  assertEquals(founderCommand('close the door'), null);
  const h = harness({ ctx: { audience: 'founder' } });
  const r = await menuTurn(h.d, msg('close QD-S-ABC234 fixed the upload', 'founder'));
  assertEquals(r.route, 'founder_close_case');
  assertEquals(h.closed, ['QD-S-ABC234:fixed the upload']);
  assertEquals(h.sent[0].to, 'whatsapp:+971500000041');
  assertMatch(h.sent[0].body, /^نفيدكم بإغلاق البلاغ رقم QD-S-ABC234/);
  assertMatch(h.sent[1].body, /Case QD-S-ABC234 is closed\. The reporter was told on WhatsApp\./);
  // Nobody but the founder can close anything.
  const s = harness();
  assertEquals((await menuTurn(s.d, msg('close QD-S-ABC234 x'))).handled, false);
  assertEquals(s.closed, []);
});

Deno.test('763/4 after "Talk to a person" the seat stays quiet until it is closed; the founder is never held', async () => {
  const h = harness({ held: true });
  for (const b of ['hello?', 'menu', 'is anyone there']) assertEquals((await menuTurn(h.d, msg(b))).route, 'held_for_human');
  assertEquals(h.sent.length, 0);
  assertEquals(h.rows.map((r) => r.route), ['held_for_human', 'held_for_human', 'held_for_human']);
  const f = harness({ held: true, ctx: { audience: 'founder' } });
  assertEquals((await menuTurn(f.d, msg('Hi', 'founder'))).route, 'menu_welcome');
  const d = harness({ ctx: { audience: 'founder' } });
  assertEquals((await menuTurn(d.d, msg('DONE +971500000041', 'founder'))).route, 'founder_close_human');
  assertEquals(d.closed, ['human:971500000041']);
});

Deno.test('763/4 the reply is honest about timing, and the alert is actionable', () => {
  assertMatch(optionReply('qd_person', 'en', { audience: 'unknown', name: null }, new Date('2026-09-22T06:00:00Z')),
    /working hours are Monday to Friday, 9am to 6pm \(GST\), excluding UAE public holidays\.\nAutomatic replies/);
  assertMatch(optionReply('qd_person', 'en', { audience: 'unknown', name: null }, new Date('2026-09-22T16:00:00Z')), /outside those hours now/);
  const a = humanAlert({ phone: 'whatsapp:+971500000041', name: 'management@quotesdone.com', profile: 'ZZ DEMO Ahmad',
                         audience: 'customer', lastMessages: ['my quote is missing', 'hello?'] });
  assertEquals(a.event, 'WhatsApp: ZZ DEMO Ahmad asks to talk to a person');
  assert(!a.event.includes('@') && !a.detail.includes('management@'));
  assertMatch(a.detail, /Reply now: https:\/\/wa\.me\/971500000041/);
  assertMatch(a.detail, /Last messages:\n- "my quote is missing"\n- "hello\?"/);
  assertMatch(a.detail, /send DONE \+971500000041/);
});

Deno.test('763/5 wa_inbound asks the FAQ with the gte-small embedding, never text alone', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(src.includes("new (globalThis as any).Supabase.ai.Session('gte-small')"));
  assertMatch(src, /rpc\('fn_faq_answer', \{\s*p_text: q, p_min_rank: 0\.15, p_embedding: await embedQuestion\(q\), p_min_similarity: FAQ_MIN_SIMILARITY/);
  assert(!/rpc\('fn_faq_answer', \{ p_text: [^}]*\}\)/.test(src), 'a text-only FAQ call is back');
});

// ---- An unmatched question gets a proper answer (22 Sep 2026, wa_messages 271) -----------------------
// The founder's exact conversation: MENU, "General question", "What suppliers you have" (answered by the
// FAQ), then "What sectors you cover", which fell through to agent_brain and came back as an internal
// error. It must now be answered from the live trade list, and nothing unanswered may carry internal text.

// Wording that must never reach a customer or supplier: internal names, status codes, fault admissions.
const INTERNAL = /\bHTTP\b|brain|agent_|\bfn_[a-z]|edge function|ai_gateway|supabase|stack trace|exception|undefined|\bnull\b|\b[45]0\d\b|could not reach|returned no reply/i;

Deno.test('271: the founder\'s exact message after the menu gets the grouped coverage answer from the live list', async () => {
  const h = harness({ ctx: { audience: 'founder' }, history: [{ route: 'menu_answer', await: null, lang: 'en' }], meaning: 'coverage:list' });
  assertEquals((await menuTurn(h.d, msg('What sectors you cover', 'founder'))).handled, false); // not a menu choice
  assertEquals(await answerFromFaq(h.d, msg('What sectors you cover', 'founder')), true);
  const body = h.sent[0].body;
  assertMatch(body, /We match quotation requests to verified UAE suppliers in these trades:/);
  // Twelve group headings leave less room than five did: every trade is either named or counted in its
  // group ("and N more"), and every group that has a trade is there — nothing is dropped.
  accountsForEveryTrade(body, 'en');
  // Grouped by the twelve live groups, in their table order — not the five this file used to carry.
  assertMatch(body, /• Construction & Building: /);
  assertMatch(body, /• MEP & Building Systems: HVAC & air conditioning, Electrical/);
  assert(body.indexOf('• Construction & Building') < body.indexOf('• MEP & Building Systems'), 'groups in their sort order');
  assert(!/• MEP: |• Fit-out & finishes|• Services & tech/.test(body), 'none of the five retired groups');
  assertMatch(body, /only to suppliers of that exact trade\. New trades are welcome: https:\/\/quotesdone\.com\/supplier/);
  assertMatch(body, /Request a quotation: https:\/\/quotesdone\.com\/me\?new=1/);
  assert(body.length <= 1700, 'fits one WhatsApp message: ' + body.length);
  assert(!INTERNAL.test(body), 'internal wording: ' + body.match(INTERNAL));
  assertEquals(h.rows[0].route, 'faq_answer');
  assertEquals(h.gaps.length, 0);
});

// WHETHER a message is a coverage question, and which trade it names, is REASONED (think(): the coverage:* and
// trade:<code> options of _shared/reasoned_channels.ts, 23 Sep 2026). The phrasings this file used to pin against
// regexes are what the reasoning is asked; here: each reasoned meaning gets its answer from the live list.
Deno.test('a reasoned coverage question gets the list, in English and formal Arabic, and a named trade its answer', () => {
  const ar = coverageReply('coverage:list', TRADES, 'ar')!;
  assertMatch(ar, /^نطابق طلبات عروض الأسعار مع موردين موثّقين في الإمارات/);
  accountsForEveryTrade(ar, 'ar');
  assertMatch(ar, /\nhttps:\/\/quotesdone\.com\/ar\/supplier\n/); // a link on its own line in RTL text
  assertMatch(ar, /\nhttps:\/\/quotesdone\.com\/ar\/me\?new=1$/);
  assert(ar.length <= 1500, 'Arabic fits one WhatsApp message: ' + ar.length);
  assertMatch(coverageReply('trade:mep_general', TRADES, 'en')!, /^Yes, MEP \(combined\) is one of the trades we match quotation requests to\./);
  assertMatch(coverageReply('trade:landscaping', TRADES, 'ar')!, /^نعم، تنسيق الحدائق والمسابح من التخصصات/);
  // A trade we do not list (reasoned coverage:other) gets the list and the welcome — never a claim.
  assertEquals(coverageReply('coverage:other', TRADES, 'en'), coverageReply('coverage:list', TRADES, 'en'));
});

Deno.test('the exact-trade rule: only a reasoned coverage meaning is answered from the list, and nothing is claimed otherwise', () => {
  for (const m of ['none', 'size', 'intent:pricing', 'intent:how_to_register', '']) assertEquals(coverageReply(m, TRADES, 'en'), null, m);
  // A trade:<code> no longer on the live list is not claimed: the list is sent instead.
  assertMatch(coverageReply('trade:zz_demo_gone', TRADES, 'en')!, /^We match quotation requests to verified UAE suppliers in these trades:/);
  // A trade registered tomorrow is listed at once, under "Other trades", never dropped.
  const more = [...TRADES, { code: 'zz_demo_trade', label: 'ZZ DEMO Trade', label_ar: 'تخصص تجريبي', aliases: [] }];
  assertEquals(groupedTrades(more, 'en').at(-1), { title: 'Other trades', labels: ['ZZ DEMO Trade'] });
  // Twenty more trades registered: every group still appears, counts replace names, the links survive.
  const grown = [...TRADES, ...Array.from({ length: 20 }, (_, i) => ({ code: 'zz_demo_' + i, label: 'ZZ DEMO Trade number ' + i, label_ar: 'تخصص تجريبي رقم ' + i, aliases: [] }))];
  for (const lang of ['en', 'ar'] as Lang[]) {
    const r = coverageReply('coverage:list', grown, lang)!;
    assert(r.length <= 1430, lang + ' grown list overflows: ' + r.length);
    assertMatch(r, /me\?new=1$/);
    assertMatch(r, lang === 'ar' ? /تخصصات أخرى: .* و\d+ أخرى/ : /Other trades: .* and \d+ more/);
  }
  // No rows readable: no list is invented.
  assertEquals(coverageReply('coverage:list', [], 'en'), null);
});

Deno.test('held (the model hold): a coverage question is not guessed at; unanswered, its meaning is filed for replay', async () => {
  const h = harness({ meaning: null });
  assertEquals(await answerFromFaq(h.d, msg('what trades do you cover?')), false, 'no meaning, no FAQ: nothing answered on a guess');
  await unanswered(h.d, msg('what trades do you cover?'), 'no_grounded_answer');
  assertEquals(h.queued, ['what trades do you cover?']);
  assertEquals(h.rows[0].route, 'menu_reoffer'); // the courteous line and the menu went now
  // Reasoned to be nothing we hold: filed as a gap, never queued for a replay that has nothing to send.
  const n = harness({ meaning: 'none' });
  await unanswered(n.d, msg('what is your opinion of the new metro line'), 'no_grounded_answer');
  assertEquals(n.queued, []);
});

Deno.test('held: a first contact gets the welcome AND its meaning is queued, so the question is answered on replay', async () => {
  const h = harness({ meaning: null });
  assertEquals(await welcomeFirstContact(h.d, msg('what trades do you cover?')), true);
  assertEquals(h.queued, ['what trades do you cover?']);
  const a = harness({ meaning: 'coverage:list' });
  await welcomeFirstContact(a.d, msg('what trades do you cover?'));
  assertEquals(a.queued, [], 'answered now: nothing to replay');
});

Deno.test('held: a size question is not guessed to be one (no capability answer), and a menu choice is never reasoned', async () => {
  const h = harness({ meaning: null });
  assertEquals((await menuTurn(h.d, msg('how many suppliers do you have'))).handled, false);
  assertEquals(h.sent.length, 0);
  const c = harness({ meaning: 'size', history: [{ route: 'menu_welcome', await: null, lang: 'en' }] });
  const r = await menuTurn(c.d, msg('2'));
  assert(r.route?.startsWith('menu_qd_'), 'a bare number after the menu is the option: ' + r.route);
  assertEquals(c.reasoned, [], 'a menu choice is structured data, not text to reason over');
});

Deno.test('an unknown question gets the courteous fallback and the menu, is filed for the team, and carries no internal text', async () => {
  for (const [body, lang] of [['what is your opinion of the new metro line', 'en'], ['ما رأيكم في مشروع المترو الجديد', 'ar']] as const) {
    const h = harness({ ctx: { audience: 'founder' } });
    assertEquals(await answerFromFaq(h.d, msg(body, 'founder')), false);
    await unanswered(h.d, msg(body, 'founder'), 'no_grounded_answer');
    assertEquals(h.gaps, ['no_grounded_answer:' + body]);
    const sent = h.sent[0].body;
    assert(h.written[0].includes('recorded for the team') && h.written[0].includes('Talk to a person')); // told; the words are the model's
    assert(sent.startsWith(h.written[0].replace(/\s*\n+\s*/g, ' ')));
    assertMatch(sent, lang === 'ar' ? /التحدث إلى أحد الموظفين/ : /Talk to a person/); // the way to a real reply is on the menu
    assert(!INTERNAL.test(sent), 'internal wording: ' + sent.match(INTERNAL));
    assertEquals(h.rows[0].route, 'menu_reoffer');
    assertEquals((h.rows[0].extra as Record<string, unknown>).unanswered_reason, 'no_grounded_answer'); // kept for the team, not shown
  }
  // If the question could not be filed, the reply does not say it was.
  const f = harness({ gapOk: false });
  await unanswered(f.d, msg('what is your opinion of the new metro line'), 'no_grounded_answer');
  assert(!/recorded/.test(f.written[0]));
});

Deno.test('no reply text the menu, the options, the cases or the coverage answer can send carries internal wording', () => {
  const ctxs: MenuContext[] = [{ audience: 'unknown', name: null }, { audience: 'supplier', name: 'ZZ DEMO Co', approved: false },
    { audience: 'customer', name: null, requests: [{ id: 'r1', rfq_no: 12, status: 'open', created_at: '2026-09-22' }] }];
  const texts: string[] = [];
  for (const lang of ['en', 'ar'] as Lang[]) {
    for (const c of ctxs) for (const id of MENU_IDS) texts.push(optionReply(id, lang, c));
    texts.push(welcomeText(lang, 'unknown', null), caseConfirm(lang, { ref: 'QD-S-ZZ2345', slaHours: 24 }), caseConfirm(lang, { ref: null }),
               sorryLead(lang, true), sorryLead(lang, false), coverageReply('coverage:list', TRADES, lang)!);
  }
  for (const t of texts) assert(!INTERNAL.test(t), 'internal wording in a reply: ' + t.match(INTERNAL) + ' in ' + t.slice(0, 80));
});

Deno.test('wa_inbound never builds a reply from an internal error, and never calls agent_brain again', async () => {
  const src = (await Deno.readTextFile(new URL('./index.ts', import.meta.url)))
    .split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');   // comments may name the defect; code may not
  assert(!/agent_brain|company brain/.test(src), 'agent_brain is back in wa_inbound');
  assert(!/reply\s*=[^;\n]*(brainErr|\(HTTP|\.status\b)/.test(src), 'a reply is built from an error again');
  // The Twilio download error names hosts and codes; the supplier hears a plain sentence instead.
  assert(src.includes("note: 'the file could not be downloaded from WhatsApp — please send it again'"));
  assert(!src.includes('note: got.err'));
});

// ---- Internal figures stay internal (founder_instruction 777, 22 Sep 2026) ----------------------------
// He asked "how many suppliers do we have" and got "0": "we shouldn't be sharing such numbers; instead a
// professional response". A size question gets the capability statement from EVERY number, his included;
// the internal reading goes to his number only, on the command word FIGURES / «أرقام» as the whole message.
// Every field below carries a different number so a reading answered from the wrong field fails.
const FIG: Figures = {
  ok: true, read_at_local: '19:33 on Tue 22 Sep',
  suppliers: { registered: 11, registered_7d: 12, verified: 13 }, requests: { today: 21, last_7d: 22 },
  quotes: { total: 31, last_7d: 32 }, reveals_month: { paid: 41, fee_aed: 4200 },
  support: { open_cases: 51, waiting_for_person: 52 }, it: { open_findings: 61 },
  marketing_7d: { posts_published: 71, posts_scheduled: 72, ad_spend_aed: 73 }, brief: { local_time: '20:00', sent_today: false },
};
function founderHarness(audience: Audience = 'founder', figures: Figures = FIG, meaning: string | null = 'none') {
  const h = harness({ ctx: { audience }, meaning });
  const asked: string[] = [];
  h.d.founderFigures = (from) => { asked.push(from); return Promise.resolve(figures); };
  return { ...h, asked };
}
// No digit may survive once the links are taken out: a count cannot hide in the capability answer.
const noCount = (body: string) => !/\d/.test(body.replace(/https?:\/\/\S+/g, ''));

Deno.test('777: a size question from ANY number gets the capability answer, never a number, and never reads the figures', async () => {
  const asks: Array<[string, Lang]> = [
    ['how many suppliers do we have', 'en'], ['How many suppliers do you have?', 'en'], ['how many customers use quotesdone', 'en'],
    ['how big are you', 'en'], ['what is your revenue', 'en'], ['how many requests have you received so far', 'en'],
    ['كم عدد الموردين لديكم', 'ar'], ['كم عدد الموردين؟', 'ar'], ['كم عدد العملاء المسجلين في المنصة', 'ar'], ['ما حجم شركتكم', 'ar'],
  ];
  for (const aud of ['founder', 'customer', 'supplier', 'unknown'] as Audience[]) {
    for (const [q, lang] of asks) {
      const h = founderHarness(aud, FIG, 'size'); // reasoned: a size question (reasoned_channels.ts SIZE)
      const r = await menuTurn(h.d, msg(q, aud));
      assertEquals(r.route, 'capability_answer', aud + ': ' + q);
      assertEquals(h.sent.length, 1);
      const body = h.sent[0].body;
      assert(noCount(body), aud + ': ' + q + ' carries a digit: ' + body);
      assert(!INTERNAL.test(body), q + ': internal wording');
      assertEquals(h.asked.length, 0, aud + ': ' + q + ' must not even read the figures');
      if (lang === 'ar') {
        assertMatch(body, /نطابق كل طلب عرض سعر مع موردين موثّقين[\s\S]*لطلب عرض سعر:\nhttps:\/\/quotesdone\.com\/ar\/me\?new=1[\s\S]*«قائمة»/);
      } else {
        assertMatch(body, /We match each quotation request to verified suppliers across the UAE in the exact trade[\s\S]*To request a quotation: https:\/\/quotesdone\.com\/me\?new=1\n\nReply MENU/);
      }
    }
  }
});

Deno.test('777: FIGURES from the founder is his internal reading; from anyone else it is ordinary text that reads nothing', async () => {
  for (const cmd of ['FIGURES', 'figures', 'Figures.', 'أرقام', 'الأرقام']) {
    const h = founderHarness('founder');
    assertEquals((await menuTurn(h.d, msg(cmd, 'founder'))).route, 'founder_figures', cmd);
    assertEquals(h.asked.length, 1);
    const body = h.sent[0].body;
    if (/[a-z]/i.test(cmd)) {
      assertMatch(body, /^Internal figures at 19:33 on Tue 22 Sep \(UAE time\), for internal use only:/);
      for (const n of ['Suppliers: 11 registered (12 in the last 7 days), 13 verified.', 'Customer requests: 21 today, 22', 'Quotes: 31 in total', 'Reveals this month: 41 paid, AED 4,200', 'Support: 51 open', 'IT: 61 open', 'Marketing (7 days): 71']) assert(body.includes(n), n);
    } else {
      assertMatch(body, /^الأرقام الداخلية \(19:33 on Tue 22 Sep بتوقيت الإمارات\)، للاطلاع الداخلي فقط:/);
      assert(body.includes('الموردون: 11 مسجّل (12 خلال 7 أيام)، و13 موثّق.'));
    }
  }
  // The routine's refusal is said plainly, never turned into numbers.
  const refused = founderHarness('founder', { ok: false });
  await menuTurn(refused.d, msg('FIGURES', 'founder'));
  assertEquals(refused.sent[0].body, 'The internal figures could not be read just now; please try again shortly.');
  // Anyone else (figures_command, point 74): the command word is ordinary text — never matched as a command,
  // never reads the figures, and nothing sent carries a count.
  for (const aud of ['customer', 'supplier', 'unknown'] as Audience[]) {
    const h = founderHarness(aud);
    // Not matched as a command: the menu turn leaves it to the reasoned handlers, sends nothing itself, reads nothing.
    assertEquals(await menuTurn(h.d, msg('FIGURES', aud)), { handled: false }, aud);
    assertEquals(h.asked.length, 0, aud + ' must not read the figures');
    assertEquals(h.sent.length, 0, aud);
  }
  // Only the whole message is the command.
  for (const t of ['figures please', 'send figures', 'the figures for the quote']) assertEquals(isFiguresCommand(t), false, t);
});

Deno.test('780: an unrecognised founder question gets the customer reply: courteous line and menu, no internal wording', async () => {
  const h = founderHarness('founder');
  await founderUnanswered(h.d, msg('Any specific number', 'founder'), 'no_grounded_answer');
  const body = h.sent.map((m) => m.body || '').join(' ');
  assert(!/FIGURES|internal figures|model|on hold|IT findings/i.test(body), 'internal wording reached a normal reply: ' + body);
  assertEquals(h.asked.length, 0, 'no reading is attached');
  assertEquals(h.gaps, ['no_grounded_answer:Any specific number']);
  assertEquals(h.rows[0].route, 'menu_reoffer');
});

Deno.test('777: the figures are read in exactly one place, behind the command word', async () => {
  const flow = await Deno.readTextFile(new URL('./menu_flow.ts', import.meta.url));
  const calls = flow.split('d.founderFigures(').length - 1;
  assertEquals(calls, 1, 'fn_founder_whatsapp_figures must be read in one place only');
  const at = flow.indexOf('d.founderFigures(');
  const guard = flow.lastIndexOf("if (inp.audience === 'founder' && isFiguresCommand(body))", at);
  assert(guard > 0 && at - guard < 200, 'the only read sits directly behind the founder + FIGURES guard');
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(!src.includes('answerFounder('), 'the natural-question figures path must not return');
  // The size question is decided (by reasoning) before any other handler in the turn.
  const sizeAt = flow.indexOf("(await d.intent(body)) === 'size'");
  assert(sizeAt > 0 && sizeAt < flow.indexOf('// 1. The message after "Report a problem"'));
  assert(src.indexOf('menuTurn(menuDeps, menuIn)') < src.indexOf("if (audience === 'founder') {\n      const question"));
});

// RULINGS 1195/1196/1197 (12 Oct 2026): every CONVERSATION reply is written by a model in that turn. This fails the
// moment any menu path sends text the fake model did not write in the same turn. Notifications are the only exception,
// and they are named: a case-reference receipt, the founder's close confirmations and his FIGURES report.
// founder_instruction 1339 (27 Oct 2026): the case confirmation is a reply to their message, so it left this list: the model
// writes it (carrying the reference); the fixed caseConfirm goes out only when OpenRouter is down (extra.outage_fallback).
const NOTIFICATION_ROUTES = new Set(['founder_close_case', 'founder_close_human', 'founder_figures']);
const ONE_LINE = (t: string) => t.replace(/\s*\n+\s*/g, ' ');
Deno.test('1195-1197: no conversation reply leaves the menu unless a model wrote it in this turn; with no model, nothing is sent', async () => {
  const menuShown = [{ route: 'menu_welcome', await: null, lang: 'en' as Lang }];
  const turns: Array<[string, () => Promise<unknown>, ReturnType<typeof harness>]> = [];
  const add = (name: string, o: Parameters<typeof harness>[0], run: (h: ReturnType<typeof harness>) => Promise<unknown>) => {
    const h = harness(o); turns.push([name, () => run(h), h]);
  };
  for (const noModel of [false, true]) {
    add('hi', { noModel }, (h) => menuTurn(h.d, msg('Hi')));
    add('salam', { noModel }, (h) => menuTurn(h.d, msg('السلام عليكم')));
    for (const id of MENU_IDS) add('option ' + id, { noModel, history: menuShown }, (h) => menuTurn(h.d, msg('', 'customer', { listId: id })));
    add('size', { noModel, meaning: 'size' }, (h) => menuTurn(h.d, msg('how many suppliers do you have')));
    add('faq', { noModel, faq: 'Posting a job is free.' }, (h) => answerFromFaq(h.d, msg('is it free')));
    add('first contact', { noModel, faq: 'Posting a job is free.' }, (h) => welcomeFirstContact(h.d, msg('is it free')));
    add('after general question', { noModel, faq: 'Posting a job is free.', history: [{ route: 'menu_qd_general', await: 'question', lang: 'en' }] }, (h) => menuTurn(h.d, msg('is it free')));
    add('unanswered', { noModel }, (h) => unanswered(h.d, msg('what about the metro'), 'no_grounded_answer'));
    add('founder unanswered', { noModel, ctx: { audience: 'founder' } }, (h) => founderUnanswered(h.d, msg('anything', 'founder'), 'no_grounded_answer'));
    add('reoffer', { noModel }, (h) => reofferMenu(h.d, msg('blah'), 'Their message was unclear.'));
    add('problem case', { noModel, history: [{ route: 'menu_qd_problem', await: 'problem', lang: 'en' }] }, (h) => menuTurn(h.d, msg('the supplier never came')));
  }
  let conversational = 0;
  for (const [name, run, h] of turns) {
    await run();
    h.rows.forEach((row, i) => {
      if (NOTIFICATION_ROUTES.has(String(row.route))) return;
      const extra = row.extra as Record<string, unknown>;
      if (extra.outage_fallback === true) {
        assertEquals(h.written.length, 0, name + ': a code-written outage fallback went out while a model was writing');
        return;
      }
      if (extra.held_notice === true) {
        // no model: the person still hears from us — the fixed receipt, never an answer
        assert(Object.values(HELD_NOTICE).includes(String(row.reply)), name + ': a held turn sent something other than the held notice');
        return;
      }
      if (!row.sent) return;
      conversational++;
      const body = String(row.reply);
      assert(h.written.some((w) => body === w || body.startsWith(ONE_LINE(w))), name + ' #' + i + ': sent text no model wrote this turn: ' + body.slice(0, 80));
    });
    if (h.written.length === 0) {
      // no model answered: only notifications and the held notice went out, and the person was not left silent
      for (const s of h.sent) {
        const row = h.rows.find((r) => r.reply === s.body);
        assert(row && (NOTIFICATION_ROUTES.has(String(row.route)) || (row.extra as Record<string, unknown>).held_notice === true || (row.extra as Record<string, unknown>).outage_fallback === true),
          name + ': with no model a conversation reply was still sent: ' + s.body.slice(0, 80));
      }
      assert(h.sent.length > 0, name + ': with no model the person was left silent');
    }
  }
  assert(conversational >= 15, 'the scenarios really sent conversation replies: ' + conversational);
});
