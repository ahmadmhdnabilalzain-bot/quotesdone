// my_data_pdf/document.ts — a person's data copy, from the export to the blocks the QuotesDone PDF template draws.
//
// WHY (customer_support, built by it_engineer, 12 Nov 2026). The founder pressed "Download my data" as a supplier on his
// iPhone and got raw JSON in a Safari tab: machine keys, `null`, `[]`, ISO timestamps, a literal "\n" and "ðŸ'‹" where
// an emoji was (ledger 1669: "Again, horrible."); then (ledger 1671): "Download my data should be a pdf with our
// template". This file turns what pdpl_request_me('export') returns into a document a person reads: plain sections,
// labels instead of keys, Dubai time written out, every line break kept, emoji named in words (the brand fonts carry
// no emoji, and a dropped glyph would silently change what he wrote), and one plain line for a section with nothing in
// it. It has no I/O: index.ts is the door, ../pdf_native/render.ts draws.
//
// IT ALSO DEFENDS ITSELF. Only named fields are ever printed, so a field the routine returns that is not his (until
// scripts/sql/a_copy_of_a_persons_data_holds_their_own_records_and_nobody_elses.sql is applied the routine hands a
// supplier the customer's payment row, staff names and internal notes) never reaches the page. A supplier's copy
// shows that a quotation was revealed and when, never what the customer paid.

export type Lang = 'en' | 'ar';
export type Role = 'customer' | 'supplier';
// deno-lint-ignore no-explicit-any
type Rec = Record<string, any>;
// deno-lint-ignore no-explicit-any
export type Block = Record<string, any>;

