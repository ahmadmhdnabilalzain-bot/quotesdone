// supplier_api/quote_review.ts — THE SALES ENGINEER REVIEWS A SUPPLIER'S QUOTATION, BY RULE.
// Assigned: sales_engineer (founder, 14 Sep 2026: "its always the sales agent. no other agent is
// involved in customer or supplier portal").
//
// THE FOUNDER, 15 Sep 2026: "this is the most important part in the whole supplier portal". The
// supplier attaches a quotation in a chat with the sales engineer; the engineer reviews it at once
// against our rules and either replies "Quotation approved for submission" or lists, line by line,
// the adjustments and clarifications needed. The supplier answers in the same conversation.
//
// THE RULES, in the order they are checked. Nothing here calls a model (OpenRouter is on hold, and a
// review must say the same thing every time it is asked):
//   1. every line of the job's bill of quantities is priced in the quotation (matched by words);
//   2. the quantity and the unit of each matched line agree with the BOQ;
//   3. every quotation line that states a quantity also states a price;
//   4. the line amounts add up to the total;
//   5. prices are in AED;
//   6. the VAT basis is stated — includes, excludes, or not VAT-registered. A business below the
//      AED 375,000 registration threshold is not registered and needs no TRN, so a TRN is never asked
//      for (founder: "no VAT till AED 375k; never ask again");
//   7. the validity of the prices is concrete (a number of days or a date);
//   8. the exact-specs rules the hold desk already enforces (founder, 14 Sep 2026, "exact specs or the
//      quote is held"): per-line material specification for the trade and for every component the
//      customer named, a concrete delivery date or lead time, installation and warranty when they
//      apply, and the price excluding VAT — _shared/line_specs/assess.ts, called here unchanged, so
//      the chat and the hold gate submit_quote runs can never disagree about what is missing.
//
// WHAT IT DOES NOT DO: it never decides a price is too high or too low, never compares a supplier to
// another supplier, and never tells a supplier anything about the customer beyond the scrubbed
// inquiry the inbox already serves. Pure: no I/O, no clock, no model.
import { assessQuote, readDelivery, readInstallation, readWarranty, requirementsOf, type Line, type MissingItem, type TermsSpec } from '../_shared/line_specs/assess.ts';
import { normText, VAGUE } from '../_shared/line_specs/model.ts';
import { OPTION_HEAD } from '../_shared/line_specs/options.ts';
import { readVat } from '../_shared/line_specs/vat.ts';
import { maskIdentityNumbers } from '../_shared/identity_numbers.ts';
import { scrubIdentity } from '../drawing_boq/boq_from_text.ts';
import type { Proposal } from '../quote_extract/quote_from_document.ts';

export const SEAT = 'sales_engineer' as const;
export type Lang = 'en' | 'ar';

// ---------------------------------------------------------------------------------------------
// The shapes the review reads.
// ---------------------------------------------------------------------------------------------
/** One row of the job's bill of quantities, as the supplier inbox serves it (already scrubbed). */
export type BoqRow = { section?: string | null; description?: string | null; qty?: number | string | null; unit?: string | null };
/** The inquiry as this supplier may see it — the output of supplier_api `inbox`, never the raw row. */
export type SafeInquiry = {
  id: string; job_no: string; category: string | null; emirate: string | null; spec: unknown;
  boq_rows: BoqRow[]; boq_withheld: boolean; concluded: boolean; revealed: boolean;
};
export type WLine = {
  description: string; qty: string; unit: string; unit_price: number | null; amount: number | null; option?: number;
  spec?: Record<string, string>; spec_source?: Record<string, 'extracted' | 'supplier_portal'>;
};
/** The quotation under review: what the file said, plus every detail the supplier confirmed in the chat. */
export type Working = {
  lines: WLine[]; amount: number | null; subtotal: number | null; vat_amount: number | null;
  vat_treatment: string | null; price_ex_vat: number | null; trn: string | null;
  lead_time: string; validity: string; payment_terms: string; warranty: string;
  scope: string; conditions: string; exclusions: string; notes: string;
  terms_spec: TermsSpec; masked_terms: string[]; option_totals: Record<string, number>;
  /** A currency other than AED seen in the file, until the supplier confirms the prices are AED. */
  foreign_currency: string | null;
  /** BOQ line number → the supplier's reason it is excluded. */
  boq_excluded: Record<string, string>;
  /** BOQ line number → the supplier's explanation of a quantity that differs on purpose; "<n>:unit" → of a unit. */
  qty_explained: Record<string, string>;
  /** Every detail changed in the chat, in order — the audit trail of what the engineer was told. */
  corrections: { field: string; value: string; line?: number | null }[];
};

export type IssueCode =
  | 'boq_line_not_priced' | 'qty_mismatch' | 'unit_mismatch' | 'line_unpriced' | 'total_mismatch'
  | 'currency_not_aed' | 'vat_basis' | 'vat_ex_price' | 'validity'
  | 'spec' | 'line_items' | 'delivery' | 'installation_included' | 'installation_detail'
  | 'warranty_period' | 'warranty_coverage' | 'price_ex_vat' | 'component';
export type Issue = {
  code: IssueCode; kind: 'adjustment' | 'clarification';
  /** The supplier's own line (1-based, in the order of their quotation). */
  line_no: number | null;
  /** The job's BOQ line (1-based, as the inquiry shows it). */
  boq_line: number | null;
  attr: string | null; en: string; ar: string;
};
export type Review = { approved: boolean; issues: Issue[]; price_ex_vat: number | null; boq_lines: number; matched: number };

/** The key that tracks one request across reviews: the same missing detail is the same request. */
export const issueKey = (i: Pick<Issue, 'code' | 'line_no' | 'boq_line' | 'attr'>) => `${i.code}|${i.line_no ?? ''}|${i.boq_line ?? ''}|${i.attr ?? ''}`;
/** The job number every supplier-facing surface prints — the same 8 characters the hold notices use. */
export const jobNo = (inquiryId: string) => String(inquiryId || '').slice(0, 8).toUpperCase();

