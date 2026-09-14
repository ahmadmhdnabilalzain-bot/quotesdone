// supplier_charge_documents.ts — the recovery file for an unpaid clause 33 non-response charge.
//
// 14 Sep 2026, agent: accountant. The founder:
//   "you need to check as per UAE law the deadline for that and accordingly set it. once the deadline
//    is over, the accountant need to issue a proper legal document that i can take to dubai police or
//    court and complain officially. all as per UAE law exactly, i am not gonna hire any lawyer so make
//    sure the form and the wordings is done correctly"
//
// What the research found (docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md, every point cited there):
// an unpaid contractual charge is a CIVIL/COMMERCIAL debt. It goes to the Dubai Courts, not to the
// police. The route for a fixed, written, due sum is a payment order (أمر أداء), which the law allows
// only after the debtor has been formally required to pay (تكليف بالوفاء) and given the minimum period.
// So this module builds, from one case record and with no model:
//   1. the commercial invoice (no VAT: QuotesDone is not VAT-registered),
//   2. reminder letters 1 and 2,
//   3. the formal final demand (إنذار / تكليف بالوفاء),
//   4. the filing pack: a draft payment-order application, the evidence index, and a one-page guide.
// Arabic is the filing language of the Dubai Courts, so every document is built in Arabic (primary)
// and in English (for the supplier and for the file). Figures come from supplier_charge.ts only.
//
// What this does NOT do: it sends nothing, files nothing and writes no row. It is a pure function from
// a case record to renderer bodies; the caller (the accountant seat) owns delivery and the ledger.
import { computeCharge, money, addDays, type Charge } from './supplier_charge.ts';
import { FALLBACK } from './doc_template.ts';

export type Lang = 'en' | 'ar';
export const RECOVERY_DOC_VERSION = 'v1.0';

export type CaseFile = {
  case_ref: string;
  supplier: { legal_name: string; legal_name_ar: string; licence_no: string; licence_authority: string; licence_authority_ar: string; address: string; address_ar: string; email: string; mobile: string; signatory?: string };
  acceptance: { version: string; accepted_at: string; ip?: string; sha256: string };
  inquiry: { id: string; summary: string; summary_ar: string };
  quote_value: number;
  reveal: { paid_at: string; payment_intent: string; reveal_fee: number; processing_fee: number };
  ladder: { chase_day3_at: string; final_call_day5_at: string; chase_delivery: string; chase_delivery_ar: string; final_call_outcome: string; final_call_outcome_ar: string };
  refund: { refunded_at: string; refund_id: string; reveal_fee: number; processing_fee: number };
  invoice: { number: string; date: string };
  reminders: { n: number; date: string }[];
  // service_ref: the delivery ids alone, for the evidence index (the demand letter prints the full sentence).
  final_demand: { date: string; service: string; service_ar: string; service_ref?: string };
  as_of: string;
  payments?: { date: string; amount: number }[];
};

// ── The law, in one place. Each entry names the instrument and article exactly as the research doc
// cites it; the doc quotes the text and says which points were read on the primary source.
export const LEGAL = {
  demand_days: 5, // CPL Art. 144(1): the notice for payment gives "at least five [5] days"
  final_demand_days: 7, // what QuotesDone gives: above the minimum, never below it
  cpl: { en: 'Federal Decree-Law No. 42 of 2022 promulgating the Civil Procedure Code', ar: 'المرسوم بقانون اتحادي رقم (42) لسنة 2022 بإصدار قانون الإجراءات المدنية' },
  cpl_po_arts: { en: 'Articles 143 to 148 (writ of debt / payment order)', ar: 'المواد من (143) إلى (148) (أمر الأداء)' },
  cpl_service: { en: 'Articles 8 and 9 (service by email, SMS, smart applications or an agreed means)', ar: 'المادتان (8) و(9) (الإعلان بالبريد الإلكتروني أو الرسائل النصية أو التطبيقات الذكية أو الوسيلة المتفق عليها)' },
  ctl_arts: { en: 'Articles 73, 84, 86 and 88 (agreed delay interest from the due date; no compound interest) and Article 92 (five-year limitation)', ar: 'المواد (73) و(84) و(86) و(88) (فائدة التأخير المتفق عليها من تاريخ الاستحقاق، ولا فائدة مركّبة) والمادة (92) (التقادم بخمس سنوات)' },
  ctl: { en: 'Federal Decree-Law No. 50 of 2022 promulgating the Commercial Transactions Law', ar: 'المرسوم بقانون اتحادي رقم (50) لسنة 2022 بإصدار قانون المعاملات التجارية' },
  // Art 340(1), verbatim from the official texts (uaelegislation.gov.ae/en|ar/legislations/4011), confirmed
  // by the coordinator 14 Sep 2026. The Arabic filing quotes the official Arabic, not a translation.
  civil: { en: 'Federal Decree-Law No. 25 of 2025 promulgating the Civil Transactions Law', ar: 'المرسوم بقانون اتحادي رقم (25) لسنة 2025 بإصدار قانون المعاملات المدنية' },
  civil_340_1: { en: '"The contracting parties may pre-determine the amount of compensation by stipulating it in the contract or in a subsequent agreement, subject to the provisions of the law."', ar: '«يجوز للمتعاقدين أن يُحددا مقدمًا قيمة التعويض بالنص عليها في العقد أو في اتفاق لاحق، مع مراعاة أحكام القانون.»' },
  etl: { en: 'Federal Decree-Law No. 46 of 2021 on Electronic Transactions and Trust Services', ar: 'المرسوم بقانون اتحادي رقم (46) لسنة 2021 بشأن المعاملات الإلكترونية وخدمات الثقة' },
};

const MONTHS_EN = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const MONTHS_AR = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
export function fmtDate(iso: string, lang: Lang): string {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  return `${d} ${(lang === 'ar' ? MONTHS_AR : MONTHS_EN)[m - 1]} ${y}`;
}
const pct = (r: number) => (r * 100).toFixed(0) + '%';