const T = {
  en: {
    title: 'Your data held by QuotesDone',
    kicker: 'PERSONAL DATA COPY',
    prepared_for: 'Prepared for', email: 'E-mail', produced_on: 'Produced on {d}',
    subtitle: 'A copy of the personal data QuotesDone holds about you, under the UAE Personal Data Protection Law.',
    at_dubai: '{d}, Dubai time',
    controller_h: 'Who holds your data',
    controller: 'The data controller is QuotesDone Technologies, a Dubai Sole Establishment, DET Dubai Trader License No. 1633275, Dubai, United Arab Emirates. Questions about your data: management@quotesdone.com.',
    s_account: 'Your account', s_company: 'Your company', s_requests: 'Your requests', s_quotes: 'Your quotations',
    s_wa: 'Messages on WhatsApp', s_chat: 'Messages in the portal', s_sent: 'E-mails we sent you',
    s_recv: 'E-mails you sent us', s_pay: 'Payments and refunds', s_mkt: 'Marketing preferences', s_fix: 'Correcting or erasing your data',
    none_account: 'You have no customer account with us.', none_company: 'We hold no company record for you.',
    none_requests: 'You have not posted any requests.', none_quotes: 'Your company has not sent any quotations.',
    none_wa: 'We have no WhatsApp messages with you.', none_chat: 'There are no portal messages.',
    none_sent: 'We have not sent you any e-mails.', none_recv: 'We have not received any e-mails from you.',
    none_pay: 'There are no payments or refunds.',
    wa_note: 'Messages from a verified number of yours, from the day your account was opened.',
    not_sent: '{n} more e-mail(s) addressed to you were prepared but never sent.',
    you: 'You', qd: 'QuotesDone', the_customer: 'The customer', the_supplier: 'The supplier', attached: '(A file was attached.)',
    wa_channel: 'Sent on WhatsApp',
    yes: 'Yes', no: 'No',
    // account
    f_name: 'Name', f_email: 'E-mail', f_mobile: 'Mobile', f_mobile_ok: 'Mobile verified', f_wa: 'WhatsApp number',
    f_email_ok: 'E-mail verified', f_dob: 'Date of birth', f_industry: 'Industry', f_lang: 'Language', f_opened: 'Account opened',
    f_terms_v: 'Terms version', f_terms_at: 'Terms accepted', f_terms_ip: 'Terms accepted from (IP address)',
    f_wa_updates: 'WhatsApp updates', f_suspended: 'Account suspended', f_suspension: 'Reason for the suspension',
    // company
    f_company: 'Company', f_registered: 'Registered by you', f_contact: 'Contact name', f_signatory: 'Authorised signatory',
    f_login: 'Sign-in e-mail', f_company_email: 'Company e-mail', f_phone: 'Phone', f_web: 'Website', f_address: 'Address',
    f_serves: 'Emirates you serve', f_about: 'About the company', f_products: 'Products', f_services: 'Services',
    f_certs: 'Certifications', f_licence_no: 'Trade licence number', f_authority: 'Licence authority',
    f_licence_exp: 'Licence expiry', f_licence_name: 'Name on the licence', f_trn: 'Tax registration number (TRN)',
    f_owner_dob: 'Owner date of birth', f_eid: 'Emirates ID', f_reg: 'Registration', f_reg_exp: 'Registration valid until',
    f_approval: 'Approval', f_approved_at: 'Approved on', f_rejection: 'Reason given', f_docs: 'Documents you uploaded',
    f_listed: 'On our list since', f_source: 'Where we found the listing',
    // requests and quotations
    request: 'Request', f_created: 'Posted', f_status: 'Status', f_emirate: 'Emirate', f_budget: 'Budget', f_by: 'Needed by',
    f_summary: 'Summary', f_wrote: 'What you wrote', quotation_for: 'Quotation for request{r}', f_sent_on: 'Sent',
    f_amount: 'Amount', f_ex_vat: 'Price before VAT', f_vat: 'VAT', f_lead: 'Lead time', f_valid: 'Validity',
    f_terms: 'Payment terms', f_warranty: 'Warranty', f_scope: 'Scope', f_excl: 'Exclusions', f_cond: 'Conditions', f_file: 'File',
    // payments
    payment_h: 'Reveal of request{r}', f_revealed: 'Revealed on', f_quote_amt: 'Quotation', f_fee: 'Reveal fee',
    f_total: 'Total charged', f_pay: 'Payment', f_invoice: 'Invoice number', f_refund: 'Refund', f_refund_amt: 'Amount refunded',
    invoice_link: 'Open your invoice', refund_h: 'Refund requested on {d}', f_reason: 'Reason', f_settled: 'Settled on',
    receipt_link: 'Open your refund receipt',
    reveal_line: 'On {d}, a customer revealed your quotation for request{r}.',
    ack_line: 'You acknowledged it on {d}.',
    refund_on_yours: 'On {d}, the reveal fee for one of your quotations was refunded to the customer ({why}).',
    // marketing
    opted_out: 'You opted out of marketing e-mails on {d}.',
    not_opted_out: 'You have not opted out of marketing e-mails.',
    consent_yes: 'You agreed to receive marketing messages on {d}.', consent_yes_nodate: 'You agreed to receive marketing messages.',
    consent_no: 'You have not agreed to receive marketing messages.',
    service_mail: 'Messages about your requests, quotations, payments and refunds are sent whatever you choose here.',
    // correction / erasure
    fix_1: 'To correct your details, change them on the account page of the portal, or write to management@quotesdone.com.',
    fix_2: 'To have your account and data erased, use "Delete my account and data" on the same page. Nothing is erased for 7 days, and you can cancel in that time.',
    fix_3: 'Invoices, payments and tax records are kept for 5 years, as UAE law requires.',
    emoji: 'emoji', lang_en: 'English', lang_ar: 'Arabic',
  },
  ar: {
    title: 'بياناتكم المحفوظة لدى QuotesDone',
    kicker: 'نسخة من البيانات الشخصية',
    prepared_for: 'أُعدّت من أجل', email: 'البريد الإلكتروني', produced_on: 'أُعدّت في {d}',
    subtitle: 'نسخة من البيانات الشخصية التي تحفظها QuotesDone عنكم، وفق قانون حماية البيانات الشخصية في الإمارات.',
    at_dubai: '{d} بتوقيت دبي',
    controller_h: 'الجهة التي تحفظ بياناتكم',
    controller: 'المتحكم في البيانات هو QuotesDone Technologies، مؤسسة فردية في دبي، رخصة تاجر من دائرة الاقتصاد والسياحة في دبي رقم 1633275، دبي، الإمارات العربية المتحدة. للاستفسار عن بياناتكم: management@quotesdone.com',
    s_account: 'حسابكم', s_company: 'شركتكم', s_requests: 'طلباتكم', s_quotes: 'عروض أسعاركم',
    s_wa: 'رسائل واتساب', s_chat: 'الرسائل في البوابة', s_sent: 'الرسائل الإلكترونية التي أرسلناها إليكم',
    s_recv: 'الرسائل الإلكترونية التي أرسلتموها إلينا', s_pay: 'المدفوعات والمبالغ المستردّة', s_mkt: 'تفضيلات التسويق', s_fix: 'تصحيح بياناتكم أو حذفها',
    none_account: 'لا يوجد لديكم حساب عميل لدينا.', none_company: 'لا نحتفظ بسجلّ شركة باسمكم.',
    none_requests: 'لم تنشروا أي طلب.', none_quotes: 'لم ترسل شركتكم أي عرض سعر.',
    none_wa: 'لا توجد رسائل واتساب بيننا وبينكم.', none_chat: 'لا توجد رسائل في البوابة.',
    none_sent: 'لم نرسل إليكم أي رسالة إلكترونية.', none_recv: 'لم تصلنا منكم أي رسالة إلكترونية.',
    none_pay: 'لا توجد مدفوعات ولا مبالغ مستردّة.',
    wa_note: 'رسائل من رقم موثّق لديكم، منذ يوم فتح حسابكم.',
    not_sent: 'أُعدّت {n} رسالة إلكترونية أخرى باسمكم ولم تُرسل.',
    you: 'أنتم', qd: 'QuotesDone', the_customer: 'العميل', the_supplier: 'المورّد', attached: '(أُرفق ملف.)',
    wa_channel: 'أُرسلت عبر واتساب',
    yes: 'نعم', no: 'لا',
    f_name: 'الاسم', f_email: 'البريد الإلكتروني', f_mobile: 'رقم الجوال', f_mobile_ok: 'توثيق الجوال', f_wa: 'رقم واتساب',
    f_email_ok: 'توثيق البريد الإلكتروني', f_dob: 'تاريخ الميلاد', f_industry: 'القطاع', f_lang: 'اللغة', f_opened: 'تاريخ فتح الحساب',
    f_terms_v: 'إصدار الشروط', f_terms_at: 'تاريخ قبول الشروط', f_terms_ip: 'عنوان IP عند قبول الشروط',
    f_wa_updates: 'تحديثات واتساب', f_suspended: 'الحساب موقوف', f_suspension: 'سبب الإيقاف',
    f_company: 'الشركة', f_registered: 'سجّلتموها بأنفسكم', f_contact: 'اسم جهة التواصل', f_signatory: 'المفوّض بالتوقيع',
    f_login: 'بريد تسجيل الدخول', f_company_email: 'بريد الشركة', f_phone: 'الهاتف', f_web: 'الموقع الإلكتروني', f_address: 'العنوان',
    f_serves: 'الإمارات التي تخدمونها', f_about: 'نبذة عن الشركة', f_products: 'المنتجات', f_services: 'الخدمات',
    f_certs: 'الشهادات', f_licence_no: 'رقم الرخصة التجارية', f_authority: 'جهة إصدار الرخصة',
    f_licence_exp: 'تاريخ انتهاء الرخصة', f_licence_name: 'الاسم في الرخصة', f_trn: 'رقم التسجيل الضريبي',
    f_owner_dob: 'تاريخ ميلاد المالك', f_eid: 'رقم الهوية الإماراتية', f_reg: 'التسجيل', f_reg_exp: 'التسجيل ساري حتى',
    f_approval: 'الاعتماد', f_approved_at: 'تاريخ الاعتماد', f_rejection: 'السبب المذكور', f_docs: 'المستندات التي رفعتموها',
    f_listed: 'مدرجة لدينا منذ', f_source: 'مصدر الإدراج',
    request: 'الطلب', f_created: 'تاريخ النشر', f_status: 'الحالة', f_emirate: 'الإمارة', f_budget: 'الميزانية', f_by: 'مطلوب بحلول',
    f_summary: 'الملخّص', f_wrote: 'ما كتبتموه', quotation_for: 'عرض سعر للطلب{r}', f_sent_on: 'تاريخ الإرسال',
    f_amount: 'المبلغ', f_ex_vat: 'السعر قبل الضريبة', f_vat: 'ضريبة القيمة المضافة', f_lead: 'مدة التنفيذ', f_valid: 'مدة الصلاحية',
    f_terms: 'شروط الدفع', f_warranty: 'الضمان', f_scope: 'نطاق العمل', f_excl: 'الاستثناءات', f_cond: 'الشروط', f_file: 'الملف',
    payment_h: 'كشف هوية المورّد في الطلب{r}', f_revealed: 'تاريخ الكشف', f_quote_amt: 'قيمة العرض', f_fee: 'رسوم الكشف',
    f_total: 'إجمالي المبلغ المدفوع', f_pay: 'الدفع', f_invoice: 'رقم الفاتورة', f_refund: 'الاسترداد', f_refund_amt: 'المبلغ المستردّ',
    invoice_link: 'فتح الفاتورة', refund_h: 'طلب استرداد بتاريخ {d}', f_reason: 'السبب', f_settled: 'تاريخ التسوية',
    receipt_link: 'فتح إيصال الاسترداد',
    reveal_line: 'في {d} كشف عميل هوية شركتكم في عرض السعر للطلب{r}.',
    ack_line: 'أكّدتم استلامه في {d}.',
    refund_on_yours: 'في {d} أُعيدت إلى العميل رسوم الكشف عن أحد عروض أسعاركم ({why}).',
    opted_out: 'ألغيتم الاشتراك في الرسائل التسويقية في {d}.',
    not_opted_out: 'لم تلغوا الاشتراك في الرسائل التسويقية.',
    consent_yes: 'وافقتم على تلقّي الرسائل التسويقية في {d}.', consent_yes_nodate: 'وافقتم على تلقّي الرسائل التسويقية.',
    consent_no: 'لم توافقوا على تلقّي الرسائل التسويقية.',
    service_mail: 'تصلكم الرسائل المتعلّقة بطلباتكم وعروض الأسعار والمدفوعات والمبالغ المستردّة أيًّا كان اختياركم هنا.',
    fix_1: 'لتصحيح بياناتكم، عدّلوها من صفحة الحساب في البوابة، أو راسلونا على management@quotesdone.com.',
    fix_2: 'لحذف حسابكم وبياناتكم، استخدموا زر «حذف حسابي وبياناتي» في الصفحة نفسها. لا يُحذف أي شيء قبل مرور 7 أيام، ويمكنكم الإلغاء خلالها.',
    fix_3: 'تُحفظ الفواتير والمدفوعات والسجلات الضريبية مدة 5 سنوات وفقًا لما يقتضيه القانون في الإمارات.',
    emoji: 'رمز تعبيري', lang_en: 'الإنجليزية', lang_ar: 'العربية',
  },
} as const;
type Key = keyof typeof T.en;
const tr = (lang: Lang, k: Key, v: Record<string, string | number> = {}) =>
  String(T[lang][k]).replace(/\{(\w+)\}/g, (_, n) => String(v[n] ?? ''));

