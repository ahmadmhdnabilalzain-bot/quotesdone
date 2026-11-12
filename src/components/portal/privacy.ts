// SELF-SERVICE PRIVACY: the copy, the answer-reading and the remembered erase request behind
// PrivacyControls.tsx (sales_engineer, 7 Oct 2026). Kept free of React so the branches that decide what a
// person is told about their own data run under `node --test` (privacy.test.mjs).
//
// THE CONTRACT IS THE ONE #1237 SHIPPED (scripts/sql/a_person_can_get_a_copy_of_their_data_and_have_it_
// erased_where_no_law_requires_it_kept.sql), read, not guessed:
//   pdpl_request_me('export')        -> { ok, request_id, export }               no code: the signed-in session
//                                                                                 plus a verified email IS the check
//   pdpl_request_me('delete')        -> { ok, request_id, code_sent_to }        a 6-digit code is emailed
//   pdpl_confirm_me(request, code)   -> { ok, status:'cooling_off', confirm_after, plan:{ erase_now, deferred[] } }
//                                       or { ok:false, error, attempts_left? } / { ok:false, code:'not_yours' }
//   pdpl_cancel_me(request)          -> { ok } or { ok:false, error:'no erasure in its cooling-off window' }
//   pdpl_status_me()                 -> { ok, requests:[{ request_id, kind, status, confirm_after, deferred }] }  (#1273)
//   any of them, unverified email    -> { ok:false, code:'email_not_verified' }
// The PDF copy (12 Nov 2026) is drawn by the edge function my_data_pdf from the same export, as the same person:
//   POST functions/v1/my_data_pdf { lang, role } -> 200 application/pdf (attachment, no-store)
//                                                  or { ok:false, code } / { error } with a 4xx/5xx status
// The JSON button keeps calling pdpl_request_me('export') itself: the policy's data-portability promise.
// pdpl_status_me (#1273) reads the open requests on any device, so Cancel shows wherever the person signs in.

export type Lang = 'en' | 'ar';
export type Deferred = { record?: string; legal_hold?: boolean; kept_until?: string; reason?: string };
export type Pending = { id: string; confirm_after: string; deferred: Deferred[] };

export const STORE_KEY = 'qd-pdpl-erase';

const EN = {
  h: 'Your data',
  sub: 'Get a copy of the personal data we hold for you, or ask us to erase it.',
  // the policy these controls carry out, linked from inside both portals (website audit 10 Nov 2026)
  policy: 'Read our Privacy Policy',
  exp_h: 'Download my data',
  // 12 Nov 2026 (founder ledgers 1669, 1671): the copy is a PDF in our document template, made by my_data_pdf.
  exp_p: 'A PDF with your account details, requests, quotations, WhatsApp and portal messages, the e-mails we sent you, and your payments, refunds and marketing choices.',
  exp_btn: 'Download my data (PDF)',
  exp_busy: 'Preparing your PDF…',
  exp_done: 'Your PDF is ready.',
  exp_open: 'Open your PDF',
  exp_tap: 'Your PDF is ready. Tap "Open your PDF" to view it, then Share to save it to Files.',
  exp_retry: 'Try again',
  json_btn: 'Download the data file (JSON)',
  json_p: 'The same data in a machine-readable file, if you want to move it to another service.',
  json_busy: 'Preparing the file…',
  json_done: 'Your data file is ready.',
  del_h: 'Delete my account and data',
  del_warn_h: 'Before you continue',
  del_warn: [
    'Your contact details are removed and we stop all marketing to you.',
    'Invoices, payments and tax records are kept for 5 years, as UAE law requires.',
    'Anything linked to an open dispute, refund or unpaid amount is kept until it is settled.',
    'Nothing is erased for 7 days. You can cancel at any time in that window.',
  ],
  del_ack: 'I understand what is removed and what is kept.',
  del_btn: 'Email me a code',
  del_busy: 'Sending…',
  code_sent: 'We sent a 6-digit code to {email}. It expires in 24 hours.',
  code_label: 'Confirmation code',
  confirm_btn: 'Confirm deletion',
  confirm_busy: 'Confirming…',
  sched: 'Deletion scheduled for {date}. You can cancel any time before then.',
  kept_h: 'What we keep, and why',
  kept_law: 'Kept until {date}: records the law requires us to keep.',
  kept_hold: 'On hold: {what} is linked to an open dispute, refund, complaint or unpaid amount. It is kept until that is settled.',
  rec_customer: 'your customer account',
  rec_supplier: 'your supplier record',
  cancel_btn: 'Cancel deletion',
  cancel_busy: 'Cancelling…',
  cancelled: 'Deletion cancelled. Your account stays as it was.',
  e_unverified: 'Verify your email address in your account first.',
  e_wrong: 'That code is wrong or has expired. {n} tries left.',
  e_spent: 'That code can no longer be used. Ask for a new one.',
  e_many: 'Too many attempts. Try again in an hour.',
  e_window: 'This deletion can no longer be cancelled.',
  e_generic: 'Something went wrong. Please try again.',
  e_too_many: 'You asked for your data several times just now. Please try again in 10 minutes.',
};
type Key = keyof typeof EN;