const CO = {
  en: { name: FALLBACK.name, form: 'Sole Establishment', licence: 'Trader License No. 1633275 issued by the Dubai Department of Economy and Tourism', city: 'Dubai, United Arab Emirates', email: FALLBACK.email, phone: FALLBACK.phone, signer: FALLBACK.signer, title: FALLBACK.title },
  ar: { name: FALLBACK.name, form: 'مؤسسة فردية', licence: 'رخصة تاجر رقم 1633275 صادرة عن دائرة الاقتصاد والسياحة في دبي', city: 'دبي، الإمارات العربية المتحدة', email: FALLBACK.email, phone: FALLBACK.phone, signer: 'أحمد الزين', title: 'المؤسس والمدير الإداري' },
};
const NO_VAT = { en: 'QuotesDone Technologies is not registered for VAT; no VAT is charged on this invoice.', ar: 'QuotesDone Technologies غير مسجّلة في ضريبة القيمة المضافة؛ ولا تُحتسب أي ضريبة على هذه الفاتورة.' };
const FORMULA = {
  en: (c: Charge) => `Interest = unpaid principal × ${pct(c.rate_pa)} × days after the due date ÷ 365, simple, never compounded: ${money(c.daily_interest)} a day.`,
  ar: (c: Charge) => `الفائدة = أصل المبلغ غير المسدَّد × ${pct(c.rate_pa)} × عدد الأيام بعد تاريخ الاستحقاق ÷ 365 (فائدة بسيطة غير مركّبة). الاستحقاق اليومي على ${money(c.unpaid_principal, 'ar')}: ${money(c.daily_interest, 'ar')}.`,
};

function chargeOf(c: CaseFile, asOf = c.as_of): Charge {
  return computeCharge({ refunded_reveal_fee: c.refund.reveal_fee, refunded_processing_fee: c.refund.processing_fee, notice_date: c.invoice.date, as_of: asOf, payments: c.payments });
}

// deno-lint-ignore no-explicit-any
type Block = Record<string, any>;
function breakdown(ch: Charge, lang: Lang, withInterest = true): Block[] {
  const ar = lang === 'ar';
  const rows = ar
    ? [['1', 'رسم عدم الاستجابة (أ): رسوم الكشف المستردّة إلى العميل (3% من قيمة عرض السعر)', money(ch.refunded_reveal_fee, 'ar')],
      ['2', 'رسم عدم الاستجابة (أ): رسوم معالجة البطاقة المستردّة إلى العميل', money(ch.refunded_processing_fee, 'ar')],
      ['3', 'الرسم الإداري (ب)', money(ch.admin_fee, 'ar')]]
    : [['1', 'Non-response charge (a): reveal fee refunded (3% of quotation value)', money(ch.refunded_reveal_fee)],
      ['2', 'Non-response charge (a): card processing fee refunded', money(ch.refunded_processing_fee)],
      ['3', 'Administrative fee (b)', money(ch.admin_fee)]];
  const tot: (string | boolean)[][] = [[ar ? 'أصل المبلغ المستحق' : 'Principal due', money(ch.principal, lang), !withInterest]];
  if (ch.paid > 0) tot.push([ar ? 'المسدَّد' : 'Paid', '− ' + money(ch.paid, lang), false]);
  if (withInterest) {
    tot.push([ar ? `الفائدة (ج) بواقع ${pct(ch.rate_pa)} سنويًا عن ${ch.days_overdue} يومًا حتى ${fmtDate(ch.as_of, 'ar')}` : `Interest (c) at ${pct(ch.rate_pa)} p.a. for ${ch.days_overdue} days to ${fmtDate(ch.as_of, 'en')}`, money(ch.interest, lang), false]);
    tot.push([ar ? 'الإجمالي المستحق' : 'Total due', money(ch.total_due, lang), true]);
  }
  return [
    { t: 'table', head: ar ? ['#', 'البيان', 'المبلغ'] : ['#', 'Description', 'Amount'], rows, widths: [0.06, 0.7, 0.24] },
    { t: 'totals', rows: tot, note: '' },
    { t: 'note', text: FORMULA[lang](ch) },
  ];
}
function parties(c: CaseFile, lang: Lang, roleTo: string, roleFrom: string): Block[] {
  const ar = lang === 'ar', s = c.supplier, co = CO[lang];
  // One block, the two parties side by side: as two blocks each took half the width and stacked,
  // ~300pt of page 1, which pushed Reminder 2's totals alone onto an 80%-empty page 2 (14 Sep 2026).
  return [
    { t: 'kv', pairs: [[roleFrom, `${co.name} (${co.form}) · ${co.licence} · ${co.city} · ${co.email}`],
      [roleTo, `${ar ? s.legal_name_ar : s.legal_name} · ${ar ? 'رخصة تجارية رقم' : 'Trade Licence No.'} ${s.licence_no} (${ar ? s.licence_authority_ar : s.licence_authority}) · ${ar ? s.address_ar : s.address} · ${s.email} · ${s.mobile}`]] },
  ];
}
function basisBlocks(c: CaseFile, lang: Lang): Block[] {
  const ar = lang === 'ar';
  return ar ? [
    { t: 'p', label: 'الأساس التعاقدي', text: `قَبِل المورّد اتفاقية المورّد لدى QuotesDone (الإصدار ${c.acceptance.version}) إلكترونيًا بتاريخ ${fmtDate(c.acceptance.accepted_at, 'ar')}، وهو قبول مُلزِم وفقًا لـ${LEGAL.etl.ar}. ويُلزم البند 33 منها المورّد، إذا لم يستجب للعميل بعد الكشف وردّت QuotesDone المبلغ إلى العميل، بأن يدفع: (أ) رسم عدم استجابة يعادل المبلغ المستردّ بالضبط، و(ب) رسمًا إداريًا قدره 250 درهمًا، و(ج) فائدة بسيطة بسعر البند 31 البالغ 9% سنويًا من تاريخ الاستحقاق حتى السداد. وتستحق هذه المبالغ خلال سبعة (7) أيام من إشعار QuotesDone.` },
    { t: 'p', label: 'الوقائع', text: `كشف العميل عن بيانات المورّد بشأن الطلب "${c.inquiry.summary_ar}" بتاريخ ${fmtDate(c.reveal.paid_at, 'ar')}، ولم يستجب المورّد رغم المتابعة في اليوم الثالث (${fmtDate(c.ladder.chase_day3_at, 'ar')}) والاتصال الأخير في اليوم الخامس (${fmtDate(c.ladder.final_call_day5_at, 'ar')})، فردّت QuotesDone إلى العميل كامل ما دفعه بتاريخ ${fmtDate(c.refund.refunded_at, 'ar')} (مرجع الاسترداد ${c.refund.refund_id}).` },
  ] : [
    { t: 'p', label: 'Contractual basis', text: `The Supplier accepted the QuotesDone Supplier Agreement (version ${c.acceptance.version}) electronically on ${fmtDate(c.acceptance.accepted_at, 'en')}, a binding acceptance under ${LEGAL.etl.en}. Clause 33 obliges the Supplier, where it does not respond to a Customer after a Reveal and QuotesDone refunds the Customer, to pay: (a) a non-response charge equal to the exact amount refunded, (b) an administrative fee of AED 250, and (c) simple interest at the clause 31 rate of 9% per annum from the due date until settled. These amounts are payable within seven (7) days of QuotesDone's notice.` },
    { t: 'p', label: 'Facts', text: `The Customer revealed the Supplier for the request "${c.inquiry.summary}" on ${fmtDate(c.reveal.paid_at, 'en')}. The Supplier did not respond despite the day-3 chase (${fmtDate(c.ladder.chase_day3_at, 'en')}) and the day-5 final call (${fmtDate(c.ladder.final_call_day5_at, 'en')}), and QuotesDone refunded the Customer in full on ${fmtDate(c.refund.refunded_at, 'en')} (refund reference ${c.refund.refund_id}).` },
  ];
}
function signOff(lang: Lang): Block[] {
  const co = CO[lang];
  return [{ t: 'space', h: 8 }, { t: 'kv', pairs: [[lang === 'ar' ? 'عن QuotesDone Technologies' : 'For QuotesDone Technologies', `${co.signer} — ${co.title}`]] }];
}
function doc(lang: Lang, ref: string, dateIso: string, title: string, kicker: string, subtitle: string, meta: string[][], figures: string[][], blocks: Block[], sign: boolean) {
  const ar = lang === 'ar';
  return {
    lang, ref, name: `${ref}-${lang}`, title,
    cover: { kicker, title, subtitle, meta, figures },
    control: `${ref} · ${RECOVERY_DOC_VERSION} · ${ar ? 'أُصدر في' : 'Issued'} ${fmtDate(dateIso, lang)} · ${ar ? 'أعدّه محاسب QuotesDone' : 'Prepared by the QuotesDone accountant'}`,
    // Founder, 14 Sep 2026: "with stamp and signature of course". Every recovery document except the filing
    // guide carries his signature image and the company stamp. The renderer fetches both from the brand
    // bucket (qd_signature.png, qd_stamp.png) — one controlled store, nothing copied into code — and refuses
    // to issue a signed document if any character would be missing. signingRecord() records what went out.
    blocks, options: { letterhead: true, sign, stamp: sign }, issued_iso: dateIso,
    ...(ar ? { date_ar: fmtDate(dateIso, 'ar') } : { date: fmtDate(dateIso, 'en') }),
  };
}

