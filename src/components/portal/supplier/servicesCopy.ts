// Every word the Services tab shows, English and Arabic side by side (15 Sep 2026, sales_engineer).
// One table so scripts/checks/supplier_services_checklist_is_bilingual.test.mjs can prove the two
// languages carry the same keys and that no Arabic line is left in English.
//
// 18 Sep 2026 (instruction 438): ADDING a service is no longer a dropdown or a row of checkboxes. The
// "add a trade" picker and the one-at-a-time extras field are gone; in their place is one free text
// box the supplier writes or dictates into, and the sales engineer's rewrite it confirms. The
// PREPARED checklist stays a checklist — that is the sales engineer's proposal, not the supplier
// adding something. Keys removed with the widgets: add_trade, add_trade_ph, extras_title,
// extras_help, extras_ph, extras_label, resolves_to, new_for_review.
export const SERVICES_COPY = {
  en: {
    title: 'Your services',
    // Founder_instruction 862 (23 Sep 2026): the first visit starts unticked, so the prompt asks him to
    // TICK what he does rather than untick what he does not. It also says what an unticked service
    // means under 857, because that is the whole consequence of leaving one blank.
    first_run: 'These services decide which inquiries you receive. Our sales engineer has listed the trades we believe you work in, with their services, and nothing is ticked yet. Tick each service you actually do, add anything missing, then confirm. A service you do not tick is one you have not confirmed, and inquiries that name it will not reach you.',
    confirmed: 'Your services are confirmed. Inquiries that match them reach you in the Inquiries tab.',
    loading: 'Loading your services…',
    load_failed: 'Could not load your services.',
    retry: 'Retry',
    no_prep: 'We have nothing to prepare from yet. Describe your services below, or upload your company profile and our sales engineer will prepare the list for you.',
    go_documents: 'Upload documents',
    from_docs: 'From your documents',
    on_file: 'On file',
    refine_badge: 'More specific trade: tick only what you do',
    confirmed_badge: 'Confirmed',
    found_in: 'Found in your documents',
    select_all: 'Select all',
    clear_all: 'Clear',
    remove_trade: 'Remove this trade',
    trade_removed: 'Removed. It is dropped from your services when you press Update.',
    undo: 'Undo',
    under_review: 'Under review by our sales engineer',
    no_services_listed: 'We do not list services for this trade yet. Describe yours below.',
    add: 'Add',
    remove: 'Remove',
    // ── the free text box, and the sales engineer's rewrite ──
    describe_title: 'Add the services you provide',
    describe_help: 'Write or dictate everything your company does, in your own words, in English or Arabic. Our sales engineer rewrites it into our standard service names, and those are what we cross-match inquiries against.',
    describe_label: 'Your services, in your own words',
    describe_ph: 'e.g. We do interior decoration and fit-out for villas and offices, gypsum partitions, and chiller maintenance.',
    rewrite: 'Rewrite my services',
    rewriting: 'Our sales engineer is reading it…',
    rewrite_failed: 'Could not read that text. Please try again.',
    rewrite_title: 'Sales engineer’s version',
    rewrite_help: 'This is what we will match inquiries against. Remove anything you do not provide, or edit your description and rewrite it again.',
    rewrite_none: 'We could not find a service in that text. Please describe the work your company does.',
    stated_title: 'Services we recognised',
    implied_title: 'Services this also covers',
    implied_help: 'Companies that do the work above normally do these as well, so we include them. Remove any you do not provide.',
    implied_because: 'Included because',
    own_words_title: 'Kept in your own words',
    own_words_help: 'We do not list these yet, so we keep them exactly as you wrote them and our sales engineer reviews them. We never drop them ourselves — remove one only if you did not mean it.',
    // ADD vs ADD BACK (23 Sep 2026, re-review of SP-F-06). `restore` is for a stated service the
    // supplier removed — that one really is coming back. The meaning layer's proposals start OFF and
    // were never on the list, so they use the existing `add` key above instead.
    restore: 'Add back',
    removed_badge: 'Removed',
    edit_text: 'Edit my description',
    // ── a catalogue read as a catalogue; supply only; the meaning layer (21 Sep 2026) ──
    read_catalogue: 'Read my uploaded catalogue',
    no_catalogue: 'We have no readable catalogue from you yet. Upload one in Documents, or describe your services here.',
    supply_only_note: 'We read your company as supply only — an importer, wholesaler or stockist — so we have not proposed installation work, and nothing is added on top of what you listed.',
    supply_install_note: 'We read your company as one that also installs, so installation work is proposed where your words name it.',
    we_also_install: 'We also install',
    we_only_supply: 'We only supply',
    meaning_title: 'Services we understood from your wording',
    meaning_help: 'These are not word-for-word matches: we read what the line means, and each is shown with the line that supports it. None of them is on your list yet — add the ones you do.',
    meaning_because: 'From:',
    mic_start: 'Speak your services',
    mic_stop: 'Stop recording',
    mic_busy: 'Turning your voice into text…',
    mic_soon: 'Voice input is coming soon. Please type your services for now.',
    mic_unsupported: 'This device cannot record audio here. Please type your services.',
    mic_denied: 'Microphone access was refused. Please type your services.',
    mic_failed: 'We could not turn that recording into text. Please type it instead.',
    mic_limited: 'You have used voice input many times this hour. Please type, or try again later.',
    roles_title: 'Your role',
    need_trade_role: 'Choose at least one role, and tick or describe at least one service.',
    count: (s: number, r: number) => `${s} service${s === 1 ? '' : 's'} · ${r} role${r === 1 ? '' : 's'} selected`,
    confirm: 'Confirm my services',
    update: 'Update my services',
    saving: 'Saving…',
    saved: 'Saved. Your services are confirmed.',
    // What the confirm's verification answered (j.gate, supplier_capability.ts rerunGateAfterConfirm). 10 Nov 2026: a confirm
    // that waited on the gate showed nothing, and the supplier stayed Pending with no word on screen.
    gate_approved: 'Your registration is approved. Matching inquiries now reach you in the Inquiries tab.',
    gate_finishing: 'We are finishing your verification. Your status updates within a minute; you do not need to do anything.',
    save_failed: 'Could not save your services.',
    review_sent: 'Services we could not match to a trade were sent to our sales engineer. The outcome will show here.',
    proposals_title: 'Trades under review',
    p_pending: 'under review by our sales engineer',
    p_added: 'added to our trade list',
    p_rejected: 'not added to our list',
    p_mapped: 'replaced by a listed trade, with your agreement',
    p_offer: 'we suggest the listed trade:',
    p_use: 'Use this trade',
  },
  ar: {
    title: 'خدماتكم',
    first_run: 'تحدّد هذه الخدمات الاستفسارات التي تصلكم. أدرج مهندس المبيعات التخصصات التي نرى أنكم تعملون فيها مع خدماتها، ولم نحدّد أيًّا منها بعد. يُرجى تحديد كل خدمة تقدّمونها فعلًا، وإضافة ما ينقص، ثم التأكيد. فالخدمة التي لا تحدّدونها تُعدّ غير مؤكَّدة، ولن تصلكم الاستفسارات التي تطلبها.',
    confirmed: 'أُكّدت خدماتكم، وتصلكم الاستفسارات المطابقة لها في تبويب الاستفسارات.',
    loading: 'جارٍ تحميل خدماتكم…',
    load_failed: 'تعذّر تحميل خدماتكم.',
    retry: 'إعادة المحاولة',
    no_prep: 'لا تتوفر لدينا بعد معلومات نُعدّ منها القائمة. يُرجى وصف خدماتكم أدناه، أو رفع ملف تعريف شركتكم ليُعدّ مهندس المبيعات القائمة نيابةً عنكم.',
    go_documents: 'رفع المستندات',
    from_docs: 'من مستنداتكم',
    on_file: 'مسجَّل لدينا',
    refine_badge: 'تخصص أدق: حدّدوا ما تقدّمونه منه فقط',
    confirmed_badge: 'مؤكَّد',
    found_in: 'وجدناه في مستنداتكم',
    select_all: 'تحديد الكل',
    clear_all: 'إلغاء التحديد',
    remove_trade: 'إزالة هذا التخصص',
    trade_removed: 'أُزيلت، وستُحذف من خدماتكم عند الضغط على «تحديث».',
    undo: 'تراجع',
    under_review: 'قيد المراجعة لدى مهندس المبيعات',
    no_services_listed: 'لم نُدرج بعد خدمات لهذا التخصص. يُرجى وصف خدماتكم أدناه.',
    add: 'إضافة',
    remove: 'إزالة',
    describe_title: 'أضيفوا الخدمات التي تقدّمونها',
    describe_help: 'اكتبوا أو سجّلوا صوتيًا كل ما تقدّمه شركتكم بأسلوبكم، بالعربية أو الإنجليزية. يعيد مهندس المبيعات صياغته وفق أسماء الخدمات المعتمدة لدينا، وهي المرجع في مطابقة الاستفسارات.',
    describe_label: 'خدماتكم بأسلوبكم',
    describe_ph: 'مثال: ننفّذ الديكور الداخلي والتجهيز للفلل والمكاتب، وقواطع الجبس، وصيانة التشيلر.',
    rewrite: 'إعادة صياغة خدماتي',
    rewriting: 'يقرأ مهندس المبيعات ما كتبتموه…',
    rewrite_failed: 'تعذّرت قراءة هذا النص. يُرجى المحاولة مرة أخرى.',
    rewrite_title: 'صياغة مهندس المبيعات',
    rewrite_help: 'هذه هي القائمة التي نطابق بها الاستفسارات. يُرجى إزالة ما لا تقدّمونه، أو تعديل وصفكم وإعادة الصياغة.',
    rewrite_none: 'لم نجد أي خدمة في هذا النص. يُرجى وصف الأعمال التي تنفّذها شركتكم.',
    stated_title: 'خدمات تعرّفنا عليها',
    implied_title: 'خدمات يشملها هذا العمل أيضًا',
    implied_help: 'الشركات التي تنفّذ الأعمال أعلاه تقدّم هذه الخدمات عادةً، لذا أدرجناها. يُرجى إزالة ما لا تقدّمونه منها.',
    implied_because: 'أُدرجت لأن',
    own_words_title: 'محفوظة بكلماتكم',
    own_words_help: 'هذه الخدمات غير مدرجة لدينا بعد، لذا نحفظها كما كتبتموها تمامًا ويراجعها مهندس المبيعات. لن نحذف أيًّا منها من جانبنا — أزيلوا فقط ما لم تقصدوه.',
    restore: 'إعادة الإضافة',
    removed_badge: 'مُزالة',
    edit_text: 'تعديل وصفي',
    read_catalogue: 'قراءة الكتالوج المرفوع',
    no_catalogue: 'لا يتوفر لدينا بعد كتالوج مقروء منكم. يُرجى رفعه في تبويب المستندات، أو وصف خدماتكم هنا.',
    supply_only_note: 'صنّفنا شركتكم على أنها للتوريد فقط — مستورد أو تاجر جملة أو موزّع من المخزون — لذا لم نقترح أعمال تركيب، ولم نُضف شيئًا إلى ما ذكرتموه.',
    supply_install_note: 'صنّفنا شركتكم على أنها تنفّذ أعمال التركيب أيضًا، لذا نقترح أعمال التركيب حيثما وردت في وصفكم.',
    we_also_install: 'نتولّى التركيب أيضًا',
    we_only_supply: 'نكتفي بالتوريد',
    meaning_title: 'خدمات استخلصناها من وصفكم',
    meaning_help: 'هذه ليست مطابقة حرفية للكلمات؛ فقد قرأنا معنى كل سطر، وتظهر كل خدمة مع السطر الذي تستند إليه. ولم تُضَف أيٌّ منها إلى قائمتكم بعد — أضيفوا ما تنفّذونه منها.',
    meaning_because: 'من:',
    mic_start: 'تسجيل الخدمات صوتيًا',
    mic_stop: 'إيقاف التسجيل',
    mic_busy: 'جارٍ تحويل التسجيل الصوتي إلى نص…',
    mic_soon: 'الإدخال الصوتي متاح قريبًا. يُرجى كتابة خدماتكم في الوقت الحالي.',
    mic_unsupported: 'لا يدعم هذا الجهاز تسجيل الصوت هنا. يُرجى كتابة خدماتكم.',
    mic_denied: 'رُفض الإذن باستخدام الميكروفون. يُرجى كتابة خدماتكم.',
    mic_failed: 'تعذّر تحويل هذا التسجيل إلى نص. يُرجى كتابته بدلًا من ذلك.',
    mic_limited: 'استخدمتم الإدخال الصوتي مرات عديدة خلال هذه الساعة. يُرجى الكتابة، أو المحاولة لاحقًا.',
    roles_title: 'دوركم',
    need_trade_role: 'يُرجى اختيار دور واحد على الأقل، وتحديد خدمة واحدة على الأقل أو وصفها.',
    // Arabic number agreement: 1 and 2 have their own forms, 3-10 take the plural, 11+ the singular.
    count: (s: number, r: number) => {
      const svc = s === 0 ? 'لا توجد خدمات' : s === 1 ? 'خدمة واحدة' : s === 2 ? 'خدمتان' : s <= 10 ? `${s} خدمات` : `${s} خدمةً`;
      const role = r === 0 ? 'لا توجد أدوار' : r === 1 ? 'دور واحد' : r === 2 ? 'دوران' : r <= 10 ? `${r} أدوار` : `${r} دورًا`;
      return `${svc} · ${role}`;
    },
    confirm: 'تأكيد خدماتي',
    update: 'تحديث خدماتي',
    saving: 'جارٍ الحفظ…',
    saved: 'تم الحفظ، وخدماتكم مؤكَّدة.',
    gate_approved: 'اعتُمد تسجيلكم، وتصلكم الاستفسارات المطابقة الآن في تبويب الاستفسارات.',
    gate_finishing: 'نُكمل الآن التحقق من تسجيلكم، وتتحدّث حالتكم خلال دقيقة دون أن يلزمكم أي إجراء.',
    save_failed: 'تعذّر حفظ خدماتكم.',
    review_sent: 'أحلنا الخدمات التي لم نطابقها مع أي تخصص إلى مهندس المبيعات، وستظهر النتيجة هنا.',
    proposals_title: 'تخصصات قيد المراجعة',
    p_pending: 'قيد المراجعة لدى مهندس المبيعات',
    p_added: 'أُضيف إلى قائمة التخصصات',
    p_rejected: 'لم يُضف إلى القائمة',
    p_mapped: 'استُبدل بتخصص من القائمة بموافقتكم',
    p_offer: 'نقترح التخصص المدرج:',
    p_use: 'اعتماد هذا التخصص',
  },
} as const;

