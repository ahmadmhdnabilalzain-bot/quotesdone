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
  // review round 2 (12 Nov 2026, hard profile H09): a profile whose work is all in project captions names no trade of his own, yet its services
  // are listed below; "found no service" was said above 35 of them. Said only when the list is truly empty (listedProfileState).
  profile_listed: 'We read your company profile. The services we found in it are listed below: tick each one you do, or describe anything else in your own words.',
  // Review round 2 (12 Nov 2026): a whole reading takes 22-161 s (p50 101 s, run c0afdde7); he is told so, and that he can go on.
  profile_reading: 'Reading your profile. This takes one to two minutes; you can carry on and come back. This page updates by itself.',
  // The model could not be asked yet (11 Nov 2026, ruling 1627): nothing is guessed from words meanwhile, and the sweep asks it again.
  profile_pending: 'We are still reading your documents to understand the services you do. Until we finish, the trade you chose at sign-up is listed below and you can confirm it. The services we understand from your documents will appear here when the reading is done.',
  // The readings could not agree on anything his documents say ('held'). Nothing re-reads such a document, so "still reading" was said
  // for ever: measured 12 Nov 2026 on the hard-profile set, 4 of 12 companies (the recruitment company, the one-page maintenance company,
  // the glossy 30-page fit-out contractor, the near-empty profile) ended there. He is asked instead (ruling 1647; design 3.3, the
  // "nothing evidenced" card), and the free-text box below is where he answers.
  // Review of 12 Nov 2026: "does not say what your company does" was untrue of most held profiles (the readings disagreed, the profile said
  // plenty), and the box below adds the services it recognises already included, each with Remove: the sentence says what the screen does.
  profile_unclear: 'We read your company profile but could not be sure which services you offer. Please tell us in a line or two in the box below and we will add the matching services for you to check, or tick what you do in the list below.',
  profile_scan: 'Your company profile is a scan or photo that we could not read as text yet. Tick what you do below, or describe it in your own words.',
  profile_failed: 'We could not read your company profile. Upload a clear PDF or Word file in Documents, or tick what you do below, or describe it in your own words.',
  profile_damaged: 'Your company profile file is damaged, so we could not open it. Upload it again in Documents, or tick what you do below, or describe it in your own words.',
  profile_missing: 'No company profile has been read yet. Upload it in Documents, or describe your services below.',
  doc_read_none: 'read, no service matched',
  // The trade he picked in "Register your company" (leads.sector), on the list before he confirms even when nothing was proposed
  // (11 Nov 2026, registration certification finding 4; _shared/supplier_services.ts preparedTrades).
  signup_trade: 'Chosen at sign-up',
  // NO WHOLE TRADE IN ONE TAP (12 Nov 2026, ruling 1647; service-profiling report 1.4): the one real supplier through this step confirmed 33
  // service keys, whole trades ticked, from a 22-word description. Every service of his trades is still here to browse and tick one by one.
  browse_trades: 'Browse all services of my trades',
  browse_trades_help: 'Tick only the services you do. Requests that name a ticked service reach you.',
} as const;

// EVERY SENTENCE TRUE IN EVERY STATE: since slice 4 (12 Nov 2026) the check screen opens with ONE sentence per state, FLOW_COPY.state_* picked
// by stateLine below; servicesSentences and its VERIFY_COPY_NO_LIST variants (two to three sentences a state) were deleted with the screen
// that printed them. Guard: scripts/checks/a_supplier_is_asked_never_assumed.test.mjs.

// THE SERVICES READ OFF THE SUPPLIER'S OWN DOCUMENTS, AND HIS LICENCE (10 Nov 2026, sales_engineer; founder ledger 1573). English only to a
// supplier (ruling 1008), like VERIFY_COPY. Offered, not ticked (founder 862): the button ticks them for him to review before he confirms.
export const PROPOSED_COPY = {
  title: 'Services we understood from your documents',
  help: 'Our sales engineer read your documents together and understood these services from them. Tick each one you do, then press Confirm my services. Your words become the names customers find you by.',
  tick_all: 'Tick all proposed services',
  untick_all: 'Untick all proposed services',
  from_line: 'From your document:',
  not_on_licence: 'Not on your trade licence',
  not_on_licence_help: 'Your trade licence does not list this activity. You can still confirm it; our sales engineer will check it with your licence. If your licence covers it under another name, upload the licence page that shows it in Documents.',
  licence_lists: 'Your trade licence lists:',
  licence_unread: 'We could not read the activities on your trade licence yet, so these services are not checked against it.',
  // READ FIRST, MAPPED SECOND (12 Nov 2026, ruling 1647; _shared/supplier_profile_reading.ts). A service his documents say is delivered through
  // someone else is shown with its sentence and marked, never ticked by "Tick all"; a phrase with no standard name is kept in his words.
  through_partner: 'Through a partner',
  through_partner_help: 'Your documents say this is delivered through a partner. Tick it only if you take this work and deliver it through them.',
  // reader @5, review of branch 2 (12 Nov 2026): nothing the reading found is invisible; each row says what it rests on
  from_projects: 'From your projects',
  from_brands: 'From your brand list',
  from_projects_help: 'We saw this in your projects or brand list, not in your list of services. Tick it only if you take this work as a job of its own.',
  please_check: 'Please check',
  please_check_help: 'We matched this from your words to our nearest service name. Tick it only if it is what you do.',
  progress_title: 'What we read in your profile, in your words',
  progress_help: 'We are now matching these to our standard service names. This takes about another minute; the list to tick appears here by itself, and you can carry on meanwhile.',
  own_words_title: 'In your own words',
  own_words_help: 'We have no standard name for these yet. Tick the ones you do: we keep them exactly as written and add them to our list.',
} as const;