// ── Words for the values the database stores as codes. An unknown code is shown as words, never as a key.
const STATUS: Record<Lang, Record<string, string>> = {
  en: { draft: 'Draft', open: 'Open', submitted: 'Sent', quoted: 'Quotations received', revealed: 'Supplier revealed',
    completed: 'Completed', cancelled: 'Cancelled', canceled: 'Cancelled', expired: 'Expired', lost: 'Closed without a supplier',
    withdrawn: 'Withdrawn', paid: 'Paid', pending: 'Pending', succeeded: 'Refunded', refunded: 'Refunded', requested: 'Requested',
    rejected: 'Not approved', approved: 'Approved', exempt: 'Free (one of our first suppliers)', unpaid: 'Unpaid', active: 'Active',
    in: 'On', out: 'Off', yes: 'On', no: 'Off', on: 'On', off: 'Off', supplier_non_response: 'the supplier did not respond' },
  ar: { draft: 'مسودّة', open: 'مفتوح', submitted: 'مُرسل', quoted: 'وصلت عروض أسعار', revealed: 'كُشفت هوية المورّد',
    completed: 'مكتمل', cancelled: 'ملغى', canceled: 'ملغى', expired: 'منتهي الصلاحية', lost: 'أُغلق دون اختيار مورّد',
    withdrawn: 'مسحوب', paid: 'مدفوع', pending: 'قيد الانتظار', succeeded: 'تمّ الاسترداد', refunded: 'تمّ الاسترداد', requested: 'مطلوب',
    rejected: 'غير معتمد', approved: 'معتمد', exempt: 'مجاني (من أوائل المورّدين)', unpaid: 'غير مدفوع', active: 'نشط',
    in: 'مفعّل', out: 'غير مفعّل', yes: 'مفعّل', no: 'غير مفعّل', on: 'مفعّل', off: 'غير مفعّل', supplier_non_response: 'لم يردّ المورّد' },
};
export function words(lang: Lang, code: unknown): string {
  const s = String(code ?? '').trim(); if (!s) return '';
  const hit = STATUS[lang][s.toLowerCase()]; if (hit) return hit;
  const plain = s.replace(/[_-]+/g, ' ').toLowerCase();
  return plain.charAt(0).toUpperCase() + plain.slice(1);
}