export type ServicesLang = keyof typeof SERVICES_COPY;
export type ServicesKey = Exclude<keyof typeof SERVICES_COPY.en, 'count'>;
export const sc = (lang: string, k: ServicesKey): string => SERVICES_COPY[lang === 'ar' ? 'ar' : 'en'][k];
export const scCount = (lang: string, s: number, r: number): string => SERVICES_COPY[lang === 'ar' ? 'ar' : 'en'].count(s, r);
// THE SERVICES COUNT, ONE RULE FOR BEFORE AND AFTER A RELOAD (audit 21 Sep 2026, finding 11: "8
// services" after a rewrite whose services were already ticked, "5" after reload). A service is counted
// once by its key however many lists carry it (the ticked checklist, the rewrite, the implications),
// and an own-words phrase once however it is capitalised. scripts/checks/services_tab_count_and_removal.test.mjs.
export function countServices(keys: readonly string[], ownWords: readonly string[]): number {
  const words = new Set(ownWords.map((w) => w.replace(/\s+/g, ' ').trim().toLowerCase()).filter((w) => w.length >= 2));
  return new Set(keys).size + words.size;
}

// English only, on purpose (ledger 1469; suppliers are always written to in English, ruling 1008): what the Services tab says about
// verification and about what was read from the company profile.
export const VERIFY_COPY = {
  verify_needed: 'To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct anything wrong, then press Confirm my services. Until you do, your registration stays Pending, even when your mobile, e-mail, trade licence, company profile and terms are complete.',
  profile_summary_title: 'Summary of your company profile',
  profile_keywords: 'Keywords of your services',
  profile_none: 'We read your company profile and found no service we could match. Tick what you do below, or describe it in your own words.',
  profile_reading: 'We are still reading your company profile. This page updates by itself when the read finishes.',
  profile_scan: 'Your company profile is a scan or photo that we could not read as text yet. Tick what you do below, or describe it in your own words.',
  profile_failed: 'We could not read your company profile. Upload a clear PDF or Word file in Documents, or tick what you do below, or describe it in your own words.',
  profile_damaged: 'Your company profile file is damaged, so we could not open it. Upload it again in Documents, or tick what you do below, or describe it in your own words.',
  profile_missing: 'No company profile has been read yet. Upload it in Documents, or describe your services below.',
  doc_read_none: 'read, no service matched',
} as const;

