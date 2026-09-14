// line_specs/assess.ts — the hold decision: is every detail the founder requires stated, exactly?
//
// Four things, and only these four (founder, 14 Sep 2026): (1) the material specification of every
// line, per its trade (model.ts); (2) a concrete delivery date or lead time; (3) installation — is it
// included, and its scope or timeline — where installation applies; (4) the warranty period and what
// it covers, where a warranty applies. A quote with any of them missing is HELD: never rejected,
// never shown to the customer, and the supplier is told exactly which line and which detail.
//
// Pure: no I/O, no model, no clock except the `now` passed in. workflow.ts does the writing.
import { attrsForLine, COMPOSITE, installApplies, NON_MATERIAL, normText, TRADES, tradeOfCategory, tradeOfLine, VAGUE, warrantyApplies, type Attr } from './model.ts';
import { OPTION_HEAD } from './options.ts';

export type Line = {
  line_no: number; description: string; brand?: string | null; model?: string | null; specification?: string | null;
  qty?: number | string | null; unit?: string | null; unit_price?: number | null; labour?: number | null; install?: number | null;
  amount?: number | null; notes?: string | null;
  spec?: Record<string, string> | null; spec_source?: Record<string, 'extracted' | 'supplier_portal'> | null;
};
export type Terms = {
  lead_time?: string | null; warranty?: string | null; scope?: string | null; exclusions?: string | null;
  conditions?: string | null; notes?: string | null; terms_spec?: TermsSpec | null;
  /** The figure compared and charged 3% on (vat.ts). Null when it could not be determined exactly. */
  price_ex_vat?: number | null;
};
export type TermsSpec = {
  delivery?: { value: string; source: Src } | null;
  installation?: { included: 'yes' | 'no'; detail?: string | null; source: Src } | null;
  warranty?: { period: string; coverage: string; source: Src } | null;
};
type Src = 'extracted' | 'supplier_portal';
/** The customer's answers from intake (inquiries.spec.requirements) — see docs/contracts/technical_comparison.md. */
export type Requirements = {
  installation?: 'required' | 'not_required' | 'no_preference' | null;
  warranty?: { required?: boolean | 'no_preference' | null; min_months?: number | null } | null;
  delivery_by?: string | null;
  materials?: { component: string; attr?: string | null; value: string }[] | null;
} | null;

export type MissingItem = {
  scope: 'line' | 'quote'; line_no: number | null; description: string | null; attr: string;
  label_en: string; label_ar: string; type: 'text' | 'number' | 'choice'; unit?: string; unit_ar?: string; options?: string[];
};
export type LineResult = {
  line_no: number; description: string; trade: string | null; material: boolean;
  spec: Record<string, string>; source: Record<string, Src>; asked: string[]; missing: string[];
};
export type TermResult = {
  delivery: { applies: true; value: string | null; days: number | null; date: string | null; source: Src | null };
  installation: { applies: boolean; included: 'yes' | 'no' | null; detail: string | null; source: Src | null };
  warranty: { applies: boolean; period: string | null; months: number | null; coverage: string | null; source: Src | null };
};
export type Assessment = { trade: string; held: boolean; lines: LineResult[]; terms: TermResult; missing: MissingItem[] };

// ---------------------------------------------------------------------------------------------
// Quote-level readers. Each returns null for what is not stated, and for what is stated vaguely.
// ---------------------------------------------------------------------------------------------
const MONTHS = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|يناير|فبراير|مارس|أبريل|ابريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر';
const DATE_RE = new RegExp(`\\b(\\d{4}-\\d{2}-\\d{2}|\\d{1,2}[\\/.\\-]\\d{1,2}[\\/.\\-]\\d{2,4}|\\d{1,2}\\s+(?:${MONTHS})\\s*,?\\s*\\d{0,4}|(?:${MONTHS})\\s+\\d{1,2}(?:,\\s*\\d{4})?)`, 'i');
const DUR_RE = /(\d+(?:\.\d+)?)\s*(?:-\s*\d+\s*)?(working\s*days?|business\s*days?|days?|weeks?|months?|wks?|يوم عمل|أيام عمل|يوم|أيام|يوما|يوماً|أسبوع|أسابيع|اسبوع|اسابيع|شهر|أشهر|شهور)/i;
const IMMEDIATE = /\b(ex[\s-]?stock|from\s*stock|immediate(?:ly)?|same\s*day|next\s*day)\b|من المخزون|فوري|فورا|فوراً/i;