// ---------------------------------------------------------------------------------------------
// Reading a quotation file's proposal (quote_extract/quote_from_document.ts) into the working quote.
// ---------------------------------------------------------------------------------------------
const num = (v: unknown): number | null => { const n = Number(v); return Number.isFinite(n) && String(v ?? '').trim() !== '' ? n : null; };
export function parseQty(q: unknown): { n: number | null; unit: string } {
  const s = normText(String(q ?? ''));
  const m = s.match(/-?\d[\d,]*(?:\.\d+)?/);
  const n = m ? Number(m[0].replace(/,/g, '')) : null;
  return { n: n != null && Number.isFinite(n) ? n : null, unit: (m ? s.replace(m[0], '') : s).trim() };
}
const FOREIGN = /\b(USD|US\$|EUR|GBP|SAR|QAR|OMR|KWD|BHD|INR|CNY|RMB)\b|[€£]/;
export function foreignCurrency(text: string): string | null { const m = String(text || '').match(FOREIGN); return m ? m[0] : null; }

export function workingFromProposal(p: Proposal, fileText = ''): Working {
  const lines: WLine[] = (p.line_items || []).map((l) => {
    const { n, unit } = parseQty(l.qty);
    const amount = l.amount == null ? null : Number(l.amount);
    return { description: String(l.description || ''), qty: n == null ? '' : String(n), unit, amount,
      unit_price: n && amount ? Math.round((amount / n) * 100) / 100 : null, ...(l.option != null ? { option: l.option } : {}) };
  });
  return {
    lines, amount: p.amount, subtotal: p.subtotal, vat_amount: p.vat_amount, vat_treatment: p.vat_treatment ?? null,
    price_ex_vat: p.price_ex_vat, trn: p.trn, lead_time: p.lead_time || '', validity: p.validity || '', payment_terms: p.payment_terms || '',
    warranty: p.warranty || '', scope: p.scope || '', conditions: p.conditions || '', exclusions: p.exclusions || '', notes: '',
    terms_spec: {}, masked_terms: p.masked_terms || [], option_totals: p.option_totals || {},
    foreign_currency: foreignCurrency(fileText), boq_excluded: {}, qty_explained: {}, corrections: [],
  };
}

// ---------------------------------------------------------------------------------------------
// Matching the BOQ to the quotation, by words.
// ---------------------------------------------------------------------------------------------
const STOP = new Set(['and', 'the', 'for', 'with', 'all', 'per', 'including', 'incl', 'supply', 'install', 'installation', 'fixing',
  'item', 'items', 'work', 'works', 'provide', 'providing', 'nos', 'sqm', 'each', 'type', 'توريد', 'تركيب', 'وتركيب', 'مع', 'في', 'من', 'على']);
const toks = (s: unknown) => normText(String(s ?? '')).toLowerCase().split(/[^\p{L}\p{N}]+/u)
  .filter((w) => w.length >= 3 && !STOP.has(w) && !/^\d+$/.test(w)).map((w) => w.replace(/ies$/, 'y').replace(/s$/, ''));
const UNIT: [RegExp, string][] = [
  [/^(m2|m²|sqm|sq\.?\s?m(?:tr|t)?|square\s*met(?:er|re)s?|متر مربع|م2|م²)$/i, 'm2'],
  [/^(m3|m³|cum|cbm|cu\.?\s?m|cubic\s*met(?:er|re)s?|متر مكعب|م3)$/i, 'm3'],
  [/^(lm|rm|rmt|r\.m|l\.m|m|mtrs?|met(?:er|re)s?|linear\s*met(?:er|re)s?|running\s*met(?:er|re)s?|متر طولي|م\.ط|متر|م)$/i, 'm'],
  [/^(nos?|nr|pcs?|pieces?|each|ea|units?|عدد|قطعة|حبة|وحدة)$/i, 'nr'],
  [/^(sets?|طقم|مجموعة)$/i, 'set'],
  [/^(ls|l\.s|lot|lump\s*sum|job|مقطوعية)$/i, 'ls'],
  [/^(kg|kgs|kilograms?|كغ|كجم)$/i, 'kg'],
  [/^(t|tons?|tonnes?|طن)$/i, 't'],
  [/^(l|ltr|litres?|liters?|لتر)$/i, 'l'],
];
/** A unit in one spelling, so "sqm" and "m²" agree. An unknown unit is returned as written. */
export function normUnit(u: unknown): string {
  const s = normText(String(u ?? '')).toLowerCase().replace(/\.$/, '');
  if (!s) return '';
  for (const [re, v] of UNIT) if (re.test(s)) return v;
  return s;
}
const priced = (l: WLine) => (Number(l.amount) || 0) > 0 || (Number(l.unit_price) || 0) > 0;
const heading = (l: WLine) => OPTION_HEAD.test(l.description) && !priced(l);

/**
 * Each BOQ line to at most one quotation line and back: the pair sharing the largest share of the
 * BOQ line's words wins first. Half the BOQ line's words, or three words, is a match.
 * ponytail: word overlap, not meaning — "WC" and "water closet" do not match. The supplier sees the
 * unmatched line by name and answers "BOQ line 3 is my line 2" or prices it; add a synonym table
 * when a real quotation shows it is needed.
 */
export function matchBoq(boq: BoqRow[], lines: WLine[]): Map<number, number> {
  const cand: { i: number; j: number; s: number }[] = [];
  boq.forEach((b, i) => {
    const bt = toks(b.description); if (!bt.length) return;
    lines.forEach((l, j) => {
      if (heading(l)) return;
      const lt = new Set(toks(l.description));
      const shared = bt.filter((t) => lt.has(t)).length;
      const s = shared / bt.length;
      if (s >= 0.5 || shared >= 3) cand.push({ i, j, s });
    });
  });
  cand.sort((a, b) => b.s - a.s || a.i - b.i || a.j - b.j);
  const out = new Map<number, number>(); const used = new Set<number>();
  for (const c of cand) { if (out.has(c.i) || used.has(c.j)) continue; out.set(c.i, c.j); used.add(c.j); }
  return out;
}

