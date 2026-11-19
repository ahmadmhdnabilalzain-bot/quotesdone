// THE WORDS FOR MESSAGES, DOCUMENTS AND INSIGHTS, IN BOTH LANGUAGES (15 Sep 2026, sales_engineer).
//
// The server returns codes and numbers (supplier_portal insights_summary / supporting_*, messages_api
// mailbox — docs/api/supplier_portal_messages_documents_insights.md); every sentence a supplier reads is
// here, English and Arabic side by side, so a mobile client can ship the same table. No imports: the
// parity test (scripts/checks/supplier_workspace_copy_is_bilingual.test.mjs) loads this file directly.
//
// {name} is replaced from params. Arabic numbers stay Western digits inside <bdi dir="ltr"> in the UI.

type Dict = Record<string, string>;

// ARABIC NUMBER AGREEMENT (audit 22 Sep 2026, SP-I-04).
//
// Every counted noun here printed one form for every n, so one unpriced inquiry read
// "1 استفسارًا" and two read "2 استفسارًا"; Arabic writes no digit for 1 or 2, uses the plural
// genitive for 3–10 and the accusative singular from 11. The rule is ONE rule and it is
// `arCount` in src/lib/durationLabel.ts — [1, 2, 3–10, 11+], in that order.
//
// WHY IT IS NOT IMPORTED HERE. This module is loaded straight into node by its parity check
// (scripts/checks/supplier_workspace_copy_is_bilingual.test.mjs does
// `import(pathToFileURL('…/workspaceCopy.ts'))`), where the "@/" alias does not exist and an
// extensionless relative import is ERR_MODULE_NOT_FOUND — measured 22 Sep 2026 on node v24.16.
// So the FORMS live here as data and `ws()` picks between them with the same four indices. If the
// check is ever given a loader that resolves the alias, delete AR_COUNTED's selection and call
// arCount directly; nothing else here depends on the copy.
type Forms = readonly [string, string, string, string];
const INQUIRY: Forms = ['استفسار واحد', 'استفسارين', 'استفسارات', 'استفسارًا'];   // after a preposition (genitive)
const UNREAD_MSG: Forms = ['رسالة واحدة غير مقروءة', 'رسالتان غير مقروءتين', 'رسائل غير مقروءة', 'رسالة غير مقروءة'];
const DOCUMENT: Forms = ['مستند واحد', 'مستندان', 'مستندات', 'مستندًا'];
// CASE MATTERS FOR THE DUAL ONLY, and it is decided by what stands before the number.
// DAY — genitive dual «يومين» — for a count governed by a preposition: «خلال {days}»، «نحو {n}».
const DAY: Forms = ['يوم واحد', 'يومين', 'أيام', 'يومًا'];
// DAY_NOM — nominative dual «يومان» — for a count that is the predicate of a nominal sentence with
// no preposition over it: «متوسط مدة التنفيذ {days}». Reviewer, 22 Sep 2026: hint_lead_time_t took
// the genitive from DAY although nothing governs it. Same four indices, different dual — pick by
// the position the placeholder sits in, never by the noun.
const DAY_NOM: Forms = ['يوم واحد', 'يومان', 'أيام', 'يومًا'];

/** Which {placeholder} of which key is a counted Arabic noun, and the noun's four forms. */
const AR_COUNTED: Record<string, Record<string, Forms>> = {
  hint_quote_more_t: { unquoted: INQUIRY },
  hint_doc_expiring_t: { days: DAY },
  hint_lead_time_t: { days: DAY_NOM },
  days: { n: DAY },
  mb_unread: { n: UNREAD_MSG },
  sd_err_limit_reached: { max: DOCUMENT },
};
const arCounted = (forms: Forms, v: string | number): string => {
  const k = Math.abs(Math.trunc(Number(v)));
  if (!Number.isFinite(k)) return String(v);
  // ZERO TAKES THE ACCUSATIVE SINGULAR, AS AT 11+ — never the 3-10 plural (re-review of #858,
  // 23 Sep 2026). Without this line '0' fell through to forms[2] and printed '0 ايام'. The rule and
  // its reason belong to src/lib/countedNoun.ts, which this file cannot import (see above); the four
  // indices and this branch are kept identical to arCount there, and the check named below fails if
  // this branch is removed.
  if (k === 0) return `0 ${forms[3]}`;
  if (k === 1) return forms[0];
  if (k === 2) return forms[1];
  return `${k} ${k <= 10 ? forms[2] : forms[3]}`;
};