export function readDelivery(text: string): { value: string; days: number | null; date: string | null } | null {
  const s = normText(text); if (!s || VAGUE.test(s)) return null;
  const d = s.match(DUR_RE);
  if (d) { const n = Number(d[1]); const u = d[2].toLowerCase(); const days = /week|wk|أسبوع|أسابيع|اسبوع|اسابيع/.test(u) ? n * 7 : /month|شهر|أشهر|شهور/.test(u) ? n * 30 : n; return { value: s.slice(0, 120), days, date: null }; }
  const dt = s.match(DATE_RE); if (dt) return { value: s.slice(0, 120), days: null, date: dt[1] };
  if (IMMEDIATE.test(s)) return { value: s.slice(0, 120), days: 0, date: null };
  return null;
}

const INSTALL_YES = /supply\s*(?:&|and|\+|,)\s*(?:install|fix|apply|lay|erect)|s\s*[&\/]\s*i\b|supply,?\s*install|includ(?:es|ing|ed)?\s*(?:the\s*)?(?:install|fixing)|install(?:ation)?\s*(?:is\s*)?includ|incl\.?\s*install|install(?:ation)?\s*(?:&|and)\s*commission|توريد وتركيب|شامل التركيب|يشمل التركيب|مع التركيب|التركيب مشمول/i;
const INSTALL_NO = /supply\s*only|install(?:ation)?\s*(?:is\s*)?(?:not\s*included|excluded|by\s*others|extra)|exclud(?:es|ing|ed)?\s*(?:the\s*)?install|without\s*install|توريد فقط|بدون تركيب|التركيب غير مشمول|لا يشمل التركيب|غير شامل التركيب/i;
const INSTALL_LINE = /^(?:\d+[.)]\s*)?(?:install|fix|fixing|erect|lay(?:ing)?|تركيب)|\binstall(?:ation)?\s*(?:of|labou?r|charges?)|تركيب/i;
const INSTALL_TIME = /install\w*\s*(?:period|time|duration|within|in)?\s*[:\-]?\s*(\d+\s*(?:working\s*)?(?:days?|weeks?|يوم|أيام|أسبوع|أسابيع))|(\d+\s*(?:working\s*)?(?:days?|weeks?|يوم|أيام|أسبوع|أسابيع))\s*(?:for\s*)?(?:install|تركيب)|(?:مدة التركيب)\s*[:\-]?\s*([^,;.]{2,30})/i;

export function readInstallation(lines: Line[], t: Terms): { included: 'yes' | 'no' | null; detail: string | null } {
  const lineText = lines.map((l) => `${l.description} ${l.specification ?? ''} ${l.notes ?? ''}`).join(' \n ');
  const all = `${lineText}\n${t.scope ?? ''}\n${t.conditions ?? ''}\n${t.notes ?? ''}`;
  const pricedInstall = lines.some((l) => (Number(l.install) || 0) > 0 || (Number(l.labour) || 0) > 0);
  const installLine = lines.find((l) => INSTALL_LINE.test(l.description) || INSTALL_YES.test(l.description));
  const timeM = normText(all).match(INSTALL_TIME);
  const time = timeM ? (timeM[1] || timeM[2] || timeM[3] || '').trim() : '';
  const detail = time ? `Installation in ${time}` : installLine ? `Scope: ${installLine.description.slice(0, 100)}` : pricedInstall ? 'Installation priced per line' : null;
  if (pricedInstall || installLine) return { included: 'yes', detail };
  if (INSTALL_NO.test(all) || INSTALL_NO.test(t.exclusions ?? '')) return { included: 'no', detail: null };
  if (INSTALL_YES.test(all)) {
    // "Supply and installation of the complete joinery package" in the scope IS the installation
    // scope; a bare "installation included" in the notes names no scope and no timeline.
    const src = [t.scope, t.conditions, t.notes].find((x) => x && INSTALL_YES.test(x) && normText(x).length > 25);
    return { included: 'yes', detail: detail ?? (src ? `Scope: ${normText(src).slice(0, 100)}` : null) };
  }
  return { included: null, detail: null };
}

