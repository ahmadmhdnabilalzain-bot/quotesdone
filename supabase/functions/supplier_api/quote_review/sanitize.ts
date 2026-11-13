import { type TermsSpec } from '../../_shared/line_specs/assess.ts';
import { VAGUE } from '../../_shared/line_specs/model.ts';
import { type VatTreatment } from '../../_shared/line_specs/vat.ts';
import { type Correction, type Topic, clean } from './reply.ts';
import { type Said, arPeriod } from './said.ts';
import { fmt } from './review.ts';
import { type Issue, type Lang } from './types.ts';

// ---------------------------------------------------------------------------------------------
// What the chat confirmed, carried into submit_quote so the hold gate reads the same details.
// submit_quote accepts them from any caller, so they are cleaned there too: a value is text, at most
// 120 characters, with contact details and identity numbers removed, and a vague value is dropped.
// ---------------------------------------------------------------------------------------------
const okVal = (v: unknown, n = 120) => { if (v == null || typeof v === 'object') return null; const s = clean(String(v), n); return s && !VAGUE.test(s) ? s : null; };
/** A line's specification by attribute code (line_specs/model.ts), cleaned. */
export function sanitizeSpec(spec: unknown): { spec: Record<string, string>; source: Record<string, 'supplier_portal'> } {
  const out: Record<string, string> = {}; const source: Record<string, 'supplier_portal'> = {};
  if (spec && typeof spec === 'object' && !Array.isArray(spec)) {
    for (const [k, v] of Object.entries(spec as Record<string, unknown>).slice(0, 40)) {
      if (!/^[a-z][a-z0-9_:]{0,60}$/.test(k)) continue;
      const s = okVal(v); if (s) { out[k] = s; source[k] = 'supplier_portal'; }
    }
  }
  return { spec: out, source };
}
/** Delivery / installation / warranty as the supplier confirmed them (assess.ts TermsSpec), cleaned. */
export function sanitizeTermsSpec(ts: unknown): TermsSpec | null {
  if (!ts || typeof ts !== 'object' || Array.isArray(ts)) return null;
  // deno-lint-ignore no-explicit-any
  const t = ts as any; const out: TermsSpec = {};
  const dv = okVal(t.delivery?.value); if (dv) out.delivery = { value: dv, source: 'supplier_portal' };
  if (t.installation?.included === 'yes' || t.installation?.included === 'no') out.installation = { included: t.installation.included, detail: t.installation.included === 'yes' ? okVal(t.installation.detail) : null, source: 'supplier_portal' };
  const wp = okVal(t.warranty?.period, 60); if (wp) out.warranty = { period: wp, coverage: okVal(t.warranty?.coverage) ?? '', source: 'supplier_portal' };
  if (t.components && typeof t.components === 'object') {
    const c: Record<string, { value: string; source: 'supplier_portal' }> = {};
    for (const [k, v] of Object.entries(t.components as Record<string, { value?: unknown }>).slice(0, 20)) { const s = okVal(v?.value); if (s && /^[a-z][a-z0-9_]{0,40}$/.test(k)) c[k] = { value: s, source: 'supplier_portal' }; }
    if (Object.keys(c).length) out.components = c;
  }
  return Object.keys(out).length ? out : null;
}

