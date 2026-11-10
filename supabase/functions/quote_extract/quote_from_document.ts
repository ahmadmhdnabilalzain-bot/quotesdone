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
// the supplier's own company name passed in as `terms`. Since 10 Nov 2026 every line also carries
// `customer_description`, its words with each brand, model number and product line generalised to
// '<tier> <origin> brand' (_shared/quote_generalise.ts), and those terms join masked_terms. Every removed term is listed in masked_terms,
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
import { generaliseText } from '../_shared/quote_generalise.ts';
import { OPTION_HEAD, optionAmount, optionNumber, splitOptions } from '../_shared/line_specs/options.ts';
import type { VatTreatment } from '../_shared/line_specs/vat.ts';
import { AFTER_DISCOUNT, statedPrice } from '../_shared/stated_price.ts';
import type { QuoteTermKey } from '../_shared/reasoned_suppliers.ts';

export type QuoteLine = { description: string; qty: string; amount: number | null; option?: number; /** A "Specification" column, when the file has one. */ specification?: string;
  /** The line as the customer reads it before the reveal: brand -> "<tier> <origin> brand", model withheld (ledger 1589). */ customer_description?: string };
export type Proposal = {
  /** Why no amount was taken although figures were found: the total is held for the supplier to state (#1562). */
  review_reason?: 'total_without_currency' | 'conflicting_totals' | 'option_total_mismatch' | 'foreign_currency' | null;
  amount: number | null; currency: 'AED'; line_items: QuoteLine[]; lead_time: string; validity: string;
  payment_terms: string; warranty: string; scope: string; conditions: string; exclusions: string; notes: string;
  description_anonymized: string; masked_terms: string[]; confidence: 'low'; method: 'document';
  /** Internal record only; never shown to a customer. */
  subtotal: number | null; vat_amount: number | null; total_incl_vat: number | null; vat_treatment: VatTreatment; price_ex_vat: number | null; trn: string | null;
  /** Ruling 1207: the supplier's discount exactly as stated (null when none). */
  gross_amount: number | null; discount_amount: number | null; discount_label: string | null;
  options: { option_no: number; amount: number | null }[]; option_totals: Record<string, number>;
};

// A DECIMAL COMMA (audit, 10 Nov 2026, customer_support): "3.000,00" (thousands dots, a decimal comma, as many
// European and some Gulf price lists print it) had its commas stripped and was read as 3.00000, so a AED 3,000 line
// became AED 3. Unambiguous shapes only: dot-grouped thousands followed by a ,dd decimal, or two or more dot groups.
const DECIMAL_COMMA = /^-?\d{1,3}(?:\.\d{3})+,\d{1,2}$|^-?\d{1,3}(?:\.\d{3}){2,}$/;
const num = (v: Cell): number | null => {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  let s0 = String(v ?? '').replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/(AED|Dhs?\.?|د\.?\s?إ\.?|درهم)/gi, '').replace(/\s/g, '');
  if (DECIMAL_COMMA.test(s0)) s0 = s0.replace(/\./g, '').replace(',', '.');
  const s = s0.replace(/,/g, '');
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