// ---------------------------------------------------------------------------------------------
// The review.
// ---------------------------------------------------------------------------------------------
const cut = (s: unknown, n = 60) => { const t = normText(String(s ?? '')); return t.length > n ? t.slice(0, n - 1) + '…' : t; };
const fmt = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(2));
const I = (code: IssueCode, kind: Issue['kind'], line_no: number | null, boq_line: number | null, attr: string | null, en: string, ar: string): Issue => ({ code, kind, line_no, boq_line, attr, en, ar });
const assessLines = (w: Working): Line[] => w.lines.map((l, i) => ({ line_no: i + 1, description: l.description, qty: l.qty, unit: l.unit, unit_price: l.unit_price, amount: l.amount, spec: l.spec ?? null, spec_source: l.spec_source ?? null }));

export function reviewQuotation(inq: SafeInquiry, w: Working): Review {
  const issues: Issue[] = [];
  const boq = inq.boq_withheld ? [] : (inq.boq_rows || []).filter((r) => normText(String(r.description ?? '')));
  const lines = w.lines;

  // 1–2. The BOQ, line by line.
  const match = matchBoq(boq, lines);
  boq.forEach((b, i) => {
    const n = i + 1; const d = cut(b.description);
    if (w.boq_excluded[String(n)]) return;
    const j = match.get(i);
    const l = j == null ? null : lines[j];
    if (!l || !priced(l)) {
      issues.push(I('boq_line_not_priced', 'adjustment', l ? j! + 1 : null, n, null,
        `BOQ line ${n} (${d}) is not priced in your quotation. Add its price, or tell me it is excluded and why (for example: "BOQ line ${n} excluded — by others").`,
        `البند ${n} من جدول الكميات (${d}) غير مسعّر في عرضك. أضف سعره، أو أخبرني أنه مستثنى وسبب ذلك (مثال: "البند ${n} مستثنى — من قبل الغير").`));
      return;
    }
    // A quantity and a unit are explained separately ("BOQ line 3 quantity — …" / "… unit — …"): an
    // explained quantity must not silence a unit that differs (TypeScript review, 15 Sep 2026).
    const bq = num(b.qty); const lq = parseQty(l.qty).n;
    if (!w.qty_explained[String(n)] && bq != null && lq != null && Math.abs(bq - lq) > Math.max(0.01, Math.abs(bq) * 0.01)) {
      issues.push(I('qty_mismatch', 'clarification', j! + 1, n, 'qty',
        `BOQ line ${n} (${d}): your line ${j! + 1} prices ${fmt(lq)} ${l.unit || ''}`.trimEnd() + ` but the BOQ asks for ${fmt(bq)} ${b.unit || ''}`.trimEnd() + `. Price the BOQ quantity, or tell me why yours differs (for example: "BOQ line ${n} quantity — measured on site").`,
        `البند ${n} من جدول الكميات (${d}): بندك ${j! + 1} يسعّر ${fmt(lq)} ${l.unit || ''}`.trimEnd() + ` بينما يطلب الجدول ${fmt(bq)} ${b.unit || ''}`.trimEnd() + `. سعّر كمية الجدول، أو اذكر سبب الاختلاف (مثال: "البند ${n} الكمية — حسب القياس في الموقع").`));
    }
    const bu = normUnit(b.unit), lu = normUnit(l.unit);
    if (!w.qty_explained[`${n}:unit`] && bu && lu && bu !== lu) {
      issues.push(I('unit_mismatch', 'clarification', j! + 1, n, 'unit',
        `BOQ line ${n} (${d}) is measured in ${b.unit}, your line ${j! + 1} in ${l.unit}. Re-state it in ${b.unit}, or explain the conversion.`,
        `البند ${n} من جدول الكميات (${d}) مقاس بوحدة ${b.unit}، وبندك ${j! + 1} بوحدة ${l.unit}. أعد ذكره بوحدة ${b.unit} أو وضّح التحويل.`));
    }
  });

  // 3. A line with a quantity and no price.
  lines.forEach((l, j) => {
    if (heading(l) || priced(l) || !l.qty) return;
    if ([...match.values()].includes(j)) return;   // already raised against its BOQ line
    issues.push(I('line_unpriced', 'adjustment', j + 1, null, null,
      `Your line ${j + 1} (${cut(l.description)}) has a quantity but no price. Add its price.`,
      `بندك ${j + 1} (${cut(l.description)}) فيه كمية دون سعر. أضف سعره.`));
  });

  // 5. Currency.
  if (w.foreign_currency) {
    issues.push(I('currency_not_aed', 'adjustment', null, null, 'currency',
      `Your quotation shows prices in ${w.foreign_currency}. Every price must be in UAE dirhams (AED): re-state them in AED, or reply "all prices in AED" if they already are.`,
      `يظهر في عرضك سعر بعملة ${w.foreign_currency}. يجب أن تكون كل الأسعار بالدرهم الإماراتي: أعد ذكرها بالدرهم، أو اكتب "كل الأسعار بالدرهم" إن كانت كذلك.`));
  }

  // 6. The VAT basis. The price the customer compares is the price excluding VAT (vat.ts).
  const vatText = [w.notes, w.scope, w.conditions, w.exclusions, w.payment_terms].join('\n');
  const stated = w.vat_treatment && w.vat_treatment !== 'not_stated' ? w.vat_treatment : null;
  const vat = readVat({ amount: w.amount, subtotal: w.subtotal, vat_amount: w.vat_amount, text: vatText, stated, price_ex_vat: w.price_ex_vat });
  const vatIssue = vat.treatment === 'not_stated' || (vat.treatment === 'inclusive' && !vat.price_ex_vat);
  if (vat.treatment === 'not_stated') {
    issues.push(I('vat_basis', 'adjustment', null, null, 'vat',
      'State whether your total includes VAT, excludes VAT, or that you are not VAT-registered. A business below the AED 375,000 registration threshold is not VAT-registered and needs no TRN — just reply "not VAT registered".',
      'اذكر هل الإجمالي شامل ضريبة القيمة المضافة أم غير شامل لها، أو أنك غير مسجل في الضريبة. المنشأة التي تقل إيراداتها عن 375,000 درهم غير مسجلة ولا تحتاج رقمًا ضريبيًا — اكتب فقط "غير مسجل في الضريبة".'));
  } else if (vat.treatment === 'inclusive' && !vat.price_ex_vat) {
    issues.push(I('vat_ex_price', 'adjustment', null, null, 'price_ex_vat',
      'Your total includes VAT, but the VAT amount is not stated. Tell me the total excluding VAT (for example: "price excluding VAT 10,500").',
      'إجماليك شامل الضريبة لكن مبلغ الضريبة غير مذكور. أخبرني بالإجمالي غير شامل الضريبة (مثال: "السعر غير شامل الضريبة 10,500").'));
  }
  const exVat = vat.price_ex_vat;

  // 4. The lines add up to the total (a single-option quotation only; options are totalled apiece).
  const sum = lines.filter((l) => !heading(l)).reduce((s, l) => s + (Number(l.amount) || 0), 0);
  const totals = [exVat, w.amount, w.subtotal].filter((x): x is number => Number(x) > 0);
  if (sum > 0 && totals.length && Object.keys(w.option_totals || {}).length < 2 && !totals.some((t) => Math.abs(t - sum) <= Math.max(1, t * 0.01))) {
    issues.push(I('total_mismatch', 'clarification', null, null, 'total',
      `Your line amounts add up to AED ${fmt(Math.round(sum * 100) / 100)}, but the quotation's total is AED ${fmt(totals[0])}. Correct the lines or the total, or tell me what the difference is (for example a discount).`,
      `مجموع مبالغ بنودك ${fmt(Math.round(sum * 100) / 100)} درهم، بينما إجمالي العرض ${fmt(totals[0])} درهم. صحّح البنود أو الإجمالي، أو وضّح سبب الفرق (كخصم مثلًا).`));
  }

  // 7. Validity.
  if (!readDelivery(w.validity)) {
    issues.push(I('validity', 'adjustment', null, null, 'validity',
      'State how long your prices are valid, as a number of days or a date (for example: "validity 30 days").',
      'اذكر مدة صلاحية أسعارك بعدد الأيام أو بتاريخ (مثال: "الصلاحية 30 يومًا").'));
  }

  // 8. The exact-specs rules, exactly as the hold gate reads them.
  const a = assessQuote({ category: inq.category, lines: assessLines(w), requirements: requirementsOf(inq.spec),
    terms: { lead_time: w.lead_time, warranty: w.warranty, scope: w.scope, exclusions: w.exclusions, conditions: w.conditions, notes: w.notes, terms_spec: w.terms_spec, price_ex_vat: exVat } });
  for (const m of a.missing) {
    if (m.attr === 'price_ex_vat' && vatIssue) continue;   // already asked, in the VAT basis's words
    issues.push(fromMissing(m));
  }
  return { approved: issues.length === 0, issues, price_ex_vat: exVat, boq_lines: boq.length, matched: match.size };
}