const W_PERIOD = /(\d+(?:\.\d+)?)\s*(years?|yrs?|months?|mos?|سنة|سنوات|سنه|عام|أعوام|اعوام|شهر|أشهر|شهور)|\b(one|two|three|five|ten)\s+years?\b|(سنتين|سنتان|عامين)/i;
const W_COVER = /(manufactur\w*|parts?|spare\s*parts|labou?r|workmanship|compressor|motor|leak\w*|defects?|materials?|installation|panels?|inverters?|performance|replacement|on\s*-?\s*site|structural|finish|mechanical|electrical|مصنعية|المصنعية|الصناعة|قطع(?:\s*الغيار)?|العمالة|عمالة|تسريب|التسريب|العيوب|عيوب|المواد|الضاغط|الكمبروسر|المحرك|التركيب|الأداء|الاستبدال|شامل)/gi;
const WORDNUM: Record<string, number> = { one: 1, two: 2, three: 3, five: 5, ten: 10 };
export function readWarranty(text: string): { period: string | null; months: number | null; coverage: string | null } {
  const s = normText(text);
  if (!s || VAGUE.test(s)) return { period: null, months: null, coverage: null };
  let period: string | null = null, months: number | null = null;
  const m = s.match(W_PERIOD);
  if (m) {
    if (m[1]) { const n = Number(m[1]); const u = m[2].toLowerCase(); const isMonth = /month|mo|شهر|أشهر|شهور/.test(u); months = isMonth ? n : n * 12; period = `${n} ${isMonth ? (n === 1 ? 'month' : 'months') : (n === 1 ? 'year' : 'years')}`; }
    else if (m[3]) { months = WORDNUM[m[3].toLowerCase()] * 12; period = `${months / 12} years`; }
    else if (m[4]) { months = 24; period = '2 years'; }
  }
  const cov = [...new Set([...s.matchAll(W_COVER)].map((x) => x[1].toLowerCase()))];
  return { period, months, coverage: cov.length ? cov.join(', ') : null };
}

const TERM_LABEL: Record<string, [string, string, MissingItem['type']]> = {
  line_items: ['Itemised lines, each with its material specification', 'بنود مفصّلة، لكل بند مواصفات مادته', 'text'],
  delivery: ['Delivery date or lead time (e.g. 21 days, or 30 Oct 2026)', 'تاريخ التسليم أو مدة التنفيذ (مثل 21 يومًا أو 30 أكتوبر 2026)', 'text'],
  installation_included: ['Is installation included?', 'هل التركيب مشمول؟', 'choice'],
  installation_detail: ['Installation scope or timeline', 'نطاق التركيب أو مدته', 'text'],
  warranty_period: ['Warranty period', 'مدة الضمان', 'text'],
  warranty_coverage: ['What the warranty covers', 'ما يغطيه الضمان', 'text'],
  price_ex_vat: ['Total price excluding VAT', 'السعر الإجمالي غير شامل ضريبة القيمة المضافة', 'number'],
};
const termItem = (attr: string): MissingItem => {
  const [en, ar, type] = TERM_LABEL[attr];
  return { scope: 'quote', line_no: null, description: null, attr, label_en: en, label_ar: ar, type, ...(type === 'choice' ? { options: ['yes', 'no'] } : {}), ...(attr === 'price_ex_vat' ? { unit: 'AED', unit_ar: 'درهم' } : {}) };
};
const lineItem = (l: Line, a: Attr): MissingItem => ({
  scope: 'line', line_no: l.line_no, description: l.description, attr: a.code, label_en: a.en, label_ar: a.ar, type: a.type,
  ...(a.unit ? { unit: a.unit, unit_ar: a.unit_ar } : {}), ...(a.options ? { options: a.options } : {}),
});

export const lineText = (l: Line) => [l.description, l.brand, l.model, l.specification, l.notes].filter((x) => x != null && String(x).trim() !== '').join(' · ');

