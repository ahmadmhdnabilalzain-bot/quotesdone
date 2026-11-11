import { arDuration } from '../../_shared/quote_documents.ts';
import { type Review, type WLine, type Working } from './types.ts';
import { fmt } from './review.ts';

// A period the supplier typed, read back in Arabic where the glossary knows it (audit 21 Sep 2026, finding 26:
// the Arabic acknowledgement said "الصلاحية 30 days"). A period it does not know stays in the supplier's words.
const arPeriod = (v: unknown) => arDuration(v) ?? String(v ?? '');
// ---------------------------------------------------------------------------------------------
// The engineer's words. Every message exists in both languages; the reader's language picks one.
// ---------------------------------------------------------------------------------------------
export type Said = { en: string; ar: string };
/** THE JOB NUMBER THE ENGINEER MUST WRITE (11 Nov 2026, sales_engineer; nightly run 077cbbfc, jobs 164941 and 164942). Every
 *  review fact code writes names its job as "Job <no>" (greeting, reviewSaid, readyToSubmitSaid ...). The model rewrites the
 *  facts into the engineer's message (rulings 1195-1197) and was only ASKED to keep the job number (the voice's rules), so
 *  the opening message of two viewports named no job. Passed as aiReply `must`, a draft that leaves it out is rewritten by
 *  the model with that named (ai_reply.ts), never patched by code. Code-made facts only: a supplier's own words never reach here.
 *  prevented by: supplier_api/the_engineer_always_names_the_job.test.ts */