/** One missing detail the hold desk reports (assess.ts MissingItem), in the engineer's words. */
export function fromMissing(m: MissingItem): Issue {
  if (m.scope === 'line') {
    const d = cut(m.description);
    return I('spec', 'adjustment', m.line_no, null, m.attr,
      `Your line ${m.line_no} (${d}): state the exact ${m.label_en.toLowerCase()}${m.unit ? ` (${m.unit})` : ''} (for example: "line ${m.line_no} ${m.label_en.toLowerCase()}: …").`,
      `بندك ${m.line_no} (${d}): اذكر ${m.label_ar} بدقة${m.unit_ar || m.unit ? ` (${m.unit_ar || m.unit})` : ''} (مثال: "البند ${m.line_no} ${m.label_ar}: …").`);
  }
  const code: IssueCode = m.attr.startsWith('component:') ? 'component' : (m.attr as IssueCode);
  const ex: Record<string, [string, string]> = {
    delivery: [' (for example: "lead time 3 weeks")', ' (مثال: "مدة التسليم 3 أسابيع")'],
    installation_included: [' (for example: "installation included, 5 working days on site" or "supply only")', ' (مثال: "التركيب مشمول، 5 أيام عمل في الموقع" أو "توريد فقط")'],
    installation_detail: [' (for example: "installation 5 working days on site")', ' (مثال: "التركيب 5 أيام عمل في الموقع")'],
    warranty_period: [' (for example: "warranty 2 years")', ' (مثال: "الضمان سنتان")'],
    warranty_coverage: [' (for example: "warranty covers parts and labour")', ' (مثال: "الضمان يشمل القطع والعمالة")'],
    price_ex_vat: [' (for example: "price excluding VAT 10,500")', ' (مثال: "السعر غير شامل الضريبة 10,500")'],
  };
  const [en, ar] = ex[m.attr] ?? ['', ''];
  return I(code, 'adjustment', null, null, m.attr, `State: ${m.label_en}${en}.`, `اذكر: ${m.label_ar}${ar}.`);
}