// The currencies a quotation may be priced in other than AED (supplier_api quote_review/working.ts reads the same list for
// the review's rule 5), and AED in every way it is written.
const FOREIGN_CURRENCY = /\b(USD|US\$|EUR|GBP|SAR|QAR|OMR|KWD|BHD|INR|CNY|RMB)\b|[€£]/;
const AED_ANYWHERE = /\bAED\b|\bDhs?\b\.?|د\.?\s?إ|درهم|dirham/i;
// A discount row (ruling 1207): kept as the supplier's discount, never a priced line and never folded into the terms.
// `total_first`: the only total written came before the discount, so it is the price before the discount.
type Disc = { amount: number; label: string; net: number | null; total_first: boolean };
type Table = { lines: QuoteLine[]; totals: Record<string, number>; subtotal: number | null; vat: number | null; discount?: Disc | null };
const DISCOUNT = /discount|rebate|\u062E\u0635\u0645/i;
function tableQuote(rows: Cell[][], clean: (s: string) => string): Table | null {
  for (let r = 0; r < Math.min(rows.length, 30); r++) {
    const cols: Partial<Record<Col, number>> = {};
    (rows[r] || []).forEach((c, i) => { const k = roleOf(norm(c)); if (k && cols[k] === undefined) cols[k] = i; });
    if (cols.desc === undefined || (cols.amount === undefined && cols.rate === undefined)) continue;
    const lines: QuoteLine[] = [];
    const totals: Record<string, number> = {}; const grand: Record<string, boolean> = {};
    let subtotal: number | null = null, vat: number | null = null, cur: number | null = null, seq = 0;
    let discount: Disc | null = null;
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
      if (DISCOUNT.test(label) && !AFTER_DISCOUNT.test(label)) {
        const v = lastNum();
        if (v != null && cur == null) discount = { amount: Math.abs(v), label: clean(raw || label).replace(/[\s:–-]+$/, '').slice(0, 80), net: null, total_first: totals.all != null };
        continue;
      }
      if (discount && AFTER_DISCOUNT.test(label)) { const v = lastNum(); if (v != null && cur == null) { discount.net = v; discount.total_first = false; } }
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
    if (lines.some((l) => l.amount != null || l.qty)) return { lines, totals, subtotal, vat, discount };
  }
  return null;
}

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
  // An option heading in the text ("Option 2 - National Paints") numbers the priced lines under it, as the table
  // reader does; without it a two-option PDF came back as one quotation (QA walk, 19 Oct 2026).
  let cur: number | null = null, seq = 0;
  for (const raw of String(text || '').split('\n')) {
    const line = raw.replace(/\s+/g, ' ').trim();
    if (!line || TOTAL_ROW.test(line)) continue;
    const m = line.match(TEXT_LINE);
    if (!m && OPTION_HEAD.test(line)) { cur = optionNumber(line, seq + 1); seq = Math.max(seq, cur); out.push({ description: line.slice(0, 300), qty: '', amount: null, option: cur }); continue; }
    if (!m) continue;
    const desc = clean(m[2].replace(/[\s,;:–-]+$/, ''));
    if (!/\p{L}{3,}/u.test(desc)) continue;
    const qty = num(m[3]); const unit = m[4].replace(/\.$/, '');
    const a = num(m[5]); const b = m[6] != null ? num(m[6]) : null;
    // two figures: rate then amount; one figure: the amount (a rate alone would need a quantity to multiply)
    const amount = b != null ? b : (a != null && qty != null ? Math.round(a * qty * 100) / 100 : a);
    if (qty == null || amount == null) continue;
    out.push({ description: desc.slice(0, 300), qty: `${qty} ${unit}`.slice(0, 40), amount, ...(cur != null ? { option: cur } : {}) });
  }
  return out;
}
const LABEL_BEFORE = /(?:option|opt\.?|alternative|alt\.?|item|line|no\.?|#|البديل|الخيار|خيار|بديل|رقم)\s*$/i;
const OPTION_IN_LINE = /(?:option|alternative|alt\.?|choice|offer)\s*(?:no\.?|#)?\s*(?:\d{1,2}|[a-e]\b|one|two|three|four|five)|(?:البديل|الخيار|خيار|بديل)\s*(?:رقم\s*)?(?:[0-9٠-٩]{1,2}|الأول|الاول|الثاني|الثالث|الرابع)/i;
// THE FIGURE AFTER A TOTAL LABEL (QA walk, 19 Oct 2026; #1562 review). "Total Option 1: AED 11730" was read as AED 1.
// A total is the figure written WITH its currency; with none, the first figure that is not a label (option / item /
// line / no. / #), a reference ("QD-10234"), a year ("(2026)"), a quantity with its unit ("450 m2") or a rate ("5%").
// A total read without any currency is reported as such, so the caller holds it for review instead of guessing.
const CUR_BEFORE = new RegExp(CUR.replace(/\)\?$/, ')') + String.raw`\s*$`, 'i');
const CUR_AFTER = new RegExp(String.raw`^\s*` + CUR.replace(/\)\?$/, ')'), 'i');
const UNIT_AFTER = /^\s*(?:m2|m²|m3|sq\.?\s*m|sqm|sqft|lm|rm|m\b|nos?\b|pcs\b|pieces\b|units?\b|kg\b|l\b|ltrs?\b|tons?\b|coats?\b|days?\b|weeks?\b|months?\b|years?\b|%)/i;
const REF_BEFORE = /[A-Za-z]{1,8}[-/]\s*$/;
const YEAR = /^(?:19|20)\d{2}$/;
export function figureOf(rest: string): { value: number; currency: boolean } | null {
  const s = String(rest || '');
  let first: number | null = null;
  for (const m of s.matchAll(new RegExp(NUM, 'g'))) {
    const at = m.index ?? 0, before = s.slice(0, at), after = s.slice(at + m[0].length);
    if (CUR_BEFORE.test(before) || CUR_AFTER.test(after)) return { value: num(m[0])!, currency: true };
    if (first != null) continue;
    if (/[A-Za-z]$/.test(before) || LABEL_BEFORE.test(before) || REF_BEFORE.test(before) || UNIT_AFTER.test(after) || (YEAR.test(m[0]) && (/[(/]\s*$/.test(before) || /^\s*[)/]/.test(after)))) continue;
    first = num(m[0]);
  }
  return first == null ? null : { value: first, currency: false };
}
export const figureAfter = (rest: string): number | null => figureOf(rest)?.value ?? null;
/** Subtotal, VAT amount and total written in prose, even side by side on one line; a per-option total by its option. */
export type TextTotals = { subtotal: number | null; vat: number | null; total: number | null; options: Record<string, number>; ambiguous: string | null };
export function totalsFromText(text: string): TextTotals {
  const t = String(text || '');
  const pick = (re: RegExp) => { const m = t.match(re); return m ? num(m[1]) : null; };
  const subtotal = pick(new RegExp(String.raw`(?:sub\s*-?\s*total|total\s*(?:before|excl\w*\.?)\s*(?:of\s*)?vat|المجموع الفرعي|الإجمالي قبل الضريبة|الإجمالي غير شامل)\s*:?\s*${CUR}\s*${NUM}`, 'i'));
  // "Total incl. VAT 2,100" names the VAT the total INCLUDES; its figure is the total, never the VAT amount (audit,
  // 10 Nov 2026: it was read as VAT 2,100 on a 2,000 + 100 quotation, and the inclusive total became the compared price).
  const vat = pick(new RegExp(String.raw`(?<!incl\w*\.?\s*(?:of\s*)?|inclusive\s*(?:of\s*)?|including\s*|with\s*|شامل(?:ة)?\s*)\b(?:vat|tax|ضريبة(?:\s*القيمة\s*المضافة)?)\s*(?:@|at|بنسبة)?\s*(?:\d+(?:\.\d+)?\s*%)?\s*:?\s*${CUR}\s*${NUM}`, 'i'));
  let total: number | null = null, noCurrency = false;
  const options: Record<string, number> = {};
  const seen: { v: number; decisive: boolean }[] = [];
  for (const m of t.matchAll(/(grand\s*total|net\s*total|total\s*amount|total\s*\(?incl[^\n:]*|\btotal\b|الإجمالي|المجموع)([^\n]*)/gi)) {
    const head = m[1] + m[2].slice(0, 40);
    if (VAT.test(head) && !/incl/i.test(head)) continue;
    if (SUBTOTAL.test(head)) continue;
    const f = figureOf(m[2]);
    if (f == null) continue;
    const v = f.value;
    if (!f.currency) noCurrency = true;
    // "Total Option 2 - National Paints: AED 8,940" is that option's total, never the quotation's.
    const opt = m[2].match(OPTION_IN_LINE);
    if (opt) { options[String(optionNumber(opt[0].trim(), Object.keys(options).length + 1))] = v; continue; }
    seen.push({ v, decisive: /grand|net|incl/i.test(m[1]) });
    if (total == null || /grand|net|incl/i.test(m[1])) total = v;
  }
  // HELD, NEVER GUESSED (#1562 review): a total with no currency, or totals that disagree with nothing to decide
  // between them (not exactly one grand / net / incl. total), is not taken as the price.
  const values = new Set(seen.map((x) => x.v)), decisive = new Set(seen.filter((x) => x.decisive).map((x) => x.v));
  // A conflict is recorded before a missing currency: corroboration by the lines may excuse a missing currency, never a conflict.
  const ambiguous = values.size > 1 && decisive.size !== 1 ? 'conflicting_totals' : (noCurrency ? 'total_without_currency' : null);
  return { subtotal, vat, total, options, ambiguous };
}

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

/** The file's text as quoteFromExtracted reads it (tables' rows first, then the reader's text), for the
 *  reasoning that reads the terms. */
export function quoteText(ex: Extracted): string {
  const out: string[] = [];
  const visit = (e: Extracted) => { for (const tb of e.tables) out.push(tb.map(rowText).join('\n')); if (e.text) out.push(e.text); for (const c of e.children) visit(c.doc); };
  visit(ex);
  return out.join('\n');
}

export function quoteFromExtracted(ex: Extracted, terms: string[] = [], read: Partial<Record<QuoteTermKey, string>> = {}): Proposal {
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
  // 10 Nov 2026 (founder ledger 1589): what the CUSTOMER will read of a line. This path removed the supplier's own name
  // and contact shapes only, so "Grohe Eurosmart 33265003 basin mixer" reached the customer as written. The line itself
  // stays as the supplier wrote it: it is the supplier's own working copy, and the hold gate needs the brand and
  // product it names (measured: generalising it here made the quotation chat ask a painter for the brand his file
  // already stated, 8 tests in supplier_api/quote_review.test.ts). The customer's words are kept beside it, and
  // every pre-reveal surface generalises again from the stored line (_shared/quote_generalise.ts).
  const forCustomer = (s: string) => { const g = generaliseText(s, { supplierNames: t }); for (const r of g.replaced) masked.add(r.term); return g.text; };
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
  // A total written in the text ("Grand Total: AED 12,450.00") wins over a sum of lines; the subtotal
  // and the VAT amount written in the text are the VAT basis when no table carried them.
  const tt = totalsFromText(text);
  const textTotal = tt.total;
  // No table at all (a PDF's text layer, a plain email): the priced lines are read from the text.
  let b = best as Table | null;
  if (!b) { const tl = linesFromText(text, clean); if (tl.length) b = { lines: tl, totals: { ...tt.options }, subtotal: null, vat: null }; }
  const plain = b ? b.lines.filter((l) => l.amount != null || l.qty) : [];
  const sum = plain.reduce((s, l) => s + (l.amount || 0), 0);
  const gross = b?.totals.all ?? textTotal ?? (sum > 0 ? Math.round(sum * 100) / 100 : null);
  const dsc = b?.discount ?? null;
  // Ruling 1208: the price after the stated discount, excluding VAT, is the price compared and the fee base.
  const vat = statedPrice({ amount: gross, subtotal: b?.subtotal ?? tt.subtotal, vat_amount: b?.vat ?? tt.vat, text,
    discount_amount: dsc?.amount ?? null, discount_label: dsc?.label ?? null, net_amount: dsc?.net ?? null, amount_is_gross: !!dsc?.total_first });
  const option_totals: Record<string, number> = {};
  for (const [k, v] of Object.entries(b?.totals ?? {})) if (k !== 'all') option_totals[k] = v;
  const split = b && b.lines.some((l) => l.option != null) ? splitOptions(b.lines, option_totals) : [];
  const options = split.length > 1 ? split.map((o) => ({ option_no: o.option_no, amount: optionAmount(o) })) : [];
  const lineItems = (b ? b.lines.slice(0, 200) : []).map((l) => { const c = forCustomer(l.description); return c !== l.description ? { ...l, customer_description: c } : l; });
  const p: Proposal = {
    amount: options.length ? options[0].amount : (vat.price_ex_vat ?? gross), currency: 'AED', line_items: lineItems,
    lead_time: '', validity: '', payment_terms: '', warranty: '', scope: '', conditions: '', exclusions: '', description_anonymized: '', masked_terms: [], confidence: 'low', method: 'document',
    notes: `Read from the ${ex.kind.toUpperCase()} file with no model${b ? `: ${plain.length} priced line(s)` : ''}${options.length ? `, ${options.length} options (each is sent as its own quotation)` : ''}. Please check every figure before sending.`,
    subtotal: b?.subtotal ?? null, vat_amount: vat.vat_amount, total_incl_vat: vat.vat_amount && vat.total_as_stated ? vat.total_as_stated : null, vat_treatment: vat.treatment,
    price_ex_vat: options.length ? null : vat.price_ex_vat, trn: vat.trn, options, option_totals,
    gross_amount: options.length ? null : vat.gross_amount, discount_amount: options.length ? null : vat.discount_amount, discount_label: options.length ? null : vat.discount_label,
  };
  // HELD FOR REVIEW, NEVER GUESSED (#1562 review). An option whose stated total disagrees with the sum of its own
  // lines, or a text total read with no currency or among totals that disagree, is not pre-filled as the price.
  const sumOf = (k: string) => (b?.lines ?? []).filter((l) => String(l.option) === k).reduce((x, l) => x + (l.amount || 0), 0);
  const mismatch = options.length > 0 && Object.entries(option_totals).some(([k, v]) => { const t = sumOf(k); return t > 0 && Math.abs(t - v) > 1; });
  // A total written without a currency is still taken when the priced lines add up to it: the lines corroborate
  // it ("Total 15000" under lines of 11,400 and 3,600). Uncorroborated, it is held.
  // The same file's table text and plain text can both carry a line, so the lines are counted once each.
  const uniqueSum = [...new Map(plain.map((l) => [`${l.description}|${l.qty}|${l.amount}`, l.amount || 0])).values()].reduce((x, y) => x + y, 0);
  const corroborated = uniqueSum > 0 && textTotal != null && Math.abs(uniqueSum - textTotal) <= 1;
  const textDoubt = tt.ambiguous === 'total_without_currency' && corroborated ? null : tt.ambiguous;
  // PRICED IN ANOTHER CURRENCY (audit, 10 Nov 2026): a sheet headed "Amount (USD)" was read as AED 3,000. The file
  // states a currency other than AED and never AED: its figures are not AED and are not converted on a guess.
  const foreign = FOREIGN_CURRENCY.test(text) && !AED_ANYWHERE.test(text);
  const review = foreign ? 'foreign_currency' : mismatch ? 'option_total_mismatch' : (!best && textTotal != null && gross === textTotal ? textDoubt : null);
  if (review) {
    p.review_reason = review as Proposal['review_reason'];
    p.amount = null; p.price_ex_vat = null; p.gross_amount = null; p.options = [];
    p.notes += ' The total could not be read with certainty (' + review.replace(/_/g, ' ') + '): please type the total yourself.';
  }
  // THE TERMS (lead time, validity, payment, warranty, exclusions, installation / conditions) are what the
  // file MEANS, so they are not read here by label patterns (founder_instruction 886-903): quote_extract
  // reasons them from quoteText() (_shared/reasoned_suppliers.ts quoteTerms) and passes them in as `read`.
  // They are masked like every other field. Under the model hold `read` is empty and the supplier types them.
  for (const [k, v] of Object.entries(read)) {
    const s = clean(String(v ?? '').trim()).replace(/[.;,\s]+$/, '').slice(0, k === 'conditions' ? 600 : 200);
    if (s) (p as Record<string, unknown>)[k] = s;
  }
  if (vat.trn) masked.add('TRN');
  p.masked_terms = [...masked];
  return p;
}