const AR: Record<Key, string | string[]> = {
  h: 'بياناتكم',
  sub: 'احصلوا على نسخة من بياناتكم الشخصية المحفوظة لدينا، أو اطلبوا حذفها.',
  policy: 'اطّلعوا على سياسة الخصوصية',
  exp_h: 'تنزيل بياناتي',
  exp_p: 'ملف PDF يتضمّن بيانات حسابكم وطلباتكم وعروض الأسعار ورسائل واتساب والبوابة والرسائل الإلكترونية التي أرسلناها إليكم ومدفوعاتكم والمبالغ المستردّة وتفضيلات التسويق.',
  exp_btn: 'تنزيل بياناتي (PDF)',
  exp_busy: 'جارٍ تجهيز ملف PDF…',
  exp_done: 'ملف PDF جاهز.',
  exp_open: 'فتح ملف PDF',
  exp_tap: 'ملف PDF جاهز. اضغطوا «فتح ملف PDF» لعرضه، ثم «مشاركة» لحفظه في «الملفات».',
  exp_retry: 'إعادة المحاولة',
  json_btn: 'تنزيل ملف البيانات (JSON)',
  json_p: 'البيانات نفسها في ملف تقرؤه الأنظمة، إن أردتم نقلها إلى خدمة أخرى.',
  json_busy: 'جارٍ تجهيز الملف…',
  json_done: 'ملف البيانات جاهز.',
  del_h: 'حذف حسابي وبياناتي',
  del_warn_h: 'قبل المتابعة',
  del_warn: [
    'نحذف بيانات التواصل معكم، ونتوقّف عن إرسال أي رسائل تسويقية إليكم.',
    'تُحفظ الفواتير والمدفوعات والسجلات الضريبية مدة 5 سنوات وفقًا لما يقتضيه القانون في الإمارات.',
    'يُحفظ كل ما يتعلّق بنزاع قائم أو استرداد أو مبلغ غير مسدَّد إلى حين تسويته.',
    'لا يُحذف أي شيء قبل مرور 7 أيام، ويمكنكم الإلغاء في أي وقت خلالها.',
  ],
  del_ack: 'أدرك ما سيُحذف وما سيُحفظ.',
  del_btn: 'أرسلوا لي رمزًا',
  del_busy: 'جارٍ الإرسال…',
  code_sent: 'أرسلنا رمزًا من 6 أرقام إلى {email}، وتنتهي صلاحيته خلال 24 ساعة.',
  code_label: 'رمز التأكيد',
  confirm_btn: 'تأكيد الحذف',
  confirm_busy: 'جارٍ التأكيد…',
  sched: 'سيُنفَّذ الحذف في {date}، ويمكنكم الإلغاء في أي وقت قبل ذلك.',
  kept_h: 'ما نحتفظ به وسببه',
  kept_law: 'يُحفظ حتى {date}: سجلات يُلزمنا القانون بالاحتفاظ بها.',
  kept_hold: 'محفوظ مؤقتًا: {what} مرتبط بنزاع قائم أو استرداد أو شكوى أو مبلغ غير مسدَّد، ويبقى محفوظًا إلى حين تسويته.',
  rec_customer: 'حسابكم بصفتكم عميلًا',
  rec_supplier: 'سجلّكم بصفتكم مورّدًا',
  cancel_btn: 'إلغاء الحذف',
  cancel_busy: 'جارٍ الإلغاء…',
  cancelled: 'أُلغي الحذف، ويبقى حسابكم كما كان.',
  e_unverified: 'يُرجى توثيق بريدكم الإلكتروني في حسابكم أولًا.',
  e_wrong: 'الرمز غير صحيح أو انتهت صلاحيته. المحاولات المتبقية: {n}.',
  e_spent: 'لم يعد بالإمكان استخدام هذا الرمز، يُرجى طلب رمز جديد.',
  e_many: 'محاولات كثيرة. يُرجى المحاولة مجددًا بعد ساعة.',
  e_window: 'لم يعد بالإمكان إلغاء هذا الحذف.',
  e_generic: 'حدث خطأ ما. يُرجى المحاولة مجددًا.',
  e_too_many: 'طلبتم بياناتكم عدّة مرات قبل قليل، يُرجى المحاولة مجددًا بعد 10 دقائق.',
};