// ---------------------------------------------------------------------------------------------
// The engineer's words. Every message exists in both languages; the reader's language picks one.
// ---------------------------------------------------------------------------------------------
export type Said = { en: string; ar: string };
export function greeting(job: string): Said {
  return {
    en: `Hello — I am the QuotesDone sales engineer for Job ${job}. Attach your quotation here (PDF with text, Excel, Word, CSV or email) and I will review it straight away against the job: every BOQ line priced, quantities and units, AED prices, the VAT basis, validity, delivery, and the exact specifications. Nothing reaches the customer until it is complete.`,
    ar: `مرحبًا — أنا مهندس المبيعات في QuotesDone للطلب ${job}. أرفق عرض سعرك هنا (PDF نصي أو Excel أو Word أو CSV أو بريد إلكتروني) وسأراجعه فورًا مقابل الطلب: تسعير كل بنود جدول الكميات، والكميات والوحدات، والأسعار بالدرهم، وأساس الضريبة، والصلاحية، والتسليم، والمواصفات الدقيقة. لا يصل شيء إلى العميل قبل اكتماله.`,
  };
}
export function reviewSaid(job: string, r: Review): Said {
  if (r.approved) {
    const boqEn = r.boq_lines ? `all ${r.boq_lines} BOQ line${r.boq_lines === 1 ? ' is' : 's are'} priced with matching quantities and units, ` : '';
    const boqAr = r.boq_lines ? `كل بنود جدول الكميات (${r.boq_lines}) مسعّرة بكميات ووحدات مطابقة، و` : '';
    return {
      en: `Quotation approved for submission. I checked it against Job ${job}: ${boqEn}prices are in AED, and the VAT basis, validity, delivery and every required specification are stated exactly.`,
      ar: `تمت الموافقة على عرض السعر للتقديم. راجعته مقابل الطلب ${job}: ${boqAr}الأسعار بالدرهم، وأساس الضريبة والصلاحية والتسليم وكل المواصفات المطلوبة مذكورة بدقة.`,
    };
  }
  const n = r.issues.length;
  return {
    en: `I reviewed your quotation for Job ${job}. Before it can be submitted I need ${n} thing${n === 1 ? '' : 's'}:\n\n${r.issues.map((x, i) => `${i + 1}. ${x.en}`).join('\n')}\n\nReply here with the details (for example "validity 30 days", "lead time 3 weeks", "prices exclude VAT"), or attach a revised file. Nothing is sent to the customer until everything is complete.`,
    ar: `راجعت عرض سعرك للطلب ${job}. قبل تقديمه أحتاج إلى ${n} ${n === 1 ? 'أمر' : n === 2 ? 'أمرين' : 'أمور'}:\n\n${r.issues.map((x, i) => `${i + 1}. ${x.ar}`).join('\n')}\n\nاكتب التفاصيل هنا (مثل "الصلاحية 30 يومًا" أو "مدة التسليم 3 أسابيع" أو "الأسعار غير شاملة الضريبة")، أو أرفق ملفًا معدّلًا. لا يُرسل شيء إلى العميل قبل اكتمال كل شيء.`,
  };
}
export function choiceSaid(): Said {
  return {
    en: 'One last step: would you like to upload a new version of your quotation yourself, or shall I generate the standardised QuotesDone quotation for you from what we agreed? Reply "upload" or "generate", or use the buttons.',
    ar: 'خطوة أخيرة: هل تريد رفع نسخة جديدة من عرضك بنفسك، أم أُعدّ لك عرض QuotesDone الموحّد مما اتفقنا عليه؟ اكتب "رفع" أو "إعداد"، أو استخدم الأزرار.',
  };
}
export const awaitingUploadSaid = (): Said => ({
  en: 'Please attach the new version of your quotation here. I will review it the moment it arrives.',
  ar: 'يُرجى إرفاق النسخة الجديدة من عرضك هنا. سأراجعها فور وصولها.',
});
export const readyToSubmitSaid = (job: string): Said => ({
  en: `This version is approved. Press "Submit to Job ${job}" and it goes to the customer's comparison.`,
  ar: `هذه النسخة معتمدة. اضغط "قدّم إلى الطلب ${job}" لتدخل مقارنة العميل.`,
});
export const submittedSaid = (job: string, ref: string | null, generated: boolean): Said => ({
  en: `${generated ? `I generated your standardised quotation${ref ? ` ${ref}` : ''} and submitted` : 'I submitted your quotation'} to Job ${job}. It is now in the customer's comparison; they see it without your name until they choose to reveal it. This conversation is now closed.`,
  ar: `${generated ? `أعددت عرضك الموحّد${ref ? ` ${ref}` : ''} وقدّمته` : 'قدّمت عرض سعرك'} إلى الطلب ${job}. أصبح الآن ضمن مقارنة العميل، ويراه دون اسمك إلى أن يختار الكشف عنه. أُغلقت هذه المحادثة الآن.`,
});
export const unreadableSaid = (kind: string): Said => kind === 'image'
  ? { en: 'That is a photo or a scan, and I read quotations by their text. Please attach the quotation as a PDF with text, an Excel or Word file, or a CSV.', ar: 'هذا ملف صورة أو مسح ضوئي، وأنا أقرأ العروض من نصها. يُرجى إرفاق العرض بصيغة PDF نصية أو ملف Excel أو Word أو CSV.' }
  : { en: 'I could not find a priced list or a total in that file. Please attach the quotation with its line items and total — a PDF with text, an Excel or Word file, or a CSV.', ar: 'لم أجد في هذا الملف بنودًا مسعّرة أو إجماليًا. يُرجى إرفاق العرض ببنوده وإجماليه — PDF نصي أو ملف Excel أو Word أو CSV.' };
export const closedSaid = (): Said => ({
  // Founder, 14 Sep 2026: no customer- or supplier-facing text says a copy is kept.
  en: 'This job is closed — the customer has already chosen, so no further quotation can be submitted to it.',
  ar: 'أُغلق هذا الطلب — اختار العميل بالفعل، فلا يمكن تقديم عرض آخر إليه.',
});

// ---------------------------------------------------------------------------------------------
// The supplier's reply, read by rule: the details they state, the choice they make, the question they ask.
// ---------------------------------------------------------------------------------------------
export type Correction =
  | { field: 'validity' | 'lead_time' | 'warranty' | 'vat_treatment'; value: string }
  | { field: 'price_ex_vat'; value: number }
  | { field: 'installation'; included: 'yes' | 'no'; detail: string | null }
  | { field: 'warranty_terms'; period: string | null; coverage: string | null }
  | { field: 'aed' }
  | { field: 'boq_excluded' | 'qty_explained'; boq_line: number; value: string; what?: 'qty' | 'unit' }
  | { field: 'line_spec'; line_no: number; attr: string; value: string };
export type Topic = 'vat' | 'validity' | 'currency' | 'boq' | 'customer' | 'delivery' | 'warranty' | 'installation' | 'missing' | 'general';
export type ReplyRead = { corrections: Correction[]; choice: 'generate' | 'reupload' | null; submit: boolean; topic: Topic | null };

