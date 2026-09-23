// SERVER-AUTHORED SUPPLIER COPY, RENDERED IN THE SUPPLIER'S LANGUAGE.
//
// supplier_api and supplier_portal used to author supplier-facing sentences in English and the portal
// printed them raw, so a supplier who switched to عربي still read why they were not being matched,
// what each document is for, their alerts and every gate error in English (website audit 2026-09-14,
// supplier portal, "Arabic is incomplete"). The servers now return a stable `code` (+ `params`) beside
// the English text; this file owns the EN/AR wording for every code. The English text on the response
// stays as the fallback, so an older client, an email, or a code this table does not know yet still
// reads correctly — `srvText` never returns an empty string when the server sent a sentence.

import { arDays } from '@/lib/durationLabel';
import { price } from './money';
type P = Record<string, any>;
type L = 'en' | 'ar';
type Entry = { en: (p: P) => string; ar: (p: P) => string };
const s = (en: string | ((p: P) => string), ar: string | ((p: P) => string)): Entry => ({
  en: typeof en === 'string' ? () => en : en,
  ar: typeof ar === 'string' ? () => ar : ar,
});

const EMIRATE_AR: Record<string, string> = {
  'Dubai': 'دبي', 'Abu Dhabi': 'أبوظبي', 'Sharjah': 'الشارقة', 'Ajman': 'عجمان',
  'Ras Al Khaimah': 'رأس الخيمة', 'Umm Al Quwain': 'أم القيوين', 'Fujairah': 'الفجيرة',
};
export const emirateLabel = (lang: string, e: string) => (lang === 'ar' ? EMIRATE_AR[e] || e : e);

// taxonomy_trade / taxonomy_role carry an English `label` only (40 trades, 8 roles, read 14 Sep 2026).
// The codes are the controlled vocabulary, so the Arabic rides on the code; an unknown code falls back
// to the server's English label rather than to nothing.
const TRADE_AR: Record<string, string> = {
  hvac: 'التكييف والتهوية', electrical: 'الأعمال الكهربائية', building_materials: 'مواد البناء والتشييد',
  engineering_consultancy: 'الاستشارات الهندسية والعمارة', power_generators: 'المولدات ومعدات الطاقة',
  heavy_equipment: 'المعدات الثقيلة والآليات', labour_supply: 'توريد العمالة', plumbing: 'السباكة والأدوات الصحية',
  safety_equipment: 'معدات السلامة والوقاية الشخصية', solar: 'الطاقة الشمسية والمتجددة',
  chemicals: 'الكيماويات الصناعية والإنشائية', plastics_pipes: 'البلاستيك والأنابيب والتجهيزات',
  oilfield: 'مستلزمات حقول النفط والصناعة', home_automation: 'أتمتة المنازل والمباني',
  logistics_moving: 'النقل والتخزين والخدمات اللوجستية', packaging: 'مستلزمات التغليف والطباعة',
  marine: 'المستلزمات والأعمال البحرية', fire_fighting: 'مكافحة الحريق وأنظمة السلامة',
  it_services: 'خدمات تقنية المعلومات والشبكات', joinery: 'النجارة والأعمال الخشبية', glazing: 'الزجاج والواجهات الزجاجية',
  aluminium: 'الألمنيوم والتكسية', steel: 'الحديد وتشكيل المعادن', flooring: 'الأرضيات', painting: 'الدهانات والتشطيبات',
  gypsum: 'الجبس والقواطع والأسقف', signage: 'اللافتات والطباعة', landscaping: 'تنسيق الحدائق والمسابح',
  security_systems: 'الأنظمة الأمنية', elevators: 'المصاعد والسلالم المتحركة', doors: 'الأبواب والنوافذ',
  waterproofing: 'العزل المائي والحراري', upholstery: 'التنجيد والمفروشات', wallpaper: 'ورق الجدران والتشطيبات الجدارية',
  scaffolding: 'السقالات ومعدات الوصول', cleaning: 'التنظيف وخدمات المرافق', av_it: 'الصوت والصورة والتيار الخفيف',
  interior_fitout: 'التشطيبات والتجهيزات الداخلية', civil_works: 'الأعمال المدنية والإنشائية',
  mep_general: 'الأعمال الكهروميكانيكية المتكاملة (MEP)',
  office_equipment: 'المعدات المكتبية والطباعة', pos_retail: 'أنظمة نقاط البيع وتقنيات التجزئة',
};
const ROLE_AR: Record<string, string> = {
  manufacturer: 'مصنّع', distributor: 'موزّع معتمد', supplier: 'مورّد / تجارة', installer: 'مركّب / منفّذ',
  contractor: 'مقاول', turnkey_fitout: 'مقاول تسليم مفتاح / تجهيزات', maintenance: 'صيانة / عقود صيانة سنوية',
  consultant: 'استشاري / مصمّم',
};
export const vocabLabel = (lang: string, kind: 'trade' | 'role', code: string, fallback?: string) =>
  lang === 'ar' ? ((kind === 'trade' ? TRADE_AR : ROLE_AR)[code] || fallback || code) : (fallback || code);

