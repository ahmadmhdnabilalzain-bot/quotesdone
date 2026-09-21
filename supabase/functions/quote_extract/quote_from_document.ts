// quote_from_document — a supplier's quotation FILE read into quote_extract's proposal shape with no
// model (14 Sep 2026).
//
// WHY. quote_extract read quotations only through a vision model, and every route is held, so every
// uploaded quotation failed and the supplier was told to type it into the form. A quotation sent as
// Excel, Word, CSV, email, zip or a PDF with a text layer states its prices as data; _shared/doc_read
// opens all of them, and this turns what it read into {amount, line_items, lead_time, ...}.
//
// WHAT IT KEEPS AND WHAT IT REMOVES. The PRICES are kept: this is the supplier's own quotation and the
// customer compares on them. The SUPPLIER'S IDENTITY is removed, because the customer pays to reveal
// it: emails, URLs, UAE phones, company-name patterns, TRNs and licence numbers (scrubIdentity), plus
// the supplier's own company name passed in as `terms`. Every removed term is listed in masked_terms,
// which the supplier reviews and the customer never sees. Confidence is always 'low': a deterministic
// read of a column layout it has not seen before can pick the wrong column, and the supplier confirms
// before sending.
//
// VAT (founder, 14 Sep 2026: supplier VAT details are hidden from the customer). The subtotal, the
// VAT row and the grand total are read separately; `amount` is the price EXCLUDING VAT whenever that
// can be determined exactly (line_specs/vat.ts), and the VAT figures and the supplier's TRN are
// returned for the supplier's own review and the internal record only.
//
// OPTIONS (founder, 14 Sep 2026: two options are two quotations). A heading row ("Option 1",
// "Alternative B", "الخيار 2") starts an option; each line after it carries `option`, and a total
// written inside an option is that option's total (option_totals). supplier_api splits on them.
import type { Cell, Extracted } from '../_shared/doc_read/types.ts';
import { scrubIdentity } from '../drawing_boq/boq_from_text.ts';
import { OPTION_HEAD, optionAmount, optionNumber, splitOptions } from '../_shared/line_specs/options.ts';
import { readVat, type VatTreatment } from '../_shared/line_specs/vat.ts';

export type QuoteLine = { description: string; qty: string; amount: number | null; option?: number; /** A "Specification" column, when the file has one. */ specification?: string };
export type Proposal = {
  amount: number | null; currency: 'AED'; line_items: QuoteLine[]; lead_time: string; validity: string;
  payment_terms: string; warranty: string; scope: string; conditions: string; exclusions: string; notes: string;
  description_anonymized: string; masked_terms: string[]; confidence: 'low'; method: 'document';
  /** Internal record only; never shown to a customer. */
  subtotal: number | null; vat_amount: number | null; total_incl_vat: number | null; vat_treatment: VatTreatment; price_ex_vat: number | null; trn: string | null;
  options: { option_no: number; amount: number | null }[]; option_totals: Record<string, number>;
};