const EN: Dict = {
  // navigation (founder's order, 15 Sep 2026)
  tab_services: 'Services', tab_rfqs: 'Inquiries received', tab_quotes: 'Quotations submitted', tab_messages: 'Messages',
  tab_documents: 'Documents', tab_insights: 'Insights', account_menu: 'Account', acct_profile: 'Profile', acct_billing: 'Billing', acct_settings: 'Settings',

  // inquiries received — a drawing page that could not be opened (18 Sep 2026, sales_engineer). The
  // server counts what was expected, served and failed (supplier_api inbox: drawing_pages_expected /
  // _served / _failed); showing fewer drawings than exist, with no word said, is what these replace.
  rfq_pages_unavailable: '{n} of {total} drawing pages could not be opened — please refresh to try again.',
  rfq_pages_row_missing: '{n} could not be opened',
  rfq_pages_none: 'The drawings for this inquiry could not be opened — please refresh to try again. Please do not price from the bill of quantities alone.',
  // 22 Sep 2026: a held drawing or a CAD file is not shown, and the supplier is told it exists (supplier_api drawing_withheld).
  rfq_file_withheld: 'The customer attached a drawing or document that is not shown here, because it could not be shared without revealing who they are. Any quantities we could read from it are in the bill of quantities below. If you need a detail from it, ask a question below.',
  // 17 Nov 2026: the drawing's sheets are still being checked; they are added here and the supplier is e-mailed when they are.
  rfq_pages_follow: 'Redacted drawing pages follow: they are being checked and will be added to this inquiry. We will e-mail you when they are here. Any quantities we could read from the drawing are in the bill of quantities below.',

  // messages
  mb_loading: 'Loading your messages…', mb_err: 'We could not load your messages. Please try again.', mb_retry: 'Try again',
  mb_locked_h: 'Customer messaging opens when you win a job',
  mb_locked_body: 'Your mailbox with a customer becomes available once that customer selects your quotation and pays to reveal it. Until then the customer stays anonymous, and so do you.',
  mb_step1: 'You submit a quotation for an inquiry you received.', mb_step2: 'The customer compares quotations and selects yours.',
  mb_step3: 'They pay the reveal fee: the job is revealed and this mailbox opens for it.',
  mb_locked_cta: 'See inquiries received',
  mb_jobs_h: 'Revealed jobs', mb_threads_h: 'Conversations', mb_customer: 'Customer', mb_no_msgs: 'No messages yet. Say hello and confirm the next step.',
  mb_respond_by: 'Respond by {date}', mb_overdue: 'Response overdue since {date}', mb_acked: 'You confirmed contact',
  mb_unread: '{n} unread', mb_back: 'Back to conversations', mb_type: 'Write a message to the customer', mb_send: 'Send', mb_sending: 'Sending…',
  mb_send_err: 'Your message was not sent. Please try again.', mb_warning: 'Messages here are kept on record for both of you. Please keep them about this job.',
  mb_closed_policy: 'This conversation is closed due to a policy violation.', mb_not_open: 'This conversation is not open yet.',
  mb_status_open: 'Open', mb_status_none: 'Not started', mb_status_banned: 'Closed — policy', mb_status_closed: 'Closed',

  // supporting documents (walk of 12 Nov 2026, S5: there is no share control, and the server keeps these from customers by design,
  // supabase/functions/supplier_portal/supporting_documents.ts; the line said "until you share them" and now says what is true)
  sd_title: 'Supporting company documents', sd_sub: 'Certificates, reference letters, project references and policies, kept with your account. Only you see these files; customers never do.',
  sd_label: 'Document name', sd_label_ph: 'e.g. Civil Defence approval 2026', sd_type: 'Type', sd_file: 'File', sd_choose: 'Choose file',
  sd_add: 'Add document', sd_uploading: 'Uploading…', sd_replace: 'Replace file', sd_remove: 'Remove', sd_remove_confirm: 'Confirm remove', sd_cancel: 'Cancel',
  sd_download: 'Download', sd_opening: 'Opening…', sd_empty: 'No supporting documents yet.', sd_count: '{n} of {max}', sd_uploaded: 'Uploaded {date}', sd_limits: 'PDF, image or office file, up to 25 MB each.',
  sd_saved: 'Saved.', sd_removed: 'Removed from your documents.',
  sd_err_label_required: 'Give the document a name.', sd_err_file_required: 'Choose a file to upload.', sd_err_too_large: 'That file is larger than 25 MB.',
  sd_err_file_refused: 'That file could not be accepted. Upload a PDF, an image or an office document.', sd_err_limit_reached: 'You have reached the limit of {max} documents. Remove one to add another.',
  sd_err_generic: 'That did not work. Please try again.',
  sd_t_certificate: 'Certificate', sd_t_accreditation: 'Accreditation', sd_t_reference_letter: 'Reference letter', sd_t_project_reference: 'Project reference',
  sd_t_financial_statement: 'Financial statement', sd_t_organisation_chart: 'Organisation chart', sd_t_hse_policy: 'HSE policy', sd_t_quality_policy: 'Quality policy',
  sd_t_brochure: 'Brochure', sd_t_other: 'Other',

  // insights
  in_title: 'Your performance', in_sub: 'Measured from your own inquiries and quotations. Competitor prices are never shown — only where yours sit.',
  in_loading: 'Measuring your performance…', in_err: 'We could not load your insights. Please try again.',
  tot_received: 'Inquiries received', tot_quoted: 'Quotations submitted', tot_won: 'Jobs won', tot_revenue: 'Revenue from won jobs',
  in_empty_note: 'No activity yet. These fill in from your first inquiry — nothing here is a sample.',
  in_price_h: 'Your price against the market', band_below: 'Below market average', band_around: 'Around market average', band_above: 'Above market average', band_no_data: 'No comparison yet',
  gauge_below: 'Lower', gauge_above: 'Higher', gauge_market: 'Market average',
  price_detail: 'On average your quotes are {pct} against the market average, across {n}, in 5-point steps.',
  price_no_data: 'Not enough comparisons yet. Your position shows once 5 closed inquiries you quoted on each had quotes from at least 3 other suppliers, in 5-point steps. We never show anyone else’s price.',
  in_funnel_h: 'From inquiry to won job', st_received: 'Received', st_quoted: 'Quoted', st_revealed: 'Revealed by the customer', st_won: 'Won',
  conv_of_prev: '{pct} of previous', in_trend_h: 'Last 12 months', trend_quotes: 'Quotations', trend_reveals: 'Reveals', trend_empty: 'No quotations or reveals in the last 12 months yet.',
  in_rates_h: 'Rates', r_win: 'Win rate', r_reveal: 'Reveal rate', r_response: 'Response rate', r_lead: 'Average lead time', r_lost: 'Lost to others', days: '{n}',
  in_hints_h: 'How to improve', hint_go: 'Open',
  hint_not_eligible_t: 'Finish your registration checklist', hint_not_eligible_b: 'Requests cannot reach you until every step in the checklist on the Documents tab is complete.',
  hint_doc_expired_t: '{doc} has expired', hint_doc_expired_b: 'Upload a renewed copy. An expired document pauses matching or weakens how customers compare you.',
  hint_doc_expiring_t: '{doc} expires in {days}', hint_doc_expiring_b: 'Renew it now so nothing pauses when it lapses.',
  hint_quote_more_t: '{unquoted} you have not priced', hint_quote_more_b: 'You quoted fewer than half of the {received} inquiries you received. Every quotation is a chance to be selected.',
  hint_price_above_t: 'Your prices sit {pct}% above the market average', hint_price_above_b: 'Check scope and inclusions against the inquiry. A clearer breakdown or a sharper price wins more comparisons.',
  hint_price_below_no_reveal_t: 'Competitive prices, no reveals yet', hint_price_below_no_reveal_b: 'You price {pct}% below average but no customer has revealed you. Complete specifications and attach your company profile so customers trust the number.',
  hint_follow_up_t: 'Turn reveals into jobs', hint_follow_up_b: '{revealed} customers revealed you and {won} hired you. Reply within the 5-working-day window and follow up in Messages.',
  hint_response_rate_t: 'Response rate {pct}%', hint_response_rate_b: 'Customers choose suppliers who answer quickly. Reply to every revealed job inside 5 working days.',
  hint_lead_time_t: 'Average lead time {days}', hint_lead_time_b: 'Long lead times lose comparisons. State a realistic, shorter lead time where you can.',
  hint_first_request_t: 'Waiting for your first inquiry', hint_first_request_b: 'Keep your services and emirates up to date so every matching inquiry reaches you.',
  hint_all_good_t: 'Nothing to fix right now', hint_all_good_b: 'Keep quoting promptly and your numbers here will keep growing.',
};