export function assessQuote(input: { category: string | null; lines: Line[]; terms: Terms; requirements?: Requirements }): Assessment {
  const trade = tradeOfCategory(input.category);
  const lines: LineResult[] = [];
  const missing: MissingItem[] = [];
  const lineTrades = new Set<string>();
  let allText = '';
  for (const l of input.lines) {
    const text = lineText(l); allText += ' ' + text;
    const heading = OPTION_HEAD.test(l.description) && !(Number(l.amount) > 0) && !(Number(l.unit_price) > 0);
    const material = !heading && !NON_MATERIAL.test(l.description.trim());
    const lt = material ? tradeOfLine(trade, text) : null;
    const asked = lt ? attrsForLine(lt, text) : [];
    const spec: Record<string, string> = {}; const source: Record<string, Src> = {};
    for (const a of asked) {
      const prior = l.spec?.[a.code];
      if (prior && !VAGUE.test(normText(prior))) { spec[a.code] = prior; source[a.code] = l.spec_source?.[a.code] ?? 'extracted'; continue; }
      const v = a.find(text);
      if (v) { spec[a.code] = v; source[a.code] = 'extracted'; }
    }
    const miss = asked.filter((a) => a.mandatory && !spec[a.code]);
    if (lt) lineTrades.add(lt);
    for (const a of miss) missing.push(lineItem(l, a));
    lines.push({ line_no: l.line_no, description: l.description, trade: lt, material, spec, source, asked: asked.map((a) => a.code), missing: miss.map((a) => a.code) });
  }
  if (!lineTrades.size && (TRADES[trade] || COMPOSITE.has(trade))) missing.unshift(termItem('line_items'));

  const ts = input.terms.terms_spec ?? {};
  const req = input.requirements ?? null;
  const tradesInPlay = lineTrades.size ? [...lineTrades] : [trade];

  // (2) Delivery — every quote.
  const dPortal = ts.delivery?.value ? readDelivery(ts.delivery.value) : null;
  const d = dPortal ?? readDelivery(input.terms.lead_time ?? '');
  const delivery: TermResult['delivery'] = { applies: true, value: d?.value ?? null, days: d?.days ?? null, date: d?.date ?? null, source: d ? (dPortal ? 'supplier_portal' : 'extracted') : null };
  if (!d) missing.push(termItem('delivery'));

  // (3) Installation — where the trade installs something and the customer did not ask for supply only.
  const instApplies = req?.installation !== 'not_required' && tradesInPlay.some(installApplies);
  const iPortal = ts.installation?.included ? ts.installation : null;
  const iRead = iPortal ? { included: iPortal.included, detail: iPortal.detail ?? null } : readInstallation(input.lines, input.terms);
  const installation: TermResult['installation'] = { applies: instApplies, included: instApplies ? iRead.included : null, detail: instApplies ? iRead.detail : null, source: instApplies && iRead.included ? (iPortal ? 'supplier_portal' : 'extracted') : null };
  if (instApplies) {
    if (!iRead.included) missing.push(termItem('installation_included'));
    else if (iRead.included === 'yes' && !(iRead.detail && !VAGUE.test(normText(iRead.detail)))) missing.push(termItem('installation_detail'));
  }

  // (4) Warranty — where the trade or item carries one, or the customer asked for one.
  const warrantyText = `${input.terms.warranty ?? ''} ${input.lines.filter((l) => /warrant|guarant|ضمان/i.test(lineText(l))).map(lineText).join(' ')}`;
  const wApplies = req?.warranty?.required === true || tradesInPlay.some((tr) => warrantyApplies(tr, allText));
  const wPortal = ts.warranty?.period ? ts.warranty : null;
  const wRead = wPortal ? { ...readWarranty(wPortal.period), coverage: wPortal.coverage } : readWarranty(warrantyText);
  const warranty: TermResult['warranty'] = { applies: wApplies, period: wApplies ? wRead.period : null, months: wApplies ? wRead.months : null, coverage: wApplies ? wRead.coverage : null, source: wApplies && wRead.period ? (wPortal ? 'supplier_portal' : 'extracted') : null };
  if (wApplies) {
    if (!wRead.period) missing.push(termItem('warranty_period'));
    if (!(wRead.coverage && !VAGUE.test(normText(wRead.coverage)))) missing.push(termItem('warranty_coverage'));
  }

  // (5) The price excluding VAT (founder, 14 Sep 2026: VAT details are hidden from the customer, and
  // the ex-VAT price is what is compared and charged on). Missing or ambiguous is held.
  if (!(Number(input.terms.price_ex_vat) > 0)) missing.push(termItem('price_ex_vat'));

  return { trade, held: missing.length > 0, lines, terms: { delivery, installation, warranty }, missing };
}