// THE SERVICES READ OFF THE SUPPLIER'S OWN DOCUMENTS, AND HIS LICENCE (10 Nov 2026, sales_engineer; founder ledger 1573). English only to a
// supplier (ruling 1008), like VERIFY_COPY. Offered, not ticked (founder 862): the button ticks them for him to review before he confirms.
export const PROPOSED_COPY = {
  title: 'Services we found in your company profile',
  help: 'Our sales engineer read these from your own documents. Tick each one you do, then press Confirm my services. Your words become the names customers find you by.',
  tick_all: 'Tick all proposed services',
  untick_all: 'Untick all proposed services',
  from_line: 'From your profile:',
  not_on_licence: 'Not on your trade licence',
  not_on_licence_help: 'Your trade licence does not list this activity. You can still confirm it; our sales engineer will check it with your licence. If your licence covers it under another name, upload the licence page that shows it in Documents.',
  licence_lists: 'Your trade licence lists:',
  licence_unread: 'We could not read the activities on your trade licence yet, so these services are not checked against it.',
} as const;

// WHAT THE SERVICES TAB MAY SAY ABOUT THE COMPANY PROFILE (ledger 1469, browser walk scripts/e2e/supplier_profile_read_walk.mjs, 2 Nov 2026).
// A profile saved as a picture is read by the vision model and its trades are HELD for the sales engineer (status 'read', trades [],
// source 'photo_text'); the tab said "We read your company profile and found no service we could match" about a file that states services.
// A refused or unreadable file got the same words, or "a scan or photo". "found no service" is said only of a file that was read as
// text and named nothing; every file that was not read as text says so.
export type ProfileDocLike = { status?: string; source?: string; choice?: string; trades?: readonly unknown[]; vision_held?: readonly unknown[] };
// Since ledger 1442 a picture or a scanned PDF is read by the model the licence uses and its trades are proposed like a text profile's; 'scan'
// is what is left when that read found nothing on the page (a blank page, or a photo too poor to read), 'damaged' a file that does not open.
export type ProfileState = 'hits' | 'reading' | 'scan' | 'damaged' | 'failed' | 'none' | 'missing';
export function profileStateOf(docs: readonly ProfileDocLike[]): ProfileState {
  if (docs.some((d) => (d.trades || []).length)) return 'hits';
  if (docs.some((d) => d.status === 'reading')) return 'reading';
  if (docs.some((d) => d.status === 'needs_ocr' || (d.vision_held || []).length)) return 'scan';   // vision_held: records written before ledger 1442
  if (docs.some((d) => d.status === 'unreadable')) return 'damaged';
  if (docs.some((d) => d.status === 'refused' || d.status === 'needs_cad_conversion' || d.choice === 'unavailable')) return 'failed';
  return docs.length ? 'none' : 'missing';
}