// ── Dubai time, written out. The UAE keeps no daylight saving, so Asia/Dubai is UTC+4 all year.
export function dubaiDateTime(iso: unknown, lang: Lang): string {
  const d = new Date(String(iso ?? '')); if (!iso || isNaN(d.getTime())) return '';
  const loc = lang === 'ar' ? 'ar-AE-u-nu-latn' : 'en-GB';
  const date = d.toLocaleDateString(loc, { timeZone: 'Asia/Dubai', day: 'numeric', month: 'long', year: 'numeric' });
  const time = d.toLocaleTimeString(loc, { timeZone: 'Asia/Dubai', hour: 'numeric', minute: '2-digit', hour12: true });
  return lang === 'ar' ? `${date}، الساعة ${time}` : `${date} at ${time}`;
}
export function dubaiDate(iso: unknown, lang: Lang): string {
  const s = String(iso ?? ''); if (!s) return '';
  // a bare date (YYYY-MM-DD) is a calendar day, not an instant: never shifted by a time zone
  const d = /^\d{4}-\d{2}-\d{2}$/.test(s) ? new Date(s + 'T12:00:00+04:00') : new Date(s); if (isNaN(d.getTime())) return '';
  return d.toLocaleDateString(lang === 'ar' ? 'ar-AE-u-nu-latn' : 'en-GB', { timeZone: 'Asia/Dubai', day: 'numeric', month: 'long', year: 'numeric' });
}
const money = (v: unknown) => { const n = Number(v); return v == null || v === '' || !isFinite(n) ? '' : 'AED ' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };

// ── Emoji. The brand fonts (Sora, the Arabic face) carry none, and the renderer drops a glyph it cannot draw. A
// dropped emoji changes what a person said ("Hi 👋" would print as "Hi"), so each is named in words instead.
const EMOJI: Record<string, [string, string]> = {
  '👋': ['waving hand', 'يد تلوّح'], '😊': ['smiling face', 'وجه مبتسم'], '🙂': ['smiling face', 'وجه مبتسم'], '😀': ['grinning face', 'وجه ضاحك'],
  '😃': ['grinning face', 'وجه ضاحك'], '😄': ['grinning face', 'وجه ضاحك'], '😁': ['grinning face', 'وجه ضاحك'], '😂': ['tears of joy', 'دموع الفرح'],
  '👍': ['thumbs up', 'إبهام مرفوع'], '👌': ['OK hand', 'علامة موافقة'], '🙏': ['folded hands', 'يدان مضمومتان'], '✅': ['check mark', 'علامة صح'],
  '✔': ['check mark', 'علامة صح'], '❤': ['heart', 'قلب'], '🎉': ['party popper', 'احتفال'], '⭐': ['star', 'نجمة'], '🌟': ['star', 'نجمة'],
  '📄': ['document', 'مستند'], '📎': ['paperclip', 'مشبك ورق'], '📞': ['telephone', 'هاتف'], '📧': ['e-mail', 'بريد إلكتروني'],
  '🔒': ['lock', 'قفل'], '👉': ['pointing right', 'إشارة'], '👇': ['pointing down', 'إشارة'], '☺': ['smiling face', 'وجه مبتسم'],
  '🤝': ['handshake', 'مصافحة'], '💰': ['money bag', 'كيس نقود'], '🏗': ['construction', 'إنشاءات'], '🚚': ['delivery truck', 'شاحنة توصيل'],
};
const EMOJI_RE = /(?:\p{Regional_Indicator}{2}|\p{Extended_Pictographic}(?:\u{FE0F}|\p{Emoji_Modifier}|\u{200D}\p{Extended_Pictographic}\u{FE0F}?)*)/gu;
export function nameEmoji(s: string, lang: Lang): string {
  return s.replace(EMOJI_RE, (m) => {
    if (/^[©®™‼⁉]$/.test(m)) return m; // ©, ®, ™, ‼, ⁉: text symbols the renderer handles
    const base = [...m][0];
    const n = EMOJI[base]?.[lang === 'ar' ? 1 : 0];
    return n ? `[${n}]` : `[${tr(lang, 'emoji')}]`;
  }).replace(/[\u{FE0F}\u{200D}]/gu, '');
}