/** Supplier text that becomes part of a quotation is scrubbed of contact details and identity numbers. */
const clean = (s: string, n = 160) => maskIdentityNumbers(scrubIdentity(normText(s))).slice(0, n).trim();
const DUR = String.raw`\d+(?:\.\d+)?\s*(?:-\s*\d+\s*)?(?:working\s*|business\s*)?(?:days?|weeks?|months?|يوم(?:ا|اً)?|أيام|يوم عمل|أيام عمل|أسبوع|أسابيع|اسبوع|اسابيع|شهر|أشهر|شهور)`;
const DATE = String.raw`\d{4}-\d{2}-\d{2}|\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4}|\d{1,2}\s+[A-Za-z؀-ۿ]{3,9}\s*,?\s*\d{4}`;
const RE_VALIDITY = new RegExp(String.raw`(?:validity|valid(?:\s+for|\s+until|\s+till)?|offer\s+valid|صلاحية(?:\s+العرض)?|الصلاحية|ساري(?:ة)?(?:\s+لمدة)?)\s*[:\-–]?\s*(?:is\s+|of\s+|for\s+|لمدة\s+)?(${DUR}|${DATE})`, 'i');
const RE_LEAD = new RegExp(String.raw`(?:lead\s*time|delivery(?:\s+(?:time|period|date))?|deliver(?:ed|y)?\s+(?:in|within|by|on)|مدة\s+التسليم|مدة\s+التنفيذ|التسليم|تسليم)\s*[:\-–]?\s*(?:is\s+|in\s+|within\s+|by\s+|on\s+|خلال\s+)?(${DUR}|${DATE})`, 'i');
const RE_EXVAT = /(?:ex(?:cl(?:uding|usive|\.)?)?\.?\s*(?:of\s*)?vat|before\s*vat|غير\s*شامل\s*(?:ال)?ضريبة(?:\s*القيمة\s*المضافة)?|قبل\s*(?:ال)?ضريبة)[^\d\n]{0,25}([\d][\d,]*(?:\.\d+)?)|([\d][\d,]*(?:\.\d+)?)\s*(?:aed|درهم)?\s*(?:ex(?:cl(?:uding|\.)?)?\.?\s*vat|before\s*vat|غير\s*شامل\s*(?:ال)?ضريبة)/i;
const LINE = String.raw`(?:line|item|بند|البند|بندي)\s*#?\s*(\d{1,3})`;
const RE_EXCLUDED = new RegExp(String.raw`(boq\s*|جدول\s*الكميات\s*)?${LINE}[^.\n;]{0,40}?(excluded|not\s+included|by\s+others|not\s+in\s+(?:our|my)\s+scope|مستثنى|غير\s+مشمول|خارج\s+النطاق|من\s+قبل\s+الغير)([^.\n;]{0,100})`, 'gi');
const RE_QTYWHY = new RegExp(String.raw`(boq\s*|جدول\s*الكميات\s*)?${LINE}[^.\n;]{0,30}?(quantity|qty|unit|الكمية|الوحدة)\s*[:\-–]?\s*([^\n;]{3,140})`, 'gi');
const RE_SPEC = new RegExp(String.raw`${LINE}\s*[,:\-–]?\s*([^\n:=;]{2,40}?)\s*[:=]\s*([^\n;]{1,120})`, 'gi');
const RE_AED = /\b(?:all\s+)?(?:prices?\s+|amounts?\s+)?(?:are\s+)?in\s+aed\b|\ball\s+(?:prices?\s+)?(?:are\s+)?aed\b|\baed\s+only\b|بالدرهم/i;
const RE_GENERATE = /\bgenerate\b|\b(?:prepare|create|make)\s+(?:it|the\s+quot\w*|a\s+quot\w*)?\s*for\s+me\b|\byou\s+(?:do|prepare|generate)\s+it\b|إعداد|أعدّه|اعده|أعدها|أنشئ|انشئ|ولّد|جهّز/i;
const RE_REUPLOAD = /\bre-?upload\b|\bupload\b|\bnew\s+version\b|\brevised\s+(?:file|quot\w*)\b|\bi\s*(?:will|'ll)\s+(?:attach|send)\b|رفع|ارفع|سأرفع|نسخة\s+جديدة|نسخة\s+معدلة/i;
const RE_SUBMIT = /^\s*(?:please\s+)?submit\b|\bsubmit\s+(?:it|now|the\s+quot\w*)\b|^\s*قدّم|^\s*قدم|^\s*أرسله/i;
const RE_QUESTION = /[?؟]|^\s*(?:what|why|how|which|when|where|can|could|do|does|is|are|should|will|ماذا|لماذا|كيف|هل|ما|متى|أين|أي)\b/i;

export function readReply(text: string, open: Issue[]): ReplyRead {
  const t = normText(text);
  const out: Correction[] = [];
  const has = (code: IssueCode) => open.some((i) => i.code === code);
  const v = t.match(RE_VALIDITY); if (v) out.push({ field: 'validity', value: clean(v[1], 60) });
  const d = t.match(RE_LEAD); if (d) out.push({ field: 'lead_time', value: clean(d[1], 60) });
  const ex = t.match(RE_EXVAT); if (ex) { const n = Number(String(ex[1] || ex[2]).replace(/,/g, '')); if (n > 0) out.push({ field: 'price_ex_vat', value: n }); }
  if (!ex) {
    const vr = readVat({ amount: null, text: t });
    if (vr.treatment !== 'not_stated') out.push({ field: 'vat_treatment', value: vr.treatment });
  }
  if (/warrant|guarant|ضمان/i.test(t)) {
    const w = readWarranty(t);
    if (w.period || w.coverage) out.push({ field: 'warranty_terms', period: w.period, coverage: w.coverage });
  }
  if (/install|تركيب|supply\s*only|توريد\s*فقط/i.test(t)) {
    const ri = readInstallation([], { scope: t });
    if (ri.included) out.push({ field: 'installation', included: ri.included, detail: ri.detail ? clean(ri.detail, 120) : null });
  }
  if (RE_AED.test(t) && has('currency_not_aed')) out.push({ field: 'aed' });
  const excluded = new Set<number>();
  for (const m of t.matchAll(RE_EXCLUDED)) {
    const n = Number(m[2]);
    if (m[1] || open.some((i) => i.boq_line === n)) { excluded.add(n); out.push({ field: 'boq_excluded', boq_line: n, value: clean(`${m[3]}${m[4] || ''}`, 120) }); }
  }
  for (const m of t.matchAll(RE_QTYWHY)) {
    const n = Number(m[2]); const what: 'qty' | 'unit' = /unit|الوحدة/i.test(m[3]) ? 'unit' : 'qty';
    const code = what === 'unit' ? 'unit_mismatch' : 'qty_mismatch';
    if (!excluded.has(n) && open.some((i) => i.boq_line === n && i.code === code)) out.push({ field: 'qty_explained', boq_line: n, value: clean(m[4], 140), what });
  }
  for (const m of t.matchAll(RE_SPEC)) {
    const n = Number(m[1]); const key = normText(m[2]).toLowerCase(); const val = clean(m[3], 120);
    if (!val || VAGUE.test(val)) continue;
    const hit = open.find((i) => i.code === 'spec' && i.line_no === n && i.attr && (key.includes(String(i.attr).replace(/_/g, ' ')) || i.en.toLowerCase().includes(`exact ${key}`) || i.ar.includes(key)));
    if (hit) out.push({ field: 'line_spec', line_no: n, attr: String(hit.attr), value: val });
  }
  const choice = RE_GENERATE.test(t) ? 'generate' : RE_REUPLOAD.test(t) ? 'reupload' : null;
  const q = RE_QUESTION.test(t);
  const topic: Topic | null = !q ? null
    : /vat|tax|trn|ضريب/i.test(t) ? 'vat'
    : /missing|remain|left|else|still|outstanding|ناقص|متبق|تبق|المطلوب/i.test(t) ? 'missing'
    : /customer|client|who is|name|contact|phone|العميل|اسم|رقم/i.test(t) ? 'customer'
    : /valid|صلاحي/i.test(t) ? 'validity'
    : /currenc|aed|usd|dirham|عملة|درهم/i.test(t) ? 'currency'
    : /boq|quantit|qty|unit|كمي|جدول|وحد/i.test(t) ? 'boq'
    : /deliver|lead|تسليم/i.test(t) ? 'delivery'
    : /warrant|ضمان/i.test(t) ? 'warranty'
    : /install|تركيب/i.test(t) ? 'installation'
    : 'general';
  return { corrections: out, choice, submit: RE_SUBMIT.test(t), topic };
}

/** The working quotation with the supplier's stated details applied. Pure: returns a new object. */
export function applyCorrections(w0: Working, cs: Correction[]): Working {
  const w: Working = structuredClone(w0);
  const log = (field: string, value: string, line: number | null = null) => w.corrections.push({ field, value, line });
  for (const c of cs) {
    switch (c.field) {
      case 'validity': w.validity = c.value; log('validity', c.value); break;
      case 'lead_time': w.lead_time = c.value; w.terms_spec = { ...w.terms_spec, delivery: { value: c.value, source: 'supplier_portal' } }; log('lead_time', c.value); break;
      case 'warranty': w.warranty = c.value; log('warranty', c.value); break;
      case 'vat_treatment': w.vat_treatment = c.value; if (c.value !== 'inclusive') w.price_ex_vat = c.value === 'not_registered' || c.value === 'exclusive' ? (w.amount ?? w.price_ex_vat) : w.price_ex_vat; log('vat_treatment', c.value); break;
      case 'price_ex_vat': w.price_ex_vat = c.value; w.vat_treatment = 'confirmed_on_portal'; log('price_ex_vat', String(c.value)); break;
      case 'warranty_terms': {
        const prior = w.terms_spec.warranty ?? null; const read = readWarranty(w.warranty);
        const period = c.period ?? prior?.period ?? read.period ?? null;
        const coverage = c.coverage ?? prior?.coverage ?? read.coverage ?? '';
        w.warranty = [period, coverage].filter(Boolean).join(' — ');
        if (period) w.terms_spec = { ...w.terms_spec, warranty: { period, coverage, source: 'supplier_portal' } };
        log('warranty', w.warranty); break;
      }
      case 'installation': {
        const prior = w.terms_spec.installation ?? null;
        const detail = c.included === 'yes' ? (c.detail ?? prior?.detail ?? null) : null;
        w.terms_spec = { ...w.terms_spec, installation: { included: c.included, detail, source: 'supplier_portal' } };
        log('installation', c.included + (detail ? ' — ' + detail : '')); break;
      }
      case 'aed': w.foreign_currency = null; log('currency', 'AED'); break;
      case 'boq_excluded': {
        w.boq_excluded = { ...w.boq_excluded, [String(c.boq_line)]: c.value || 'excluded' };
        const note = `BOQ line ${c.boq_line} excluded${c.value ? ': ' + c.value : ''}`;
        w.exclusions = [w.exclusions, note].filter(Boolean).join('; ').slice(0, 2000);
        log('boq_excluded', c.value, c.boq_line); break;
      }
      case 'qty_explained': {
        const unit = c.what === 'unit';
        w.qty_explained = { ...w.qty_explained, [unit ? `${c.boq_line}:unit` : String(c.boq_line)]: c.value };
        w.conditions = [w.conditions, `BOQ line ${c.boq_line} ${unit ? 'unit' : 'quantity'}: ${c.value}`].filter(Boolean).join('; ').slice(0, 2000);
        log('qty_explained', c.value, c.boq_line); break;
      }
      case 'line_spec': {
        const l = w.lines[c.line_no - 1]; if (!l) break;
        l.spec = { ...(l.spec ?? {}), [c.attr]: c.value }; l.spec_source = { ...(l.spec_source ?? {}), [c.attr]: 'supplier_portal' };
        log(`line_spec:${c.attr}`, c.value, c.line_no); break;
      }
    }
  }
  return w;
}

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
    if (c.field === 'validity') { en.push(`validity ${c.value}`); ar.push(`الصلاحية ${c.value}`); }
    else if (c.field === 'lead_time') { en.push(`lead time ${c.value}`); ar.push(`مدة التسليم ${c.value}`); }
    else if (c.field === 'price_ex_vat') { en.push(`price excluding VAT AED ${fmt(c.value)}`); ar.push(`السعر غير شامل الضريبة ${fmt(c.value)} درهم`); }
    else if (c.field === 'vat_treatment') {
      const m: Record<string, [string, string]> = { exclusive: ['prices exclude VAT', 'الأسعار غير شاملة الضريبة'], inclusive: ['prices include VAT', 'الأسعار شاملة الضريبة'], not_registered: ['not VAT-registered', 'غير مسجل في الضريبة'] };
      const x = m[c.value]; if (x) { en.push(x[0]); ar.push(x[1]); }
    }
    else if (c.field === 'warranty_terms') { en.push(`warranty ${[c.period, c.coverage].filter(Boolean).join(', ')}`); ar.push(`الضمان ${[c.period, c.coverage].filter(Boolean).join('، ')}`); }
    else if (c.field === 'installation') { en.push(c.included === 'yes' ? `installation included${c.detail ? ` (${c.detail})` : ''}` : 'supply only, no installation'); ar.push(c.included === 'yes' ? `التركيب مشمول${c.detail ? ` (${c.detail})` : ''}` : 'توريد فقط دون تركيب'); }
    else if (c.field === 'aed') { en.push('all prices in AED'); ar.push('كل الأسعار بالدرهم'); }
    else if (c.field === 'boq_excluded') { en.push(`BOQ line ${c.boq_line} excluded${c.value ? ` (${c.value})` : ''}`); ar.push(`البند ${c.boq_line} مستثنى${c.value ? ` (${c.value})` : ''}`); }
    else if (c.field === 'qty_explained') { const u = c.what === 'unit'; en.push(`BOQ line ${c.boq_line} ${u ? 'unit' : 'quantity'} explained`); ar.push(u ? `وُضّحت وحدة البند ${c.boq_line}` : `وُضّحت كمية البند ${c.boq_line}`); }
    else if (c.field === 'line_spec') { en.push(`line ${c.line_no}: ${c.value}`); ar.push(`البند ${c.line_no}: ${c.value}`); }
  }
  return { en: `Thank you — noted: ${en.join('; ')}.`, ar: `شكرًا — سجّلت: ${ar.join('؛ ')}.` };
}