/** What the engineer says to a stated detail: which ones it took, in the supplier's own words. */
export function tookSaid(cs: Correction[]): Said | null {
  if (!cs.length) return null;
  const en: string[] = [], ar: string[] = [];
  for (const c of cs) {
    if (c.field === 'validity') { en.push(`validity ${c.value}`); ar.push(`الصلاحية ${arPeriod(c.value)}`); }
    else if (c.field === 'lead_time') { en.push(`lead time ${c.value}`); ar.push(`مدة التسليم ${arPeriod(c.value)}`); }
    else if (c.field === 'price_ex_vat') { en.push(`price excluding VAT AED ${fmt(c.value)}`); ar.push(`السعر غير شامل الضريبة ${fmt(c.value)} درهم`); }
    else if (c.field === 'vat_treatment') {
      // Every treatment readVat can return is worded here — a value with no wording would have been
      // applied to the quotation and never acknowledged back to the supplier.
      const m: Record<Exclude<VatTreatment, 'not_stated'>, [string, string]> = {
        exclusive: ['prices exclude VAT', 'الأسعار غير شاملة الضريبة'],
        inclusive: ['prices include VAT', 'الأسعار شاملة الضريبة'],
        not_registered: ['not VAT-registered', 'غير مسجل في الضريبة'],
        zero_rated: ['the supply is zero-rated (0% VAT)', 'التوريد خاضع لنسبة الصفر'],
        exempt: ['the supply is exempt from VAT', 'التوريد معفى من الضريبة'],
        confirmed_on_portal: ['the price excluding VAT as you stated it', 'السعر غير شامل الضريبة كما ذكرتموه'],
      };
      const x = m[c.value]; en.push(x[0]); ar.push(x[1]);
    }
    else if (c.field === 'warranty_terms') { en.push(`warranty ${[c.period, c.coverage].filter(Boolean).join(', ')}`); ar.push(`الضمان ${[c.period ? arPeriod(c.period) : null, c.coverage].filter(Boolean).join('، ')}`); }
    else if (c.field === 'installation') { en.push(c.included === 'yes' ? `installation included${c.detail ? ` (${c.detail})` : ''}` : 'supply only, no installation'); ar.push(c.included === 'yes' ? `التركيب مشمول${c.detail ? ` (${c.detail})` : ''}` : 'توريد فقط دون تركيب'); }
    else if (c.field === 'aed') { en.push('all prices in AED'); ar.push('كل الأسعار بالدرهم'); }
    else if (c.field === 'boq_excluded') { en.push(`BOQ line ${c.boq_line} excluded${c.value ? ` (${c.value})` : ''}`); ar.push(`البند ${c.boq_line} مستثنى${c.value ? ` (${c.value})` : ''}`); }
    else if (c.field === 'qty_explained') { const u = c.what === 'unit'; en.push(`BOQ line ${c.boq_line} ${u ? 'unit' : 'quantity'} explained`); ar.push(u ? `وُضّحت وحدة البند ${c.boq_line}` : `وُضّحت كمية البند ${c.boq_line}`); }
    else if (c.field === 'line_spec') { en.push(`line ${c.line_no}: ${c.value}`); ar.push(`البند ${c.line_no}: ${c.value}`); }
    else if (c.field === 'boq_price') {
      const parts = [c.unit_price != null ? `AED ${fmt(c.unit_price)} per unit` : '', c.amount != null ? `AED ${fmt(c.amount)}` : ''].filter(Boolean).join(' = ');
      const partsAr = [c.unit_price != null ? `${fmt(c.unit_price)} درهم للوحدة` : '', c.amount != null ? `${fmt(c.amount)} درهم` : ''].filter(Boolean).join(' = ');
      en.push(`BOQ line ${c.boq_line} priced at ${parts}`); ar.push(`سُعّر البند ${c.boq_line}: ${partsAr}`);
    }
    else if (c.field === 'line_price') {
      const parts = [c.unit_price != null ? `AED ${fmt(c.unit_price)} per unit` : '', c.amount != null ? `AED ${fmt(c.amount)}` : ''].filter(Boolean).join(' = ');
      const partsAr = [c.unit_price != null ? `${fmt(c.unit_price)} درهم للوحدة` : '', c.amount != null ? `${fmt(c.amount)} درهم` : ''].filter(Boolean).join(' = ');
      en.push(`your line ${c.line_no} priced at ${parts}`); ar.push(`سُعّر بندكم ${c.line_no}: ${partsAr}`);
    }
    else if (c.field === 'total') { en.push(`total AED ${fmt(c.value)}`); ar.push(`الإجمالي ${fmt(c.value)} درهم`); }
    else if (c.field === 'total_explained') { en.push(`difference in the total: ${c.value}`); ar.push(`سبب الفرق في الإجمالي: ${c.value}`); }
    else if (c.field === 'component') { en.push(`${c.label_en}: ${c.value}`); ar.push(`${c.label_ar}: ${c.value}`); }
  }
  return { en: `Thank you — noted: ${en.join('; ')}.`, ar: `شكرًا لكم، سجّلت ما يلي: ${ar.join('؛ ')}.` };
}

