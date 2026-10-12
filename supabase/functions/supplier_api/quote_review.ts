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
// inquiry the inbox already serves. Pure: no I/O, no clock, no model — except readWorking, which takes its model as deps.
import { assessQuote, readDelivery, readInstallation, readWarranty, requirementsOf, type Line, type MissingItem, type TermsSpec } from '../_shared/line_specs/assess.ts';
import { normText, VAGUE } from '../_shared/line_specs/model.ts';
import { applyReading, readQuote } from '../_shared/reasoned_matching.ts';
import type { ThinkDeps } from '../_shared/think.ts';
import { OPTION_HEAD } from '../_shared/line_specs/options.ts';
import { readVat, type VatTreatment } from '../_shared/line_specs/vat.ts';
import { arDuration, jobNoOf } from '../_shared/quote_documents.ts';
// A period the supplier typed, read back in Arabic where the glossary knows it (audit 21 Sep 2026, finding 26:
// the Arabic acknowledgement said "الصلاحية 30 days"). A period it does not know stays in the supplier's words.
const arPeriod = (v: unknown) => arDuration(v) ?? String(v ?? '');
import { maskIdentityNumbers } from '../_shared/identity_numbers.ts';
import { scrubIdentity } from '../drawing_boq/boq_from_text.ts';
import type { Proposal } from '../quote_extract/quote_from_document.ts';

export const SEAT = 'sales_engineer' as const;
export type Lang = 'en' | 'ar';

// ---------------------------------------------------------------------------------------------
// The shapes the review reads.
// ---------------------------------------------------------------------------------------------
/** One row of the job's bill of quantities, as the supplier inbox serves it (already scrubbed). */
export type BoqRow = { section?: string | null; description?: string | null; qty?: number | string | null; unit?: string | null; qty_status?: string | null };
/** The inquiry as this supplier may see it — the output of supplier_api `inbox`, never the raw row. */
export type SafeInquiry = {
  id: string; job_no: string; category: string | null; emirate: string | null; spec: unknown;
  boq_rows: BoqRow[]; boq_withheld: boolean; concluded: boolean; revealed: boolean;
};
export type WLine = {
  description: string; qty: string; unit: string; unit_price: number | null; amount: number | null; option?: number;
  /** The file's own "Specification" column for this line, read with the description by every spec reader. */
  specification?: string;
  spec?: Record<string, string>; spec_source?: Record<string, 'extracted' | 'supplier_portal' | 'reasoned'>;
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
/** The quotation-level attributes assess.ts can report missing, as issue codes. */
const TERM_CODES = new Set<IssueCode>(['delivery', 'installation_included', 'installation_detail',
  'warranty_period', 'warranty_coverage', 'price_ex_vat', 'line_items']);
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
/**
 * The job number every surface prints: inquiries.rfq_no, the same number the customer portal shows
 * and every notice carries ('RFQ-151767'). Measured 21 Sep 2026 (audit finding 7): this printed the
 * first 8 characters of the uuid (D958E1EA) while the customer read 151767 for the same job, so
 * neither side could quote the other's number. The uuid prefix remains only as a fallback for a row
 * read without rfq_no, which the column's NOT NULL makes a caller's omission rather than a state.
 */
export const jobNo = (inq: { rfq_no?: number | string | null; id?: string | null } | string) =>
  jobNoOf(typeof inq === 'string' ? { id: inq } : inq);

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
      unit_price: n && amount ? Math.round((amount / n) * 100) / 100 : null, ...(l.option != null ? { option: l.option } : {}),
      ...(l.specification ? { specification: String(l.specification) } : {}) };
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
const assessLines = (w: Working): Line[] => w.lines.map((l, i) => ({ line_no: i + 1, description: l.description, specification: l.specification ?? null, qty: l.qty, unit: l.unit, unit_price: l.unit_price, amount: l.amount, spec: l.spec ?? null, spec_source: l.spec_source ?? null }));

/**
 * What reasoning reads from the working quotation (decision points 29-30, _shared/reasoned_matching.ts readQuote),
 * written onto its lines' spec and its terms_spec as source 'reasoned', so the review asks exactly what the hold
 * gate will. Held (the model hold): the working is returned unread, and every detail is asked. No word reader.
 */
