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
// it: emails, URLs, UAE phones and company-name patterns (scrubIdentity), plus the supplier's own
// company name passed in as `terms`. Every removed term is listed in masked_terms, which the supplier
// reviews and the customer never sees. Confidence is always 'low': a deterministic read of a column
// layout it has not seen before can pick the wrong column, and the supplier confirms before sending.
import type { Cell, Extracted } from '../_shared/doc_read/types.ts';
import { scrubIdentity } from '../drawing_boq/boq_from_text.ts';

export type QuoteLine = { description: string; qty: string; amount: number | null };
export type Proposal = {
  amount: number | null; currency: 'AED'; line_items: QuoteLine[]; lead_time: string; validity: string;
  payment_terms: string; warranty: string; scope: string; conditions: string; exclusions: string; notes: string;
  description_anonymized: string; masked_terms: string[]; confidence: 'low'; method: 'document';
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
const TOTAL = /(grand\s*total|net\s*total|total\s*amount|total\s*\(?incl|^\s*(?:sub\s*)?total\b|الإجمالي|المجموع)/i;
const VAT = /(vat|tax|ضريبة)/i;

function tableQuote(rows: Cell[][], clean: (s: string) => string) {
  for (let r = 0; r < Math.min(rows.length, 30); r++) {
    const cols: Partial<Record<Col, number>> = {};
    (rows[r] || []).forEach((c, i) => { const k = roleOf(norm(c)); if (k && cols[k] === undefined) cols[k] = i; });
    if (cols.desc === undefined || (cols.amount === undefined && cols.rate === undefined)) continue;
    const lines: QuoteLine[] = [];
    let total: number | null = null, grand = false;
    for (const row of rows.slice(r + 1)) {
      const at = (k: Col) => (cols[k] === undefined ? '' : row[cols[k]!]);
      const desc = clean(String(at('desc') ?? '').trim());
      const rate = num(at('rate')), qty = num(at('qty'));
      const amount = num(at('amount')) ?? (rate != null && qty != null ? Math.round(rate * qty * 100) / 100 : null);
      const label = (row || []).map((c) => String(c ?? '')).join(' ');
      if (TOTAL.test(label) && !VAT.test(label)) {
        const v = amount ?? [...row].reverse().map(num).find((x) => x != null) ?? null;
        if (v != null && (!grand || /grand/i.test(label))) { total = v; grand = /grand|net|incl/i.test(label); }
        continue;
      }
      // A row with neither a quantity nor a price ("Lead time: 3 weeks") is a note, not a priced line.
      if (!desc || VAT.test(desc) || (amount == null && qty == null)) continue;
      lines.push({ description: desc.slice(0, 300), qty: [at('qty'), at('unit')].map((x) => String(x ?? '').trim()).filter(Boolean).join(' ').slice(0, 40), amount });
    }
    if (lines.length) return { lines, total };
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
  let best: { lines: QuoteLine[]; total: number | null } | null = null;
  const visit = (e: Extracted) => {
    if (e.text) texts.push(e.text);
    for (const tb of e.tables) { const q = tableQuote(tb, clean); if (q && (!best || q.lines.length > best.lines.length)) best = q; }
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
    const v = num(m[2]);
    if (v != null && (textTotal == null || /grand|net|incl/i.test(m[1]))) textTotal = v;
  }
  const b = best as { lines: QuoteLine[]; total: number | null } | null;
  const sum = b ? b.lines.reduce((s, l) => s + (l.amount || 0), 0) : 0;
  const amount = b?.total ?? textTotal ?? (sum > 0 ? Math.round(sum * 100) / 100 : null);
  const p: Proposal = {
    amount, currency: 'AED', line_items: b ? b.lines.slice(0, 200) : [], lead_time: '', validity: '', payment_terms: '', warranty: '',
    scope: '', conditions: '', exclusions: '', description_anonymized: '', masked_terms: [], confidence: 'low', method: 'document',
    notes: `Read from the ${ex.kind.toUpperCase()} file with no model${b ? `: ${b.lines.length} priced line(s)` : ''}. Please check every figure before sending.`,
  };
  for (const [k, re] of FIELD) { const m = text.match(re); if (m) (p as Record<string, unknown>)[k] = clean(m[1].trim()).slice(0, 200); }
  p.masked_terms = [...masked];
  return p;
}