/** A stored text as the person wrote it: real line breaks (an escaped "\n" from an older writer is one too), named emoji. */
export function clean(v: unknown, lang: Lang): string {
  if (v == null) return '';
  const s = typeof v === 'string' ? v : String(v);
  return nameEmoji(s.replace(/\\r\\n|\\n/g, '\n').replace(/\r\n?/g, '\n'), lang).replace(/[ \t]+\n/g, '\n').trim();
}
/** " 123" for a request reference, "" when there is none, so a sentence never reads "request ." */
const ref = (v: unknown) => (v == null || v === '' ? '' : ' ' + String(v));
const pick = (r: Rec, ...ks: string[]) => { for (const k of ks) { const v = r?.[k]; if (v !== undefined && v !== null && v !== '') return v; } return undefined; };
const list = (v: unknown): Rec[] => (Array.isArray(v) ? v.filter((x) => x && typeof x === 'object') : []);

type Kind = 'text' | 'date' | 'when' | 'bool' | 'status' | 'list' | 'money' | 'lang' | 'long';
type Field = [Key, string[], Kind];

function value(lang: Lang, v: unknown, kind: Kind): string {
  if (v === undefined || v === null || v === '') return '';
  switch (kind) {
    case 'date': return dubaiDate(v, lang);
    case 'when': return dubaiDateTime(v, lang);
    case 'bool': return v === true || v === 'true' ? tr(lang, 'yes') : v === false || v === 'false' ? tr(lang, 'no') : '';
    case 'status': return words(lang, v);
    case 'money': return money(v);
    case 'lang': return /^ar/i.test(String(v)) ? tr(lang, 'lang_ar') : /^en/i.test(String(v)) ? tr(lang, 'lang_en') : String(v);
    case 'list': return (Array.isArray(v) ? v : String(v).split(/\s*[,;]\s*/)).map((x) => clean(x, lang)).filter(Boolean).join(', ');
    default: return clean(v, lang);
  }
}

/** Named fields as a two-column key/value block, and the long ones as labelled paragraphs beneath it. */
function fieldsBlocks(lang: Lang, r: Rec, fields: Field[]): Block[] {
  const pairs: [string, string][] = []; const long: Block[] = [];
  for (const [label, keys, kind] of fields) {
    const v = value(lang, pick(r, ...keys), kind); if (!v) continue;
    if (kind === 'long' || v.length > 60 || v.includes('\n')) long.push({ t: 'p', label: tr(lang, label), text: v, lines: true });
    else pairs.push([tr(lang, label), v]);
  }
  return [...(pairs.length ? [{ t: 'kv', pairs }] : []), ...long];
}