export async function readWorking(think: ThinkDeps, inq: SafeInquiry, w: Working, key: string): Promise<Working> {
  const lines = assessLines(w);
  const reading = await readQuote(think, { quoteId: key, category: inq.category, lines, requirements: requirementsOf(inq.spec),
    terms: { lead_time: w.lead_time, warranty: w.warranty, scope: w.scope, exclusions: w.exclusions, conditions: w.conditions, notes: w.notes, terms_spec: w.terms_spec } });
  if (!reading) return w;
  const ap = applyReading(lines, w.terms_spec, reading);
  return { ...w, terms_spec: ap.terms_spec, lines: w.lines.map((l, i) => ({ ...l, spec: ap.lines[i].spec ?? l.spec, spec_source: ap.lines[i].spec_source ?? l.spec_source })) };
}

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
        `البند ${n} من جدول الكميات (${d}) غير مسعّر في عرضكم. يُرجى إضافة سعره، أو إفادتي بأنه مستثنى مع ذكر السبب (مثال: «البند ${n} مستثنى — يتولاه الغير»).`));
      return;
    }
    // A quantity and a unit are explained separately ("BOQ line 3 quantity — …" / "… unit — …"): an
    // explained quantity must not silence a unit that differs (TypeScript review, 15 Sep 2026).
    const bq = num(b.qty); const lq = parseQty(l.qty).n;
    if (!w.qty_explained[String(n)] && bq != null && lq != null && Math.abs(bq - lq) > Math.max(0.01, Math.abs(bq) * 0.01)) {
      issues.push(I('qty_mismatch', 'clarification', j! + 1, n, 'qty',
        `BOQ line ${n} (${d}): your line ${j! + 1} prices ${fmt(lq)} ${l.unit || ''}`.trimEnd() + ` but the BOQ asks for ${fmt(bq)} ${b.unit || ''}`.trimEnd() + `. Price the BOQ quantity, or tell me why yours differs (for example: "BOQ line ${n} quantity — measured on site").`,
        `البند ${n} من جدول الكميات (${d}): يسعّر بندكم ${j! + 1} كمية ${fmt(lq)} ${l.unit || ''}`.trimEnd() + `، في حين يطلب الجدول ${fmt(bq)} ${b.unit || ''}`.trimEnd() + `. يُرجى تسعير كمية الجدول، أو ذكر سبب الاختلاف (مثال: «البند ${n} الكمية — حسب القياس في الموقع»).`));
    }
    const bu = normUnit(b.unit), lu = normUnit(l.unit);
    if (!w.qty_explained[`${n}:unit`] && bu && lu && bu !== lu) {
      issues.push(I('unit_mismatch', 'clarification', j! + 1, n, 'unit',
        `BOQ line ${n} (${d}) is measured in ${b.unit}, your line ${j! + 1} in ${l.unit}. Re-state it in ${b.unit}, or explain the conversion.`,
        `البند ${n} من جدول الكميات (${d}) مقيس بوحدة ${b.unit}، بينما بندكم ${j! + 1} بوحدة ${l.unit}. يُرجى إعادة ذكره بوحدة ${b.unit}، أو توضيح طريقة التحويل.`));
    }
  });

  // 3. A line with a quantity and no price.
  lines.forEach((l, j) => {
    if (heading(l) || priced(l) || !l.qty) return;
    if ([...match.values()].includes(j)) return;   // already raised against its BOQ line
    issues.push(I('line_unpriced', 'adjustment', j + 1, null, null,
      `Your line ${j + 1} (${cut(l.description)}) has a quantity but no price. Add its price.`,
      `بندكم ${j + 1} (${cut(l.description)}) ذُكرت كميته دون سعر. يُرجى إضافة سعره.`));
  });

  // 5. Currency.
  if (w.foreign_currency) {
    issues.push(I('currency_not_aed', 'adjustment', null, null, 'currency',
      `Your quotation shows prices in ${w.foreign_currency}. Every price must be in UAE dirhams (AED): re-state them in AED, or reply "all prices in AED" if they already are.`,
      `يتضمّن عرضكم أسعارًا بعملة ${w.foreign_currency}، ويجب أن تكون الأسعار كافة بالدرهم الإماراتي. يُرجى إعادة ذكرها بالدرهم، أو كتابة «كل الأسعار بالدرهم» إن كانت كذلك.`));
  }

  // 6. The VAT basis. The price the customer compares is the price excluding VAT (vat.ts).
  const vatText = [w.notes, w.scope, w.conditions, w.exclusions, w.payment_terms].join('\n');
  const stated = w.vat_treatment && w.vat_treatment !== 'not_stated' ? w.vat_treatment : null;
  const vat = readVat({ amount: w.amount, subtotal: w.subtotal, vat_amount: w.vat_amount, text: vatText, stated, price_ex_vat: w.price_ex_vat });
  const vatIssue = vat.treatment === 'not_stated' || (vat.treatment === 'inclusive' && !vat.price_ex_vat);
  if (vat.treatment === 'not_stated') {
    issues.push(I('vat_basis', 'adjustment', null, null, 'vat',
      'State whether your total includes VAT, excludes VAT, or that you are not VAT-registered. A business below the AED 375,000 registration threshold is not VAT-registered and needs no TRN — just reply "not VAT registered".',
      'يُرجى بيان ما إذا كان الإجمالي شاملًا ضريبة القيمة المضافة أم غير شامل لها، أو أنكم غير مسجّلين في الضريبة. والمنشأة التي تقل إيراداتها عن حدّ التسجيل البالغ 375,000 درهم غير مسجّلة ولا تحتاج إلى رقم ضريبي، ويكفي أن تكتبوا «غير مسجل في الضريبة».'));
  } else if (vat.treatment === 'inclusive' && !vat.price_ex_vat) {
    issues.push(I('vat_ex_price', 'adjustment', null, null, 'price_ex_vat',
      'Your total includes VAT, but the VAT amount is not stated. Tell me the total excluding VAT (for example: "price excluding VAT 10,500").',
      'إجماليكم شامل الضريبة، لكن مبلغ الضريبة غير مذكور. يُرجى إفادتي بالإجمالي غير شامل الضريبة (مثال: «السعر غير شامل الضريبة 10,500»).'));
  }
  const exVat = vat.price_ex_vat;

  // 4. The lines add up to the total (a single-option quotation only; options are totalled apiece).
  const sum = lines.filter((l) => !heading(l)).reduce((s, l) => s + (Number(l.amount) || 0), 0);
  const totals = [exVat, w.amount, w.subtotal].filter((x): x is number => Number(x) > 0);
  if (sum > 0 && totals.length && !w.qty_explained?.total && Object.keys(w.option_totals || {}).length < 2 && !totals.some((t) => Math.abs(t - sum) <= Math.max(1, t * 0.01))) {
    issues.push(I('total_mismatch', 'clarification', null, null, 'total',
      `Your line amounts add up to AED ${fmt(Math.round(sum * 100) / 100)}, but the quotation's total is AED ${fmt(totals[0])}. Correct the lines or the total, or tell me what the difference is (for example a discount).`,
      `مجموع مبالغ بنودكم ${fmt(Math.round(sum * 100) / 100)} درهم، في حين أن إجمالي العرض ${fmt(totals[0])} درهم. يُرجى تصحيح البنود أو الإجمالي، أو توضيح سبب الفرق (كخصم مثلًا).`));
  }

  // 7. Validity.
  if (!readDelivery(w.validity)) {
    issues.push(I('validity', 'adjustment', null, null, 'validity',
      'State how long your prices are valid, as a number of days or a date (for example: "validity 30 days").',
      'يُرجى ذكر مدة صلاحية أسعاركم بعدد الأيام أو بتاريخ محدد (مثال: «الصلاحية 30 يومًا»).'));
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
      `بندكم ${m.line_no} (${d}): يُرجى ذكر ${m.label_ar} بدقة${m.unit_ar || m.unit ? ` (${m.unit_ar || m.unit})` : ''} (مثال: «البند ${m.line_no} ${m.label_ar}: …»).`);
  }
  // assess.ts types MissingItem.attr as a plain string, so a term added there that nothing here knows
  // would otherwise reach the database as an invalid code. An unknown attribute is asked as a `spec`.
  const code: IssueCode = m.attr.startsWith('component:') ? 'component'
    : (TERM_CODES.has(m.attr as IssueCode) ? m.attr as IssueCode : 'spec');
  const ex: Record<string, [string, string]> = {
    delivery: [' (for example: "lead time 3 weeks")', ' (مثال: «مدة التسليم 3 أسابيع»)'],
    installation_included: [' (for example: "installation included, 5 working days on site" or "supply only")', ' (مثال: «التركيب مشمول، 5 أيام عمل في الموقع» أو «توريد فقط»)'],
    installation_detail: [' (for example: "installation 5 working days on site")', ' (مثال: «التركيب 5 أيام عمل في الموقع»)'],
    warranty_period: [' (for example: "warranty 2 years")', ' (مثال: «الضمان سنتان»)'],
    warranty_coverage: [' (for example: "warranty covers parts and labour")', ' (مثال: «الضمان يشمل القطع والعمالة»)'],
    price_ex_vat: [' (for example: "price excluding VAT 10,500")', ' (مثال: «السعر غير شامل الضريبة 10,500»)'],
  };
  const [en, ar] = ex[m.attr] ?? ['', ''];
  return I(code, 'adjustment', null, null, m.attr, `State: ${m.label_en}${en}.`, `يُرجى ذكر: ${m.label_ar}${ar}.`);
}