const AR: Dict = {
  tab_services: 'الخدمات', tab_rfqs: 'الاستفسارات الواردة', tab_quotes: 'عروض الأسعار المقدَّمة', tab_messages: 'الرسائل',
  tab_documents: 'المستندات', tab_insights: 'الرؤى', account_menu: 'الحساب', acct_profile: 'الملف التعريفي', acct_billing: 'الفواتير', acct_settings: 'الإعدادات',

  rfq_pages_unavailable: 'تعذّر فتح {n} من أصل {total} من صفحات المخططات — يُرجى تحديث الصفحة والمحاولة مرة أخرى.',
  rfq_pages_row_missing: 'تعذّر فتح {n} منها',
  rfq_pages_none: 'تعذّر فتح مخططات هذا الاستفسار — يُرجى تحديث الصفحة والمحاولة مرة أخرى. يُرجى عدم التسعير بالاعتماد على جدول الكميات وحده.',
  rfq_file_withheld: 'أرفق العميل مخططاً أو مستنداً لا يُعرض هنا، لأنه تعذّرت مشاركته دون الكشف عن هويته. الكميات التي أمكننا قراءتها منه واردة في جدول الكميات أدناه، وإن احتجتم إلى أي تفصيل منه فيُرجى طرح سؤالكم أدناه.',
  rfq_pages_follow: 'لوحات المخطّط المنقّحة ستلحق بهذا الطلب: هي قيد الفحص الآن وستُضاف إليه، وسنراسلكم بالبريد الإلكتروني عند وصولها. الكميات التي أمكن قراءتها من المخطّط موجودة في جدول الكميات أدناه.',

  mb_loading: 'جارٍ تحميل رسائلكم…', mb_err: 'تعذّر تحميل رسائلكم. يُرجى المحاولة مرة أخرى.', mb_retry: 'إعادة المحاولة',
  mb_locked_h: 'تُتاح مراسلة العملاء عند فوزكم بمشروع',
  mb_locked_body: 'يُتاح صندوق الرسائل مع العميل بعد أن يختار عرض سعركم ويسدّد رسوم الكشف عنه. وحتى ذلك الحين تبقى هوية العميل غير معلنة، وكذلك هويتكم.',
  mb_step1: 'تقدّمون عرض سعر على استفسار وصلكم.', mb_step2: 'يقارن العميل العروض ويختار عرضكم.',
  mb_step3: 'يسدّد العميل رسوم الكشف، فيُكشف المشروع ويُفتح صندوق رسائله.',
  mb_locked_cta: 'عرض الاستفسارات الواردة',
  mb_jobs_h: 'المشاريع المكشوفة', mb_threads_h: 'المحادثات', mb_customer: 'العميل', mb_no_msgs: 'لا توجد رسائل بعد. رحّبوا بالعميل وأكّدوا الخطوة التالية.',
  mb_respond_by: 'الرد قبل {date}', mb_overdue: 'انقضت مهلة الرد منذ {date}', mb_acked: 'أكّدتم التواصل',
  mb_unread: 'لديكم {n}', mb_back: 'العودة إلى المحادثات', mb_type: 'اكتبوا رسالة إلى العميل', mb_send: 'إرسال', mb_sending: 'جارٍ الإرسال…',
  mb_send_err: 'لم تُرسل رسالتكم. يُرجى المحاولة مرة أخرى.', mb_warning: 'تُحفظ الرسائل هنا في السجل لكلا الطرفين. يُرجى قصرها على هذا المشروع.',
  mb_closed_policy: 'أُغلقت هذه المحادثة بسبب مخالفة للسياسة.', mb_not_open: 'هذه المحادثة غير مفتوحة بعد.',
  mb_status_open: 'مفتوحة', mb_status_none: 'لم تبدأ', mb_status_banned: 'مغلقة — مخالفة', mb_status_closed: 'مغلقة',

  sd_title: 'مستندات داعمة للشركة', sd_sub: 'كل ما يساعد العميل على اختياركم: الشهادات وخطابات التوصية ومراجع المشاريع والسياسات. تبقى هذه الملفات مرئية لكم وحدكم إلى أن تشاركوها.',
  sd_label: 'اسم المستند', sd_label_ph: 'مثال: موافقة الدفاع المدني 2026', sd_type: 'النوع', sd_file: 'الملف', sd_choose: 'اختيار ملف',
  sd_add: 'إضافة مستند', sd_uploading: 'جارٍ الرفع…', sd_replace: 'استبدال الملف', sd_remove: 'إزالة', sd_remove_confirm: 'تأكيد الإزالة', sd_cancel: 'إلغاء',
  sd_download: 'تنزيل', sd_opening: 'جارٍ الفتح…', sd_empty: 'لا توجد مستندات داعمة بعد.', sd_count: '{n} من {max}', sd_uploaded: 'رُفع في {date}', sd_limits: 'ملف PDF أو صورة أو مستند مكتبي، حتى 25 ميغابايت لكل ملف.',
  sd_saved: 'تم الحفظ.', sd_removed: 'أُزيل من مستنداتكم.',
  sd_err_label_required: 'يُرجى إدخال اسم للمستند.', sd_err_file_required: 'يُرجى اختيار ملف لرفعه.', sd_err_too_large: 'حجم هذا الملف أكبر من 25 ميغابايت.',
  sd_err_file_refused: 'تعذّر قبول هذا الملف. يُرجى رفع ملف PDF أو صورة أو مستند مكتبي.', sd_err_limit_reached: 'بلغتم الحد الأقصى وهو {max}. يُرجى إزالة مستند لإضافة آخر.',
  sd_err_generic: 'تعذّر إتمام العملية. يُرجى المحاولة مرة أخرى.',
  sd_t_certificate: 'شهادة', sd_t_accreditation: 'اعتماد', sd_t_reference_letter: 'خطاب توصية', sd_t_project_reference: 'مرجع مشروع',
  sd_t_financial_statement: 'بيان مالي', sd_t_organisation_chart: 'الهيكل التنظيمي', sd_t_hse_policy: 'سياسة الصحة والسلامة والبيئة', sd_t_quality_policy: 'سياسة الجودة',
  sd_t_brochure: 'كتيّب تعريفي', sd_t_other: 'أخرى',

  in_title: 'أداؤكم', in_sub: 'محسوب من استفساراتكم وعروض أسعاركم وحدها. لا نعرض أسعار المنافسين أبدًا، بل موقع أسعاركم منها فقط.',
  in_loading: 'جارٍ قياس أدائكم…', in_err: 'تعذّر تحميل الرؤى. يُرجى المحاولة مرة أخرى.',
  tot_received: 'الاستفسارات الواردة', tot_quoted: 'عروض الأسعار المقدَّمة', tot_won: 'المشاريع التي فزتم بها', tot_revenue: 'الإيرادات من المشاريع التي فزتم بها',
  in_empty_note: 'لا يوجد نشاط بعد. تبدأ هذه الأرقام بالظهور مع أول استفسار يصلكم — ولا شيء هنا بيانات تجريبية.',
  in_price_h: 'أسعاركم مقارنةً بالسوق', band_below: 'أقل من متوسط السوق', band_around: 'قريب من متوسط السوق', band_above: 'أعلى من متوسط السوق', band_no_data: 'لا توجد مقارنة بعد',
  gauge_below: 'أقل', gauge_above: 'أعلى', gauge_market: 'متوسط السوق',
  price_detail: 'تأتي عروضكم في المتوسط بفارق {pct} عن متوسط السوق، في {n} من الاستفسارات التنافسية، بخطوات من 5 نقاط.',
  price_no_data: 'لا توجد مقارنات كافية بعد. يظهر موقع أسعاركم عند إغلاق 5 استفسارات قدّمتم عروضًا عليها وقدّم على كلٍّ منها 3 موردين آخرين على الأقل، بخطوات من 5 نقاط. لا نعرض سعر أي طرف آخر أبدًا.',
  in_funnel_h: 'من الاستفسار إلى الفوز بالمشروع', st_received: 'وردت إليكم', st_quoted: 'قدّمتم عرضًا', st_revealed: 'كشف عنها العميل', st_won: 'فزتم بها',
  conv_of_prev: '{pct} من المرحلة السابقة', in_trend_h: 'آخر 12 شهرًا', trend_quotes: 'عروض الأسعار', trend_reveals: 'مرات الكشف', trend_empty: 'لا توجد عروض أو مرات كشف في آخر 12 شهرًا بعد.',
  in_rates_h: 'المعدلات', r_win: 'معدل الفوز', r_reveal: 'معدل الكشف', r_response: 'معدل الاستجابة', r_lead: 'متوسط مدة التنفيذ', r_lost: 'خسرتموها لصالح منافسين', days: 'نحو {n}',
  in_hints_h: 'كيف تحسّنون أداءكم', hint_go: 'فتح',
  hint_not_eligible_t: 'أكملوا قائمة التسجيل', hint_not_eligible_b: 'لن تصلكم الطلبات حتى تكتمل جميع خطوات القائمة في تبويب المستندات.',
  hint_doc_expired_t: 'انتهت صلاحية {doc}', hint_doc_expired_b: 'يُرجى رفع نسخة مجدَّدة؛ فالمستند المنتهي يوقف المطابقة أو يُضعف موقعكم عند مقارنة العملاء.',
  hint_doc_expiring_t: 'تنتهي صلاحية {doc} خلال {days}', hint_doc_expiring_b: 'يُرجى تجديده الآن حتى لا يتوقف شيء عند انتهاء صلاحيته.',
  hint_quote_more_t: 'لم تقدّموا عرضًا على {unquoted}', hint_quote_more_b: 'قدّمتم عروضًا على أقل من نصف الاستفسارات الواردة إليكم، وعددها {received}. كل عرض فرصة ليقع الاختيار عليكم.',
  hint_price_above_t: 'أسعاركم أعلى من متوسط السوق بنسبة {pct}%', hint_price_above_b: 'راجعوا النطاق والبنود المشمولة مقارنةً بالاستفسار؛ فالتفصيل الأوضح أو السعر الأدق يكسب مقارنات أكثر.',
  hint_price_below_no_reveal_t: 'أسعار تنافسية دون كشف بعد', hint_price_below_no_reveal_b: 'أسعاركم أقل من المتوسط بنسبة {pct}%، لكن لم يكشف عنكم أي عميل بعد. أكملوا المواصفات وأرفقوا الملف التعريفي لشركتكم ليثق العملاء بالسعر.',
  hint_follow_up_t: 'حوّلوا مرات الكشف إلى مشاريع', hint_follow_up_b: 'كشف عنكم {revealed} من العملاء، وتعاقد معكم {won} منهم. احرصوا على الرد خلال مهلة 5 أيام عمل والمتابعة عبر الرسائل.',
  hint_response_rate_t: 'معدل الاستجابة {pct}%', hint_response_rate_b: 'يفضّل العملاء الموردين الذين يردّون بسرعة. احرصوا على الرد على كل مشروع مكشوف خلال 5 أيام عمل.',
  hint_lead_time_t: 'متوسط مدة التنفيذ {days}', hint_lead_time_b: 'مدد التنفيذ الطويلة تُضعف فرصكم في المقارنة. اذكروا مدة واقعية وأقصر حيثما أمكن.',
  hint_first_request_t: 'بانتظار أول استفسار يصلكم', hint_first_request_b: 'حدّثوا خدماتكم والإمارات التي تعملون فيها ليصلكم كل استفسار مطابق.',
  hint_all_good_t: 'لا شيء يحتاج إلى إصلاح الآن', hint_all_good_b: 'واصلوا تقديم العروض بسرعة، وستواصل أرقامكم هنا النمو.',
};