// THE SIGN-UP TRADE IS A taxonomy_trade CODE (15 Sep 2026, agent: customer_support). The sign-up form
// offered 29 free-text suggestions ("Pest Control", "Handyman", "AC Duct Cleaning", "Other") and 25 of
// them had no code, so leads.sector held words fn_match_capability's exact-code overlap never meets.
// A supplier with no company yet cannot read taxonomy_trade (RLS on, no policy; supplier_api
// capability_state answers no_company), so the English labels are mirrored here, in taxonomy_trade
// `sort` order, read from production on 15 Sep 2026 (40 active codes). TRADE_AR above carries the same
// 40 keys; scripts/checks/signup_trade_codes_are_the_taxonomy.test.mjs fails if the two drift apart.
// When supplier_api serves the vocabulary before create_company, this mirror should go.
export const TRADE_EN: Record<string, string> = {
  hvac: 'HVAC & air conditioning', electrical: 'Electrical', building_materials: 'Building & Construction Materials',
  engineering_consultancy: 'Engineering Consultancy & Architecture', power_generators: 'Generators & Power Equipment',
  heavy_equipment: 'Heavy Equipment & Plant', labour_supply: 'Manpower & Labour Supply', plumbing: 'Plumbing & sanitary',
  safety_equipment: 'Safety Equipment & PPE', solar: 'Solar & Renewable Energy', chemicals: 'Industrial & Construction Chemicals',
  plastics_pipes: 'Plastics, Pipes & Fittings', oilfield: 'Oilfield & Industrial Supplies', home_automation: 'Home & Building Automation',
  logistics_moving: 'Logistics, Movers & Storage', packaging: 'Packaging & Printing Supplies', marine: 'Marine & Offshore Supplies',
  fire_fighting: 'Fire fighting & life safety', it_services: 'IT & Network Services', joinery: 'Joinery & carpentry',
  glazing: 'Glass & glazing', aluminium: 'Aluminium & cladding', steel: 'Steel & metal fabrication', flooring: 'Flooring',
  painting: 'Painting & finishes', gypsum: 'Gypsum, partitions & ceilings', signage: 'Signage & printing',
  landscaping: 'Landscaping & pools', security_systems: 'Security systems', elevators: 'Elevators & escalators',
  doors: 'Doors & windows', waterproofing: 'Waterproofing & insulation', upholstery: 'Upholstery & soft furnishing',
  wallpaper: 'Wallpaper & wall finishes', scaffolding: 'Scaffolding & access', cleaning: 'Cleaning & facility services',
  av_it: 'AV, IT & low current', interior_fitout: 'Interior fit-out', civil_works: 'Civil & construction works',
  mep_general: 'MEP (combined)',
  office_equipment: 'Office equipment & printing', pos_retail: 'Point-of-sale & retail technology',
};
export const TRADE_CODES = Object.keys(TRADE_EN);
export const tradeLabel = (lang: string, code: string) => vocabLabel(lang, 'trade', code, TRADE_EN[code]);

const DOC_AR: Record<string, string> = {
  'Trade licence': 'الرخصة التجارية', 'Insurance': 'التأمين', 'ISO certification': 'شهادة ISO',
  'Manufacturer authorisation': 'تفويض الشركة المصنّعة', 'Trade licence (legacy)': 'الرخصة التجارية',
};
const docAr = (d: unknown) => DOC_AR[String(d || '')] || String(d || 'المستند');
const plural = (n: number, one: string, many: string) => (Number(n) === 1 ? one : many);