/** The engineer's answer to a question, from the rules and the job — never a guess. */
export function answerSaid(topic: Topic, job: string, open: Issue[], boqLines: number): Said {
  const list = (lang: Lang) => open.length
    ? (lang === 'en' ? `Still open for Job ${job}:\n` : `ما زال مطلوبًا للطلب ${job}:\n`) + open.map((x, i) => `${i + 1}. ${lang === 'en' ? x.en : x.ar}`).join('\n')
    : (lang === 'en' ? `Nothing is outstanding on Job ${job}.` : `لا توجد نقاط معلّقة على الطلب ${job}.`);
  switch (topic) {
    case 'vat': return {
      en: 'The customer compares prices excluding VAT and never sees your VAT details or TRN. Tell me whether your total includes VAT, excludes VAT, or that you are not VAT-registered. A business below the AED 375,000 registration threshold is not VAT-registered and does not need a TRN — just reply "not VAT registered".',
      ar: 'يقارن العميل الأسعار غير شاملة الضريبة، ولا يطّلع على بياناتكم الضريبية ولا على رقمكم الضريبي. يُرجى إفادتي بما إذا كان إجماليكم شاملًا الضريبة أم غير شامل لها، أو أنكم غير مسجّلين. والمنشأة التي تقل إيراداتها عن حدّ التسجيل البالغ 375,000 درهم غير مسجّلة ولا تحتاج إلى رقم ضريبي، ويكفي أن تكتبوا «غير مسجل في الضريبة».' };
    case 'validity': return { en: 'Validity is how long your prices hold. State it as a number of days or a date, for example "validity 30 days".', ar: 'الصلاحية هي المدة التي تظل فيها أسعاركم سارية. يُرجى ذكرها بعدد الأيام أو بتاريخ محدد، مثل «الصلاحية 30 يومًا».' };
    case 'currency': return { en: 'Every price must be in UAE dirhams (AED). If your file shows another currency, re-state the prices in AED, or reply "all prices in AED" if they already are.', ar: 'يجب أن تكون الأسعار كافة بالدرهم الإماراتي. فإن تضمّن ملفكم عملة أخرى، يُرجى إعادة ذكر الأسعار بالدرهم، أو كتابة «كل الأسعار بالدرهم» إن كانت كذلك.' };
    case 'boq': return {
      en: `I compare every line of the job's bill of quantities${boqLines ? ` (${boqLines} lines)` : ''} with your quotation: each must be priced, with the same quantity and unit. If a line is excluded, reply "BOQ line 3 excluded — reason". If your quantity differs on purpose, reply "BOQ line 3 quantity — why".`,
      ar: `أقارن كل بند في جدول كميات الطلب${boqLines ? ` (عدد البنود: ${boqLines})` : ''} بما يقابله في عرضكم، ويجب أن يكون مسعّرًا بالكمية والوحدة ذاتهما. فإن كان أحد البنود مستثنى فاكتبوا «البند 3 مستثنى — السبب»، وإن اختلفت كميتكم عن قصد فاكتبوا «البند 3 الكمية — السبب».` };
    case 'customer': return {
      en: "The customer's identity stays private until they choose to reveal a quotation — that is how QuotesDone works, for them and for you. Keep your own contact details out of the quotation as well; they are removed before the customer sees it.",
      ar: 'تظل هوية العميل محجوبة إلى أن يختار الكشف عن أحد العروض؛ فهذا هو أسلوب عمل QuotesDone حمايةً له ولكم. ويُرجى كذلك عدم إدراج بيانات التواصل مع شركتكم في العرض، إذ تُحذف قبل أن يطّلع عليه العميل.' };
    case 'delivery': return { en: 'State a concrete delivery date or lead time, for example "lead time 3 weeks" or "delivery 30 Oct 2026".', ar: 'يُرجى ذكر تاريخ تسليم أو مدة تنفيذ محددة، مثل «مدة التسليم 3 أسابيع» أو «التسليم 30 أكتوبر 2026».' };
    case 'warranty': return { en: 'State the warranty period and what it covers, for example "warranty 2 years, parts and labour".', ar: 'يُرجى ذكر مدة الضمان وما يشمله، مثل «الضمان سنتان، القطع والعمالة».' };
    case 'installation': return { en: 'Tell me whether installation is included and its scope or timeline, for example "installation included, 5 working days on site", or "supply only".', ar: 'يُرجى إفادتي بما إذا كان التركيب مشمولًا، مع نطاقه أو مدته، مثل «التركيب مشمول، 5 أيام عمل في الموقع»، أو «توريد فقط».' };
    default: return { en: list('en'), ar: list('ar') };
  }
}
export const notUnderstoodSaid = (job: string, open: Issue[]): Said => {
  const a = answerSaid('missing', job, open, 0);
  return { en: `I could not match that to an open point. ${a.en}`, ar: `لم أتمكن من ربط ردّكم بأي من النقاط المفتوحة. ${a.ar}` };
};