export const WORKSPACE_COPY = { en: EN, ar: AR } as const;

// ENGLISH COUNTS TOO (walk of 12 Nov 2026, S12): "1 inquiries you have not priced", "expires in 1 days" and "You were the lowest bid on 0."
// were on screen. A counted English value is written with its noun, singular for one; the lowest-price sentence is said only when
// there is a lowest price to report. The Arabic counts (AR_COUNTED) are untouched.
const enNoun = (one: string, many: string) => (v: string | number) => { const k = Number(v); return `${v} ${k === 1 ? one : many}`; };
const EN_COUNTED: Record<string, Record<string, (v: string | number) => string>> = {
  hint_quote_more_t: { unquoted: enNoun('inquiry', 'inquiries') },
  hint_doc_expiring_t: { days: enNoun('day', 'days') },
  hint_lead_time_t: { days: enNoun('day', 'days') },
  days: { n: enNoun('day', 'days') },
  // No "lowest on k of them" since 19 Nov 2026: times_lowest is no longer sent (a supplier moving his own price on an open
  // request could watch it flip and find the lowest rival's price).
  price_detail: { n: enNoun('competitive inquiry', 'competitive inquiries') },
};

export function ws(lang: string, key: string, params: Record<string, string | number> = {}): string {
  const ar = lang === 'ar' && AR[key] != null;
  const s = ar ? AR[key] : EN[key] ?? key;
  const counted = ar ? AR_COUNTED[key] : undefined;
  const enCounted = ar ? undefined : EN_COUNTED[key];
  return s.replace(/\{(\w+)\}/g, (_, k) => {
    if (params[k] == null) return '';
    const forms = counted && counted[k];
    if (forms) return arCounted(forms, params[k]);
    const en = enCounted && enCounted[k];
    return en ? en(params[k]) : String(params[k]);
  });
}