const ACCOUNT: Field[] = [
  ['f_name', ['full_name'], 'text'], ['f_email', ['email'], 'text'], ['f_mobile', ['mobile', 'phone'], 'text'],
  ['f_mobile_ok', ['mobile_verified', 'phone_verified'], 'bool'], ['f_wa', ['whatsapp_number', 'whatsapp_phone'], 'text'],
  ['f_email_ok', ['email_verified'], 'bool'], ['f_dob', ['date_of_birth'], 'date'], ['f_industry', ['industry'], 'text'],
  ['f_lang', ['language', 'locale'], 'lang'], ['f_opened', ['opened_at', 'created_at'], 'when'],
  ['f_terms_v', ['terms_version', 'tos_version'], 'text'], ['f_terms_at', ['terms_accepted_at', 'tos_accepted_at'], 'when'],
  ['f_terms_ip', ['terms_accepted_from_ip', 'tos_ip'], 'text'], ['f_wa_updates', ['whatsapp_updates', 'whatsapp_opt'], 'status'],
];
const COMPANY: Field[] = [
  ['f_company', ['company_name'], 'text'], ['f_contact', ['contact_name'], 'text'], ['f_signatory', ['signatory_name'], 'text'],
  ['f_login', ['login_email', 'claimed_by'], 'text'], ['f_company_email', ['company_email', 'email'], 'text'],
  ['f_phone', ['phone', 'phone_e164'], 'text'], ['f_wa', ['whatsapp_number', 'whatsapp_phone'], 'text'], ['f_web', ['website'], 'text'],
  ['f_address', ['_address'], 'text'], ['f_serves', ['service_emirates'], 'list'],
  ['f_licence_no', ['trade_licence_number', 'trade_license_no'], 'text'], ['f_authority', ['licence_authority', 'license_authority'], 'text'],
  ['f_licence_exp', ['licence_expiry', 'license_expiry'], 'date'], ['f_licence_name', ['licence_name', 'licence_legal_name'], 'text'],
  ['f_trn', ['trn', 'vat_number'], 'text'], ['f_owner_dob', ['owner_date_of_birth', 'owner_dob'], 'date'], ['f_eid', ['emirates_id'], 'text'],
  ['f_reg', ['registration', 'registration_status'], 'status'], ['f_reg_exp', ['registration_expires', 'registration_expires_at'], 'date'],
  ['f_approval', ['approval', 'approval_status'], 'status'], ['f_approved_at', ['approved_at'], 'date'],
  ['f_terms_v', ['terms_version', 'accepted_terms_version'], 'text'], ['f_terms_at', ['terms_accepted_at', 'accepted_terms_at'], 'when'],
  ['f_terms_ip', ['terms_accepted_from_ip', 'accepted_terms_ip'], 'text'], ['f_docs', ['documents', '_docs'], 'list'],
  ['f_listed', ['listed_since', 'created_at'], 'date'], ['f_source', ['where_we_found_the_listing', 'source'], 'status'],
  ['f_wa_updates', ['whatsapp_updates', 'whatsapp_opt'], 'status'],
  ['f_rejection', ['rejection_reason'], 'long'], ['f_about', ['description'], 'long'], ['f_products', ['products'], 'long'],
  ['f_services', ['services'], 'long'], ['f_certs', ['certifications'], 'long'],
];
const SUSPENSION: Field[] = [['f_suspended', ['suspended', 'banned'], 'bool'], ['f_suspension', ['suspension_reason', 'banned_reason'], 'long']];

function section(lang: Lang, k: Key, body: Block[], none: Key | null): Block[] {
  if (!body.length && !none) return [];
  return [{ t: 'h2', text: tr(lang, k) }, ...(body.length ? body : [{ t: 'p', text: tr(lang, none as Key), muted: true }])];
}
/** One message: who and when on a small line, then the text with its own line breaks. */
const msg = (who: string, at: unknown, text: string, lang: Lang, extra = ''): Block =>
  // Arabic puts the date first: a Latin speaker ("QuotesDone") followed by a date that starts with a digit is one
  // left-to-right run to the bidi algorithm, and the day number was drawn on the wrong side of the name (sample render).
  ({ t: 'p', label: (lang === 'ar' ? [dubaiDateTime(at, lang), who] : [who, dubaiDateTime(at, lang)]).filter(Boolean).join(' · '),
     text: [text, extra].filter(Boolean).join('\n'), lines: true });

export type CopyInput = { exp: Rec; lang: Lang; role: Role };
export type CopyBody = { title: string; lang: Lang; cover: Rec; blocks: Block[]; options: Rec };