/** The renderer's compact cover band (58pt shorter) for letters and indexes that must fit, signed, on one page. */
function compact<T extends { cover: Record<string, unknown> }>(b: T): T { b.cover.compact = true; return b; }

// ── 1. The commercial invoice ────────────────────────────────────────────────────────────────
export function invoiceDocument(c: CaseFile, lang: Lang) {
  const ar = lang === 'ar', ch = chargeOf(c, c.invoice.date);
  const due = fmtDate(ch.due_date, lang);
  return doc(lang, c.invoice.number, c.invoice.date,
    ar ? 'فاتورة تجارية' : 'Commercial Invoice', ar ? 'فاتورة — غير خاضعة لضريبة القيمة المضافة' : 'Invoice — not subject to VAT',
    ar ? `رسم عدم الاستجابة وفق البند 33 من اتفاقية المورّد — القضية ${c.case_ref}` : `Clause 33 non-response charge under the Supplier Agreement — case ${c.case_ref}`,
    [[ar ? 'رقم الفاتورة' : 'Invoice no.', c.invoice.number], [ar ? 'تاريخ الفاتورة' : 'Invoice date', fmtDate(c.invoice.date, lang)], [ar ? 'تاريخ الاستحقاق' : 'Due date', due], [ar ? 'مرجع القضية' : 'Case ref.', c.case_ref]],
    [[ar ? 'المبلغ المستحق' : 'Amount due', money(ch.principal, lang)], [ar ? 'يُسدَّد خلال' : 'Payable within', ar ? '7 أيام' : '7 days'], [ar ? 'فائدة التأخير' : 'Late interest', ar ? '9% سنويًا' : '9% p.a.']],
    [
      { t: 'section', n: 1, text: ar ? 'الطرفان' : 'Parties' }, ...parties(c, lang, ar ? 'إلى (المورّد)' : 'To (Supplier)', ar ? 'من' : 'From'),
      { t: 'section', n: 2, text: ar ? 'تفاصيل المبلغ' : 'Amount' }, ...breakdown(ch, lang, false),
      { t: 'note', text: NO_VAT[lang] },
      { t: 'section', n: 3, text: ar ? 'الأساس والاستحقاق' : 'Basis and due date' }, ...basisBlocks(c, lang),
      { t: 'callout', tone: 'gold', title: ar ? 'السداد' : 'Payment', text: ar ? `يُرجى سداد ${money(ch.principal, 'ar')} في موعد أقصاه ${due}. وبعد هذا التاريخ تُحتسب فائدة بسيطة بواقع 9% سنويًا على المبلغ غير المسدَّد عن كل يوم تأخير حتى السداد التام (البندان 31 و33).` : `Please pay ${money(ch.principal)} by ${due}. After that date simple interest of 9% per annum accrues daily on the unpaid amount until paid in full (clauses 31 and 33).` },
      { t: 'kv', pairs: [[ar ? 'طرق السداد' : 'How to pay', ar ? 'رابط الدفع في بوابة المورّد، أو تحويل بنكي بعد طلب بيانات الحساب من ' + CO.ar.email : 'The payment link in the supplier portal, or bank transfer — request account details from ' + CO.en.email]] },
      ...signOff(lang),
    ], true);
}