// ---------------------------------------------------------------------------------------------
// Portal fill-in validation. The same readers decide, so a value the portal accepts is a value the
// hold gate accepts.
// ---------------------------------------------------------------------------------------------
export type FillError = { scope: 'line' | 'quote'; line_no: number | null; attr: string; code: 'vague' | 'not_a_number' | 'not_concrete' | 'choose_yes_or_no' | 'unknown_attribute' | 'too_long' };
export function validateLineValue(a: Attr, raw: unknown): { ok: true; value: string } | { ok: false; code: FillError['code'] } {
  const v = normText(String(raw ?? ''));
  if (!v || VAGUE.test(v) || v.length < 1) return { ok: false, code: 'vague' };
  if (v.length > 120) return { ok: false, code: 'too_long' };
  if (a.type === 'number') { const n = Number(v.replace(/[^\d.]/g, '')); if (!(n > 0) || !/\d/.test(v)) return { ok: false, code: 'not_a_number' }; return { ok: true, value: String(n) }; }
  if (v.length < 2) return { ok: false, code: 'vague' };
  return { ok: true, value: v };
}
export function validateTerm(attr: string, raw: unknown): { ok: true; value: string } | { ok: false; code: FillError['code'] } {
  const v = normText(String(raw ?? ''));
  if (attr === 'installation_included') return v === 'yes' || v === 'no' ? { ok: true, value: v } : { ok: false, code: 'choose_yes_or_no' };
  if (!v || VAGUE.test(v)) return { ok: false, code: 'vague' };
  if (v.length > 200) return { ok: false, code: 'too_long' };
  if (attr === 'price_ex_vat') { const n = Number(v.replace(/[^\d.]/g, '')); return n > 0 && /\d/.test(v) ? { ok: true, value: String(Math.round(n * 100) / 100) } : { ok: false, code: 'not_a_number' }; }
  if (attr === 'delivery') return readDelivery(v) ? { ok: true, value: v } : { ok: false, code: 'not_concrete' };
  if (attr === 'warranty_period') return readWarranty(v).period ? { ok: true, value: v } : { ok: false, code: 'not_concrete' };
  if (attr === 'installation_detail' || attr === 'warranty_coverage') return v.length >= 3 ? { ok: true, value: v } : { ok: false, code: 'vague' };
  return { ok: false, code: 'unknown_attribute' };
}

// ---------------------------------------------------------------------------------------------
// The hold note and the supplier's notice, in the supplier's language, signed by the seat that owns
// the supplier portal (founder, 14 Sep 2026: "its always the sales agent").
// ---------------------------------------------------------------------------------------------
export const SEAT = 'sales_engineer' as const;
export const SEAT_LABEL = { en: 'QuotesDone sales engineer', ar: 'مهندس المبيعات في QuotesDone' } as const;

export function holdLines(a: Assessment, lang: 'en' | 'ar'): string[] {
  const ar = lang === 'ar';
  return a.missing.map((m) => {
    const label = ar ? m.label_ar : m.label_en;
    if (m.scope === 'quote') return `• ${label}`;
    return ar ? `• البند ${m.line_no} (${(m.description ?? '').slice(0, 70)}): ${label}` : `• Line ${m.line_no} (${(m.description ?? '').slice(0, 70)}): ${label}`;
  });
}
export function holdNotice(a: Assessment, lang: 'en' | 'ar', ref: string, optionLabel?: string | null): { subject: string; body: string } {
  const ar = lang === 'ar';
  const opt = optionLabel ? (ar ? ` — ${optionLabel}` : ` — ${optionLabel}`) : '';
  const subject = ar ? `عرضك معلّق حتى تُذكر التفاصيل الدقيقة — الطلب ${ref}${opt}` : `Your quote is on hold until the exact details are stated — RFQ ${ref}${opt}`;
  const lines = holdLines(a, lang).join('\n');
  const body = ar
    ? `مرحبًا،\n\nعرضك للطلب ${ref}${opt} معلّق ولن يُعرض على العميل حتى تُذكر التفاصيل الدقيقة التالية:\n\n${lines}\n\nلديك طريقتان:\n1) أكمل التفاصيل الناقصة في بوابة المورّدين، وسنعيد إعداد عرضك بالصيغة الموحّدة لتراجعه وتؤكد أنه صحيح، ثم يُرسل إلى العميل.\n2) أو ارفع عرضًا معدّلًا جديدًا يتضمن هذه التفاصيل.\n\n${SEAT_LABEL.ar}`
    : `Hello,\n\nYour quote for RFQ ${ref}${opt} is on hold and will not be shown to the customer until the following exact details are stated:\n\n${lines}\n\nYou have two ways to release it:\n1) Fill in the missing details on the supplier portal. We will regenerate your quotation in the standard format for you to check and confirm it is correct, and it is then sent to the customer.\n2) Or upload a new revised quote that states these details.\n\n${SEAT_LABEL.en}`;
  return { subject, body };
}