export function dataCopyBody({ exp, lang: langIn, role }: CopyInput): CopyBody {
  // Suppliers are written to in English on every channel (standing rule, ledger 1008).
  const lang: Lang = role === 'supplier' ? 'en' : langIn === 'ar' ? 'ar' : 'en';
  const accounts = list(exp.customer_accounts), companies = list(exp.supplier_records);
  const name = clean(role === 'supplier' ? pick(companies[0] ?? {}, 'company_name') ?? pick(accounts[0] ?? {}, 'full_name')
    : pick(accounts[0] ?? {}, 'full_name') ?? pick(companies[0] ?? {}, 'contact_name'), lang);
  const email = clean(exp.email, lang);
  const produced = tr(lang, 'at_dubai', { d: dubaiDateTime(exp.generated_at || new Date().toISOString(), lang) });
  const blocks: Block[] = [];

  blocks.push({ t: 'p', text: tr(lang, 'subtitle') });
  blocks.push({ t: 'callout', tone: 'grey', title: tr(lang, 'controller_h'), text: tr(lang, 'controller') });

  // Account and company. The section that belongs to the portal he pressed it in is always there (with one line when
  // empty); the other appears only when he has one.
  const acct = accounts.flatMap((a) => [...fieldsBlocks(lang, a, ACCOUNT), ...(a.suspended || a.banned ? fieldsBlocks(lang, a, SUSPENSION) : [])]);
  const comp = companies.flatMap((c, i) => {
    const addr = [c.street, c.city, c.emirate].map((x) => clean(x, lang)).filter(Boolean).join(', ');
    const docs = c.documents ?? [c.license_doc_name, c.egr_doc_name].filter(Boolean);
    const r = { ...c, _address: addr, _docs: docs };
    return [...(companies.length > 1 ? [{ t: 'h3', text: clean(c.company_name, lang) || tr(lang, 'f_company') + ' ' + (i + 1) }] : []),
      ...fieldsBlocks(lang, r, COMPANY), ...(c.suspended || c.banned ? fieldsBlocks(lang, c, SUSPENSION) : [])];
  });
  if (role === 'supplier') { blocks.push(...section(lang, 's_company', comp, 'none_company'), ...section(lang, 's_account', acct, null)); }
  else { blocks.push(...section(lang, 's_account', acct, 'none_account'), ...section(lang, 's_company', comp, null)); }

  // Requests (a customer's)
  const reqs = list(exp.requests).flatMap((q) => {
    const ref = q.reference != null ? String(q.reference) : '';
    return [{ t: 'h3', text: [tr(lang, 'request') + (ref ? ' ' + ref : ''), clean(q.category, lang)].filter(Boolean).join(': ') },
      ...fieldsBlocks(lang, q, [['f_created', ['created_at'], 'when'], ['f_status', ['status'], 'status'], ['f_emirate', ['emirate'], 'text'],
        ['f_budget', ['budget'], 'text'], ['f_by', ['required_by'], 'date'], ['f_summary', ['summary'], 'long'], ['f_wrote', ['what_you_wrote'], 'long']])];
  });
  if (role === 'customer' || reqs.length) blocks.push(...section(lang, 's_requests', reqs, 'none_requests'));

  // Quotations (a supplier's). Shown only when the routine returns them: saying "none" for a list it does not
  // return would be false (the routine before 12 Nov 2026 returned no quotations at all).
  if (Array.isArray(exp.quotations)) {
    const qs = list(exp.quotations).flatMap((q) => [{ t: 'h3', text: tr(lang, 'quotation_for', { r: ref(q.request_reference) }) + (q.category ? ': ' + clean(q.category, lang) : '') },
      ...fieldsBlocks(lang, q, [['f_sent_on', ['created_at'], 'when'], ['f_status', ['status'], 'status'], ['f_amount', ['amount_aed'], 'money'],
        ['f_ex_vat', ['price_ex_vat_aed'], 'money'], ['f_vat', ['vat_aed'], 'money'], ['f_lead', ['lead_time'], 'text'], ['f_valid', ['validity'], 'text'],
        ['f_terms', ['payment_terms'], 'text'], ['f_warranty', ['warranty'], 'text'], ['f_file', ['file_name'], 'text'],
        ['f_scope', ['scope'], 'long'], ['f_excl', ['exclusions'], 'long'], ['f_cond', ['conditions'], 'long']])]);
    if (role === 'supplier' || qs.length) blocks.push(...section(lang, 's_quotes', qs, 'none_quotes'));
  }

  // WhatsApp
  const wa = list(exp.whatsapp).flatMap((w) => [
    ...(clean(w.received, lang) ? [msg(tr(lang, 'you'), w.at, clean(w.received, lang), lang)] : []),
    ...(clean(w.replied, lang) ? [msg(tr(lang, 'qd'), w.replied_at ?? w.at, clean(w.replied, lang), lang)] : []),
  ]);
  blocks.push(...section(lang, 's_wa', wa.length ? [{ t: 'note', text: tr(lang, 'wa_note') }, ...wa] : [], 'none_wa'));

  // Portal messages: delivered ones only (the routine before 12 Nov 2026 did not filter blocked ones out).
  const other = role === 'supplier' ? tr(lang, 'the_customer') : tr(lang, 'the_supplier');
  const chat = list(exp.portal_chat).filter((m) => m.blocked !== true).map((m) =>
    msg(String(m.from || '') === role ? tr(lang, 'you') : String(m.from || '') === 'support' ? tr(lang, 'qd') : other, m.at, clean(m.text, lang), lang,
      m.attachment ? tr(lang, 'attached') : ''));
  blocks.push(...section(lang, 's_chat', chat, 'none_chat'));

  // E-mails we sent: sent ones only; the rest counted.
  const all = list(exp.emails_we_sent);
  const sent = all.filter((n) => n.status == null || n.status === 'sent');
  const notSent = (all.length - sent.length) + (Number(exp.emails_not_sent) || 0);
  const mails = sent.flatMap((n) => [
    { t: 'p', label: [dubaiDateTime(n.at, lang), n.channel === 'whatsapp' ? tr(lang, 'wa_channel') : ''].filter(Boolean).join(' · '),
      text: clean(n.subject, lang) || '—', bold: true },
    ...(clean(n.text, lang) ? [{ t: 'p', text: clean(n.text, lang), lines: true, size: 9 }] : []),
    { t: 'space', h: 4 },
  ]);
  blocks.push(...section(lang, 's_sent', [...mails, ...(notSent > 0 ? [{ t: 'note', text: tr(lang, 'not_sent', { n: notSent }) }] : [])], 'none_sent'));

  const recv = list(exp.emails_we_received).flatMap((n) => [
    { t: 'p', label: dubaiDateTime(n.at, lang), text: clean(n.subject, lang) || '—', bold: true },
    ...(clean(n.text, lang) ? [{ t: 'p', text: clean(n.text, lang), lines: true, size: 9 }] : []),
  ]);
  if (recv.length) blocks.push(...section(lang, 's_recv', recv, null));

  // Payments and refunds
  const pay: Block[] = [];
  if (role === 'customer') {
    for (const t of list(exp.transactions)) {
      pay.push({ t: 'h3', text: tr(lang, 'payment_h', { r: ref(t.request_reference) }) });
      pay.push(...fieldsBlocks(lang, t, [['f_revealed', ['revealed_at'], 'when'], ['f_quote_amt', ['quotation_aed', 'quote_amount'], 'money'],
        ['f_fee', ['reveal_fee_aed', 'reveal_fee'], 'money'], ['f_total', ['total_charged_aed', 'total_charged'], 'money'],
        ['f_pay', ['payment', 'fee_status'], 'status'], ['f_invoice', ['invoice_number', 'stripe_invoice_number'], 'text'],
        ['f_refund', ['refund', 'refund_status'], 'status'], ['f_refund_amt', ['refund_aed', 'refund_amount_aed'], 'money']]));
      const link = pick(t, 'invoice_link', 'stripe_invoice_hosted_url');
      if (typeof link === 'string' && /^https:\/\//.test(link)) pay.push({ t: 'link', text: tr(lang, 'invoice_link'), link });
    }
    for (const r of list(exp.refunds).filter((r) => !r.on_your_quotation)) {
      pay.push({ t: 'h3', text: tr(lang, 'refund_h', { d: dubaiDate(pick(r, 'requested_at', 'created_at'), lang) }) });
      const amt = r.amount_aed ?? (r.amount_fils != null ? Number(r.amount_fils) / 100 : undefined);
      pay.push(...fieldsBlocks(lang, { ...r, _amt: amt }, [['f_refund_amt', ['_amt'], 'money'], ['f_status', ['status'], 'status'],
        ['f_reason', ['reason', 'reason_code'], 'status'], ['f_settled', ['settled_at'], 'when']]));
      const link = pick(r, 'receipt_link', 'stripe_receipt_url');
      if (typeof link === 'string' && /^https:\/\//.test(link)) pay.push({ t: 'link', text: tr(lang, 'receipt_link'), link });
    }
  } else {
    // A supplier: the date his quotation was revealed, never the customer's payment. Before 12 Nov 2026 the routine
    // returned the customer's whole transaction row here; only its date is read.
    const reveals = Array.isArray(exp.reveals) ? list(exp.reveals) : list(exp.transactions).filter((t) => t.revealed_at);
    for (const v of reveals) {
      pay.push({ t: 'p', text: tr(lang, 'reveal_line', { d: dubaiDate(v.revealed_at, lang), r: ref(v.request_reference) }) });
      const ack = pick(v, 'you_acknowledged_at', 'supplier_ack_at');
      if (ack) pay.push({ t: 'note', text: tr(lang, 'ack_line', { d: dubaiDate(ack, lang) }) });
    }
    for (const r of list(exp.refunds)) {
      pay.push({ t: 'p', text: tr(lang, 'refund_on_yours', { d: dubaiDate(pick(r, 'requested_at', 'created_at'), lang), why: words(lang, pick(r, 'reason', 'reason_code') ?? 'refunds') }) });
    }
  }
  blocks.push(...section(lang, 's_pay', pay, 'none_pay'));

  // Marketing preferences, in words
  const mk: Block[] = [];
  const oo = exp.opt_out && typeof exp.opt_out === 'object' ? exp.opt_out : null;
  mk.push({ t: 'p', text: oo ? tr(lang, 'opted_out', { d: dubaiDate(pick(oo, 'at', 'created_at'), lang) }) : tr(lang, 'not_opted_out') });
  const consentRec = [...accounts, ...companies].find((r) => r.marketing_consent === true || r.marketing_consent === false);
  if (consentRec) {
    mk.push({ t: 'p', text: consentRec.marketing_consent
      ? (consentRec.marketing_consent_at ? tr(lang, 'consent_yes', { d: dubaiDate(consentRec.marketing_consent_at, lang) }) : tr(lang, 'consent_yes_nodate'))
      : tr(lang, 'consent_no') });
  }
  mk.push({ t: 'note', text: tr(lang, 'service_mail') });
  blocks.push(...section(lang, 's_mkt', mk, null));

  blocks.push(...section(lang, 's_fix', [{ t: 'p', text: tr(lang, 'fix_1') }, { t: 'p', text: tr(lang, 'fix_2') }, { t: 'note', text: tr(lang, 'fix_3') }], null));

  return {
    title: tr(lang, 'title'), lang,
    // The cover band prints one subtitle line and the first line of each meta value, so each is kept short enough to
    // fit (measured on the sample renders, 12 Nov 2026: three meta cells cut the e-mail and the time).
    cover: { compact: true, kicker: tr(lang, 'kicker'), title: tr(lang, 'title'), subtitle: tr(lang, 'produced_on', { d: produced }),
      meta: [[tr(lang, 'prepared_for'), name || email], [tr(lang, 'email'), email]] },
    blocks,
    // The letterhead and footer of every document we issue; no signature or stamp (nothing here is attested).
    options: { letterhead: true, strict_glyphs: false },
  };
}

/** The file name a person saves: QuotesDone-my-data-YYYY-MM-DD.pdf, the date in Dubai. */
export function fileName(now = new Date()): string {
  const d = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Dubai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  return `QuotesDone-my-data-${d}.pdf`;
}