// ── 2. Reminders ─────────────────────────────────────────────────────────────────────────────
export function reminderDocument(c: CaseFile, n: number, lang: Lang) {
  const ar = lang === 'ar', r = c.reminders.find((x) => x.n === n);
  if (!r) throw new Error('no reminder ' + n + ' in the case file');
  const ch = chargeOf(c, r.date), ref = `${c.invoice.number}-R${n}`;
  const text = ar
    ? (n === 1 ? `نذكّركم بأن الفاتورة رقم ${c.invoice.number} المؤرخة ${fmtDate(c.invoice.date, 'ar')} استحقت في ${fmtDate(ch.due_date, 'ar')} ولم تُسدَّد حتى تاريخه. نرجو السداد في أقرب وقت، علمًا بأن الفائدة المتفق عليها تُحتسب يوميًا منذ تاريخ الاستحقاق.`
      : `رغم تذكيرنا السابق، لا تزال الفاتورة رقم ${c.invoice.number} غير مسدَّدة. نرجو السداد خلال سبعة (7) أيام من تاريخ هذا الخطاب، وإلا ستوجّه QuotesDone إليكم إنذارًا رسميًا بالوفاء تمهيدًا لاتخاذ الإجراءات القضائية أمام محاكم دبي.`)
    : (n === 1 ? `This is a reminder that invoice ${c.invoice.number} dated ${fmtDate(c.invoice.date, 'en')} fell due on ${fmtDate(ch.due_date, 'en')} and remains unpaid. Please settle it promptly; the agreed interest has accrued daily since the due date.`
      : `Despite our earlier reminder, invoice ${c.invoice.number} remains unpaid. Please pay within seven (7) days of this letter; otherwise QuotesDone will serve a formal demand for payment as the step before proceedings in the Dubai Courts.`);
  // A compact cover (renderer cover.compact) keeps a reminder, its statement and the signature on one page.
  return compact(doc(lang, ref, r.date, ar ? `تذكير بالسداد رقم ${n}` : `Payment Reminder ${n}`, ar ? 'تذكير' : 'Reminder',
    ar ? `الفاتورة ${c.invoice.number} — القضية ${c.case_ref}` : `Invoice ${c.invoice.number} — case ${c.case_ref}`,
    [[ar ? 'المرجع' : 'Reference', ref], [ar ? 'التاريخ' : 'Date', fmtDate(r.date, lang)], [ar ? 'تاريخ الاستحقاق' : 'Due date', fmtDate(ch.due_date, lang)]],
    // No key-figures strip: the totals block below states the amount due today, and the strip's 84pt is what
    // keeps a signed reminder on one page.
    [],
    [
      // A letter on letterhead names its addressee; the sender is the letterhead. The sign-off closes the
      // letter text, so it can never fall alone onto a second page (14 Sep 2026: it did, 94% empty).
      { t: 'kv', pairs: [[ar ? 'إلى (المورّد)' : 'To (Supplier)', `${ar ? c.supplier.legal_name_ar : c.supplier.legal_name} · ${c.supplier.email}`]] },
      { t: 'p', text },
      { t: 'section', n: 1, text: ar ? 'كشف الحساب' : 'Statement' }, ...breakdown(ch, lang),
    ], true));
}

// ── 3. The formal final demand (إنذار بالوفاء) ────────────────────────────────────────────────
export function finalDemandDocument(c: CaseFile, lang: Lang) {
  const ar = lang === 'ar', d = c.final_demand, ch = chargeOf(c, d.date);
  const deadline = addDays(d.date, LEGAL.final_demand_days), ref = `${c.case_ref}-FD`;
  const D = fmtDate(deadline, lang);
  const body: Block[] = ar ? [
    { t: 'p', text: `إلى السادة/ ${c.supplier.legal_name_ar} المحترمين،` },
    { t: 'p', text: `تحية طيبة وبعد، تُنذركم ${CO.ar.name} (${CO.ar.form}، ${CO.ar.licence}) بموجب هذا الإنذار الرسمي بالوفاء بالمبلغ المستحق عليكم المبيّن أدناه، وذلك للأسباب الآتية:` },
    ...basisBlocks(c, lang),
    { t: 'p', label: 'المطالبات السابقة', text: `أُرسلت إليكم الفاتورة رقم ${c.invoice.number} بتاريخ ${fmtDate(c.invoice.date, 'ar')} واستحقت في ${fmtDate(ch.due_date, 'ar')}، ثم التذكيرات المؤرخة ${c.reminders.map((r) => fmtDate(r.date, 'ar')).join(' و')}، ولم تُسدَّد حتى تاريخه.` },
    { t: 'section', n: 1, text: 'المبلغ المطالب به' }, ...breakdown(ch, lang),
    { t: 'section', n: 2, text: 'التكليف بالوفاء والمهلة' },
    { t: 'callout', tone: 'gold', title: 'المهلة', text: `نكلّفكم بالوفاء بالمبلغ المذكور وقدره ${money(ch.total_due, 'ar')} مضافًا إليه الفائدة المتفق عليها بواقع ${money(ch.daily_interest, 'ar')} عن كل يوم من تاريخ هذا الإنذار حتى السداد التام، وذلك خلال مدة أقصاها ${LEGAL.final_demand_days} يومًا من تاريخ إعلانكم بهذا الإنذار، أي في موعد أقصاه ${D}.` },
    { t: 'p', label: 'الأثر', text: `وفي حال عدم الوفاء خلال المهلة المحددة، ستتقدّم QuotesDone إلى محاكم دبي بطلب استصدار أمر أداء وفقًا لـ${LEGAL.cpl.ar} (${LEGAL.cpl_po_arts.ar})، مطالِبةً بالمبلغ الأصلي والفائدة المتفق عليها حتى السداد التام والرسوم والمصاريف، مع حفظ كافة حقوقها الأخرى.` },
    { t: 'p', label: 'طريقة الإعلان', text: `أُعلن هذا الإنذار بتاريخ ${fmtDate(d.date, 'ar')} على العنوان المعتمد في اتفاقية المورّد (البند 21: الإشعارات) وعن طريق ${d.service_ar}.` },
    { t: 'p', text: 'وتفضلوا بقبول فائق الاحترام،' },
  ] : [
    { t: 'p', text: `To: ${c.supplier.legal_name}` },
    { t: 'p', text: `${CO.en.name} (${CO.en.form}, ${CO.en.licence}) hereby gives you formal notice to pay the amount due from you set out below, for the following reasons:` },
    ...basisBlocks(c, lang),
    { t: 'p', label: 'Earlier requests', text: `Invoice ${c.invoice.number} was sent to you on ${fmtDate(c.invoice.date, 'en')} and fell due on ${fmtDate(ch.due_date, 'en')}, followed by reminders dated ${c.reminders.map((r) => fmtDate(r.date, 'en')).join(' and ')}. It remains unpaid.` },
    { t: 'section', n: 1, text: 'Amount demanded' }, ...breakdown(ch, lang),
    { t: 'section', n: 2, text: 'Demand for payment and deadline' },
    { t: 'callout', tone: 'gold', title: 'Deadline', text: `You are required to pay ${money(ch.total_due)}, plus the agreed interest of ${money(ch.daily_interest)} for each day from the date of this demand until payment in full, within ${LEGAL.final_demand_days} days of being served with this demand, that is no later than ${D}.` },
    { t: 'p', label: 'Consequence', text: `If you do not pay within that period, QuotesDone will apply to the Dubai Courts for a payment order under ${LEGAL.cpl.en} (${LEGAL.cpl_po_arts.en}), claiming the principal, the agreed interest until payment in full, and the court fees and costs, without prejudice to its other rights.` },
    { t: 'p', label: 'Service', text: `This demand was served on ${fmtDate(d.date, 'en')} at the address agreed in the Supplier Agreement (clause 21, Notices) and by ${d.service}.` },
  ];
  return doc(lang, ref, d.date, ar ? 'إنذار رسمي بالوفاء' : 'Formal Demand for Payment', ar ? 'إنذار — تكليف بالوفاء' : 'Legal notice — demand for payment',
    ar ? `تمهيدًا لطلب استصدار أمر أداء — القضية ${c.case_ref}` : `Before an application for a payment order — case ${c.case_ref}`,
    [[ar ? 'المرجع' : 'Reference', ref], [ar ? 'تاريخ الإنذار' : 'Date', fmtDate(d.date, lang)], [ar ? 'آخر موعد للسداد' : 'Pay by', D]],
    [[ar ? 'المطالب به' : 'Amount demanded', money(ch.total_due, lang)], [ar ? 'المهلة' : 'Period', ar ? `${LEGAL.final_demand_days} يومًا` : `${LEGAL.final_demand_days} days`]],
    [...parties(c, lang, ar ? 'المُنذَر إليه' : 'Addressee', ar ? 'المُنذِر' : 'Sender'), ...body, ...signOff(lang)], true);
}

