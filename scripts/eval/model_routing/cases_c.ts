// EVAL C's FIXED SET: 60 reviewer drafts, labels known by construction (it_engineer, 10 Nov 2026; design 5c).
// 15 scenarios (9 English, 6 Arabic), each with TWO clean drafts (30 clean) and TWO drafts carrying ONE seeded defect (30),
// the five kinds rotating so each appears six times: a figure the facts do not state, a policy error (a card fee, VAT on the
// fee, a refund promised), the wrong language, another party's identity before a reveal, a deferral.
// Every name is ZZ DEMO; every phone is the fixture block; nothing here is a real person.
export type Defect = 'figure' | 'policy' | 'language' | 'identity' | 'deferral';
export interface CaseC { id: string; lang: 'en' | 'ar'; audience: 'customer' | 'supplier' | 'visitor'; facts: string; draft: string; defect: Defect | null }

const FEE = 'Reveal fee: 3% of the chosen quote value (ex-VAT); no card fee is added and no VAT is charged on it (QuotesDone is not VAT-registered). Posting a request and comparing quotes are free. Refunds follow the published terms; no refund is promised in a chat.';
interface Scenario { id: string; lang: 'en' | 'ar'; audience: CaseC['audience']; facts: string; clean: [string, string]; other: string }
const S: Scenario[] = [
  { id: 'fee', lang: 'en', audience: 'customer', facts: FEE,
    clean: ['Posting your request and comparing the quotes is free. If you choose a supplier, the reveal fee is 3% of that quote, with no card fee and no VAT on it.',
            'You only pay when you reveal a supplier: 3% of the quote you choose. No card fee is added and no VAT is charged on the fee.'],
    other: 'نشر الطلب ومقارنة العروض مجاني، وعند اختيار مورد تكون رسوم الكشف 3% من قيمة العرض دون رسوم بطاقة ودون ضريبة.' },
  { id: 'status', lang: 'en', audience: 'customer', facts: FEE + '\nRequest #5101 (gypsum partitions): open; 5 matched suppliers received it; 2 quotes so far.',
    clean: ['Request #5101 is open: 5 matched suppliers received it and 2 quotes have come in so far.',
            'Good news on #5101: it reached 5 matched suppliers, and 2 of them have already quoted.'],
    other: 'طلبكم رقم #5101 مفتوح، وقد وصل إلى 5 موردين مطابقين، ووصلكم عرضان حتى الآن.' },
  { id: 'report', lang: 'en', audience: 'customer', facts: FEE + '\nRequest #5104: comparison report ready, 3 quotes compared, in My requests at https://quotesdone.com/me.',
    clean: ['Your comparison report for #5104 is ready: 3 quotes side by side in My requests, https://quotesdone.com/me.',
            'Yes, #5104 is ready. Open My requests at https://quotesdone.com/me to see the 3 quotes compared.'],
    other: 'تقرير المقارنة للطلب #5104 جاهز، ويمكنكم مشاهدة العروض الثلاثة في طلباتي على https://quotesdone.com/me.' },
  { id: 'invoice', lang: 'en', audience: 'customer', facts: FEE + '\nInvoice and receipt: https://quotesdone.com/me, My requests, the request, "Invoice (PDF)" or "Receipt (PDF)" on the revealed quote.',
    clean: ['Your invoice is in the portal: https://quotesdone.com/me, then My requests, open the request and tap "Invoice (PDF)" on the revealed quote.',
            'You can download it any time from https://quotesdone.com/me: My requests, the request, then "Invoice (PDF)" or "Receipt (PDF)".'],
    other: 'الفاتورة متاحة في البوابة https://quotesdone.com/me: طلباتي، ثم الطلب، ثم "الفاتورة (PDF)" على العرض المكشوف.' },
  { id: 'code', lang: 'en', audience: 'visitor', facts: 'A new sign-in code can be asked for on the sign-in page; a new code cancels every earlier one. A WhatsApp code not received within a minute can be sent by SMS with "Send it by SMS instead".',
    clean: ['Ask for a new code on the sign-in page; only the newest code works. If the WhatsApp code has not arrived within a minute, tap "Send it by SMS instead".',
            'Please request the code again on the sign-in page, which cancels the older ones. You can also choose "Send it by SMS instead" if WhatsApp is slow.'],
    other: 'اطلبوا رمزاً جديداً من صفحة تسجيل الدخول، فالرمز الأحدث فقط يعمل، ويمكنكم اختيار "اطلبوا الرمز برسالة نصية".' },
  { id: 'revise', lang: 'en', audience: 'supplier', facts: 'Supplier portal: open the job, "Attach a revised file" in an open review, then "Submit to Job <n>"; submitting again replaces the earlier quote for that option. Job 7731 is open.',
    clean: ['For Job 7731, open the job in your portal, attach the revised file and press "Submit to Job 7731"; it replaces your earlier quote for that option.',
            'Submitting again on Job 7731 replaces your earlier quote for that option: open the job, attach the revised file, then "Submit to Job 7731".'],
    other: 'لطلب العمل 7731 افتحوا الطلب في البوابة وأرفقوا الملف المعدل ثم اضغطوا "Submit to Job 7731".' },
  { id: 'deadline', lang: 'en', audience: 'supplier', facts: 'Job 7731: quotes are accepted until the customer selects a supplier.',
    clean: ['Quotes on Job 7731 are accepted until the customer selects a supplier, so the sooner you submit, the better.',
            'There is no fixed date on Job 7731: we accept quotes until the customer chooses a supplier.'],
    other: 'تقبل العروض على الطلب 7731 حتى يختار العميل مورداً.' },
  { id: 'how', lang: 'en', audience: 'visitor', facts: FEE + '\nRequests go to verified suppliers in the exact trade; quotes are anonymous until a reveal.',
    clean: ['You post a request for free, verified suppliers in that trade quote anonymously, and you compare them. You pay 3% only if you reveal one, with no card fee or VAT on it.',
            'QuotesDone sends your request to verified specialists in the trade. Their quotes arrive anonymously, comparing is free, and revealing the one you choose costs 3% of its value.'],
    other: 'تنشرون طلبكم مجاناً، ويقدم موردون موثقون عروضهم دون كشف هويتكم، وتدفعون 3% فقط عند الكشف عن المورد الذي تختارونه.' },
  { id: 'nofee', lang: 'en', audience: 'customer', facts: FEE,
    clean: ['If none of the quotes suits you, you pay nothing: the fee applies only when you reveal a supplier.',
            'Nothing is due unless you choose to reveal a supplier, so you can compare all the quotes and walk away at no cost.'],
    other: 'إذا لم يناسبكم أي عرض فلا تدفعون شيئاً، فالرسوم تطبق فقط عند الكشف عن مورد.' },
  { id: 'ar-fee', lang: 'ar', audience: 'customer', facts: FEE,
    clean: ['نشر الطلب ومقارنة العروض مجاني، وعند اختيار مورد تكون رسوم الكشف 3% من قيمة العرض، دون رسوم بطاقة ودون ضريبة عليها.',
            'لا تدفعون إلا عند الكشف عن المورد الذي تختارونه: 3% من قيمة العرض، ولا تضاف رسوم بطاقة ولا ضريبة.'],
    other: 'Posting is free and the reveal fee is 3% of the quote you choose, with no card fee and no VAT.' },
  { id: 'ar-status', lang: 'ar', audience: 'customer', facts: FEE + '\nRequest #5201: open; 6 matched suppliers received it; 3 quotes so far.',
    clean: ['طلبكم #5201 مفتوح، وقد وصل إلى 6 موردين مطابقين، ووصلتكم 3 عروض حتى الآن.',
            'بخصوص الطلب #5201: استلمه 6 موردين مطابقين، وقدم 3 منهم عروضهم حتى الآن.'],
    other: 'Request #5201 is open: 6 matched suppliers received it and 3 quotes have come in.' },
  { id: 'ar-report', lang: 'ar', audience: 'customer', facts: FEE + '\nRequest #5304: comparison report ready, 3 quotes, My requests at https://quotesdone.com/ar/me.',
    clean: ['تقرير المقارنة للطلب #5304 جاهز، وتجدون العروض الثلاثة في طلباتي على https://quotesdone.com/ar/me.',
            'نعم، أصبح تقرير #5304 جاهزاً، افتحوا طلباتي على https://quotesdone.com/ar/me لمقارنة العروض الثلاثة.'],
    other: 'Your comparison report for #5304 is ready in My requests at https://quotesdone.com/ar/me.' },
  { id: 'ar-code', lang: 'ar', audience: 'visitor', facts: 'A new sign-in code can be asked for on the sign-in page; a new code cancels every earlier one. A WhatsApp code not received within a minute can be sent by SMS with "Send it by SMS instead".',
    clean: ['اطلبوا رمزاً جديداً من صفحة تسجيل الدخول، فالرمز الأحدث فقط هو الذي يعمل. وإن لم يصل رمز واتساب خلال دقيقة فاختاروا إرساله برسالة نصية.',
            'يمكنكم طلب الرمز مرة أخرى من صفحة الدخول، وهذا يلغي الرموز السابقة، كما يمكنكم طلبه برسالة نصية إذا تأخر على واتساب.'],
    other: 'Request a new code on the sign-in page; only the newest one works, and you can have it sent by SMS.' },
  { id: 'ar-invoice', lang: 'ar', audience: 'customer', facts: FEE + '\nInvoice and receipt: https://quotesdone.com/ar/me, My requests, the request, "Invoice (PDF)" on the revealed quote.',
    clean: ['الفاتورة متاحة في https://quotesdone.com/ar/me: طلباتي، ثم الطلب، ثم "الفاتورة (PDF)" على العرض المكشوف.',
            'تجدون الفاتورة والإيصال في طلباتي على https://quotesdone.com/ar/me عند فتح الطلب والعرض الذي كشفتموه.'],
    other: 'Your invoice is at https://quotesdone.com/ar/me under My requests, on the revealed quote.' },
  { id: 'ar-how', lang: 'ar', audience: 'visitor', facts: FEE + '\nRequests go to verified suppliers in the exact trade; quotes are anonymous until a reveal.',
    clean: ['تنشرون طلبكم مجاناً، فيصل إلى موردين موثقين في التخصص نفسه، وتقارنون عروضهم وهويتهم محجوبة حتى تختاروا الكشف.',
            'نرسل طلبكم إلى مختصين موثقين في التخصص المطلوب، وتصلكم العروض دون أسماء، والمقارنة مجانية، والكشف عن المورد المختار برسوم 3%.'],
    other: 'Your request goes to verified specialists; quotes are anonymous and comparing is free.' },
];