export function jobsIn(facts: string): string[] {
  return [...new Set([...String(facts || '').matchAll(/\bJob ([0-9A-Za-z][0-9A-Za-z-]{3,})\b/g)].map((m) => m[1]))].slice(0, 3);
}
export function greeting(job: string): Said {
  return {
    en: `Hello — I am the QuotesDone sales engineer for Job ${job}. Attach your quotation here (PDF with text, Excel, Word, CSV or email) and I will review it straight away against the job: every BOQ line priced, quantities and units, AED prices, the VAT basis, validity, delivery, and the exact specifications. Nothing reaches the customer until it is complete.`,
    ar: `أهلًا بكم، معكم مهندس المبيعات في QuotesDone للطلب ${job}. يُرجى إرفاق عرض سعركم هنا (PDF نصي أو Excel أو Word أو CSV أو رسالة بريد إلكتروني)، وسأراجعه فورًا في ضوء متطلبات الطلب: تسعير جميع بنود جدول الكميات، والكميات والوحدات، والأسعار بالدرهم، وأساس احتساب الضريبة، ومدة الصلاحية، والتسليم، والمواصفات الدقيقة. ولن يصل العرض إلى العميل قبل اكتماله.`,
  };
}
export function reviewSaid(job: string, r: Review): Said {
  if (r.approved) {
    const boqEn = r.boq_lines ? `all ${r.boq_lines} BOQ line${r.boq_lines === 1 ? ' is' : 's are'} priced with matching quantities and units, ` : '';
    const boqAr = r.boq_lines ? `جميع بنود جدول الكميات (${r.boq_lines}) مسعّرة بكميات ووحدات مطابقة، و` : '';
    return {
      en: `Quotation approved for submission. I checked it against Job ${job}: ${boqEn}prices are in AED, and the VAT basis, validity, delivery and every required specification are stated exactly.`,
      ar: `اعتُمد عرض السعر للتقديم. راجعته في ضوء متطلبات الطلب ${job}: ${boqAr}الأسعار بالدرهم، وأساس احتساب الضريبة والصلاحية والتسليم وجميع المواصفات المطلوبة مذكورة بدقة.`,
    };
  }
  const n = r.issues.length;
  return {
    en: `I reviewed your quotation for Job ${job}. Before it can be submitted I need ${n} thing${n === 1 ? '' : 's'}:\n\n${r.issues.map((x, i) => `${i + 1}. ${x.en}`).join('\n')}\n\nReply here with the details (for example "validity 30 days", "lead time 3 weeks", "prices exclude VAT"), or attach a revised file. Nothing is sent to the customer until everything is complete.`,
    ar: `راجعت عرض سعركم للطلب ${job}. وقبل تقديمه، يلزم استيفاء ${n === 1 ? 'ما يلي' : n === 2 ? 'الأمرين التاليين' : 'الأمور التالية'}:\n\n${r.issues.map((x, i) => `${i + 1}. ${x.ar}`).join('\n')}\n\nيُرجى كتابة التفاصيل هنا (مثل «الصلاحية 30 يومًا» أو «مدة التسليم 3 أسابيع» أو «الأسعار غير شاملة الضريبة»)، أو إرفاق ملف معدّل. ولن يُرسل شيء إلى العميل قبل استيفاء كل ذلك.`,
  };
}
export function choiceSaid(): Said {
  return {
    en: 'One last step: would you like to upload a new version of your quotation yourself, or shall I generate the standardised QuotesDone quotation for you from what we agreed? Reply "upload" or "generate", or use the buttons.',
    ar: 'تبقّت خطوة أخيرة: هل تودّون رفع نسخة جديدة من عرضكم بأنفسكم، أم أُعدّ لكم عرض QuotesDone الموحّد بناءً على ما اتفقنا عليه؟ اكتبوا «رفع» أو «إعداد»، أو استخدموا الأزرار.',
  };
}
export const awaitingUploadSaid = (): Said => ({
  en: 'Please attach the new version of your quotation here. I will review it the moment it arrives.',
  ar: 'يُرجى إرفاق النسخة الجديدة من عرضكم هنا، وسأراجعها فور وصولها.',
});
export const readyToSubmitSaid = (job: string): Said => ({
  en: `This version is approved. Press "Submit to Job ${job}" and it goes to the customer's comparison.`,
  ar: `اعتُمدت هذه النسخة. اضغطوا «تقديم العرض إلى الطلب ${job}» ليُدرج ضمن مقارنة العميل.`,
});
// ── THE GENERATED QUOTATION, SHOWN BEFORE IT IS SENT (22 Sep 2026, finding SP-F-07) ─────────────
// "Generate it for me" used to SUBMIT immediately and print the PDF afterwards: the first time the
// supplier saw the quotation that went out in its name was after the customer already had it. The
// spec-hold path has always done the opposite — regenerate, show, and release only on the
// supplier's approval (_shared/line_specs/workflow.ts fillIn -> awaiting_approval -> approve) — and
// this now mirrors it with the state the conversation already has: ready_to_submit, whose whole
// meaning is "approved by the supplier, waiting for Submit".
//
// ponytail: the quotation is printed here as the THREAD's own itemised text, not as the PDF. The
// PDF renderer prints a quote ROW (quote_pdf takes a quote_id) and no row exists before submission;
// the content is identical because both are built from the same Working. If a pre-submission PDF is
// ever wanted, give _shared/line_specs/workflow.ts's `render` a record built from Working and
// attach it here — nothing else changes.
// THE TOTAL IS THE ONE submit_quote WILL CARRY, character for character: submitPayload sends
// `rv.price_ex_vat ?? w.amount` and `priceExVat` here IS that rv.price_ex_vat. A preview total read
// from a second expression is a preview that can differ from what is sent, which is the whole defect
// this function was written to close.
const PREVIEW_LINES = 40;
export function generatedSaid(job: string, w: Working, priceExVat: number | null): Said {
  const money = (n: number | null | undefined) => (n == null ? '—' : fmt(n));
  const lines = w.lines.slice(0, PREVIEW_LINES);
  const rowEn = (l: WLine, i: number) =>
    `${i + 1}. ${l.description}${l.qty ? ` — ${l.qty}${l.unit ? ' ' + l.unit : ''}` : ''}`
    + `${l.unit_price != null ? ` @ AED ${money(l.unit_price)}` : ''} = AED ${money(l.amount)}`;
  const rowAr = (l: WLine, i: number) =>
    `${i + 1}. ${l.description}${l.qty ? ` — ${l.qty}${l.unit ? ' ' + l.unit : ''}` : ''}`
    + `${l.unit_price != null ? ` × ${money(l.unit_price)} درهم` : ''} = ${money(l.amount)} درهم`;
  const more = w.lines.length > lines.length ? w.lines.length - lines.length : 0;
  const termsEn = [
    `Total excluding VAT: AED ${money(priceExVat ?? w.amount)}`,
    w.validity ? `Validity: ${w.validity}` : null,
    w.lead_time ? `Delivery / lead time: ${w.lead_time}` : null,
    w.warranty ? `Warranty: ${w.warranty}` : null,
    w.payment_terms ? `Payment terms: ${w.payment_terms}` : null,
    w.exclusions ? `Exclusions: ${w.exclusions}` : null,
  ].filter(Boolean);
  const termsAr = [
    `الإجمالي غير شامل الضريبة: ${money(priceExVat ?? w.amount)} درهم`,
    w.validity ? `الصلاحية: ${w.validity}` : null,
    w.lead_time ? `التسليم / مدة التنفيذ: ${w.lead_time}` : null,
    w.warranty ? `الضمان: ${w.warranty}` : null,
    w.payment_terms ? `شروط الدفع: ${w.payment_terms}` : null,
    w.exclusions ? `الاستثناءات: ${w.exclusions}` : null,
  ].filter(Boolean);
  return {
    en: `Here is the standardised QuotesDone quotation I have prepared for Job ${job}, exactly as the customer would receive it. Nothing has been sent yet.\n\n`
      + `${lines.map(rowEn).join('\n')}${more ? `\n… the first ${PREVIEW_LINES} lines are shown; the remaining ${more} ${more === 1 ? 'line is' : 'lines are'} in the quotation and in its PDF.` : ''}\n\n${termsEn.join('\n')}\n\n`
      + `Read it through. If it is right, press "Submit to Job ${job}" (or reply "submit") and I will send it and attach the PDF here. If anything is wrong, tell me what to change, or attach your own version instead.`,
    ar: `هذا هو عرض QuotesDone الموحّد الذي أعددته للطلب ${job}، بالصيغة نفسها التي سيستلمها العميل. ولم يُرسل شيء بعد.\n\n`
      + `${lines.map(rowAr).join('\n')}${more ? `\n… المعروض هنا أول ${PREVIEW_LINES} بندًا، وبقية البنود (${more}) مدرجة في العرض وفي نسخته PDF.` : ''}\n\n${termsAr.join('\n')}\n\n`
      + `يُرجى مراجعته. فإن كان صحيحًا فاضغطوا «تقديم العرض إلى الطلب ${job}» (أو اكتبوا «تقديم») لأرسله وأرفق نسخة PDF هنا. وإن كان فيه ما يحتاج تعديلًا فأخبروني به، أو أرفقوا نسختكم بدلًا منه.`,
  };
}
export const submittedSaid = (job: string, ref: string | null, generated: boolean): Said => ({
  en: `${generated ? `I generated your standardised quotation${ref ? ` ${ref}` : ''} and submitted` : 'I submitted your quotation'} to Job ${job}. It is now in the customer's comparison; they see it without your name until they choose to reveal it. This conversation is now closed.`,
  ar: `${generated ? `أعددت عرضكم الموحّد${ref ? ` ${ref}` : ''} وقدّمته` : 'قدّمت عرض سعركم'} إلى الطلب ${job}، وقد أصبح ضمن مقارنة العميل، ويطّلع عليه دون أن يظهر اسمكم إلى أن يختار الكشف عنه. وبذلك أُغلقت هذه المحادثة.`,
});
// A SCAN IS NOT A DEAD END (22 Sep 2026, finding SP-F-03). A printed, signed, stamped and
// photographed quotation is how a great many UAE contractors send one, and there is no OCR while
// the model hold stands. Telling that supplier "send a text PDF" and nothing else pushed them to
// the quote form outside this conversation — the one door that skips the review entirely. The
// typed path (quote_review_flow.ts `typed`) reads the same lines through the same parser, so the
// answer now names it.
const TYPE_IT_EN = 'Or type it here instead: one line per item — description, quantity, unit and price — and a total. '
  + 'I read typed lines exactly as I read a file, and the review is the same.';