const COPY: Record<string, Entry> = {
  // ── Documents tab hints (supplier_portal DOC_KINDS) ─────────────────────────────────────────────
  // "DED" NAMED ONE EMIRATE'S MAINLAND REGISTRAR (audit 22 Sep 2026, SP-I-06; agent: customer_support).
  // A free-zone supplier, and a mainland supplier outside Dubai, is not licensed by "دائرة التنمية
  // الاقتصادية" at all, so the hint told most of the estate to upload something they do not hold.
  // The phrase now names the class of issuer, not one of its members; supplier_portal DOC_KINDS says
  // the same in English.
  doc_hint_license: s('Required. Your current trade licence from your licensing authority (Economic Department or free-zone authority).',
    'مطلوب. رخصتكم التجارية السارية الصادرة عن جهة الترخيص (الدائرة الاقتصادية أو سلطة المنطقة الحرة).'),
  doc_hint_profile: s('Required. Your company introduction deck or PDF. Shown to customers after a reveal.', 'مطلوب. العرض التعريفي لشركتكم أو ملف PDF، ويطّلع عليه العملاء بعد الكشف.'),
  doc_hint_catalogs: s('Product or project catalogues. Upload as many as you like — new files are added, never replaced.', 'كتالوجات المنتجات أو المشاريع. ارفعوا منها ما تشاؤون؛ تُضاف الملفات الجديدة دون أن تحلّ محل السابقة.'),
  // ONE NAME FOR EACH NUMBER (audit 22 Sep 2026, SP-I-07): the TRN is «رقم التسجيل الضريبي» and the
  // EGR is «بطاقة المنشأة» everywhere on the supplier surface — «الرقم الضريبي» and «السجل الاقتصادي»
  // read as two different documents to a supplier holding one of each.
  doc_hint_vat: s('Your Tax Registration Number (TRN) certificate. Needed before you can invoice with VAT.',
    'شهادة رقم التسجيل الضريبي (TRN)، وهي مطلوبة قبل إصدار فواتير تتضمن ضريبة القيمة المضافة.'),
  doc_hint_insurance: s('Public liability or contractor all-risk cover.', 'تأمين المسؤولية العامة أو تأمين جميع أخطار المقاول.'),
  doc_hint_iso: s('Any ISO certificate you hold. Strengthens your capability score.', 'أي شهادة ISO تحملونها، وهي تعزّز تقييم قدراتكم.'),
  doc_hint_manufacturer: s('Authorised-dealer letters from the brands you carry.', 'خطابات الوكالة المعتمدة من العلامات التجارية التي تتعاملون بها.'),
  doc_hint_egr: s('Your Economic Register (EGR) card, issued with your trade licence.', 'بطاقة المنشأة (EGR) الصادرة مع رخصتكم التجارية.'),

  // ── Overview alerts (supplier_portal buildAlerts) ───────────────────────────────────────────────
  doc_expiry_title: s((p) => `${p.doc} ${p.expired ? 'has expired' : 'expires soon'}`, (p) => (p.expired ? `انتهت صلاحية ${docAr(p.doc)}` : `أوشكت صلاحية ${docAr(p.doc)} على الانتهاء`)),
  doc_expiry_detail: s(
    (p) => `Expiry ${p.expiry} — ${p.days_left < 0 ? `overdue by ${Math.abs(p.days_left)} days` : `${p.days_left} days left`}. Upload a renewed copy to stay eligible.`,
    (p) => `تاريخ الانتهاء ${p.expiry} — ${p.days_left < 0 ? `انقضى على انتهائها ${arDays(Math.abs(p.days_left))}` : p.days_left === 0 ? 'تنتهي اليوم' : `المتبقي ${arDays(p.days_left)}`}. ارفعوا نسخة مجدّدة لتبقوا ضمن المورّدين المؤهّلين.`),
  // `total` (audit 21 Sep 2026, finding 6): the bell said "1 new RFQ" beside "Inquiries received (3)";
  // both were true (two were already quoted) but neither said so. The count now names what it is out of.
  new_rfq_title: s((p) => `${p.count} new RFQ${p.count > 1 ? 's' : ''} waiting for your quote` + (p.total > p.count ? ` (of ${p.total} received)` : ''), (p) => `${p.count} ${plural(p.count, 'طلب تسعير جديد ينتظر', 'طلبات تسعير جديدة تنتظر')} عرضكم` + (p.total > p.count ? ` (من أصل ${p.total})` : '')),
  // The notices the estate wrote to this supplier (supplier_portal buildNotifications `notices`).
  notice_quote_accepted: s('A customer revealed your quote — their contact details are in Messages', 'كشف أحد العملاء عن عرضكم — تجدون بيانات التواصل معه في الرسائل'),
  notice_new_message: s('New message from a customer', 'رسالة جديدة من عميل'),
  notice_new_inquiry: s('A new request was matched to you', 'وصلكم طلب جديد يطابق نشاطكم'),
  notice_rfq_addendum: s('A customer updated a request you received', 'حدّث أحد العملاء طلبًا وصلكم'),
  notice_job_awarded_other: s('A request you quoted was awarded to another supplier', 'أُسند طلب قدّمتم عليه عرضًا إلى مورّد آخر'),
  notice_rfq_no_supplier: s('A request closed without a supplier', 'أُغلق طلب دون مورّد'),
  notice_doc_received: s('We received your document', 'استلمنا مستندكم'),
  notice_registration_received: s('We received your registration', 'استلمنا تسجيلكم'),
  notice_quote_spec_hold: s('A quotation is held until its exact details are given', 'عرض سعر معلّق إلى حين استكمال تفاصيله الدقيقة'),
  notice_quote_spec_released: s('A held quotation was released to the customer', 'أُرسل إلى العميل عرض سعر كان معلّقًا'),
  notice_quote_spec_regenerated: s('A held quotation was regenerated with your details', 'أُعيد إعداد عرض سعر معلّق وفق تفاصيلكم'),
  notice_quote: s('An update on one of your quotations', 'تحديث بشأن أحد عروضكم'),
  new_rfq_detail: s('Open requests matched to your capabilities that you have not quoted yet.', 'طلبات مفتوحة تطابق قدراتكم ولم تقدّموا عليها عروضًا بعد.'),
  draft_quote_title: s((p) => `${p.count} draft quote${p.count > 1 ? 's' : ''} to complete`, (p) => `${p.count} ${plural(p.count, 'مسودة عرض تحتاج', 'مسودات عروض تحتاج')} إلى استكمال`),
  draft_quote_detail: s('Add the missing details so we can send them to customers.', 'يُرجى إضافة التفاصيل الناقصة لنتمكّن من إرسالها إلى العملاء.'),

  // ── Eligibility (supplier_portal eligibility) ───────────────────────────────────────────────────
  elig_note: s('Each request goes to a shortlist of up to 8 suppliers, ranked by how well your listing matches what the customer asked for. Suppliers anywhere in the UAE are eligible; being in the customer’s emirate only breaks a tie.',
    'يُرسَل كل طلب إلى قائمة مختصرة تضم 8 مورّدين كحدّ أقصى، مرتّبين وفق مدى تطابق ملفكم مع ما طلبه العميل. والمورّدون من جميع إمارات الدولة مؤهّلون، ولا يُعتدّ بوجودكم في إمارة العميل إلا للترجيح عند التساوي.'),
  permanently_closed_title: s('Your listing is marked permanently closed', 'ملفكم مسجّل بحالة «مغلق نهائيًا»'),
  permanently_closed_detail: s('We will not send you requests while this is set. Contact us if this is wrong.', 'لن نرسل إليكم أي طلبات ما دام هذا الإعداد قائمًا. يُرجى التواصل معنا إن كان ذلك غير صحيح.'),
  banned_title: s('Your account is suspended', 'حسابكم موقوف'),
  banned_detail: s('Suspended accounts are excluded from all matching. Contact us to resolve it.', 'الحسابات الموقوفة مستبعدة من جميع عمليات المطابقة. يُرجى التواصل معنا لمعالجة الأمر.'),
  licence_expired_title: s('Your account is paused — trade licence expired', 'حسابكم متوقف مؤقتًا — انتهت صلاحية الرخصة التجارية'),
  licence_expired_detail: s((p) => `Your trade licence expired on ${p.date || 'an earlier date'}. Upload a valid copy and your account is restored automatically, usually within a day. There is no fee.`,
    (p) => `انتهت صلاحية رخصتكم التجارية في ${p.date || 'تاريخ سابق'}. ارفعوا نسخة سارية وسيُعاد تفعيل حسابكم تلقائيًا، خلال يوم واحد عادةً، ودون أي رسوم.`),
  insurance_expired_title: s('Your account is paused — insurance expired', 'حسابكم متوقف مؤقتًا — انتهت صلاحية التأمين'),
  insurance_expired_detail: s((p) => `Your insurance certificate expired on ${p.date || 'an earlier date'}. Upload a valid copy and your account is restored automatically. There is no fee.`,
    (p) => `انتهت صلاحية شهادة التأمين في ${p.date || 'تاريخ سابق'}. ارفعوا نسخة سارية وسيُعاد تفعيل حسابكم تلقائيًا دون أي رسوم.`),
  matching_blocked_title: s('Matching is switched off for your account', 'المطابقة معطّلة لحسابكم'),
  matching_blocked_detail: s('This was set by our team rather than automatically. Contact us to have it reviewed.', 'عطّلها فريقنا يدويًا، ولم تتعطّل تلقائيًا. يُرجى التواصل معنا لمراجعة ذلك.'),
  not_registered_title: s('Your registration is not submitted', 'لم يُرسَل تسجيلكم بعد'),
  not_registered_detail: s('Only registered suppliers receive requests. Complete the six registration steps to submit it.', 'لا تصل الطلبات إلا إلى المورّدين المسجّلين. أكملوا خطوات التسجيل الست لإرساله.'),
  scope_unconfirmed_title: s('Confirm what your company can quote for', 'أكّدوا ما يمكن لشركتكم تسعيره'),
  scope_unconfirmed_detail: s('We never guess a supplier’s scope on their behalf, so no request is sent to you until you have confirmed it yourself. It takes about a minute, once.',
    'لا نفترض نطاق عمل أي مورّد نيابةً عنه، لذا لن يصلكم أي طلب قبل أن تؤكّدوه بأنفسكم. لا يستغرق ذلك سوى دقيقة واحدة، ولمرة واحدة فقط.'),
  undiscoverable_title: s('Nothing describes what you supply', 'لا يوجد ما يصف ما تورّدونه'),
  undiscoverable_detail: s('Requests are matched on your sector, products, services and categories. All of these are empty, so no request can reach you.', 'تُطابَق الطلبات وفق قطاعكم ومنتجاتكم وخدماتكم وفئاتكم، وجميعها فارغة حاليًا، لذا لا يمكن أن يصلكم أي طلب.'),
  no_sector_title: s('Set your sector', 'حدّدوا قطاعكم'),
  no_sector_detail: s('A matching sector adds 2 points to your score on every request in that category, which decides who makes the shortlist.', 'يضيف القطاع المطابق نقطتين إلى تقييمكم في كل طلب ضمن تلك الفئة، وهو ما يحدّد من يدخل القائمة المختصرة.'),
  empty_products_title: s('Add your products', 'أضيفوا منتجاتكم'),
  empty_services_title: s('Add your services', 'أضيفوا خدماتكم'),
  empty_categories_title: s('Add your categories', 'أضيفوا فئاتكم'),
  empty_capability_summary_title: s('Add your capability summary', 'أضيفوا ملخص قدراتكم'),
  empty_detail: s('Each keyword found here raises your match score. Empty fields cannot match anything.', 'كل كلمة مفتاحية هنا ترفع تقييم مطابقتكم، أما الحقول الفارغة فلا تطابق أي طلب.'),
  no_emirate_title: s('Set your home emirate', 'حدّدوا إمارة مقرّكم'),
  no_emirate_detail: s('You receive requests from the whole UAE either way. Your emirate is used only to break a tie between equally good matches.', 'تصلكم الطلبات من جميع إمارات الدولة في كل الأحوال، ولا تُستخدم إمارتكم إلا للترجيح بين مطابقتين متساويتين.'),
  no_licence_title: s('Upload your trade licence', 'ارفعوا رخصتكم التجارية'),
  no_licence_detail: s('Required before your account can be approved.', 'مطلوبة قبل اعتماد حسابكم.'),
  confirm_scope_title: s('Confirm what your company does', 'أكّدوا طبيعة نشاط شركتكم'),
  confirm_scope_detail: s(
    (p) => `Your documents mention trades you have not confirmed: ${(p.trades || []).map((c: string) => vocabLabel('en', 'trade', c, String(c).replace(/_/g, ' '))).join(', ')}. Tick them in "What you can quote for" if your company does this work.`,
    (p) => `تذكر مستنداتكم تخصصات لم تؤكّدوها بعد: ${(p.trades || []).map((c: string) => vocabLabel('ar', 'trade', c, String(c).replace(/_/g, ' '))).join('، ')}. اختاروها في «ما يمكن لشركتكم تسعيره» إن كانت شركتكم تزاول هذا العمل.`),
  expiring_title: s((p) => `Your ${p.doc === 'insurance' ? 'insurance certificate' : 'trade licence'} expires in ${p.days} day${p.days === 1 ? '' : 's'}`,
    (p) => `تنتهي صلاحية ${p.doc === 'insurance' ? 'شهادة التأمين' : 'رخصتكم التجارية'} خلال ${arDays(p.days)}`),
  expiring_detail: s('Once it expires your account is paused automatically and you stop receiving requests. Upload a renewed copy now to avoid that.', 'عند انتهاء صلاحيتها يتوقف حسابكم تلقائيًا ولن تصلكم أي طلبات. ارفعوا نسخة مجدّدة الآن لتفادي ذلك.'),
  no_phone_title: s('Add a contact number', 'أضيفوا رقم تواصل'),
  no_phone_detail: s('Customers cannot reach you after a reveal without one.', 'لن يتمكن العملاء من التواصل معكم بعد الكشف من دونه.'),

  // ── The mandatory six (shared/supplier_registration.ts) ─────────────────────────────────────────
  reg_name: s('Company name', 'اسم الشركة'),
  reg_mobile: s('Verified mobile number', 'رقم جوال موثَّق'),
  reg_email: s('Verified e-mail', 'بريد إلكتروني موثَّق'),
  reg_licence: s('Trade licence', 'الرخصة التجارية'),
  reg_profile: s('Company profile', 'الملف التعريفي للشركة'),
  reg_terms: s('Signed supplier terms', 'الموافقة على شروط المورّد'),
  // Not one of the six: the WhatsApp answer asked in sign-up after the mobile is verified (15 Sep 2026).
  reg_whatsapp: s('Your answer on your WhatsApp number', 'إجابتكم بشأن رقم WhatsApp'),

  // ── Licence gate reasons (leads.licence_gate_reason) ────────────────────────────────────────────
  no_licence: s('no trade licence on file', 'لا توجد رخصة تجارية محفوظة'),
  licence_expired: s('the trade licence on file has expired', 'الرخصة التجارية المحفوظة منتهية الصلاحية'),

  // ── supplier_api gate and error codes ───────────────────────────────────────────────────────────
  no_company: s('Register your company first.', 'يُرجى تسجيل شركتكم أولًا.'),
  company_exists: s('Your account already manages a company.', 'حسابكم يدير شركة بالفعل.'),
  enter_company: s('Enter your company name.', 'أدخلوا اسم شركتكم.'),
  terms_not_accepted: s('Accept the supplier terms first (Profile tab).', 'يُرجى الموافقة على شروط المورّد أولًا (من تبويب الملف).'),
  not_verified: s((p) => `Your registration is not verified yet${p.reason ? ': ' + (COPY[p.reason]?.en({}) || p.reason) : ''}. Upload a clear, in-date trade licence in Documents — it is re-checked automatically the moment it is saved.`,
    (p) => `لم يُتحقَّق من تسجيلكم بعد${p.reason ? ': ' + (COPY[p.reason]?.ar({}) || p.reason) : ''}. ارفعوا رخصة تجارية واضحة وسارية في تبويب المستندات، وسيُعاد فحصها تلقائيًا فور حفظها.`),
  // ONE FEE, ONE NAME (review of #858, 22 Sep 2026). The signed Supplier Agreement v12 clause 2 defines it:
  // "Subscription Fee — the annual supplier subscription fee described in clause 6" / «رسوم الاشتراك». This entry
  // said "yearly registration", the tax documents said a third thing again. scripts/checks/one_fee_has_one_name.test.mjs
  // reads the name out of the agreement itself and refuses any other one here.
  // THE FEE AMOUNT GOES THROUGH THE ONE FORMATTER TOO (review of #858, 23 Sep 2026). This line built
  // its own: `${p.fee}` with no grouping printed "AED 1000" where the invoice says "AED 1,000", and
  // درهم where every other Arabic amount in the portal reads د.إ. `price` keeps the currency the
  // server named, so a fee quoted in another currency still reads correctly.
  registration_due: s((p) => `Your ${price('en', Number(p.fee), String(p.currency || 'AED'))} annual Subscription Fee is due. Pay it in Billing to send quotes.`, (p) => `رسوم الاشتراك السنوية (${price('ar', Number(p.fee), String(p.currency || 'AED'))}) مستحقة. يُرجى سدادها من تبويب الفواتير لتتمكّنوا من إرسال العروض.`),
  registration_state_unavailable: s('We could not confirm your registration status. Please try again shortly.', 'تعذّر التحقق من حالة تسجيلكم. يُرجى المحاولة بعد قليل.'),
  inquiry_concluded: s('This request has been concluded — the customer has already selected a supplier. Best of luck on the next one.', 'أُغلق هذا الطلب بعد أن اختار العميل مورّدًا. نتمنى لكم التوفيق في الطلبات القادمة.'),
  invalid_amount: s('Enter a valid amount.', 'أدخلوا مبلغًا صحيحًا.'),
  draft_saved: s('Your quote was saved as a draft. Add the missing details so we can send it to the customer.', 'حُفظ عرضكم كمسودة. يُرجى إضافة التفاصيل الناقصة لنتمكّن من إرساله إلى العميل.'),
  quote_no_pages: s('Could not read the file pages. Please attach a clear PDF or photo.', 'تعذّرت قراءة صفحات الملف. يُرجى إرفاق ملف PDF أو صورة واضحة.'),
  quote_read_failed: s('We could not read that quotation automatically — fill in the form below instead; nothing else is needed.', 'تعذّرت قراءة عرض السعر تلقائيًا. يُرجى تعبئة النموذج أدناه بدلًا من ذلك، ولا يلزم أي إجراء آخر.'),
  upload_failed: s('We could not store that file. Please try again.', 'تعذّر حفظ الملف. يُرجى المحاولة مرة أخرى.'),
  save_failed: s('We could not save your profile. Please try again.', 'تعذّر حفظ ملفكم. يُرجى المحاولة مرة أخرى.'),
  missing_required: s((p) => 'Still needed to register: ' + (p.missing || []).map((c: string) => COPY[c]?.en({}) || c).join(', ') + '.',
    (p) => 'ما زال مطلوبًا لإتمام التسجيل: ' + (p.missing || []).map((c: string) => COPY[c]?.ar({}) || c).join('، ') + '.'),
  capability_need_trade_role: s('Choose at least one trade and one role.', 'يُرجى اختيار تخصص واحد ودور واحد على الأقل.'),
  // Founder_instructions 857 and 862: a confirm with nothing ticked is refused rather than stored as a
  // complete, empty portfolio. Returned by capabilityConfirm for every route that confirms.
  services_none_ticked: s('Tick at least one service you do before confirming. A service you do not tick is one you have not confirmed, so inquiries that name it will not reach you.', 'يُرجى تحديد خدمة واحدة على الأقل من الخدمات التي تقدّمونها قبل التأكيد، فالخدمة التي لا تحدّدونها تُعدّ غير مؤكَّدة، ولن تصلكم الاستفسارات التي تطلبها.'),
  capability_bad_range: s('The project value range is not valid.', 'نطاق قيمة المشاريع غير صالح.'),
  capability_write_failed: s('We could not save your scope. Please try again.', 'تعذّر حفظ نطاق عملكم. يُرجى المحاولة مرة أخرى.'),
  reg_exempt: s((p) => `Your registration is permanently free — you are supplier number ${p.rank}, inside the founding 1,000. There is no fee, now or in future.`, (p) => `تسجيلكم مجاني بصفة دائمة، فأنتم المورّد رقم ${p.rank} ضمن أول 1,000 مورّد مؤسِّس. لا رسوم عليكم الآن ولا مستقبلًا.`),
  reg_not_due: s('There is nothing to pay. The yearly fee applies only from the 1,001st registration.', 'لا يوجد ما تدفعونه. تُطبَّق الرسوم السنوية اعتبارًا من التسجيل رقم 1,001 فقط.'),
  reg_paid: s((p) => `Your registration is paid${p.until ? ' until ' + p.until : ''}.`, (p) => `رسوم تسجيلكم مدفوعة${p.until ? ' حتى ' + p.until : ''}.`),
  // ── The sales engineer's hold desk (14 Sep 2026) ────────────────────────────────────────────────
  spec_hold: s('Your quote is on hold until the exact details listed are stated. Fill them in here or upload a revised quote.', 'عرضكم معلّق إلى حين ذكر التفاصيل الدقيقة المبيّنة. أكملوها هنا أو ارفعوا عرضًا معدّلًا.'),
  quote_review_changes: s('Your quote needs the changes listed in the review before we can send it to the customer.', '\u064a\u062d\u062a\u0627\u062c \u0639\u0631\u0636\u0643\u0645 \u0625\u0644\u0649 \u0627\u0644\u062a\u0639\u062f\u064a\u0644\u0627\u062a \u0627\u0644\u0648\u0627\u0631\u062f\u0629 \u0641\u064a \u0627\u0644\u0645\u0631\u0627\u062c\u0639\u0629 \u0642\u0628\u0644 \u0625\u0631\u0633\u0627\u0644\u0647 \u0625\u0644\u0649 \u0627\u0644\u0639\u0645\u064a\u0644.'),
  options_split: s((p) => `Your submission carried ${p.count} options; each is now its own quotation.`, (p) => `تضمّن عرضكم ${p.count} خيارات، وأصبح كل خيار منها عرضًا مستقلًا.`),
  option_total_missing: s((p) => `Enter the total for option ${p.option}.`, (p) => `أدخلوا الإجمالي للخيار ${p.option}.`),
  too_many_options: s('A quote can carry at most 20 options.', 'يمكن أن يتضمن العرض 20 خيارًا كحدّ أقصى.'),
  invalid_values: s('Some details are not exact yet — see the marked fields.', 'بعض التفاصيل ليست دقيقة بعد. يُرجى مراجعة الحقول المحددة.'),
  not_awaiting_approval: s('There is no regenerated quotation waiting for your approval.', 'لا يوجد عرض مُعاد إعداده بانتظار اعتمادكم.'),
  confirm_required: s('Tick the box to confirm the regenerated quotation is correct.', 'ضعوا علامة لتأكيد صحة العرض المُعاد إعداده.'),
  still_missing: s('Some required details are still missing.', 'ما زالت بعض التفاصيل المطلوبة ناقصة.'),
  no_hold: s('This quote is not on hold.', 'هذا العرض غير معلّق.'),
  not_found: s('That quote was not found.', 'لم يُعثر على هذا العرض.'),
  payment_unavailable: s('Online payment is not available right now. Please try again later.', 'الدفع الإلكتروني غير متاح حاليًا. يُرجى المحاولة لاحقًا.'),

  // ── SIGN-IN, IDENTITY, DOCUMENTS, CHAT AND PAYMENT REFUSALS (audit 22 Sep 2026, SP-I-03) ───────
  // About sixteen supplier-facing refusals in kyc, login_otp, messages_api, supplier_api and
  // supplier_pay carried English prose and NO code, so the Arabic portal printed them in English —
  // and a supplier whose code was rate-limited, whose licence upload failed or whose chat was shut
  // read an English sentence at the exact moment they needed to understand it. Every Arabic line
  // below says what its English line says; none of them is a generic apology.

  // supplier_portal read/write failures (SP-I-01). The real Postgres message is in the function log.
  load_failed: s('Could not load this section. Please try again.', 'تعذّر تحميل هذا القسم. يُرجى المحاولة مرة أخرى.'),
  remove_failed: s('We could not remove that document. Please try again.', 'تعذّرت إزالة هذا المستند. يُرجى المحاولة مرة أخرى.'),
  expiry_save_failed: s('We could not save that expiry date. Please try again.', 'تعذّر حفظ تاريخ الانتهاء. يُرجى المحاولة مرة أخرى.'),
  unexpected_error: s('Something went wrong. Please try again.', 'حدث خطأ غير متوقع. يُرجى المحاولة مرة أخرى.'),

  // Identity: the mobile, the e-mail and the six-digit codes (kyc, login_otp).
  enter_name: s('Please enter your name.', 'يُرجى إدخال اسمكم.'),
  // TWIN: src/components/portal/supplier/uaeMobile.ts and supabase/functions/_shared/uae_mobile.ts
  // hold the one rule — +9715XXXXXXXX — that the sign-up form and kyc send_sms both apply (SP-A-05).
  bad_mobile: s('Enter a valid UAE mobile number, for example 05X XXX XXXX.', 'يُرجى إدخال رقم جوال إماراتي صحيح، مثل 05X XXX XXXX.'),
  bad_phone: s('That phone number is not valid.', 'رقم الهاتف غير صحيح.'),
  bad_identifier: s('Enter a valid email address or UAE mobile number.', 'يُرجى إدخال بريد إلكتروني صحيح أو رقم جوال إماراتي.'),
  enter_code: s('Enter the 6-digit code.', 'يُرجى إدخال الرمز المكوّن من ستة أرقام.'),
  wrong_code: s('Incorrect or expired code.', 'الرمز غير صحيح أو انتهت صلاحيته.'),
  code_expired: s('That code has expired. Please request a new one.', 'انتهت صلاحية هذا الرمز. يُرجى طلب رمز جديد.'),
  too_many_attempts: s('Too many attempts. Please request a new code.', 'تجاوزتم عدد المحاولات المسموح به. يُرجى طلب رمز جديد.'),
  code_burned: s('Too many incorrect attempts. Please request a new code.', 'تكرّر إدخال رمز غير صحيح فلم يعد صالحًا. يُرجى طلب رمز جديد.'),
  verify_failed: s('We could not check that code. Please try again.', 'تعذّر التحقق من الرمز. يُرجى المحاولة مرة أخرى.'),
  session_failed: s('Could not start your session. Please try again.', 'تعذّر بدء جلستكم. يُرجى المحاولة مرة أخرى.'),
  not_signed_in: s('Please sign in first.', 'يُرجى تسجيل الدخول أولًا.'),
  // The rate limits say WHICH limit was hit — "try again later" alone tells a supplier nothing.
  rate_limited: s('Too many code requests. Please try again later.', 'طلبتم رموزًا كثيرة خلال وقت قصير. يُرجى المحاولة لاحقًا.'),
  sms_rate_limited: s('Too many SMS codes were requested for this number in the last hour. Please wait and request a new one.',
    'طُلب عدد كبير من رموز الرسائل النصية لهذا الرقم خلال الساعة الماضية. يُرجى الانتظار قليلًا ثم طلب رمز جديد.'),
  email_not_sent: s('Could not send the email code. Please try again in a minute.', 'تعذّر إرسال رمز التحقق إلى بريدكم. يُرجى المحاولة بعد دقيقة.'),
  email_suppressed: s('We cannot email this address — it is on our do-not-send list because mail to it bounced or was unsubscribed. Please contact info@quotesdone.com and we will restore it.',
    'لا يمكننا الإرسال إلى هذا البريد الإلكتروني لأنه مُدرَج في قائمة عدم الإرسال بعد ارتداد رسائل سابقة أو إلغاء الاشتراك. يُرجى مراسلتنا على info@quotesdone.com لإعادة تفعيله.'),
  sms_unavailable: s('SMS is not configured. Please contact us.', 'خدمة الرسائل النصية غير مهيّأة حاليًا. يُرجى التواصل معنا.'),
  sms_send_failed: s('Could not send the code. Please try again in a minute.', 'تعذّر إرسال الرمز. يُرجى المحاولة بعد دقيقة.'),
  send_failed: s('Could not send the code. Please try again.', 'تعذّر إرسال الرمز. يُرجى المحاولة مرة أخرى.'),
  sms_signin_unavailable: s('SMS sign-in is not enabled yet. Please sign in with your email.', 'تسجيل الدخول برسالة نصية غير مفعّل بعد. يُرجى تسجيل الدخول ببريدكم الإلكتروني.'),
  sms_not_available_for_number: s('SMS codes are not available for this number. Please sign in with your email.', 'لا تتوفر رموز الرسائل النصية لهذا الرقم. يُرجى تسجيل الدخول ببريدكم الإلكتروني.'),
  sms_signup_refused: s('We cannot create an account from a mobile number — your email address is what identifies your account. Please sign up with your email, and you can add your mobile straight afterwards.',
    'لا يمكن إنشاء حساب برقم الجوال وحده؛ فالبريد الإلكتروني هو ما يعرّف حسابكم. يُرجى التسجيل ببريدكم الإلكتروني، ثم إضافة رقم جوالكم بعد ذلك مباشرة.'),
  no_account_for_number: s("This mobile number isn't linked to a QuotesDone account yet. Please sign in with the email you registered with, or create your account first.",
    'هذا الرقم غير مرتبط بأي حساب لدى QuotesDone. يُرجى تسجيل الدخول بالبريد الإلكتروني المسجّل، أو إنشاء حسابكم أولًا.'),
  ambiguous_phone: s('More than one account carries this mobile number, so it cannot identify you. Please sign in with your email.',
    'هذا الرقم مسجّل على أكثر من حساب، فلا يمكن أن يحدّد هويتكم. يُرجى تسجيل الدخول ببريدكم الإلكتروني.'),

  // Date of birth (_shared/account_rule.ts returns these three codes verbatim).
  dob_required: s('Please enter your date of birth.', 'يُرجى إدخال تاريخ ميلادكم.'),
  dob_invalid: s('Please enter a valid date of birth.', 'يُرجى إدخال تاريخ ميلاد صحيح.'),
  under_18: s('You must be 18 or over to use QuotesDone.', 'يجب أن يكون عمركم 18 عامًا فأكثر لاستخدام QuotesDone.'),

  // The WhatsApp question inside sign-up (kyc whatsapp_*, _shared/whatsapp_choice.ts).
  bad_opt: s('Please choose one of the options.', 'يُرجى اختيار أحد الخيارات المتاحة.'),
  mobile_not_verified: s('Verify your mobile number first.', 'يُرجى توثيق رقم جوالكم أولًا.'),
  whatsapp_unavailable: s('WhatsApp verification is not available right now. Please try again later.', 'التحقق عبر WhatsApp غير متاح حاليًا. يُرجى المحاولة لاحقًا.'),
  whatsapp_unanswered: s('Tell us whether your mobile is also your WhatsApp number first.', 'يُرجى إخبارنا أولًا ما إذا كان رقم جوالكم هو نفسه رقم WhatsApp.'),

  // Documents, registration checks and PDFs (supplier_api).
  document_not_found: s('We could not find that document in our records. Please upload it again.', 'لم نعثر على هذا المستند في سجلاتنا. يُرجى رفعه مرة أخرى.'),
  receipt_not_found: s('That receipt was not found.', 'لم يُعثر على هذا الإيصال.'),
  no_terms_version: s('The current agreement version is not set. Please contact us.', 'إصدار الاتفاقية الحالي غير محدّد. يُرجى التواصل معنا.'),
  check_failed: s('We could not check your registration. Please try again.', 'تعذّر التحقق من تسجيلكم. يُرجى المحاولة مرة أخرى.'),
  verification_failed: s('Your profile was saved, but we could not check your registration. Please try again.', 'حُفظ ملفكم، لكن تعذّر التحقق من تسجيلكم. يُرجى المحاولة مرة أخرى.'),
  pdf_failed: s('We could not produce that PDF. Please try again.', 'تعذّر إنشاء ملف PDF. يُرجى المحاولة مرة أخرى.'),
  invalid_transaction: s('That transaction reference is not valid.', 'رقم العملية غير صحيح.'),
  temporarily_unavailable: s('This is temporarily unavailable. Please try again shortly.', 'هذه الخدمة غير متاحة مؤقتًا. يُرجى المحاولة بعد قليل.'),

  // Messages (messages_api).
  account_suspended: s('Your account is suspended.', 'حسابكم موقوف.'),
  suspended_offplatform: s('Your account is suspended for sharing contact details off-platform.', 'حسابكم موقوف بسبب مشاركة بيانات التواصل خارج المنصة.'),
  chat_banned: s('This chat is closed due to a policy violation.', 'أُغلقت هذه المحادثة بسبب مخالفة للسياسات.'),
  chat_not_open: s('Chat is not open. Request a chat first.', 'المحادثة غير مفتوحة. يُرجى طلب فتح محادثة أولًا.'),
  account_sanctioned: s('This conversation is closed.', 'هذه المحادثة مغلقة.'),
  empty_message: s('Write a message before sending.', 'يُرجى كتابة رسالة قبل الإرسال.'),
  message_send_failed: s('We could not send that message. Please try again.', 'تعذّر إرسال رسالتكم. يُرجى المحاولة مرة أخرى.'),

  // Payment (supplier_pay).
  payment_failed: s('We could not start the payment. Please try again shortly.', 'تعذّر بدء عملية الدفع. يُرجى المحاولة بعد قليل.'),
  no_payable_dues: s('There is nothing payable in what you selected.', 'لا توجد مستحقات قابلة للسداد ضمن اختياركم.'),
};