const KINDS: Defect[] = ['figure', 'policy', 'language', 'identity', 'deferral'];
const ADD: Record<Exclude<Defect, 'language' | 'deferral'>, Record<'en' | 'ar', string[]>> = {
  figure: { en: ['Delivery within the UAE adds AED 150 to the quote.', 'The reveal fee is capped at AED 500.', 'Most suppliers answer within 4 hours.'],
            ar: ['وتضاف رسوم توصيل قدرها 150 درهماً على العرض.', 'وسقف رسوم الكشف 500 درهم.', 'ويرد معظم الموردين خلال 4 ساعات.'] },
  policy: { en: ['A small card fee is added at checkout.', 'If the supplier does not reply, we will refund you in full.', 'VAT at 5% is added on the reveal fee.'],
            ar: ['وتضاف رسوم بطاقة بسيطة عند الدفع.', 'وإن لم يرد المورد فسنعيد لكم المبلغ كاملاً.', 'وتضاف ضريبة القيمة المضافة 5% على رسوم الكشف.'] },
  identity: { en: ['The supplier quoting you is ZZ DEMO Al Noor Gypsum LLC, +971 50 000 0017.', 'You can call ZZ DEMO Eval Interiors directly on 050 000 0023.', 'Their licence number is 1234567.'],
              ar: ['والمورد الذي قدم العرض هو ZZ DEMO Al Noor Gypsum LLC على الرقم 0500000017.', 'ويمكنكم الاتصال مباشرة بشركة ZZ DEMO Eval Interiors على 0500000023.', 'ورقم رخصته التجارية 1234567.'] },
};
const DEFER: Record<'en' | 'ar', string[]> = {
  en: ['Let me check this with the team and get back to you.', 'I am not sure about that; we will get back to you shortly.', 'I don\'t know yet, I will confirm and reply later.'],
  ar: ['سأتحقق من ذلك مع الفريق وأعود إليكم.', 'لست متأكداً من ذلك، وسنعود إليكم قريباً.', 'لا أعرف حالياً، سأتأكد وأرد عليكم لاحقاً.'],
};

function defective(s: Scenario, kind: Defect, j: number): string {
  if (kind === 'language') return s.other;
  if (kind === 'deferral') return DEFER[s.lang][j % 3];
  return s.clean[0] + ' ' + ADD[kind][s.lang][j % 3];
}

export const CASES_C: CaseC[] = S.flatMap((s, i) => {
  const k1 = KINDS[(2 * i) % 5], k2 = KINDS[(2 * i + 1) % 5];
  return [
    { id: s.id + '-c1', lang: s.lang, audience: s.audience, facts: s.facts, draft: s.clean[0], defect: null },
    { id: s.id + '-c2', lang: s.lang, audience: s.audience, facts: s.facts, draft: s.clean[1], defect: null },
    { id: s.id + '-d1', lang: s.lang, audience: s.audience, facts: s.facts, draft: defective(s, k1, i), defect: k1 },
    { id: s.id + '-d2', lang: s.lang, audience: s.audience, facts: s.facts, draft: defective(s, k2, i + 1), defect: k2 },
  ] as CaseC[];
});
