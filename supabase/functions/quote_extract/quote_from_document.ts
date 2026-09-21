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

export type QuoteLine = { description: string; qty: string; amount: number | null; option?: number };
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
type Col = 'desc' | 'qty' | 'unit' | 'rate' | 'amount';
function roleOf(h: string): Col | null {
  if (!h) return null;
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
      lines.push({ description: desc.slice(0, 300), qty: [at('qty'), at('unit')].map((x) => String(x ?? '').trim()).filter(Boolean).join(' ').slice(0, 40), amount, ...(cur != null ? { option: cur } : {}) });
    }
    if (lines.some((l) => l.amount != null || l.qty)) return { lines, totals, subtotal, vat };
  }
  return null;
}

const FIELD: [keyof Proposal, RegExp][] = [
  ['lead_time', /^(?:lead\s*time|delivery(?:\s*(?:time|period))?|completion|مدة التسليم|مدة التنفيذ)\s*[:\-–]\s*(.{2,100})$/im],
  ['validity', /^(?:validity|valid\s*(?:for|until|till)?|offer\s*valid(?:ity)?|صلاحية العرض|العرض ساري)\s*[:\-–]?\s*(.{2,100})$/im],
  ['payment_terms', /^(?:payment(?:\s*terms)?|terms\s*of\s*payment|شروط الدفع|الدفع)\s*[:\-–]\s*(.{2,160})$/im],
  ['warranty', /^(?:warranty|guarantee|الضمان)\s*[:\-–]\s*(.{2,120})$/im],
  ['exclusions', /^(?:exclusions?|excluded|not\s*included|الاستثناءات)\s*[:\-–]\s*(.{2,200})$/im],
];

// A note row ("Exclusions: electrical fittings, painting of walls, scaffolding above 4m") is one
// sentence that the CSV reader split on its commas. Joined back with a space it lost them, and the
// customer's PDF read "electrical fittings painting of walls scaffolding above 4m" (customer audit,
// 21 Sep 2026, finding 12). A row that starts with a "Label:" cell and carries no number is such a
// sentence and is put back with its commas; every other row (a priced line) keeps the space join.
export function rowText(row: Cell[] | null | undefined): string {
  const cells = (row || []).map((c) => String(c ?? '').trim());
  const note = /^[^\d:]{2,40}[:\-–]\s*\S/.test(cells[0] || '') && !cells.slice(1).some((c) => num(c) != null);
  return cells.filter((c, i) => c || i === 0).join(note ? ', ' : ' ');
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
    // The tables' rows first, then the reader's own text: for a CSV or sheet the text is the same rows
    // tab-joined, and a FIELD match taken from it would give back the comma-less note row.
    for (const tb of e.tables) {
      texts.push(tb.map(rowText).join('\n'));
      const q = tableQuote(tb, clean); if (q && (!best || q.lines.length > best.lines.length)) best = q;
    }
    if (e.text) texts.push(e.text);
    for (const c of e.children) visit(c.doc);
  };
  visit(ex);
  const text = texts.join('\n');
  // A supplier term anywhere in the file (a letterhead never becomes an output field) is still
  // reported, so the supplier sees exactly what was withheld from the customer.
  for (const term of t) if (text.toLowerCase().includes(term.toLowerCase())) masked.add(term);
  // A total written in the text ("Grand Total: AED 12,450.00") wins over a sum of lines.
  let textTotal: number | null = null;
  for (const m of text.matchAll(/(grand\s*total|net\s*total|total\s*amount|total\s*\(?incl[^\n:]*|\btotal\b|الإجمالي|المجموع)[^\d\n]{0,40}([\d][\d,]*(?:\.\d+)?)/gi)) {
    if (VAT.test(m[0]) && !/incl/i.test(m[0])) continue;
    if (SUBTOTAL.test(m[0])) continue;
    const v = num(m[2]);
    if (v != null && (textTotal == null || /grand|net|incl/i.test(m[1]))) textTotal = v;
  }
  const b = best as Table | null;
  const plain = b ? b.lines.filter((l) => l.amount != null || l.qty) : [];
  const sum = plain.reduce((s, l) => s + (l.amount || 0), 0);
  const gross = b?.totals.all ?? textTotal ?? (sum > 0 ? Math.round(sum * 100) / 100 : null);
  const vat = readVat({ amount: gross, subtotal: b?.subtotal ?? null, vat_amount: b?.vat ?? null, text });
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
  for (const [k, re] of FIELD) { const m = text.match(re); if (m) (p as Record<string, unknown>)[k] = clean(m[1].trim()).slice(0, 200); }
  if (vat.trn) masked.add('TRN');
  p.masked_terms = [...masked];
  return p;
}
