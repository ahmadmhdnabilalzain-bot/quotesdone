// THE WORDS FOR MESSAGES, DOCUMENTS AND INSIGHTS, IN BOTH LANGUAGES (15 Sep 2026, sales_engineer).
//
// The server returns codes and numbers (supplier_portal insights_summary / supporting_*, messages_api
// mailbox — docs/api/supplier_portal_messages_documents_insights.md); every sentence a supplier reads is
// here, English and Arabic side by side, so a mobile client can ship the same table. No imports: the
// parity test (scripts/checks/supplier_workspace_copy_is_bilingual.test.mjs) loads this file directly.
//
// {name} is replaced from params. Arabic numbers stay Western digits inside <bdi dir="ltr"> in the UI.

type Dict = Record<string, string>;

const EN: Dict = {
  // navigation (founder's order, 15 Sep 2026)
  tab_services: 'Services', tab_rfqs: 'Inquiries received', tab_quotes: 'Quotations submitted', tab_messages: 'Messages',
  tab_documents: 'Documents', tab_insights: 'Insights', account_menu: 'Account', acct_profile: 'Profile', acct_billing: 'Billing', acct_settings: 'Settings',

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

  // supporting documents
  sd_title: 'Supporting company documents', sd_sub: 'Anything else that helps a customer choose you: certificates, reference letters, project references, policies. Only you see these files until you share them.',
  sd_label: 'Document name', sd_label_ph: 'e.g. Civil Defence approval 2026', sd_type: 'Type', sd_file: 'File', sd_choose: 'Choose file',
  sd_add: 'Add document', sd_uploading: 'Uploading…', sd_replace: 'Replace file', sd_remove: 'Remove', sd_remove_confirm: 'Confirm remove', sd_cancel: 'Cancel',
  sd_download: 'Download', sd_empty: 'No supporting documents yet.', sd_count: '{n} of {max}', sd_uploaded: 'Uploaded {date}', sd_limits: 'PDF, image or office file, up to 25 MB each.',
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
  price_detail: 'On average your quotes are {pct} against the market average, across {n} competitive inquiries. You were the lowest bid on {lowest}.',
  price_no_data: 'Once you have quoted on inquiries where other suppliers also quoted, you will see where your prices sit. We never show anyone else’s price.',
  in_funnel_h: 'From inquiry to won job', st_received: 'Received', st_quoted: 'Quoted', st_revealed: 'Revealed by the customer', st_won: 'Won',
  conv_of_prev: '{pct} of previous', in_trend_h: 'Last 12 months', trend_quotes: 'Quotations', trend_reveals: 'Reveals', trend_empty: 'No quotations or reveals in the last 12 months yet.',
  in_rates_h: 'Rates', r_win: 'Win rate', r_reveal: 'Reveal rate', r_response: 'Response rate', r_lead: 'Average lead time', r_lost: 'Lost to others', days: '{n} days',
  in_hints_h: 'How to improve', hint_go: 'Open',
  hint_not_eligible_t: 'Finish your registration checklist', hint_not_eligible_b: 'Requests cannot reach you until every step in the checklist on the Documents tab is complete.',
  hint_doc_expired_t: '{doc} has expired', hint_doc_expired_b: 'Upload a renewed copy. An expired document pauses matching or weakens how customers compare you.',
  hint_doc_expiring_t: '{doc} expires in {days} days', hint_doc_expiring_b: 'Renew it now so nothing pauses when it lapses.',
  hint_quote_more_t: '{unquoted} inquiries you have not priced', hint_quote_more_b: 'You quoted fewer than half of the {received} inquiries you received. Every quotation is a chance to be selected.',
  hint_price_above_t: 'Your prices sit {pct}% above the market average', hint_price_above_b: 'Check scope and inclusions against the inquiry. A clearer breakdown or a sharper price wins more comparisons.',
  hint_price_below_no_reveal_t: 'Competitive prices, no reveals yet', hint_price_below_no_reveal_b: 'You price {pct}% below average but no customer has revealed you. Complete specifications and attach your company profile so customers trust the number.',
  hint_follow_up_t: 'Turn reveals into jobs', hint_follow_up_b: '{revealed} customers revealed you and {won} hired you. Reply within the 5-working-day window and follow up in Messages.',
  hint_response_rate_t: 'Response rate {pct}%', hint_response_rate_b: 'Customers choose suppliers who answer quickly. Reply to every revealed job inside 5 working days.',
  hint_lead_time_t: 'Average lead time {days} days', hint_lead_time_b: 'Long lead times lose comparisons. State a realistic, shorter lead time where you can.',
  hint_first_request_t: 'Waiting for your first inquiry', hint_first_request_b: 'Keep your services and emirates up to date so every matching inquiry reaches you.',
  hint_all_good_t: 'Nothing to fix right now', hint_all_good_b: 'Keep quoting promptly and your numbers here will keep growing.',
};