const TYPE_IT_AR = 'أو اكتبوه هنا بدلًا من ذلك: سطر لكل بند — الوصف والكمية والوحدة والسعر — ثم الإجمالي. '
  + 'أقرأ الأسطر المكتوبة تمامًا كما أقرأ الملف، والمراجعة هي نفسها.';
export const unreadableSaid = (kind: string): Said => kind === 'image'
  ? { en: 'I could not read that photo or scan clearly, even with a second look. Please send a clearer copy — a sharp photo of the whole page, or the quotation as a PDF, Excel, Word or CSV file — and I will read it as soon as it arrives. ' + TYPE_IT_EN, ar: 'تعذّر عليّ قراءة هذه الصورة أو المسح الضوئي بوضوح حتى بعد محاولة ثانية. يُرجى إرسال نسخة أوضح — صورة واضحة للصفحة كاملة، أو العرض بصيغة PDF أو Excel أو Word أو CSV — وسأقرؤها فور وصولها. ' + TYPE_IT_AR }
  : { en: 'I could not find a priced list or a total in that file. Please attach the quotation with its line items and total — a PDF with text, an Excel or Word file, or a CSV. ' + TYPE_IT_EN, ar: 'لم أجد في هذا الملف بنودًا مسعّرة ولا إجماليًا. يُرجى إرفاق العرض ببنوده وإجماليه بصيغة PDF نصية، أو ملف Excel أو Word أو CSV. ' + TYPE_IT_AR };
/** The typed lines themselves carried no priced item: the same answer, without asking for a file. */
export const typedUnreadableSaid = (): Said => ({
  en: 'I could not read a priced item in what you typed. Put one item on each line with its quantity, unit and price — for example "Gypsum partition, 120 sqm, 95 = 11400" — and add a total line. Or attach the quotation as a PDF with text, an Excel or Word file, or a CSV.',
  ar: 'لم أتمكّن من قراءة بند مسعّر فيما كتبتموه. يُرجى وضع بند واحد في كل سطر مع كميته ووحدته وسعره — مثل «قواطع جبسية، 120 متر مربع، 95 = 11400» — مع سطر للإجمالي. أو أرفقوا العرض بصيغة PDF نصية، أو ملف Excel أو Word أو CSV.',
});
export const closedSaid = (): Said => ({
  // Founder, 14 Sep 2026: no customer- or supplier-facing text says a copy is kept.
  en: 'This job is closed — the customer has already chosen, so no further quotation can be submitted to it.',
  ar: 'أُغلق هذا الطلب بعد أن حسم العميل اختياره، فلم يعد بالإمكان تقديم عروض أخرى إليه.',
});

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { arPeriod };