/** The engineer's answer to a question, from the rules and the job — never a guess. */
export function answerSaid(topic: Topic, job: string, open: Issue[], boqLines: number): Said {
  const list = (lang: Lang) => open.length
    ? (lang === 'en' ? `Still open for Job ${job}:\n` : `ما زال مطلوبًا للطلب ${job}:\n`) + open.map((x, i) => `${i + 1}. ${lang === 'en' ? x.en : x.ar}`).join('\n')
    : (lang === 'en' ? `Nothing is outstanding on Job ${job}.` : `لا شيء معلّق على الطلب ${job}.`);
  switch (topic) {
    case 'vat': return {
      en: 'The customer compares prices excluding VAT and never sees your VAT details or TRN. Tell me whether your total includes VAT, excludes VAT, or that you are not VAT-registered. A business below the AED 375,000 registration threshold is not VAT-registered and does not need a TRN — just reply "not VAT registered".',
      ar: 'يقارن العميل الأسعار غير شاملة الضريبة ولا يرى تفاصيل ضريبتك ولا رقمك الضريبي. أخبرني هل إجماليك شامل الضريبة أم غير شامل لها، أو أنك غير مسجل. المنشأة التي تقل إيراداتها عن 375,000 درهم غير مسجلة ولا تحتاج رقمًا ضريبيًا — اكتب فقط "غير مسجل في الضريبة".' };
    case 'validity': return { en: 'Validity is how long your prices hold. State it as a number of days or a date, for example "validity 30 days".', ar: 'الصلاحية هي المدة التي تبقى فيها أسعارك سارية. اذكرها بعدد الأيام أو بتاريخ، مثل "الصلاحية 30 يومًا".' };
    case 'currency': return { en: 'Every price must be in UAE dirhams (AED). If your file shows another currency, re-state the prices in AED, or reply "all prices in AED" if they already are.', ar: 'يجب أن تكون كل الأسعار بالدرهم الإماراتي. إن ظهرت عملة أخرى في ملفك فأعد ذكر الأسعار بالدرهم، أو اكتب "كل الأسعار بالدرهم" إن كانت كذلك.' };
    case 'boq': return {
      en: `I compare every line of the job's bill of quantities${boqLines ? ` (${boqLines} lines)` : ''} with your quotation: each must be priced, with the same quantity and unit. If a line is excluded, reply "BOQ line 3 excluded — reason". If your quantity differs on purpose, reply "BOQ line 3 quantity — why".`,
      ar: `أقارن كل بند في جدول كميات الطلب${boqLines ? ` (${boqLines} بندًا)` : ''} بعرضك: يجب أن يكون مسعّرًا بالكمية والوحدة نفسيهما. إن كان بند مستثنى فاكتب "البند 3 مستثنى — السبب"، وإن اختلفت كميتك عمدًا فاكتب "البند 3 الكمية — السبب".` };
    case 'customer': return {
      en: "The customer's identity stays private until they choose to reveal a quotation — that is how QuotesDone works, for them and for you. Keep your own contact details out of the quotation as well; they are removed before the customer sees it.",
      ar: 'تبقى هوية العميل خاصة إلى أن يختار الكشف عن عرض — هكذا تعمل QuotesDone له ولك. أبقِ بيانات اتصالك خارج العرض أيضًا؛ فهي تُحذف قبل أن يراه العميل.' };
    case 'delivery': return { en: 'State a concrete delivery date or lead time, for example "lead time 3 weeks" or "delivery 30 Oct 2026".', ar: 'اذكر تاريخ تسليم أو مدة تنفيذ محددة، مثل "مدة التسليم 3 أسابيع" أو "التسليم 30 أكتوبر 2026".' };
    case 'warranty': return { en: 'State the warranty period and what it covers, for example "warranty 2 years, parts and labour".', ar: 'اذكر مدة الضمان وما يشمله، مثل "الضمان سنتان، القطع والعمالة".' };
    case 'installation': return { en: 'Tell me whether installation is included and its scope or timeline, for example "installation included, 5 working days on site", or "supply only".', ar: 'أخبرني هل التركيب مشمول ونطاقه أو مدته، مثل "التركيب مشمول، 5 أيام عمل في الموقع"، أو "توريد فقط".' };
    default: return { en: list('en'), ar: list('ar') };
  }
}
export const notUnderstoodSaid = (job: string, open: Issue[]): Said => {
  const a = answerSaid('missing', job, open, 0);
  return { en: `I could not match that to an open point. ${a.en}`, ar: `لم أتمكن من ربط ذلك بنقطة مفتوحة. ${a.ar}` };
};