// ── 4a. Draft payment-order application (for the founder to file on Dubai Courts' e-services) ──
export function claimDocument(c: CaseFile, lang: Lang, asOf = addDays(c.final_demand.date, LEGAL.final_demand_days + 1)) {
  const ar = lang === 'ar', ch = chargeOf(c, asOf), ref = `${c.case_ref}-PO`;
  const s = c.supplier, co = CO[lang];
  const blocks: Block[] = ar ? [
    { t: 'p', text: 'إلى: السيد القاضي المختص بإصدار أوامر الأداء — محاكم دبي' },
    { t: 'section', n: 1, text: 'بيانات الطالب (الدائن)' },
    { t: 'kv', pairs: [['الاسم', `${co.name} (${co.form})`], ['الرخصة', co.licence], ['العنوان', co.city], ['البريد الإلكتروني والهاتف', `${co.email} · ${co.phone}`], ['الممثل', `${co.signer} — ${co.title} (مالك المؤسسة)`]] },
    { t: 'section', n: 2, text: 'بيانات المطلوب ضده (المدين)' },
    { t: 'kv', pairs: [['الاسم', s.legal_name_ar], ['الرخصة', `${s.licence_no} — ${s.licence_authority_ar}`], ['العنوان', s.address_ar], ['البريد الإلكتروني', s.email], ['الهاتف', s.mobile]] },
    { t: 'section', n: 3, text: 'الوقائع' }, ...basisBlocks(c, lang),
    { t: 'p', text: `وأُرسلت إلى المدين الفاتورة رقم ${c.invoice.number} بتاريخ ${fmtDate(c.invoice.date, 'ar')}، والتذكيرات المؤرخة ${c.reminders.map((r) => fmtDate(r.date, 'ar')).join(' و')}، ثم أُعلن بإنذار رسمي بالوفاء بتاريخ ${fmtDate(c.final_demand.date, 'ar')} منحه مهلة ${LEGAL.final_demand_days} يومًا انقضت دون وفاء.` },
    { t: 'section', n: 4, text: 'شروط أمر الأداء' },
    { t: 'li', text: 'الدين ثابت بالكتابة: اتفاقية المورّد المقبولة إلكترونيًا (البند 33) وسجلّ القبول وقيمة الاسترداد الموثّقة لدى مزوّد الدفع.' },
    { t: 'li', text: 'الدين معيّن المقدار: يُحسب بمعادلة البند 33 من مبالغ ثابتة في السجلات.' },
    { t: 'li', text: 'الدين حالّ الأداء: استحق بعد سبعة أيام من الإشعار وفق البند 33.' },
    { t: 'li', text: `كُلّف المدين بالوفاء بإنذار رسمي مُنح فيه مهلة ${LEGAL.final_demand_days} يومًا، وهي تزيد على الحد الأدنى الذي يتطلبه القانون (${LEGAL.demand_days} أيام).` },
    { t: 'section', n: 5, text: 'المبلغ المطالب به' }, ...breakdown(ch, lang),
    { t: 'section', n: 6, text: 'الأساس القانوني' },
    { t: 'li', text: `${LEGAL.cpl.ar}، ${LEGAL.cpl_po_arts.ar} (أمر الأداء).` },
    { t: 'li', text: `${LEGAL.ctl.ar}، ${LEGAL.ctl_arts.ar}.` },
    { t: 'li', text: `${LEGAL.civil.ar}، المادة (340) البند (1) (التعويض الاتفاقي — أساس الرسم الإداري البالغ 250 درهمًا المنصوص عليه في البند 33): ${LEGAL.civil_340_1.ar}` },
    { t: 'li', text: `${LEGAL.cpl.ar}، ${LEGAL.cpl_service.ar}، والبند 21 من اتفاقية المورّد (الإشعارات).` },
    { t: 'li', text: `${LEGAL.etl.ar} (حجية القبول والتوقيع الإلكترونيين).` },
    { t: 'li', text: 'اتفاقية المورّد، البنود 21 (الإشعارات) و22 (النص العربي هو المعتمد أمام المحاكم) و31 و33 و34 (الاختصاص الحصري لمحاكم دبي).' },
    { t: 'section', n: 7, text: 'الطلبات' },
    { t: 'p', text: `يلتمس الطالب إصدار أمر أداء بإلزام المطلوب ضده بأن يؤدي إليه مبلغ ${money(ch.principal, 'ar')} (أصل الدين)، والفائدة البسيطة بواقع 9% سنويًا من تاريخ الاستحقاق ${fmtDate(ch.due_date, 'ar')} حتى السداد التام (وقدرها ${money(ch.interest, 'ar')} حتى ${fmtDate(ch.as_of, 'ar')})، مع إلزامه بالرسوم والمصاريف.` },
    { t: 'callout', tone: 'grey', title: 'مسودة للتقديم', text: 'هذه مسودة أعدّها محاسب QuotesDone ليقدّمها صاحب المؤسسة بنفسه عبر الخدمات الذكية لمحاكم دبي. تُراجَع البيانات مع نموذج الطلب الإلكتروني وقت التقديم، وتُرفق المستندات الواردة في فهرس الأدلة.' },
  ] : [
    { t: 'p', text: 'To: the Judge competent to issue payment orders — Dubai Courts' },
    { t: 'section', n: 1, text: 'Applicant (creditor)' },
    { t: 'kv', pairs: [['Name', `${co.name} (${co.form})`], ['Licence', co.licence], ['Address', co.city], ['Email and phone', `${co.email} · ${co.phone}`], ['Represented by', `${co.signer} — ${co.title} (owner)`]] },
    { t: 'section', n: 2, text: 'Respondent (debtor)' },
    { t: 'kv', pairs: [['Name', s.legal_name], ['Licence', `${s.licence_no} — ${s.licence_authority}`], ['Address', s.address], ['Email', s.email], ['Phone', s.mobile]] },
    { t: 'section', n: 3, text: 'Facts' }, ...basisBlocks(c, lang),
    { t: 'p', text: `Invoice ${c.invoice.number} was sent on ${fmtDate(c.invoice.date, 'en')}, reminders on ${c.reminders.map((r) => fmtDate(r.date, 'en')).join(' and ')}, and a formal demand was served on ${fmtDate(c.final_demand.date, 'en')} giving ${LEGAL.final_demand_days} days, which expired without payment.` },
    { t: 'section', n: 4, text: 'Conditions for a payment order' },
    { t: 'li', text: 'The debt is proven in writing: the electronically accepted Supplier Agreement (clause 33), the acceptance record and the refund recorded by the payment provider.' },
    { t: 'li', text: 'The debt is of a fixed amount: computed by the clause 33 formula from sums fixed in the records.' },
    { t: 'li', text: 'The debt is due: payable seven days after notice under clause 33.' },
    { t: 'li', text: `The debtor was formally required to pay and given ${LEGAL.final_demand_days} days, more than the minimum the law requires (${LEGAL.demand_days} days).` },
    { t: 'section', n: 5, text: 'Amount claimed' }, ...breakdown(ch, lang),
    { t: 'section', n: 6, text: 'Legal basis' },
    { t: 'li', text: `${LEGAL.cpl.en}, ${LEGAL.cpl_po_arts.en} (payment orders).` },
    { t: 'li', text: `${LEGAL.ctl.en}, ${LEGAL.ctl_arts.en}.` },
    { t: 'li', text: `${LEGAL.civil.en}, Article 340(1) (agreed compensation — the basis of the AED 250 administrative fee stipulated in clause 33): ${LEGAL.civil_340_1.en}` },
    { t: 'li', text: `${LEGAL.cpl.en}, ${LEGAL.cpl_service.en}, and Supplier Agreement clause 21 (Notices).` },
    { t: 'li', text: `${LEGAL.etl.en} (validity of electronic acceptance and signature).` },
    { t: 'li', text: 'Supplier Agreement clauses 21 (notices), 22 (the Arabic text prevails before the courts), 31, 33 and 34 (exclusive jurisdiction of the Dubai courts).' },
    { t: 'section', n: 7, text: 'Relief sought' },
    { t: 'p', text: `The Applicant asks for a payment order requiring the Respondent to pay ${money(ch.principal)} (principal), simple interest at 9% per annum from the due date ${fmtDate(ch.due_date, 'en')} until payment in full (${money(ch.interest)} to ${fmtDate(ch.as_of, 'en')}), and the court fees and costs.` },
    { t: 'callout', tone: 'grey', title: 'Draft for filing', text: 'Prepared by the QuotesDone accountant for the owner to file himself on the Dubai Courts smart services. The Arabic version is the one filed. Check the fields against the e-form at the time of filing and attach the documents in the evidence index.' },
  ];
  return doc(lang, ref, asOf, ar ? 'طلب استصدار أمر أداء' : 'Application for a Payment Order', ar ? 'مسودة — محاكم دبي' : 'Draft — Dubai Courts',
    ar ? `${co.name} ضد ${s.legal_name_ar}` : `${co.name} v. ${s.legal_name}`,
    [[ar ? 'المرجع' : 'Reference', ref], [ar ? 'التاريخ' : 'Date', fmtDate(asOf, lang)], [ar ? 'المحكمة' : 'Court', ar ? 'محاكم دبي' : 'Dubai Courts']],
    [[ar ? 'أصل الدين' : 'Principal', money(ch.principal, lang)], [ar ? 'الفائدة حتى تاريخه' : 'Interest to date', money(ch.interest, lang)], [ar ? 'الإجمالي' : 'Total', money(ch.total_due, lang)]],
    [...blocks, ...signOff(lang)], true);
}