const num = (v: Cell): number | null => {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  const s = String(v ?? '').replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/(AED|Dhs?\.?|د\.?\s?إ\.?|درهم)/gi, '').replace(/[,\s]/g, '');
  const m = s.match(/^-?\d+(\.\d+)?$/);
  return m ? Number(s) : null;
};
const norm = (v: Cell) => String(v ?? '').toLowerCase().replace(/[\s._#:()\-\/]+/g, ' ').trim();
type Col = 'desc' | 'qty' | 'unit' | 'rate' | 'amount' | 'spec';
function roleOf(h: string): Col | null {
  if (!h) return null;
  // Before 'desc': the auditor's CSV (21 Sep 2026) carried a "Specification" column that fell to no
  // role, so "12.5mm Knauf board, 100mm stud" never reached the line and every spec was asked again.
  if (/(specification|^specs?$|المواصفات|مواصفات)/.test(h)) return 'spec';
  if (/(qty|quantity|الكمية|كمية)/.test(h)) return 'qty';
  if (/(unit price|unit rate|rate|price|سعر الوحدة|السعر)/.test(h)) return 'rate';
  if (/(amount|total|value|المبلغ|الإجمالي|القيمة)/.test(h)) return 'amount';
  if (/^(unit|uom|الوحدة|وحدة)$/.test(h)) return 'unit';
  if (/(description|particulars|item|scope|material|الوصف|البيان|البند)/.test(h)) return 'desc';
  return null;
}
const SUBTOTAL = /sub\s*-?\s*total|total\s*(?:before|excl\w*\.?)\s*(?:of\s*)?vat|المجموع الفرعي|الإجمالي قبل الضريبة|الإجمالي غير شامل/i;
const TOTAL = /(grand\s*total|net\s*total|total\s*amount|total\s*\(?incl|^\s*total\b|الإجمالي|المجموع)/i;
const VAT = /(vat|tax|ضريبة)/i;

type Table = { lines: QuoteLine[]; totals: Record<string, number>; subtotal: number | null; vat: number | null };
function tableQuote(rows: Cell[][], clean: (s: string) => string): Table | null {
  for (let r = 0; r < Math.min(rows.length, 30); r++) {
    const cols: Partial<Record<Col, number>> = {};
    (rows[r] || []).forEach((c, i) => { const k = roleOf(norm(c)); if (k && cols[k] === undefined) cols[k] = i; });
    if (cols.desc === undefined || (cols.amount === undefined && cols.rate === undefined)) continue;
    const lines: QuoteLine[] = [];
    const totals: Record<string, number> = {}; const grand: Record<string, boolean> = {};
    let subtotal: number | null = null, vat: number | null = null, cur: number | null = null, seq = 0;
    for (const row of rows.slice(r + 1)) {
      const at = (k: Col) => (cols[k] === undefined ? '' : row[cols[k]!]);
      const raw = String(at('desc') ?? '').trim();
      const desc = clean(raw);
      const rate = num(at('rate')), qty = num(at('qty'));
      const amount = num(at('amount')) ?? (rate != null && qty != null ? Math.round(rate * qty * 100) / 100 : null);
      const label = (row || []).map((c) => String(c ?? '')).join(' ');
      const lastNum = () => amount ?? [...row].reverse().map(num).find((x) => x != null) ?? null;
      const key = cur == null ? 'all' : String(cur);
      if (raw && OPTION_HEAD.test(raw) && amount == null && qty == null) {
        cur = optionNumber(raw, seq + 1); seq = Math.max(seq, cur);
        lines.push({ description: desc.slice(0, 300), qty: '', amount: null, option: cur });
        continue;
      }
      if (SUBTOTAL.test(label)) { const v = lastNum(); if (v != null && cur == null) subtotal = v; continue; }
      if (VAT.test(label) && !/incl/i.test(label) && !TOTAL.test(label)) { const v = lastNum(); if (v != null && cur == null) vat = v; continue; }
      if (TOTAL.test(label)) {
        const v = lastNum();
        if (v != null && (!grand[key] || /grand/i.test(label))) { totals[key] = v; grand[key] = /grand|net|incl/i.test(label); }
        continue;
      }
      // A row with neither a quantity nor a price ("Lead time: 3 weeks") is a note, not a priced line.
      if (!desc || VAT.test(desc) || (amount == null && qty == null)) continue;
      const spec = clean(String(at('spec') ?? '').trim()).slice(0, 300);
      lines.push({ description: desc.slice(0, 300), qty: [at('qty'), at('unit')].map((x) => String(x ?? '').trim()).filter(Boolean).join(' ').slice(0, 40), amount, ...(spec ? { specification: spec } : {}), ...(cur != null ? { option: cur } : {}) });
    }
    if (lines.some((l) => l.amount != null || l.qty)) return { lines, totals, subtotal, vat };
  }
  return null;
}

// A term is read wherever it sits on a line, not only at its start. MEASURED 21 Sep 2026 (auditor's
// PDF, ZZDEMO_quotation_D958E1EA.pdf): "Ref: … Date: 21 Sep 2026 Validity: 30 days" is one line, and
// the `^`-anchored form read no validity from it. A value ends at the next "Label:" on the line, at a
// sentence end, or at the end of the line — "Lead time: 4 weeks from LPO. Payment: 50% advance" gives
// "4 weeks from LPO", not the payment terms too. A validity or lead time with no digit and no
// "immediate / ex stock" is prose ("prices valid subject to…"), not a term, and is dropped.
const VALUE = String.raw`([^\n|·]{2,160}?)(?=\s*(?:[.;]\s|\s+(?:[A-Z][a-z]+(?:\s[a-z]+)?|[؀-ۿ]+(?:\s[؀-ۿ]+)?)\s*[:\-–]\s|$))`;
const FIELD: [keyof Proposal, RegExp][] = [
  ['lead_time', new RegExp(String.raw`(?:^|[\s|·])(?:lead\s*time|delivery(?:\s*(?:time|period))?|completion|مدة التسليم|مدة التنفيذ)\s*[:\-–]\s*${VALUE}`, 'im')],
  ['validity', new RegExp(String.raw`(?:^|[\s|·])(?:validity|valid\s*(?:for|until|till)?|offer\s*valid(?:ity)?|صلاحية العرض|الصلاحية|العرض ساري)\s*[:\-–]?\s*${VALUE}`, 'im')],
  ['payment_terms', new RegExp(String.raw`(?:^|[\s|·])(?:payment(?:\s*terms)?|terms\s*of\s*payment|شروط الدفع|الدفع)\s*[:\-–]\s*${VALUE}`, 'im')],
  ['warranty', new RegExp(String.raw`(?:^|[\s|·])(?:warranty|guarantee|الضمان)\s*[:\-–]?\s*${VALUE}`, 'im')],
  ['exclusions', new RegExp(String.raw`(?:^|[\s|·])(?:exclusions?|excluded|not\s*included|الاستثناءات)\s*[:\-–]\s*${VALUE}`, 'im')],
];
const CONCRETE = /\d|immediate|ex[\s-]?stock|from\s*stock|فوري|من المخزون/i;

// ── Priced lines written as TEXT (a PDF's text layer, a plain email) ──────────────────────────
// MEASURED 21 Sep 2026: doc_read/pdf returns a PDF as visual text lines and no table, so a quotation
// whose three lines read "001 Gypsum board partition …  320 m2 @ AED 95.00 = AED 30,400.00" produced
// NO line items, and the sales engineer reported every BOQ line unpriced. A priced text line is
//   [no] description  qty unit  [@|x|at] [AED] rate  [=] [AED] amount
// or, with no rate,   [no] description  qty unit  [AED] amount
// A line that is a subtotal, VAT or total row is a total, never an item. Nothing is guessed: a line
// that does not carry a quantity, a unit and at least one figure is not a priced line.
const NUM = String.raw`(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)`;
const CUR = String.raw`(?:AED|Dhs?\.?|د\.?\s?إ\.?|درهم)?`;
// A unit starts with a letter and may carry a digit ("m2", "m3"): the first draft took letters only
// and read "320 m2" as no unit, so lines 1 and 2 of the auditor's PDF were skipped and line 3 kept.
const UNIT_TXT = String.raw`([A-Za-z][A-Za-z0-9²³]{0,5}\.?|م\.?ط|م2|م²|م3|متر(?:\s*(?:مربع|طولي|مكعب))?|عدد|قطعة|طقم|مقطوعية|كغ|لتر|طن)`;
const TEXT_LINE = new RegExp(String.raw`^\s*(?:(\d{1,3})[.)]?\s+)?(.+?)\s{1,}${NUM}\s*${UNIT_TXT}\s+(?:[@x×]|at)?\s*${CUR}\s*${NUM}(?:\s*(?:=|\s)\s*${CUR}\s*${NUM})?\s*$`, 'i');
const TOTAL_ROW = /^\s*(?:sub\s*-?\s*total|total|grand\s*total|net\s*total|vat|tax|discount|الإجمالي|المجموع|ضريبة|خصم)\b/i;
export function linesFromText(text: string, clean: (s: string) => string = (s) => s): QuoteLine[] {
  const out: QuoteLine[] = [];
  for (const raw of String(text || '').split('\n')) {
    const line = raw.replace(/\s+/g, ' ').trim();
    if (!line || TOTAL_ROW.test(line)) continue;
    const m = line.match(TEXT_LINE);
    if (!m) continue;
    const desc = clean(m[2].replace(/[\s,;:–-]+$/, ''));
    if (!/\p{L}{3,}/u.test(desc)) continue;
    const qty = num(m[3]); const unit = m[4].replace(/\.$/, '');
    const a = num(m[5]); const b = m[6] != null ? num(m[6]) : null;
    // two figures: rate then amount; one figure: the amount (a rate alone would need a quantity to multiply)
    const amount = b != null ? b : (a != null && qty != null ? Math.round(a * qty * 100) / 100 : a);
    if (qty == null || amount == null) continue;
    out.push({ description: desc.slice(0, 300), qty: `${qty} ${unit}`.slice(0, 40), amount });
  }
  return out;
}
/** Subtotal, VAT amount and total written in prose, even side by side on one line. */
function totalsFromText(text: string): { subtotal: number | null; vat: number | null; total: number | null } {
  const t = String(text || '');
  const pick = (re: RegExp) => { const m = t.match(re); return m ? num(m[1]) : null; };
  const subtotal = pick(new RegExp(String.raw`(?:sub\s*-?\s*total|total\s*(?:before|excl\w*\.?)\s*(?:of\s*)?vat|المجموع الفرعي|الإجمالي قبل الضريبة|الإجمالي غير شامل)\s*:?\s*${CUR}\s*${NUM}`, 'i'));
  const vat = pick(new RegExp(String.raw`\b(?:vat|tax|ضريبة(?:\s*القيمة\s*المضافة)?)\s*(?:@|at|بنسبة)?\s*(?:\d+(?:\.\d+)?\s*%)?\s*:?\s*${CUR}\s*${NUM}`, 'i'));
  let total: number | null = null;
  for (const m of t.matchAll(/(grand\s*total|net\s*total|total\s*amount|total\s*\(?incl[^\n:]*|\btotal\b|الإجمالي|المجموع)[^\d\n]{0,40}([\d][\d,]*(?:\.\d+)?)/gi)) {
    if (VAT.test(m[0]) && !/incl/i.test(m[0])) continue;
    if (SUBTOTAL.test(m[0])) continue;
    const v = num(m[2]);
    if (v != null && (total == null || /grand|net|incl/i.test(m[1]))) total = v;
  }
  return { subtotal, vat, total };
}

export function quoteFromExtracted(ex: Extracted, terms: string[] = []): Proposal {
  const masked = new Set<string>();
  const t = terms.map((s) => String(s || '').trim()).filter((s) => s.length >= 3);
  const clean = (s: string) => {
    let out = s;
    for (const term of t) {
      const re = new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
      if (re.test(out)) { masked.add(term); out = out.replace(re, '█'); }
    }
    const scrubbed = scrubIdentity(out);
    if (scrubbed !== out.replace(/\s{2,}/g, ' ').trim()) masked.add('contact details');
    return scrubbed;
  };
  const texts: string[] = [];
  let best: Table | null = null;
  const visit = (e: Extracted) => {
    if (e.text) texts.push(e.text);
    for (const tb of e.tables) {
      texts.push(tb.map((row) => (row || []).map((c) => String(c ?? '')).join(' ')).join('\n'));
      const q = tableQuote(tb, clean); if (q && (!best || q.lines.length > best.lines.length)) best = q;
    }
    for (const c of e.children) visit(c.doc);
  };
  visit(ex);
  const text = texts.join('\n');
  // A supplier term anywhere in the file (a letterhead never becomes an output field) is still
  // reported, so the supplier sees exactly what was withheld from the customer.
  for (const term of t) if (text.toLowerCase().includes(term.toLowerCase())) masked.add(term);
  // A total written in the text ("Grand Total: AED 12,450.00") wins over a sum of lines; the subtotal
  // and the VAT amount written in the text are the VAT basis when no table carried them.
  const tt = totalsFromText(text);
  const textTotal = tt.total;
  // No table at all (a PDF's text layer, a plain email): the priced lines are read from the text.
  let b = best as Table | null;
  if (!b) { const tl = linesFromText(text, clean); if (tl.length) b = { lines: tl, totals: {}, subtotal: null, vat: null }; }
  const plain = b ? b.lines.filter((l) => l.amount != null || l.qty) : [];
  const sum = plain.reduce((s, l) => s + (l.amount || 0), 0);
  const gross = b?.totals.all ?? textTotal ?? (sum > 0 ? Math.round(sum * 100) / 100 : null);
  const vat = readVat({ amount: gross, subtotal: b?.subtotal ?? tt.subtotal, vat_amount: b?.vat ?? tt.vat, text });
  const option_totals: Record<string, number> = {};
  for (const [k, v] of Object.entries(b?.totals ?? {})) if (k !== 'all') option_totals[k] = v;
  const split = b && b.lines.some((l) => l.option != null) ? splitOptions(b.lines, option_totals) : [];
  const options = split.length > 1 ? split.map((o) => ({ option_no: o.option_no, amount: optionAmount(o) })) : [];
  const p: Proposal = {
    amount: options.length ? options[0].amount : (vat.price_ex_vat ?? gross), currency: 'AED', line_items: b ? b.lines.slice(0, 200) : [],
    lead_time: '', validity: '', payment_terms: '', warranty: '', scope: '', conditions: '', exclusions: '', description_anonymized: '', masked_terms: [], confidence: 'low', method: 'document',
    notes: `Read from the ${ex.kind.toUpperCase()} file with no model${b ? `: ${plain.length} priced line(s)` : ''}${options.length ? `, ${options.length} options (each is sent as its own quotation)` : ''}. Please check every figure before sending.`,
    subtotal: b?.subtotal ?? null, vat_amount: vat.vat_amount, total_incl_vat: vat.vat_amount && gross ? gross : null, vat_treatment: vat.treatment,
    price_ex_vat: options.length ? null : vat.price_ex_vat, trn: vat.trn, options, option_totals,
  };
  // What the file says about installation ("Installation included 4 weeks", "supply only") has no
  // field of its own; it is kept as a condition so the hold gate's readInstallation reads it. Only
  // sentences that name installation — a note row of a CSV, a line of a PDF — never priced lines.
  const inst = [...new Set(text.split(/\n|(?<=[.;])\s+/).map((s) => s.replace(/\s+/g, ' ').trim())
    .filter((s) => s.length >= 8 && s.length <= 200 && /install|تركيب|supply\s*only|توريد\s*فقط/i.test(s) && !TEXT_LINE.test(s)))];
  if (inst.length) p.conditions = clean(inst.join(' ')).slice(0, 600);
  for (const [k, re] of FIELD) {
    const m = text.match(re); if (!m) continue;
    const v = clean(m[1].trim()).replace(/[.;,\s]+$/, '').slice(0, 200);
    if ((k === 'validity' || k === 'lead_time') && !CONCRETE.test(v)) continue;
    (p as Record<string, unknown>)[k] = v;
  }
  if (vat.trn) masked.add('TRN');
  p.masked_terms = [...masked];
  return p;
}
