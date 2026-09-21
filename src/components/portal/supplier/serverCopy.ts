// SERVER-AUTHORED SUPPLIER COPY, RENDERED IN THE SUPPLIER'S LANGUAGE.
//
// supplier_api and supplier_portal used to author supplier-facing sentences in English and the portal
// printed them raw, so a supplier who switched to عربي still read why they were not being matched,
// what each document is for, their alerts and every gate error in English (website audit 2026-09-14,
// supplier portal, "Arabic is incomplete"). The servers now return a stable `code` (+ `params`) beside
// the English text; this file owns the EN/AR wording for every code. The English text on the response
// stays as the fallback, so an older client, an email, or a code this table does not know yet still
// reads correctly — `srvText` never returns an empty string when the server sent a sentence.

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
  doc_hint_license: s('Required. Your current DED / free-zone trade licence.', 'مطلوب. رخصتك التجارية السارية الصادرة من دائرة التنمية الاقتصادية أو المنطقة الحرة.'),
  doc_hint_profile: s('Required. Your company introduction deck or PDF. Shown to customers after a reveal.', 'مطلوب. العرض التعريفي لشركتك أو ملف PDF، ويظهر للعملاء بعد الكشف.'),
  doc_hint_catalogs: s('Product or project catalogues. Upload as many as you like — new files are added, never replaced.', 'كتالوجات المنتجات أو المشاريع. ارفع ما تشاء — تُضاف الملفات الجديدة ولا تحلّ محل القديمة.'),
  doc_hint_vat: s('Your TRN certificate. Needed before you can invoice with VAT.', 'شهادة الرقم الضريبي (TRN)، ويلزم قبل إصدار فواتير تتضمن ضريبة القيمة المضافة.'),
  doc_hint_insurance: s('Public liability or contractor all-risk cover.', 'تأمين المسؤولية العامة أو تأمين جميع أخطار المقاول.'),
  doc_hint_iso: s('Any ISO certificate you hold. Strengthens your capability score.', 'أي شهادة ISO تحملها، وتقوّي تقييم قدراتك.'),
  doc_hint_manufacturer: s('Authorised-dealer letters from the brands you carry.', 'خطابات الوكالة المعتمدة من العلامات التجارية التي تتعامل بها.'),
  doc_hint_egr: s('Your establishment card (EGR), issued with your trade licence.', 'بطاقة المنشأة (EGR) الصادرة مع رخصتك التجارية.'),

  // ── Overview alerts (supplier_portal buildAlerts) ───────────────────────────────────────────────
  doc_expiry_title: s((p) => `${p.doc} ${p.expired ? 'has expired' : 'expires soon'}`, (p) => `${docAr(p.doc)} ${p.expired ? 'منتهية الصلاحية' : 'تنتهي قريبًا'}`),
  doc_expiry_detail: s(
    (p) => `Expiry ${p.expiry} — ${p.days_left < 0 ? `overdue by ${Math.abs(p.days_left)} days` : `${p.days_left} days left`}. Upload a renewed copy to stay eligible.`,
    (p) => `تاريخ الانتهاء ${p.expiry} — ${p.days_left < 0 ? `متأخرة ${Math.abs(p.days_left)} يومًا` : `متبقٍ ${p.days_left} يومًا`}. ارفع نسخة مجدّدة لتبقى مؤهّلًا.`),
  // `total` (audit 21 Sep 2026, finding 6): the bell said "1 new RFQ" beside "Inquiries received (3)";
  // both were true (two were already quoted) but neither said so. The count now names what it is out of.
  new_rfq_title: s((p) => `${p.count} new RFQ${p.count > 1 ? 's' : ''} waiting for your quote` + (p.total > p.count ? ` (of ${p.total} received)` : ''), (p) => `${p.count} ${plural(p.count, 'طلب تسعير جديد ينتظر', 'طلبات تسعير جديدة تنتظر')} عرضك` + (p.total > p.count ? ` (من أصل ${p.total})` : '')),
  // The notices the estate wrote to this supplier (supplier_portal buildNotifications `notices`).
  notice_quote_accepted: s('A customer revealed your quote — their contact details are in Messages', 'كشف عميل عن عرضك — بيانات التواصل في الرسائل'),
  notice_new_message: s('New message from a customer', 'رسالة جديدة من عميل'),
  notice_new_inquiry: s('A new request was matched to you', 'تمت مطابقة طلب جديد معك'),
  notice_rfq_addendum: s('A customer updated a request you received', 'حدّث عميل طلبًا وصلك'),
  notice_job_awarded_other: s('A request you quoted was awarded to another supplier', 'تمت ترسية طلب قدّمت عليه عرضًا على مورّد آخر'),
  notice_rfq_no_supplier: s('A request closed without a supplier', 'أُغلق طلب دون مورّد'),
  notice_doc_received: s('We received your document', 'استلمنا مستندك'),
  notice_registration_received: s('We received your registration', 'استلمنا تسجيلك'),
  notice_quote_spec_hold: s('A quotation is held until its exact details are given', 'عرض سعر محجوز حتى تُذكر تفاصيله الدقيقة'),
  notice_quote_spec_released: s('A held quotation was released to the customer', 'أُرسل عرض سعر كان محجوزًا إلى العميل'),
  notice_quote_spec_regenerated: s('A held quotation was regenerated with your details', 'أُعيد إنشاء عرض سعر محجوز بتفاصيلك'),
  notice_quote: s('An update on one of your quotations', 'تحديث على أحد عروضك'),
  new_rfq_detail: s('Open requests matched to your capabilities that you have not quoted yet.', 'طلبات مفتوحة تطابق قدراتك ولم تقدّم عليها عرضًا بعد.'),
  draft_quote_title: s((p) => `${p.count} draft quote${p.count > 1 ? 's' : ''} to complete`, (p) => `${p.count} ${plural(p.count, 'عرض مسودة يحتاج', 'عروض مسودة تحتاج')} إلى إكمال`),
  draft_quote_detail: s('Add the missing details so we can send them to customers.', 'أضف التفاصيل الناقصة لنرسلها إلى العملاء.'),

  // ── Eligibility (supplier_portal eligibility) ───────────────────────────────────────────────────
  elig_note: s('Each request goes to a shortlist of up to 8 suppliers, ranked by how well your listing matches what the customer asked for. Suppliers anywhere in the UAE are eligible; being in the customer’s emirate only breaks a tie.',
    'يُرسل كل طلب إلى قائمة مختصرة تضم حتى 8 مورّدين، تُرتَّب حسب مدى تطابق ملفك مع ما طلبه العميل. والمورّدون في أي مكان في الإمارات مؤهّلون، ولا يُرجِّح وجودك في إمارة العميل إلا عند التساوي.'),
  permanently_closed_title: s('Your listing is marked permanently closed', 'ملفك مسجّل على أنه مغلق نهائيًا'),
  permanently_closed_detail: s('We will not send you requests while this is set. Contact us if this is wrong.', 'لن نرسل إليك طلبات ما دام هذا الإعداد قائمًا. تواصل معنا إن كان ذلك خطأ.'),
  banned_title: s('Your account is suspended', 'حسابك موقوف'),
  banned_detail: s('Suspended accounts are excluded from all matching. Contact us to resolve it.', 'الحسابات الموقوفة مستبعدة من كل المطابقات. تواصل معنا لحل ذلك.'),
  licence_expired_title: s('Your account is paused — trade licence expired', 'حسابك متوقف مؤقتًا — انتهت الرخصة التجارية'),
  licence_expired_detail: s((p) => `Your trade licence expired on ${p.date || 'an earlier date'}. Upload a valid copy and your account is restored automatically, usually within a day. There is no fee.`,
    (p) => `انتهت رخصتك التجارية في ${p.date || 'تاريخ سابق'}. ارفع نسخة سارية ويُستعاد حسابك تلقائيًا، عادةً خلال يوم. لا توجد رسوم.`),
  insurance_expired_title: s('Your account is paused — insurance expired', 'حسابك متوقف مؤقتًا — انتهى التأمين'),
  insurance_expired_detail: s((p) => `Your insurance certificate expired on ${p.date || 'an earlier date'}. Upload a valid copy and your account is restored automatically. There is no fee.`,
    (p) => `انتهت شهادة التأمين في ${p.date || 'تاريخ سابق'}. ارفع نسخة سارية ويُستعاد حسابك تلقائيًا. لا توجد رسوم.`),
  matching_blocked_title: s('Matching is switched off for your account', 'المطابقة متوقفة لحسابك'),
  matching_blocked_detail: s('This was set by our team rather than automatically. Contact us to have it reviewed.', 'أوقفها فريقنا وليس النظام تلقائيًا. تواصل معنا لمراجعتها.'),
  not_registered_title: s('Your registration is not submitted', 'لم يُرسَل تسجيلك بعد'),
  not_registered_detail: s('Only registered suppliers receive requests. Complete the six registration steps to submit it.', 'لا تصل الطلبات إلا للمورّدين المسجّلين. أكمل خطوات التسجيل الست لإرساله.'),
  scope_unconfirmed_title: s('Confirm what your company can quote for', 'أكّد ما يمكن لشركتك تسعيره'),
  scope_unconfirmed_detail: s('We never guess a supplier’s scope on their behalf, so no request is sent to you until you have confirmed it yourself. It takes about a minute, once.',
    'لا نخمّن نطاق عمل أي مورّد نيابةً عنه، لذا لن يصلك أي طلب قبل أن تؤكّده بنفسك. يستغرق ذلك دقيقة واحدة، مرة واحدة.'),
  undiscoverable_title: s('Nothing describes what you supply', 'لا شيء يصف ما تورّده'),
  undiscoverable_detail: s('Requests are matched on your sector, products, services and categories. All of these are empty, so no request can reach you.', 'تُطابَق الطلبات على قطاعك ومنتجاتك وخدماتك وفئاتك، وكلها فارغة، لذا لا يمكن أن يصلك أي طلب.'),
  no_sector_title: s('Set your sector', 'حدّد قطاعك'),
  no_sector_detail: s('A matching sector adds 2 points to your score on every request in that category, which decides who makes the shortlist.', 'القطاع المطابق يضيف نقطتين إلى تقييمك في كل طلب ضمن تلك الفئة، وهو ما يحدّد من يدخل القائمة المختصرة.'),
  empty_products_title: s('Add your products', 'أضف منتجاتك'),
  empty_services_title: s('Add your services', 'أضف خدماتك'),
  empty_categories_title: s('Add your categories', 'أضف فئاتك'),
  empty_capability_summary_title: s('Add your capability summary', 'أضف ملخص قدراتك'),
  empty_detail: s('Each keyword found here raises your match score. Empty fields cannot match anything.', 'كل كلمة مفتاحية هنا ترفع تقييم مطابقتك، والحقول الفارغة لا تطابق أي شيء.'),
  no_emirate_title: s('Set your home emirate', 'حدّد إمارة مقرّك'),
  no_emirate_detail: s('You receive requests from the whole UAE either way. Your emirate is used only to break a tie between equally good matches.', 'تصلك الطلبات من الإمارات كلها في جميع الأحوال، ولا تُستخدم إمارتك إلا لترجيح مطابقة على أخرى مساوية لها.'),
  no_licence_title: s('Upload your trade licence', 'ارفع رخصتك التجارية'),
  no_licence_detail: s('Required before your account can be approved.', 'مطلوبة قبل اعتماد حسابك.'),
  confirm_scope_title: s('Confirm what your company does', 'أكّد ما تقوم به شركتك'),
  confirm_scope_detail: s(
    (p) => `Your documents mention trades you have not confirmed: ${(p.trades || []).map((c: string) => vocabLabel('en', 'trade', c, String(c).replace(/_/g, ' '))).join(', ')}. Tick them in "What you can quote for" if your company does this work.`,
    (p) => `تذكر مستنداتك تخصصات لم تؤكّدها بعد: ${(p.trades || []).map((c: string) => vocabLabel('ar', 'trade', c, String(c).replace(/_/g, ' '))).join('، ')}. اخترها في «ما الذي يمكن لشركتك تسعيره» إن كانت شركتك تقوم بهذا العمل.`),
  expiring_title: s((p) => `Your ${p.doc === 'insurance' ? 'insurance certificate' : 'trade licence'} expires in ${p.days} day${p.days === 1 ? '' : 's'}`,
    (p) => `${p.doc === 'insurance' ? 'شهادة التأمين' : 'رخصتك التجارية'} تنتهي خلال ${p.days} ${plural(p.days, 'يوم', 'أيام')}`),
  expiring_detail: s('Once it expires your account is paused automatically and you stop receiving requests. Upload a renewed copy now to avoid that.', 'عند انتهائها يتوقف حسابك تلقائيًا وتتوقف الطلبات. ارفع نسخة مجدّدة الآن لتجنّب ذلك.'),
  no_phone_title: s('Add a contact number', 'أضف رقم تواصل'),
  no_phone_detail: s('Customers cannot reach you after a reveal without one.', 'لا يستطيع العملاء التواصل معك بعد الكشف من دونه.'),

  // ── The mandatory six (shared/supplier_registration.ts) ─────────────────────────────────────────
  reg_name: s('Company name', 'اسم الشركة'),
  reg_mobile: s('Verified mobile number', 'رقم جوال تم التحقق منه'),
  reg_email: s('Verified e-mail', 'بريد إلكتروني تم التحقق منه'),
  reg_licence: s('Trade licence', 'الرخصة التجارية'),
  reg_profile: s('Company profile', 'الملف التعريفي للشركة'),
  reg_terms: s('Signed supplier terms', 'الموافقة على شروط المورّد'),
  // Not one of the six: the WhatsApp answer asked in sign-up after the mobile is verified (15 Sep 2026).
  reg_whatsapp: s('Your answer on your WhatsApp number', 'إجابتك عن رقم WhatsApp'),

  // ── Licence gate reasons (leads.licence_gate_reason) ────────────────────────────────────────────
  no_licence: s('no trade licence on file', 'لا توجد رخصة تجارية محفوظة'),
  licence_expired: s('the trade licence on file has expired', 'الرخصة التجارية المحفوظة منتهية'),

  // ── supplier_api gate and error codes ───────────────────────────────────────────────────────────
  no_company: s('Register your company first.', 'سجّل شركتك أولًا.'),
  company_exists: s('Your account already manages a company.', 'حسابك يدير شركة بالفعل.'),
  enter_company: s('Enter your company name.', 'أدخل اسم شركتك.'),
  terms_not_accepted: s('Accept the supplier terms first (Profile tab).', 'وافق على شروط المورّد أولًا (من تبويب الملف).'),
  not_verified: s((p) => `Your registration is not verified yet${p.reason ? ': ' + (COPY[p.reason]?.en({}) || p.reason) : ''}. Upload a clear, in-date trade licence in Documents — it is re-checked automatically the moment it is saved.`,
    (p) => `لم يتم التحقق من تسجيلك بعد${p.reason ? ': ' + (COPY[p.reason]?.ar({}) || p.reason) : ''}. ارفع رخصة تجارية واضحة وسارية في تبويب المستندات — يُعاد فحصها تلقائيًا فور حفظها.`),
  registration_due: s((p) => `Your ${p.currency || 'AED'} ${p.fee} yearly registration is due. Pay it in Billing to send quotes.`, (p) => `رسوم التسجيل السنوية (${p.fee} ${p.currency === 'AED' || !p.currency ? 'درهم' : p.currency}) مستحقة. ادفعها من تبويب الفواتير لإرسال العروض.`),
  registration_state_unavailable: s('We could not confirm your registration status. Please try again shortly.', 'تعذّر التحقق من حالة تسجيلك. يُرجى المحاولة بعد قليل.'),
  inquiry_concluded: s('This request has been concluded — the customer has already selected a supplier. Best of luck on the next one.', 'أُغلق هذا الطلب — اختار العميل مورّدًا بالفعل. نتمنى لك التوفيق في الطلب القادم.'),
  invalid_amount: s('Enter a valid amount.', 'أدخل مبلغًا صحيحًا.'),
  draft_saved: s('Your quote was saved as a draft. Add the missing details so we can send it to the customer.', 'حُفظ عرضك كمسودة. أضف التفاصيل الناقصة لنرسله إلى العميل.'),
  quote_no_pages: s('Could not read the file pages. Please attach a clear PDF or photo.', 'تعذّرت قراءة صفحات الملف. يُرجى إرفاق ملف PDF أو صورة واضحة.'),
  quote_read_failed: s('We could not read that quotation automatically — fill in the form below instead; nothing else is needed.', 'تعذّرت قراءة عرض السعر تلقائيًا — املأ النموذج أدناه بدلًا من ذلك، ولا يلزم شيء آخر.'),
  upload_failed: s('We could not store that file. Please try again.', 'تعذّر حفظ الملف. يُرجى المحاولة مرة أخرى.'),
  save_failed: s('We could not save your profile. Please try again.', 'تعذّر حفظ ملفك. يُرجى المحاولة مرة أخرى.'),
  missing_required: s((p) => 'Still needed to register: ' + (p.missing || []).map((c: string) => COPY[c]?.en({}) || c).join(', ') + '.',
    (p) => 'ما زال مطلوبًا للتسجيل: ' + (p.missing || []).map((c: string) => COPY[c]?.ar({}) || c).join('، ') + '.'),
  capability_need_trade_role: s('Choose at least one trade and one role.', 'اختر تخصصًا واحدًا ودورًا واحدًا على الأقل.'),
  capability_bad_range: s('The project value range is not valid.', 'نطاق قيمة المشاريع غير صالح.'),
  capability_write_failed: s('We could not save your scope. Please try again.', 'تعذّر حفظ نطاق عملك. يُرجى المحاولة مرة أخرى.'),
  reg_exempt: s((p) => `Your registration is permanently free — you are supplier number ${p.rank}, inside the founding 1,000. There is no fee, now or in future.`, (p) => `تسجيلك مجاني بشكل دائم — أنت المورّد رقم ${p.rank} ضمن أول 1,000 مورّد. لا رسوم الآن ولا مستقبلًا.`),
  reg_not_due: s('There is nothing to pay. The yearly fee applies only from the 1,001st registration.', 'لا يوجد ما تدفعه. تُطبَّق الرسوم السنوية فقط اعتبارًا من التسجيل رقم 1,001.'),
  reg_paid: s((p) => `Your registration is paid${p.until ? ' until ' + p.until : ''}.`, (p) => `رسوم تسجيلك مدفوعة${p.until ? ' حتى ' + p.until : ''}.`),
  // ── The sales engineer's hold desk (14 Sep 2026) ────────────────────────────────────────────────
  spec_hold: s('Your quote is on hold until the exact details listed are stated. Fill them in here or upload a revised quote.', 'عرضك معلّق حتى تُذكر التفاصيل الدقيقة المذكورة. أكملها هنا أو ارفع عرضًا معدّلًا.'),
  options_split: s((p) => `Your submission carried ${p.count} options; each is now its own quotation.`, (p) => `احتوى عرضك على ${p.count} خيارات؛ أصبح كل خيار عرضًا مستقلًا.`),
  option_total_missing: s((p) => `Enter the total for option ${p.option}.`, (p) => `أدخل الإجمالي للخيار ${p.option}.`),
  too_many_options: s('A quote can carry at most 20 options.', 'يمكن أن يتضمن العرض 20 خيارًا كحدّ أقصى.'),
  invalid_values: s('Some details are not exact yet — see the marked fields.', 'بعض التفاصيل ليست دقيقة بعد — راجع الحقول المحددة.'),
  not_awaiting_approval: s('There is no regenerated quotation waiting for your approval.', 'لا يوجد عرض مُعاد إعداده بانتظار اعتمادك.'),
  confirm_required: s('Tick the box to confirm the regenerated quotation is correct.', 'ضع علامة لتأكيد أن العرض المُعاد إعداده صحيح.'),
  still_missing: s('Some required details are still missing.', 'ما زالت بعض التفاصيل المطلوبة ناقصة.'),
  no_hold: s('This quote is not on hold.', 'هذا العرض غير معلّق.'),
  not_found: s('That quote was not found.', 'لم يُعثر على هذا العرض.'),
  payment_unavailable: s('Online payment is not available right now. Please try again later.', 'الدفع الإلكتروني غير متاح حاليًا. يُرجى المحاولة لاحقًا.'),
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