// ── 4b. Evidence index ───────────────────────────────────────────────────────────────────────
export function evidenceIndexDocument(c: CaseFile, lang: Lang) {
  const ar = lang === 'ar', ref = `${c.case_ref}-EV`;
  const T = (en: string, a: string) => ar ? a : en;
  const rows: string[][] = [
    [T('Supplier Agreement v' + c.acceptance.version.replace(/^v/, '') + ', signed copy (clauses 31, 33, 34)', 'اتفاقية المورّد الإصدار ' + c.acceptance.version + '، نسخة موقّعة (البنود 31 و33 و34)'), T('Accepted ', 'قُبلت ') + fmtDate(c.acceptance.accepted_at, lang), 'SHA-256 ' + c.acceptance.sha256.slice(0, 16) + '…'],
    [T('Acceptance record (time, IP, text hash)', 'سجلّ القبول الإلكتروني (الوقت، عنوان IP، بصمة النص)'), c.acceptance.accepted_at.replace('T', ' ').replace('Z', ' UTC'), 'IP ' + (c.acceptance.ip ?? '—')],
    [T('QuotesDone Trader License (DET Dubai)', 'رخصة تاجر لـ QuotesDone (دائرة الاقتصاد والسياحة في دبي)'), '1633275', T('valid to 24 June 2027', 'سارية حتى 24 يونيو 2027')],
    [T('Owner\'s Emirates ID (the person filing)', 'الهوية الإماراتية لمالك المؤسسة (مقدّم الطلب)'), '—', T('attach at filing', 'تُرفق عند التقديم')],
    [T('The customer\'s request (inquiry)', 'طلب العميل'), T(c.inquiry.summary, c.inquiry.summary_ar), c.inquiry.id],
    [T('Reveal payment receipt', 'إيصال دفع رسوم الكشف'), fmtDate(c.reveal.paid_at, lang) + ' · ' + money(c.reveal.reveal_fee + c.reveal.processing_fee, lang), c.reveal.payment_intent],
    [T('Day-3 chase (customer copied) and its delivery record', 'متابعة اليوم الثالث للمورّد مع نسخة للعميل وتأكيد التسليم'), fmtDate(c.ladder.chase_day3_at, lang), T(c.ladder.chase_delivery, c.ladder.chase_delivery_ar)],
    [T('Day-5 final call by the CEO and its outcome', 'الاتصال الأخير في اليوم الخامس ونتيجته'), fmtDate(c.ladder.final_call_day5_at, lang), T(c.ladder.final_call_outcome, c.ladder.final_call_outcome_ar)],
    [T('Refund to the customer (payment-provider record)', 'ردّ المبلغ إلى العميل (سجلّ مزوّد الدفع)'), fmtDate(c.refund.refunded_at, lang) + ' · ' + money(c.refund.reveal_fee + c.refund.processing_fee, lang), c.refund.refund_id],
    [T('Invoice and its delivery confirmation', 'الفاتورة وتأكيد تسليمها'), fmtDate(c.invoice.date, lang), c.invoice.number],
    ...c.reminders.map((r) => [T(`Reminder ${r.n} and its delivery confirmation`, `التذكير رقم ${r.n} وتأكيد تسليمه`), fmtDate(r.date, lang), `${c.invoice.number}-R${r.n}`]),
    [T('Formal demand and proof of service', 'الإنذار الرسمي بالوفاء وإثبات الإعلان'), fmtDate(c.final_demand.date, lang), c.final_demand.service_ref ?? T(c.final_demand.service, c.final_demand.service_ar)],
    [T('Statement of account with the interest calculation', 'كشف الحساب مع احتساب الفائدة'), fmtDate(c.as_of, lang), c.case_ref],
  ];
  return compact(doc(lang, ref, c.as_of, ar ? 'فهرس المستندات والأدلة' : 'Evidence Index', ar ? 'حافظة مستندات' : 'Filing pack',
    ar ? `مرفقات طلب أمر الأداء — القضية ${c.case_ref}` : `Attachments to the payment-order application — case ${c.case_ref}`,
    [[ar ? 'المرجع' : 'Reference', ref], [ar ? 'عدد المستندات' : 'Documents', String(rows.length)]], [],
    [
      { t: 'table', head: ar ? ['#', 'المستند', 'التاريخ / القيمة', 'المرجع'] : ['#', 'Document', 'Date / value', 'Reference'], rows: rows.map((r, i) => [String(i + 1), ...r]), widths: [0.05, 0.41, 0.19, 0.35], fs: 7 },
      { t: 'note', text: ar ? 'تُقدَّم المستندات باللغة العربية بصيغة PDF؛ ويُقدَّم النص العربي لاتفاقية المورّد، وهو النص المعتمد لجميع الأغراض بما فيها أمام المحاكم (البند 22)؛ وما كان منها بلغة أخرى تُرفق معه ترجمة مترجم قانوني معتمد من وزارة العدل.' : 'Filed in Arabic as PDF: the agreement in its Arabic text (clause 22); any other document with an MOJ-approved translation.' },
    ], true));
}