// THE READING ASKS WHAT HE DOES (reader @5, 12 Nov 2026): his documents named no service of his own to tick and the reading drafted the question
// "what does your company do" or a question about a vague statement (the question cards are slice 4). Until then he gets the request of
// VERIFY_COPY.profile_unclear, as a profile whose readings did not agree does: he is never told "still reading" for ever.
export type ReadingLike = { questions?: readonly { kind?: string; status?: string }[] } | null | undefined;
export function asksWhatHeDoes(reading: ReadingLike, ownProposed: number): boolean {
  return ownProposed === 0 && (reading?.questions ?? []).some((q) => (q.kind === 'nothing' || q.kind === 'vague') && q.status === 'open');
}

// WHAT THE SERVICES TAB MAY SAY ABOUT THE COMPANY PROFILE (ledger 1469, browser walk scripts/e2e/supplier_profile_read_walk.mjs, 2 Nov 2026).
// A profile saved as a picture is read by the vision model and its trades are HELD for the sales engineer (status 'read', trades [],
// source 'photo_text'); the tab said "We read your company profile and found no service we could match" about a file that states services.
// A refused or unreadable file got the same words, or "a scan or photo". "found no service" is said only of a file that was read as
// text and named nothing; every file that was not read as text says so.
export type ProfileDocLike = { status?: string; source?: string; choice?: string; trades?: readonly unknown[]; vision_held?: readonly unknown[] };
// Since ledger 1442 a picture or a scanned PDF is read by the model the licence uses and its trades are proposed like a text profile's; 'scan'
// is what is left when that read found nothing on the page (a blank page, or a photo too poor to read), 'damaged' a file that does not open.
export type ProfileState = 'hits' | 'listed' | 'reading' | 'pending' | 'unclear' | 'scan' | 'damaged' | 'failed' | 'none' | 'missing';
/** "found no service" only when nothing is listed: with services listed from his documents the state is 'listed' (review round 2, H09). */
export function listedProfileState(state: ProfileState, listed: number): ProfileState {
  return state === 'none' && listed > 0 ? 'listed' : state;
}
export function profileStateOf(docs: readonly ProfileDocLike[]): ProfileState {
  if (docs.some((d) => (d.trades || []).length)) return 'hits';
  if (docs.some((d) => d.status === 'reading')) return 'reading';
  // read as text, but the model could not be asked yet: still being read (the sweep asks it again), never "failed"
  if (docs.some((d) => d.status === 'read' && d.choice === 'unavailable')) return 'pending';
  // read as text, and the readings agreed on nothing (12 Nov 2026, ruling 1647): he is asked what his company does, never told "still reading"
  if (docs.some((d) => d.status === 'read' && d.choice === 'held')) return 'unclear';
  if (docs.some((d) => d.status === 'needs_ocr' || (d.vision_held || []).length)) return 'scan';   // vision_held: records written before ledger 1442
  if (docs.some((d) => d.status === 'unreadable')) return 'damaged';
  if (docs.some((d) => d.status === 'refused' || d.status === 'needs_cad_conversion')) return 'failed';
  return docs.length ? 'none' : 'missing';
}
// THE THREE SCREENS (12 Nov 2026, slice 4; founder rulings 1647 and 1645; report 3.9). English only (ruling 1008). The founder's standard:
// a general manager on a phone finishes in about two minutes, so ONE short sentence per screen, plain words, nothing to read before the
// first thing to tap. Every sentence is true for the state it is shown in (stateLine below picks it; scripts/checks/a_supplier_is_asked_never_assumed.test.mjs).
export const FLOW_COPY = {
  // Screen 1
  understood_title: 'Here is what we understood your company does',
  understood_lead: 'Tick what you do. These decide which requests reach you.',
  understood_list: (n: number) => `From your documents (${n})`,
  understood_new: 'Your new document shows these. Tick the ones you do.',
  all_of_these: 'Yes, we do all of these',
  next: 'Next',
  back: 'Back',
  own_words_badge: 'Your words',
  his_words: 'Your document:',
  // Screen 2
  questions_title: 'A few quick questions',
  progress: (i: number, n: number) => `${i} of ${n}`,
  tap_all: 'Tap all that apply.',
  your_profile_says: 'Your profile says:',
  none: 'None of these',
  other: 'Something else',
  other_label: 'What else do you do?',
  other_ph: 'For example: dispatch riders',
  only_inside: 'Only inside our own projects',
  partner_own: 'Own team',
  partner_partner: 'Partner',
  partner_no: 'Not offered',
  partner_all: 'All through our partner',
  partner_note: 'For partner services we send you a request when you can take the whole job.',
  licence_note: 'You can upload another licence in Documents.',
  nothing_label: 'What your company does',
  nothing_ph: 'For example: we supply drivers and cleaners to companies in Dubai',
  nothing_trade: 'Choose my trade instead',
  answer_failed: 'One answer was not saved. Your taps are kept.',
  retry: 'Try again',
  retrying: 'Saving…',
  answer_gone: 'That question no longer applies to your documents.',
  // Screen 3
  check_title: 'Check and confirm',
  check_lead: 'Customer requests are matched on this list.',
  confirmed_title: 'Your services',
  confirmed_lead: 'Your services are confirmed. Requests that match them reach you in Inquiries.',
  own_team: (n: number) => `With your own team (${n})`,
  through_partner: (n: number) => `Through a partner (${n})`,
  in_own_words: (n: number) => `In your own words (${n})`,
  own_words_note: 'We keep these exactly as written and add them to our list.',
  nothing_yet: 'Nothing ticked yet.',
  where: 'Where you work',
  where_all: 'Not set: all of the UAE',
  role: 'Your role',
  // "Your role" (founder ruling 1670): the full list is offered only on request and named for what it is, never as a suggestion
  role_from_reading: 'Read from your company profile. Change it if it is not right.',
  role_ask: 'Not chosen yet. Tap Choose and pick what your company does.',
  role_all: 'All roles. Choose only what your company does.',
  choose: 'Choose',
  edit: 'Edit',
  change: 'Change',
  done: 'Done',
  confirm: 'Confirm my services',
  update: 'Update my services',
  confirming: 'Confirming…',
  // two lines at 360 and 390 px beside the docked assistant (round-3 review of slice 4, finding 7)
  confirmed_done: 'Done. Requests for these will reach you.',
  verify_finishing: 'Verified in a minute.',
  removed_title: 'Taken out',
  add_back: 'Add back',
  need_service: 'Tick at least one service, or add one below.',
  need_role: 'Choose your role.',
  more_questions: (n: number) => (n === 1 ? 'We have 1 more question.' : `We have ${n} more questions.`),
  answer_them: 'Answer now',
  review_new: 'Review',
  add_missed: 'Add a service we missed',
  add_missed_help: 'Write what you do in your own words. We match it to our service names for you to check.',
  browse: 'Browse all services of my trades',
  // what the check screen says when there is no reading to show, one per state (stateLine)
  state_missing: 'Upload your company profile in Documents and we will read it for you, or tell us below what you do.',
  // slice 3, review round 2: a whole reading takes 22-161 s (p50 101 s, run c0afdde7); he is told so, and that he can go on
  state_reading: 'Reading your profile. This takes one to two minutes; you can carry on and come back.',
  state_listed: 'The services we found in your profile are listed to tick. Tell us below anything else you do.',
  state_pending: 'We could not read your profile just now and will try again by ourselves. Meanwhile, tell us below what you do.',
  state_unclear: 'We could not tell from your profile which services you offer. Tell us below in a line or two.',
  state_scan: 'Your profile is a scan we could not read. Tell us below what you do, or upload a clearer copy in Documents.',
  state_damaged: 'Your profile file is damaged. Upload it again in Documents, or tell us below what you do.',
  state_failed: 'We could not read your profile. Upload a PDF or Word file in Documents, or tell us below what you do.',
  state_none: 'We read your profile and found no service to list. Tell us below what you do.',
  state_hits: 'Tick the services you do in the list below, or tell us what you do.',
} as const;

/** The one sentence the check screen opens with when there is no reading of his documents to show. Every one names a place to act
 *  that is on screen: "below" is the "Add a service we missed" box, which the check screen always shows (open in these states). */
export function stateLine(state: ProfileState): string {
  return FLOW_COPY[('state_' + state) as keyof typeof FLOW_COPY] as string;
}