export function pt(lang: Lang, k: Key, vars: Record<string, string | number> = {}): string {
  const v = (lang === 'ar' ? AR[k] : EN[k]) as string;
  return String(v).replace(/\{(\w+)\}/g, (_, n) => String(vars[n] ?? ''));
}
export function ptList(lang: Lang, k: 'del_warn'): string[] {
  return (lang === 'ar' ? AR[k] : EN[k]) as string[];
}

export function fmtDate(lang: Lang, iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
}

/** The person-facing sentence for a refusal. Server wording is never shown raw: it is English only. */
export function errorText(lang: Lang, j: Record<string, unknown> | null | undefined): string {
  if (!j) return pt(lang, 'e_generic');
  if (j.code === 'email_not_verified') return pt(lang, 'e_unverified');
  if (j.code === 'too_many_exports') return pt(lang, 'e_too_many');
  const e = String(j.error || '');
  if (/wrong or expired/.test(e)) return pt(lang, 'e_wrong', { n: Number(j.attempts_left ?? 0) });
  if (/spent|no open request/.test(e)) return pt(lang, 'e_spent');
  if (/too many/.test(e)) return pt(lang, 'e_many');
  if (/cooling-off window/.test(e)) return pt(lang, 'e_window');
  return pt(lang, 'e_generic');
}

/** One line per record the erase could not remove, in the reader's language. */
export function keptLines(lang: Lang, deferred: Deferred[]): string[] {
  return (deferred || []).map((d) => {
    const what = pt(lang, String(d.record || '').startsWith('supplier') ? 'rec_supplier' : 'rec_customer');
    return d.legal_hold ? pt(lang, 'kept_hold', { what }) : pt(lang, 'kept_law', { date: fmtDate(lang, String(d.kept_until || '')) });
  });
}

/** The confirmed erase, from pdpl_confirm_me's answer; null when it did not schedule one. */
export function pendingFrom(requestId: string, j: Record<string, any> | null | undefined): Pending | null {
  if (!j || j.ok !== true || j.status !== 'cooling_off' || !j.confirm_after) return null;
  return { id: String(j.request_id || requestId), confirm_after: String(j.confirm_after), deferred: Array.isArray(j.plan?.deferred) ? j.plan.deferred : [] };
}

/** A remembered erase is shown only while it can still be cancelled. */
export function livePending(raw: string | null, now = Date.now()): Pending | null {
  try {
    const p = raw ? JSON.parse(raw) : null;
    return p && p.id && Date.parse(p.confirm_after) > now ? p : null;
  } catch { return null; }
}

/** The open erase from pdpl_status_me; undefined = the routine could not answer (keep the local one). */
export function pendingFromStatus(j: Record<string, any> | null | undefined, now = Date.now()): Pending | null | undefined {
  if (!j || j.ok !== true || !Array.isArray(j.requests)) return undefined;
  const q = j.requests.find((r: any) => r.kind === 'delete' && r.status === 'cooling_off' && Date.parse(r.confirm_after) > now);
  return q ? { id: String(q.request_id), confirm_after: String(q.confirm_after), deferred: Array.isArray(q.deferred) ? q.deferred : [] } : null;
}

export const isCode = (s: string) => /^\d{6}$/.test(s.trim());

/** The name the server gave the PDF (Content-Disposition), or one in the same form for today in Dubai. */
export function pdfName(contentDisposition: string | null, now = new Date()): string {
  const m = /filename="([^"]+\.pdf)"/i.exec(contentDisposition || '');
  if (m && /^[\w.-]+$/.test(m[1])) return m[1];
  const d = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Dubai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  return `QuotesDone-my-data-${d}.pdf`;
}

/** The machine-readable copy: UTF-8 text with no byte-order mark. The Blob that carries it declares the charset
 * (application/json;charset=utf-8): without it Safari read the bytes as Latin-1 and an emoji became "ðŸ'‹". */
export function jsonFileText(exp: unknown): string {
  return JSON.stringify(exp, null, 2) + '\n';
}
export const JSON_TYPE = 'application/json;charset=utf-8';

/** An iPhone, an iPad, or an iPad that says it is a Mac (iPadOS 13+ sends a desktop user agent but has touch points). */
export function isAppleTouch(ua: string, maxTouchPoints: number): boolean {
  return /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && maxTouchPoints > 1);
}