// ---------------------------------------------------------------------------------------------
// The engineer's words. Every message exists in both languages; the reader's language picks one.
// ---------------------------------------------------------------------------------------------
export type Said = { en: string; ar: string };
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

// ---------------------------------------------------------------------------------------------
// The supplier's reply, read by rule: the details they state, the choice they make, the question they ask.
// ---------------------------------------------------------------------------------------------
export type Correction =
  | { field: 'validity' | 'lead_time' | 'warranty'; value: string }
  // The treatment is the one readVat returns, never free text — 'not_stated' is not a correction.
  | { field: 'vat_treatment'; value: Exclude<VatTreatment, 'not_stated'> }
  | { field: 'price_ex_vat'; value: number }
  | { field: 'installation'; included: 'yes' | 'no'; detail: string | null }
  | { field: 'warranty_terms'; period: string | null; coverage: string | null }
  | { field: 'aed' }
  | { field: 'boq_excluded' | 'qty_explained'; boq_line: number; value: string; what?: 'qty' | 'unit' }
  | { field: 'line_spec'; line_no: number; attr: string; value: string }
  /** A price typed for a BOQ line: the rate, the amount, or both (at least one). */
  | { field: 'boq_price'; boq_line: number; unit_price: number | null; amount: number | null }
  // EVERY OPEN POINT CAN BE CLOSED FROM THE CHAT (audit 21 Sep 2026, finding 2). Before these, a
  // supplier's own unpriced line, a total that did not add up and a customer's material had no reply
  // that closed them — the only way out was a new file.
  /** A price typed for the supplier's OWN line N (a line_unpriced point, not a BOQ line). */
  | { field: 'line_price'; line_no: number; unit_price: number | null; amount: number | null }
  /** "total AED 65,960": the quotation's total, re-stated. */
  | { field: 'total'; value: number }
  /** "discount AED 500": why the lines and the total differ. */
  | { field: 'total_explained'; value: string }
  /** "glass: 6mm clear tempered" for a material the customer named (terms_spec.components). */
  | { field: 'component'; key: string; value: string; label_en: string; label_ar: string };
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
// SEVERAL ANSWERS IN ONE MESSAGE (audit 21 Sep 2026, finding 14): "line 1 board: Knauf. line 2
// thickness: 15mm. line 2 frame: …" — a value that ran to the end of the line swallowed every answer
// after the first, and the acknowledgement echoed the lot. A value now ends where the next "line N"
// begins, at a sentence end before it, at ";" or at the end of the line.
const NEXT_LINE = String.raw`\s*[.;,]?\s*(?:boq\s*|جدول\s*الكميات\s*)?(?:line|item|بند|البند|بندي)\s*#?\s*\d`;
const VAL = (min: number, max: number) => String.raw`((?:(?!${NEXT_LINE}|[.;؛]\s+\S)[^\n;؛]){${min},${max}})`;
const RE_EXCLUDED = new RegExp(String.raw`(boq\s*|جدول\s*الكميات\s*)?${LINE}[^.\n;]{0,40}?(excluded|not\s+included|by\s+others|not\s+in\s+(?:our|my)\s+scope|مستثنى|غير\s+مشمول|خارج\s+النطاق|من\s+قبل\s+الغير)${VAL(0, 100)}`, 'gi');
const RE_QTYWHY = new RegExp(String.raw`(boq\s*|جدول\s*الكميات\s*)?${LINE}[^.\n;]{0,30}?(quantity|qty|unit|الكمية|الوحدة)\s*[:\-–]?\s*${VAL(3, 140)}`, 'gi');
// The attribute name never runs across the next "line N" either: "line 3 excluded — by others. line 1
// thickness: 12.5mm" read "excluded — by others. line 1 thickness" as line 3's attribute.
const RE_SPEC = new RegExp(String.raw`${LINE}\s*[,:\-–]?\s*((?:(?!${NEXT_LINE})[^\n:=;]){2,40}?)\s*[:=]\s*${VAL(1, 120)}`, 'gi');
// THE PRICE GRAMMAR (audit 21 Sep 2026, finding 2: "BOQ line 1: AED 95.00 per m2 … = AED 30,400" and
// the review's own "BOQ line 1 AED 30,400" both answered "I could not match that to an open point").
// A clause is the text from "line N" to the next "line N" (or ";" / end). Inside it, a figure is:
//   a RATE when it is followed by "per <unit>", "/<unit>", "لكل", "each", or preceded by "@", "rate", "unit price", "سعر الوحدة";
//   an AMOUNT when it is preceded by "=", "total", "amount", "المبلغ", "الإجمالي", or when it is the only figure with no rate marker;
//   two bare figures are rate then amount (the order every quotation writes them in).
// Arabic-Indic digits are normalised first (normText). Nothing is guessed from an unmarked single
// figure beyond that rule, which the review states in its own words to the supplier.
const MONEY = String.raw`(?:AED|Dhs?\.?|درهم|د\.إ\.?)?\s*(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(?:AED|Dhs?\.?|درهم|د\.إ\.?)?`;
const RE_PRICE_CLAUSE = new RegExp(String.raw`(boq\s*|جدول\s*الكميات\s*)?${LINE}\s*[,:\-–]?\s*${VAL(1, 200)}`, 'gi');
const RE_FIG = new RegExp(MONEY, 'g');
// A total re-stated at the start of a sentence ("Total AED 65,960", "الإجمالي 65960 درهم") — never the
// "= total" inside a "line N" price clause. A discount states why the lines and the total differ.
const RE_TOTAL = new RegExp(String.raw`(?:^|[.;؛\n]\s*)(?:the\s+)?(?:grand\s+|net\s+)?(?:total|الإجمالي|المجموع)(?:\s+(?:is|should\s+be|excluding\s+vat|ex\.?\s*vat))?\s*[:=]?\s*${MONEY}`, 'i');
const RE_DISCOUNT = new RegExp(String.raw`(?:discount|rebate|خصم)[^\d\n]{0,20}${MONEY}`, 'i');
// "each" / "للوحدة" may end the message ("line 4 AED 150 each"); "per" / "/" / "لكل" name a unit after them.
const RATE_AFTER = /^\s*(?:(?:per|\/|لكل|لل|a\s)\s*\S|each\b|للوحدة)/i;
const RATE_BEFORE = /(?:@|rate|unit\s*price|price\s*per|سعر\s*الوحدة|السعر\s*لكل|بسعر)\s*[:=]?\s*$/i;
const AMOUNT_BEFORE = /(?:=|total|amount|المبلغ|الإجمالي|المجموع|بمبلغ|إجمالي)\s*[:=]?\s*$/i;
/** The rate and amount a clause states for one BOQ line, or null when it states no figure. */
export function readPriceClause(clause: string): { unit_price: number | null; amount: number | null } | null {
  const c = normText(clause);
  // a quantity restated ("320 m2") and a percentage are not prices
  const figs: { n: number; rate: boolean; amount: boolean }[] = [];
  for (const m of c.matchAll(RE_FIG)) {
    const n = Number(m[1].replace(/,/g, '')); if (!(n > 0)) continue;
    const before = c.slice(0, m.index!), after = c.slice(m.index! + m[0].length);
    if (/^\s*%/.test(after) || /^\s*(?:m2|m²|sqm|m3|m|lm|rm|nos?|nr|pcs?|ls|kg|set|متر|م2|م²|عدد|قطعة)\b(?!\s*(?:@|=|at|rate))/i.test(after) && !/(?:@|=|per|\/|لكل|rate|price|بسعر)\s*$/i.test(before)) continue;
    const money = /(?:AED|Dhs?\.?|درهم|د\.إ)/i.test(m[0]);
    const rate = RATE_AFTER.test(after) || RATE_BEFORE.test(before);
    const amount = AMOUNT_BEFORE.test(before);
    if (!money && !rate && !amount) continue;   // a bare number with no dirham sign and no marker is not a price
    figs.push({ n, rate, amount });
  }
  if (!figs.length) return null;
  const r = figs.find((f) => f.rate), a = figs.find((f) => f.amount && !f.rate);
  if (r || a) return { unit_price: r?.n ?? null, amount: a?.n ?? null };
  if (figs.length >= 2) return { unit_price: figs[0].n, amount: figs[1].n };
  return { unit_price: null, amount: figs[0].n };
}
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
  // The warranty is read from ITS sentence only. Measured 21 Sep 2026 (audit, finding 4): a message
  // "Installation included 4 weeks. Warranty 2 years parts and labour" read as coverage "installation,
  // on site, parts, labour", because the whole message was scanned for coverage words.
  const wSentence = t.split(/(?<=[.;؛])\s+|\n/).find((s) => /warrant|guarant|ضمان/i.test(s));
  if (wSentence) {
    const w = readWarranty(wSentence);
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
    const n = Number(m[1]); const key = normText(m[2]).toLowerCase(); const val = clean(m[3], 120).replace(/[.،]+$/, '').trim();
    if (!val || VAGUE.test(val)) continue;
    // "line 2 thickness: 15mm" names the attribute by its label ("thickness"), its code ("thickness_mm"),
    // the code's first word, or its Arabic label — the review's own example wording, in either language.
    const hit = open.find((i) => i.code === 'spec' && i.line_no === n && i.attr && (key.includes(String(i.attr).replace(/_/g, ' ')) || key.includes(String(i.attr).split('_')[0]) || i.en.toLowerCase().includes(`exact ${key}`) || i.ar.includes(key)));
    if (hit) out.push({ field: 'line_spec', line_no: n, attr: String(hit.attr), value: val });
  }
  // Prices typed for BOQ lines. A clause that also states an exclusion or a quantity reason is not a
  // price ("BOQ line 3 excluded — by others" carries no dirham figure and reads as none).
  for (const m of t.matchAll(RE_PRICE_CLAUSE)) {
    const n = Number(m[2]); if (excluded.has(n)) continue;
    // "line N" alone is the supplier's own line unless a BOQ point is open for N
    const own = !m[1] && !open.some((i) => i.boq_line === n) && open.some((i) => i.code === 'line_unpriced' && i.line_no === n);
    if (!m[1] && !own && !open.some((i) => i.boq_line === n)) continue;
    const p = readPriceClause(m[3]); if (!p) continue;
    out.push(own ? { field: 'line_price', line_no: n, unit_price: p.unit_price, amount: p.amount } : { field: 'boq_price', boq_line: n, unit_price: p.unit_price, amount: p.amount });
  }
  if (has('total_mismatch')) {
    const tot = t.match(RE_TOTAL); const tv = tot ? Number(tot[1].replace(/,/g, '')) : 0;
    if (tv > 0) out.push({ field: 'total', value: tv });
    const dis = t.match(RE_DISCOUNT);
    if (dis) out.push({ field: 'total_explained', value: clean(dis[0], 120) });
  }
  // A material the customer named: "<its name or key>: <value>", in either language.
  for (const i of open.filter((x) => x.code === 'component' && x.attr)) {
    const key = String(i.attr).slice('component:'.length);
    const names = [key.replace(/_/g, ' '), ...[i.en.match(/Material — ([^.(:]+)/)?.[1], i.ar.match(/المادة — ([^.(:]+)/)?.[1]].filter(Boolean).map((s) => s!.trim())]
      .filter((s) => s.length >= 2).map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    const m = t.match(new RegExp(String.raw`(?:^|[\s,.;؛])(?:${names.join('|')})\s*[:=\-–]\s*${VAL(2, 120)}`, 'i'));
    const val = m ? clean(m[1], 120).replace(/[.،]+$/, '').trim() : '';
    if (val && !VAGUE.test(val)) out.push({ field: 'component', key, value: val, label_en: i.en.match(/Material — ([^.(:]+)/)?.[1]?.trim() || key.replace(/_/g, ' '), label_ar: i.ar.match(/المادة — ([^.(:]+)/)?.[1]?.trim() || 'المادة' });
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

const r2 = (n: number) => Math.round(n * 100) / 100;
/** The working quotation with the supplier's stated details applied. Pure: returns a new object. `boq` is the job's BOQ, needed only to price a BOQ line. */
export function applyCorrections(w0: Working, cs: Correction[], boq: BoqRow[] = []): Working {
  const w: Working = structuredClone(w0);
  const log = (field: string, value: string, line: number | null = null) => w.corrections.push({ field, value, line });
  const drop = new Set<WLine>();
  for (const c of cs) {
    switch (c.field) {
      case 'boq_price': {
        const b = boq[c.boq_line - 1]; if (!b) break;
        const qty = num(b.qty);
        let unit_price = c.unit_price, amount = c.amount;
        if (unit_price == null && amount != null && qty) unit_price = r2(amount / qty);
        if (amount == null && unit_price != null && qty) amount = r2(unit_price * qty);
        if (amount == null && unit_price == null) break;
        // the quotation line already matched to this BOQ line is re-priced; otherwise the BOQ line
        // becomes a line of the quotation in the BOQ's own words, quantity and unit
        const j = matchBoq(boq, w.lines).get(c.boq_line - 1);
        if (j != null) { w.lines[j].unit_price = unit_price ?? w.lines[j].unit_price; w.lines[j].amount = amount ?? w.lines[j].amount; if (!w.lines[j].qty && qty != null) { w.lines[j].qty = String(qty); w.lines[j].unit = String(b.unit ?? ''); } }
        else w.lines.push({ description: String(b.description ?? ''), qty: qty == null ? '' : String(qty), unit: String(b.unit ?? ''), unit_price, amount });
        // a priced line is not an excluded one
        if (w.boq_excluded[String(c.boq_line)]) { delete w.boq_excluded[String(c.boq_line)]; w.exclusions = withoutExclusionNote(w.exclusions, c.boq_line); }
        // the total follows the lines the supplier priced; the VAT basis is asked separately
        retotal(w);
        log('boq_price', `${unit_price ?? ''}|${amount ?? ''}`, c.boq_line); break;
      }
      case 'line_price': {
        const l = w.lines[c.line_no - 1]; if (!l) break;
        const qty = num(l.qty);
        l.unit_price = c.unit_price ?? (c.amount != null && qty ? r2(c.amount / qty) : l.unit_price);
        l.amount = c.amount ?? (c.unit_price != null && qty ? r2(c.unit_price * qty) : l.amount);
        retotal(w); log('line_price', `${l.unit_price ?? ''}|${l.amount ?? ''}`, c.line_no); break;
      }
      case 'total': {
        w.amount = c.value; if (w.subtotal != null) w.subtotal = c.value; if (w.price_ex_vat != null) w.price_ex_vat = c.value; w.vat_amount = null;
        log('total', String(c.value)); break;
      }
      case 'total_explained': {
        w.qty_explained = { ...w.qty_explained, total: c.value };
        w.conditions = [w.conditions, c.value].filter(Boolean).join('; ').slice(0, 2000);
        log('total_explained', c.value); break;
      }
      case 'component': {
        w.terms_spec = { ...w.terms_spec, components: { ...(w.terms_spec.components ?? {}), [c.key]: { value: c.value, source: 'supplier_portal' } } };
        log(`component:${c.key}`, c.value); break;
      }
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
        // EXCLUDED MEANS NOT IN THE PRICE (audit 21 Sep 2026, finding 4: the generated quotation read
        // "BOQ line 3 excluded — by others" while line 3 was priced AED 7,680 and counted in the total).
        // The supplier's word in the chat is the later one: the priced line leaves the quotation and the
        // total. It is dropped after every correction of this message, so a "line N" spec in the same
        // message still names the line the supplier saw.
        const j = boq.length ? matchBoq(boq, w.lines).get(c.boq_line - 1) : undefined;
        if (j != null && priced(w.lines[j])) drop.add(w.lines[j]);
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
      // A Correction added to the union without a case here would otherwise be dropped in silence.
      default: { const _never: never = c; void _never; break; }
    }
  }
  if (drop.size) { w.lines = w.lines.filter((l) => !drop.has(l)); retotal(w); }
  return w;
}
/**
 * The total follows the priced lines. A VAT amount the file stated described the OLD total, so it is
 * cleared; the stated VAT treatment stands and the review asks the basis only if none was stated.
 */
function retotal(w: Working) {
  const sum = r2(w.lines.filter((l) => !heading(l)).reduce((s, l) => s + (Number(l.amount) || 0), 0));
  w.amount = sum; if (w.subtotal != null) w.subtotal = sum; if (w.price_ex_vat != null) w.price_ex_vat = sum;
  w.vat_amount = null;
}

const withoutExclusionNote = (s: string, n: number) => s.split(/;\s*/).filter((x) => !new RegExp(String.raw`^BOQ line ${n} excluded`).test(x)).join('; ');

// ---------------------------------------------------------------------------------------------
// A revised file keeps what the chat already settled (audit 21 Sep 2026, finding 12: after validity,
// installation and warranty were answered in the chat, a revised CSV re-opened all of them — 3 open
// points became 10). A new version replaces what the OLD FILE said; it does not un-say what the
// SUPPLIER said in the conversation. Rule: every term the new file states wins; every term it does
// not state keeps the conversation's answer; an exclusion stands only for a BOQ line the new file
// leaves unpriced; a line specification stated in the chat follows its line by description.
// ---------------------------------------------------------------------------------------------
export function carryOver(prev: Working | null, next: Working, boq: BoqRow[] = []): Working {
  if (!prev) return next;
  const w: Working = structuredClone(next);
  const log = (field: string, value: string, line: number | null = null) => w.corrections.push({ field: `carried:${field}`, value, line });
  for (const f of ['validity', 'lead_time', 'warranty', 'payment_terms'] as const) if (!w[f] && prev[f]) { w[f] = prev[f]; log(f, prev[f]); }
  const stated = (v: unknown) => v && v !== 'not_stated';
  if (!stated(w.vat_treatment) && stated(prev.vat_treatment)) {
    w.vat_treatment = prev.vat_treatment;
    if (prev.vat_treatment === 'exclusive' || prev.vat_treatment === 'not_registered') w.price_ex_vat = w.amount ?? w.price_ex_vat;
    else if (prev.price_ex_vat != null && prev.amount === w.amount) w.price_ex_vat = prev.price_ex_vat;
    log('vat_treatment', String(prev.vat_treatment));
  }
  if (w.foreign_currency && !prev.foreign_currency && prev.corrections.some((c) => c.field === 'currency')) { w.foreign_currency = null; log('currency', 'AED'); }
  // delivery / installation / warranty confirmed in the chat stay unless the new file states them
  const ts = { ...prev.terms_spec };
  if (readDelivery(w.lead_time)) delete ts.delivery;
  if (readWarranty(w.warranty).period) delete ts.warranty;
  if (readInstallation(assessLines(w), { scope: w.scope, conditions: w.conditions, notes: w.notes, exclusions: w.exclusions }).included) delete ts.installation;
  w.terms_spec = { ...ts, ...w.terms_spec };
  // exclusions and quantity reasons are about the job, not the file — unless the new file priced the line
  const match = matchBoq(boq, w.lines);
  for (const [n, why] of Object.entries(prev.boq_excluded || {})) {
    const j = match.get(Number(n) - 1);
    if (j != null && priced(w.lines[j])) continue;
    w.boq_excluded[n] = why; w.exclusions = [w.exclusions, `BOQ line ${n} excluded: ${why}`].filter(Boolean).join('; ').slice(0, 2000);
  }
  w.qty_explained = { ...(prev.qty_explained || {}), ...w.qty_explained };
  // a specification the supplier stated in the chat follows the line that says the same thing
  prev.lines.forEach((pl) => {
    const chat = Object.entries(pl.spec_source ?? {}).filter(([, s]) => s === 'supplier_portal').map(([k]) => k);
    if (!chat.length) return;
    const pt = new Set(toks(pl.description));
    const j = w.lines.findIndex((nl) => { const nt = toks(nl.description); return nt.length && nt.filter((t) => pt.has(t)).length / nt.length >= 0.5; });
    if (j < 0) return;
    const nl = w.lines[j];
    for (const k of chat) { if (!nl.spec?.[k]) { nl.spec = { ...(nl.spec ?? {}), [k]: pl.spec![k] }; nl.spec_source = { ...(nl.spec_source ?? {}), [k]: 'supplier_portal' }; log(`line_spec:${k}`, pl.spec![k], j + 1); } }
  });
  w.corrections = [...prev.corrections, ...w.corrections];
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