// ── 4c. The founder's one-page guide ─────────────────────────────────────────────────────────
export function founderGuideDocument(c: CaseFile, lang: Lang) {
  const ar = lang === 'ar', ref = `${c.case_ref}-GUIDE`, d = addDays(c.final_demand.date, LEGAL.final_demand_days);
  const steps = ar ? [
    `تأكّد أن المهلة انقضت: آخر موعد للسداد في الإنذار هو ${fmtDate(d, 'ar')}، وتحقّق في بوابة المحاسب أن المورّد لم يسدّد.`,
    'سجّل الدخول في موقع محاكم دبي (dc.gov.ae) ثم اختر خدمة "أمر الأداء" (رمز الخدمة C5)، وتُقدَّم أيضًا في مراكز الخدمة.',
    'قدّم الطلب بصفتك مالك المؤسسة الفردية وبنفسك (المادة 52 من قانون الإجراءات المدنية تجيز الحضور شخصيًا).',
    'انسخ بيانات الطالب والمطلوب ضده والوقائع والطلبات من "طلب استصدار أمر أداء" (النسخة العربية) — وهي بيانات المادة 44.',
    'ارفع بصيغة PDF وبترتيب "فهرس المستندات والأدلة": صحيفة الطلب، والإنذار بالوفاء مع إشعار تسليمه، ورخصتك التجارية؛ وما كان بغير العربية يُرفق بترجمة مترجم قانوني معتمد من وزارة العدل.',
    'ادفع الرسم إلكترونيًا: 6% من قيمة المطالبة بحد أدنى 500 درهم وحد أقصى 40,000 درهم (صفحة الخدمة C5)؛ لمطالبة بآلاف قليلة يكون الرسم 500 درهم.',
    'يصدر القاضي الأمر أو يرفضه خلال 3 أيام عمل (المادة 144/4). ويجب إعلان الأمر للمدين خلال 3 أشهر وإلا سقط (المادة 146/2).',
    'للمدين التظلم خلال 15 يومًا من إعلانه (المادة 147)؛ فإن لم يتظلم ولم يسدّد، قدّم طلب التنفيذ في محاكم دبي.',
  ] : [
    `Check the deadline has passed: the demand's pay-by date is ${fmtDate(d, 'en')}, and the accountant's ledger shows no payment.`,
    'Sign in to the Dubai Courts website (dc.gov.ae) and open the "Repayment Order" service (service code C5); a service centre also accepts it.',
    'File as the owner of the sole establishment, in person (Civil Procedure Code Art. 52 allows a litigant to appear in person).',
    'Copy the applicant, respondent, facts and relief from the "Application for a Payment Order" (Arabic version) — these are the Art. 44 particulars.',
    'Upload as PDF, in the order of the Evidence Index: the statement of case, the notice for payment with its delivery notification, and your trade licence; anything not in Arabic needs a translation by an MOJ-approved legal translator.',
    'Pay the fee online: 6% of the claim, minimum AED 500, maximum AED 40,000 (C5 service page); for a claim of a few thousand dirhams the fee is AED 500.',
    'The judge issues or refuses the order within 3 business days (Art. 144(4)). The order must be served on the debtor within 3 months or it lapses (Art. 146(2)).',
    'The debtor may file a grievance within 15 days of service (Art. 147); if he neither files one nor pays, apply for execution at the Dubai Courts.',
  ];
  return doc(lang, ref, c.as_of, ar ? 'دليل التقديم خطوة بخطوة' : 'Filing Guide — Step by Step', ar ? 'للمالك' : 'For the owner',
    ar ? 'تقديم طلب أمر الأداء إلى محاكم دبي بنفسك' : 'Filing the payment-order request with the Dubai Courts yourself',
    [[ar ? 'القضية' : 'Case', c.case_ref], [ar ? 'يُقدَّم بعد' : 'File after', fmtDate(d, lang)]], [],
    [
      ...steps.map((s, i) => ({ t: 'li', text: `${i + 1}. ${s}` })),
      { t: 'callout', tone: 'grey', title: ar ? 'ليس أمرًا للشرطة' : 'Not a police matter', text: ar ? 'عدم سداد رسم تعاقدي دَين مدني تجاري يُطالَب به أمام المحاكم، وليس جريمة تُبلَّغ بها الشرطة.' : 'An unpaid contractual charge is a civil and commercial debt claimed in the courts; it is not a crime to report to the police.' },
      { t: 'note', text: ar ? 'هذا الدليل وثيقة عمل أعدّها برنامج QuotesDone وليس استشارة قانونية؛ تُراجع النقاط المذكورة في ملف البحث مع محاكم دبي قبل أول تقديم.' : 'This guide was prepared by QuotesDone software and is not legal advice; check the points listed in the research file with the Dubai Courts before the first filing.' },
    ], false);
}

