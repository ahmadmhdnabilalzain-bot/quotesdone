// The WhatsApp welcome and menu, driven through the real routing with fakes for the database and
// Twilio (founder_instruction 759, 22 Sep 2026). Prevents "said hi, got no response" from coming back
// for any reason inside the routing: a greeting, a first message, every option, each audience, and a
// conversation that continues past the first reply all get an answer.
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/wa_inbound/menu_flow.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { answerFromFaq, type Content, founderUnanswered, type MenuDeps, type MenuInput, menuTurn, reofferMenu, type Turn, unanswered, welcomeFirstContact } from './menu_flow.ts';
import { type Figures, isFiguresCommand } from './founder_queries.ts';
import { coverageReply, groupedTrades, type Trade } from './coverage.ts';
import {
  type Audience, caseConfirm, cleanName, contentKey, founderCommand, greetLine, HOURS, humanAlert, isGreeting, type Lang, MENU_BUTTON, sorryLead,
  MENU_IDS, menuChoice, type MenuContext, menuItems, optionReply, WELCOME_TAIL, welcomeText, withinHours,
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

type Sent = { to: string; body: string; content?: Content };
function harness(o: { ctx?: Partial<MenuContext>; sids?: Record<string, string>; contentFails?: boolean; faq?: string | null;
                      enabled?: boolean; history?: Turn[]; weWrote?: boolean; held?: boolean; appended?: boolean; gapOk?: boolean;
                      /** The reasoned meaning think() would return (reasoned_channels.ts); null = held. Default 'none'. */
                      meaning?: string | null } = {}) {
  const sent: Sent[] = []; const rows: Array<Record<string, unknown>> = []; const cases: string[] = []; const notified: string[] = []; const closed: string[] = []; const gaps: string[] = [];
  const history: Turn[] = [...(o.history || [])];
  const reasoned: string[] = []; const queued: string[] = [];
  const d: MenuDeps = {
    meaning: (text) => { reasoned.push(text); return Promise.resolve(o.meaning === undefined ? 'none' : o.meaning); },
    queueMeaning: (text) => { queued.push(text); return Promise.resolve(); },
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
  return { d, sent, rows, cases, notified, closed, gaps, reasoned, queued };
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

Deno.test('greetings are recognised in English and Arabic, and a question is not a greeting', () => {
  for (const g of ['Hi', 'hi!', 'Hello there', 'السلام عليكم', 'السلام عليكم ورحمة الله وبركاته', 'مرحبا', 'مرحبًا', 'Good morning']) assert(isGreeting(g), g);
  for (const q of ['hi, what are your fees?', 'how do I register', 'أريد عرض سعر']) assert(!isGreeting(q), q);
});

Deno.test('first "Hi" from an unknown number: English welcome signed QuotesDone, sent as the interactive list', async () => {
  const h = harness({ sids: { menu_en_general: 'HX' + '0'.repeat(32) } });
  const r = await menuTurn(h.d, msg('Hi'));
  assertEquals(r.route, 'menu_welcome');
  assertEquals(h.sent.length, 1);
  assertEquals(h.sent[0].content?.sid, 'HX' + '0'.repeat(32));
  assertEquals(h.sent[0].content!.variables['1'], 'Good day, and thank you for contacting QuotesDone.');
  assert(!h.sent[0].content!.variables['1'].includes('\n'), 'a Content variable carries no line break');
  assertMatch(h.rows[0].reply as string, /Kind regards,\nQuotesDone Customer Support$/);
});

Deno.test('first "السلام عليكم": Arabic welcome that returns the salam, numbered when no Content SID exists', async () => {
  const h = harness();
  await menuTurn(h.d, msg('السلام عليكم'));
  assertEquals(h.sent.length, 1);
  assertEquals(h.sent[0].content, undefined);
  assertMatch(h.sent[0].body, /^وعليكم السلام ورحمة الله وبركاته/);
  assertMatch(h.sent[0].body, /1\. طلب عرض سعر جديد/);
  assertMatch(h.sent[0].body, /فريق خدمة العملاء في QuotesDone/);
  assertEquals(h.rows[0].lang, 'ar');
});

Deno.test('a confirmed customer is greeted by name; a supplier sees "My supplier account"', async () => {
  const c = harness({ ctx: { audience: 'customer', name: 'ZZ DEMO Customer' }, sids: { menu_en_general: 'HX' + '1'.repeat(32) } });
  await menuTurn(c.d, msg('hello', 'customer'));
  assertEquals(c.sent[0].content?.variables['1'], 'Good day ZZ DEMO Customer, and thank you for contacting QuotesDone.');
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

Deno.test('a list reply (ListId), a typed title and a bare number after the menu each select the option', () => {
  assertEquals(menuChoice({ listId: 'qd_follow' }), 'qd_follow');
  assertEquals(menuChoice({ buttonPayload: 'qd_person' }), 'qd_person');
  assertEquals(menuChoice({ body: 'Report a problem' }), 'qd_problem');
  assertEquals(menuChoice({ body: 'الإبلاغ عن مشكلة' }), 'qd_problem');
  assertEquals(menuChoice({ body: '2', numbers: true }), 'qd_follow');
  assertEquals(menuChoice({ body: '٥', numbers: true }), 'qd_problem');
  assertEquals(menuChoice({ body: '2' }), null, 'a bare number means nothing unless we just offered the menu');
  assertEquals(menuChoice({ listId: 'qd_drop_tables' }), null);
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
  const h = harness({ ctx: { audience: 'unknown', requests: [] } });
  await menuTurn(h.d, msg('Follow up my request'));
  assertMatch(h.sent[0].body, /^There is no request registered under this mobile number \(or its email\)/);
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
  assertEquals(h.sent.map((s) => s.body.slice(0, 22)), ['Posting a job is free.', h.sent[1].body.slice(0, 22)]);
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

Deno.test('in wa_inbound the first-contact welcome runs only after every handler that could claim the message', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const at = src.indexOf('await welcomeFirstContact(');
  assert(at > 0);
  for (const handler of ["admin.rpc('fn_supplier_apply_change'", "admin.rpc('fn_wa_route'", 'if (media.length) {', "if (audience === 'founder') {"]) {
    const h = src.indexOf(handler);
    assert(h > 0 && h < at, handler + ' must come before the first-contact welcome');
  }
});

Deno.test('later free text: a confident FAQ answer is sent; with none, the menu is offered again', async () => {
  const yes = harness({ faq: 'Suppliers pay no commission.', history: [{ route: 'menu_qd_general', await: 'question', lang: 'en' }] });
  assertEquals(await answerFromFaq(yes.d, msg('do suppliers pay commission')), true);
  assertMatch(yes.sent[0].body, /Suppliers pay no commission\.\n\nReply MENU/);
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
  assertMatch(body, /^We match quotation requests to verified UAE suppliers in these trades:/);
  for (const t of TRADES) assert(body.includes(t.label), 'every live trade is listed: ' + t.label);
  assertMatch(body, /• MEP: HVAC & air conditioning, Electrical/);
  assertMatch(body, /only to suppliers of that exact trade\. New trades are welcome: https:\/\/quotesdone\.com\/supplier/);
  assertMatch(body, /Request a quotation: https:\/\/quotesdone\.com\/me\?new=1/);
  assert(body.length <= 1500, 'fits one WhatsApp message: ' + body.length);
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
  for (const t of TRADES) assert(ar.includes(t.label_ar!), 'every live trade in Arabic: ' + t.label_ar);
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
    assertMatch(sent, lang === 'ar' ? /^شكرًا لسؤالكم\. لا تتوفر لديّ إجابة مؤكدة عنه حتى الآن، وأفضّل ألا أجيب دون تحقق، لذا سجّلته لدى فريقنا\./
                                    : /^Thank you for your question\. I do not have a confirmed answer to it yet and would rather not guess, so I have recorded it for our team\./);
    assertMatch(sent, lang === 'ar' ? /التحدث إلى أحد الموظفين/ : /Talk to a person/); // the way to a real reply is on the menu
    assert(!INTERNAL.test(sent), 'internal wording: ' + sent.match(INTERNAL));
    assertEquals(h.rows[0].route, 'menu_reoffer');
    assertEquals((h.rows[0].extra as Record<string, unknown>).unanswered_reason, 'no_grounded_answer'); // kept for the team, not shown
  }
  // If the question could not be filed, the reply does not say it was.
  const f = harness({ gapOk: false });
  await unanswered(f.d, msg('what is your opinion of the new metro line'), 'no_grounded_answer');
  assert(!/recorded it/.test(f.sent[0].body));
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

Deno.test('777: FIGURES from the founder is his internal reading; from anyone else it is the capability answer', async () => {
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
  // Anyone else: the command word reads nothing and gets the capability answer.
  for (const aud of ['customer', 'supplier', 'unknown'] as Audience[]) {
    const h = founderHarness(aud);
    assertEquals((await menuTurn(h.d, msg('FIGURES', aud))).route, 'capability_answer', aud);
    assertEquals(h.asked.length, 0, aud + ' must not read the figures');
    assert(noCount(h.sent[0].body));
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
  const sizeAt = flow.indexOf("(await d.meaning(body)) === 'size'");
  assert(sizeAt > 0 && sizeAt < flow.indexOf('// 1. The message after "Report a problem"'));
  assert(src.indexOf('menuTurn(menuDeps, menuIn)') < src.indexOf("if (audience === 'founder') {\n      const question"));
});