const AR: Dict = {
  tab_services: 'الخدمات', tab_rfqs: 'الاستفسارات الواردة', tab_quotes: 'عروض الأسعار المقدَّمة', tab_messages: 'الرسائل',
  tab_documents: 'المستندات', tab_insights: 'الرؤى', account_menu: 'الحساب', acct_profile: 'الملف التعريفي', acct_billing: 'الفواتير', acct_settings: 'الإعدادات',

  mb_loading: 'جارٍ تحميل رسائلك…', mb_err: 'تعذّر تحميل رسائلك. يُرجى المحاولة مرة أخرى.', mb_retry: 'إعادة المحاولة',
  mb_locked_h: 'تُفتح مراسلة العملاء عندما تفوز بعمل',
  mb_locked_body: 'يصبح صندوق الرسائل مع العميل متاحًا بعد أن يختار العميل عرض سعرك ويدفع رسوم الكشف عنه. وحتى ذلك الحين يبقى العميل مجهول الهوية، وتبقى أنت كذلك.',
  mb_step1: 'تقدّم عرض سعر على استفسار وصلك.', mb_step2: 'يقارن العميل العروض ويختار عرضك.',
  mb_step3: 'يدفع العميل رسوم الكشف، فيُكشف العمل ويُفتح صندوق الرسائل الخاص به.',
  mb_locked_cta: 'عرض الاستفسارات الواردة',
  mb_jobs_h: 'الأعمال المكشوفة', mb_threads_h: 'المحادثات', mb_customer: 'العميل', mb_no_msgs: 'لا توجد رسائل بعد. رحّب بالعميل وأكّد الخطوة التالية.',
  mb_respond_by: 'الرد قبل {date}', mb_overdue: 'تجاوزت مهلة الرد منذ {date}', mb_acked: 'أكّدت التواصل',
  mb_unread: '{n} غير مقروءة', mb_back: 'العودة إلى المحادثات', mb_type: 'اكتب رسالة إلى العميل', mb_send: 'إرسال', mb_sending: 'جارٍ الإرسال…',
  mb_send_err: 'لم تُرسل رسالتك. يُرجى المحاولة مرة أخرى.', mb_warning: 'تُحفظ الرسائل هنا في السجل لكلا الطرفين. يُرجى أن تبقى متعلقة بهذا العمل.',
  mb_closed_policy: 'أُغلقت هذه المحادثة بسبب مخالفة للسياسة.', mb_not_open: 'هذه المحادثة غير مفتوحة بعد.',
  mb_status_open: 'مفتوحة', mb_status_none: 'لم تبدأ', mb_status_banned: 'مغلقة — مخالفة', mb_status_closed: 'مغلقة',

  sd_title: 'مستندات داعمة للشركة', sd_sub: 'كل ما يساعد العميل على اختيارك: الشهادات وخطابات التوصية ومراجع المشاريع والسياسات. لا يرى هذه الملفات أحد غيرك حتى تشاركها.',
  sd_label: 'اسم المستند', sd_label_ph: 'مثال: موافقة الدفاع المدني 2026', sd_type: 'النوع', sd_file: 'الملف', sd_choose: 'اختر ملفًا',
  sd_add: 'إضافة مستند', sd_uploading: 'جارٍ الرفع…', sd_replace: 'استبدال الملف', sd_remove: 'إزالة', sd_remove_confirm: 'تأكيد الإزالة', sd_cancel: 'إلغاء',
  sd_download: 'تنزيل', sd_empty: 'لا توجد مستندات داعمة بعد.', sd_count: '{n} من {max}', sd_uploaded: 'رُفع في {date}', sd_limits: 'ملف PDF أو صورة أو مستند مكتبي، حتى 25 ميغابايت لكل ملف.',
  sd_saved: 'تم الحفظ.', sd_removed: 'أُزيل من مستنداتك.',
  sd_err_label_required: 'أدخل اسمًا للمستند.', sd_err_file_required: 'اختر ملفًا لرفعه.', sd_err_too_large: 'حجم هذا الملف أكبر من 25 ميغابايت.',
  sd_err_file_refused: 'تعذّر قبول هذا الملف. ارفع ملف PDF أو صورة أو مستندًا مكتبيًا.', sd_err_limit_reached: 'بلغت الحد الأقصى وهو {max} مستندًا. أزل مستندًا لإضافة آخر.',
  sd_err_generic: 'تعذّر إتمام العملية. يُرجى المحاولة مرة أخرى.',
  sd_t_certificate: 'شهادة', sd_t_accreditation: 'اعتماد', sd_t_reference_letter: 'خطاب توصية', sd_t_project_reference: 'مرجع مشروع',
  sd_t_financial_statement: 'بيان مالي', sd_t_organisation_chart: 'الهيكل التنظيمي', sd_t_hse_policy: 'سياسة الصحة والسلامة والبيئة', sd_t_quality_policy: 'سياسة الجودة',
  sd_t_brochure: 'كتيّب تعريفي', sd_t_other: 'أخرى',

  in_title: 'أداؤك', in_sub: 'محسوب من استفساراتك وعروض أسعارك أنت. لا نعرض أسعار المنافسين أبدًا — فقط موقع أسعارك منها.',
  in_loading: 'جارٍ قياس أدائك…', in_err: 'تعذّر تحميل الرؤى. يُرجى المحاولة مرة أخرى.',
  tot_received: 'الاستفسارات الواردة', tot_quoted: 'عروض الأسعار المقدَّمة', tot_won: 'الأعمال التي فزت بها', tot_revenue: 'الإيرادات من الأعمال التي فزت بها',
  in_empty_note: 'لا يوجد نشاط بعد. تمتلئ هذه الأرقام بدءًا من أول استفسار يصلك — لا شيء هنا بيانات تجريبية.',
  in_price_h: 'سعرك مقارنة بالسوق', band_below: 'أقل من متوسط السوق', band_around: 'قريب من متوسط السوق', band_above: 'أعلى من متوسط السوق', band_no_data: 'لا توجد مقارنة بعد',
  gauge_below: 'أقل', gauge_above: 'أعلى', gauge_market: 'متوسط السوق',
  price_detail: 'في المتوسط تأتي عروضك بفارق {pct} عن متوسط السوق، عبر {n} من الاستفسارات التنافسية. وكنت صاحب أدنى عرض في {lowest} منها.',
  price_no_data: 'بعد أن تقدّم عروضًا على استفسارات قدّم عليها موردون آخرون أيضًا، سترى موقع أسعارك. لا نعرض سعر أي طرف آخر أبدًا.',
  in_funnel_h: 'من الاستفسار إلى الفوز بالعمل', st_received: 'وردت إليك', st_quoted: 'قدّمت عرضًا', st_revealed: 'كشف عنها العميل', st_won: 'فزت بها',
  conv_of_prev: '{pct} من المرحلة السابقة', in_trend_h: 'آخر 12 شهرًا', trend_quotes: 'عروض الأسعار', trend_reveals: 'مرات الكشف', trend_empty: 'لا توجد عروض أو مرات كشف في آخر 12 شهرًا بعد.',
  in_rates_h: 'المعدلات', r_win: 'معدل الفوز', r_reveal: 'معدل الكشف', r_response: 'معدل الاستجابة', r_lead: 'متوسط مدة التنفيذ', r_lost: 'خسرتها لمنافسين', days: '{n} يومًا',
  in_hints_h: 'كيف تحسّن أداءك', hint_go: 'فتح',
  hint_not_eligible_t: 'أكمل قائمة التسجيل', hint_not_eligible_b: 'لن تصلك الطلبات حتى تكتمل كل خطوة في القائمة الموجودة في تبويب المستندات.',
  hint_doc_expired_t: 'انتهت صلاحية {doc}', hint_doc_expired_b: 'ارفع نسخة مجدَّدة. المستند المنتهي يوقف المطابقة أو يُضعف موقعك عند مقارنة العملاء.',
  hint_doc_expiring_t: 'تنتهي صلاحية {doc} خلال {days} يومًا', hint_doc_expiring_b: 'جدّده الآن حتى لا يتوقف شيء عند انتهائه.',
  hint_quote_more_t: '{unquoted} استفسارًا لم تقدّم عليها عرضًا', hint_quote_more_b: 'قدّمت عروضًا على أقل من نصف الاستفسارات الواردة إليك وعددها {received}. كل عرض فرصة لأن يقع عليك الاختيار.',
  hint_price_above_t: 'أسعارك أعلى من متوسط السوق بنسبة {pct}%', hint_price_above_b: 'راجع النطاق والبنود المشمولة مقابل الاستفسار. التفصيل الأوضح أو السعر الأدق يربح مقارنات أكثر.',
  hint_price_below_no_reveal_t: 'أسعار تنافسية دون كشف بعد', hint_price_below_no_reveal_b: 'أسعارك أقل من المتوسط بنسبة {pct}% لكن لم يكشف عنك أي عميل بعد. أكمل المواصفات وأرفق ملف شركتك التعريفي ليثق العميل بالرقم.',
  hint_follow_up_t: 'حوّل مرات الكشف إلى أعمال', hint_follow_up_b: 'كشف عنك {revealed} من العملاء ووظّفك {won} منهم. ردّ خلال مهلة 5 أيام عمل وتابع عبر الرسائل.',
  hint_response_rate_t: 'معدل الاستجابة {pct}%', hint_response_rate_b: 'يختار العملاء الموردين الذين يردّون بسرعة. ردّ على كل عمل مكشوف خلال 5 أيام عمل.',
  hint_lead_time_t: 'متوسط مدة التنفيذ {days} يومًا', hint_lead_time_b: 'مدد التنفيذ الطويلة تخسر المقارنات. اذكر مدة واقعية وأقصر حيثما أمكن.',
  hint_first_request_t: 'بانتظار أول استفسار يصلك', hint_first_request_b: 'حدّث خدماتك والإمارات التي تعمل بها ليصلك كل استفسار مطابق.',
  hint_all_good_t: 'لا شيء يحتاج إلى إصلاح الآن', hint_all_good_b: 'واصل تقديم العروض بسرعة وستستمر أرقامك هنا في النمو.',
};

export const WORKSPACE_COPY = { en: EN, ar: AR } as const;

export function ws(lang: string, key: string, params: Record<string, string | number> = {}): string {
  const s = (lang === 'ar' ? AR : EN)[key] ?? EN[key] ?? key;
  return s.replace(/\{(\w+)\}/g, (_, k) => (params[k] == null ? '' : String(params[k])));
}