export function srvText(lang: string, code: string | undefined | null, params?: P, fallback?: string): string {
  const e = code ? COPY[code] : undefined;
  if (!e) return fallback || '';
  try { return e[(lang === 'ar' ? 'ar' : 'en') as L](params || {}); } catch { return fallback || ''; }
}

// Any supplier_api / supplier_portal / kyc response: a known code renders in the supplier's language.
// Without one, English readers get the server's own sentence; Arabic readers get our Arabic fallback,
// because an English sentence inside the Arabic portal is the defect this file exists to remove.
export function srvMsg(lang: string, j: any, fallback: string): string {
  if (!j) return fallback;
  if (j.code && COPY[j.code]) return srvText(lang, j.code, j.params, fallback);
  if (lang === 'ar') return fallback;
  return j.message || (typeof j.error === 'string' && j.error.includes(' ') ? j.error : '') || fallback;
}

// Eligibility / alert rows carry `code` (+ params); titles and details are keyed `<code>_title|_detail`.
// `empty_<col>` shares one detail; `expiring_<col>` shares one title/detail pair.
export function itemCopy(lang: string, it: any): { title: string; detail: string } {
  const c = String(it?.code || it?.kind || '');
  const base = c.startsWith('expiring_') ? 'expiring' : c.startsWith('doc_expiry') ? 'doc_expiry' : c;
  const p = it?.params || {};
  const title = srvText(lang, base + '_title', p, it?.title || '');
  const detail = srvText(lang, c.startsWith('empty_') ? 'empty_detail' : base + '_detail', p, it?.detail || '');
  return { title, detail };
}