// ── What went out under the founder's signature ─────────────────────────────────────────────────
// One record per signed PDF: which document, its reference and version, the case and the agreement
// version it rests on, the SHA-256 of the exact bytes issued, who signed, and the brand-store assets
// (and their hashes, when the caller has them) that carried the signature and stamp. Null for a document
// that is not signed (the filing guide). The caller keeps these with the sent message.
export type SigningRecord = {
  document: string; ref: string; lang: Lang; doc_version: string; case_ref: string; agreement_version: string;
  issued: string; pdf_sha256: string; pages: number; signed_by: string; signer_title: string;
  signature_asset: string; stamp_asset: string; signature_asset_sha256: string | null; stamp_asset_sha256: string | null;
};
const hex = (b: ArrayBuffer) => Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, '0')).join('');
export async function sha256Hex(bytes: Uint8Array): Promise<string> { return hex(await crypto.subtle.digest('SHA-256', new Uint8Array(bytes))); }
export async function signingRecord(c: CaseFile, doc: { name: string; lang: Lang; body: ReturnType<typeof invoiceDocument> }, pdf: Uint8Array, pages: number,
  assets: { signature?: Uint8Array | null; stamp?: Uint8Array | null } = {}): Promise<SigningRecord | null> {
  if (!doc.body.options.sign) return null;
  return {
    document: doc.name, ref: doc.body.ref, lang: doc.lang, doc_version: RECOVERY_DOC_VERSION, case_ref: c.case_ref,
    agreement_version: c.acceptance.version, issued: doc.body.issued_iso, pdf_sha256: await sha256Hex(pdf), pages,
    signed_by: FALLBACK.signer, signer_title: FALLBACK.title,
    signature_asset: 'brand/qd_signature.png', stamp_asset: 'brand/qd_stamp.png',
    signature_asset_sha256: assets.signature ? await sha256Hex(assets.signature) : null,
    stamp_asset_sha256: assets.stamp ? await sha256Hex(assets.stamp) : null,
  };
}

/** Every document of a case, in filing order, both languages. */
export function recoveryPack(c: CaseFile) {
  const out: { name: string; lang: Lang; body: ReturnType<typeof doc> }[] = [];
  for (const lang of ['ar', 'en'] as Lang[]) {
    out.push({ name: '1_invoice', lang, body: invoiceDocument(c, lang) });
    for (const r of c.reminders) out.push({ name: `2_reminder_${r.n}`, lang, body: reminderDocument(c, r.n, lang) });
    out.push({ name: '3_final_demand', lang, body: finalDemandDocument(c, lang) });
    out.push({ name: '4a_payment_order_application', lang, body: claimDocument(c, lang) });
    out.push({ name: '4b_evidence_index', lang, body: evidenceIndexDocument(c, lang) });
    out.push({ name: '4c_filing_guide', lang, body: founderGuideDocument(c, lang) });
  }
  return out;
}
