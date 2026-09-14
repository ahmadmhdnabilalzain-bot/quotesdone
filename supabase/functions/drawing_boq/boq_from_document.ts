// boq_from_document — any document doc_read can open, turned into the customer BOQ shape drawing_boq
// has always returned ({boq, assumptions, missing_info, confidence, ...}).
//
// WHY (14 Sep 2026). Founder: "the sales agent need to be extremely capable of reading all types of
// document." doc_read says what a file contains; this decides what of it becomes a BOQ line a
// supplier sees, and it is the single place the CUSTOMER rules are applied:
//   * a table is read through boqFromRows, which finds the header (NRM / FIDIC / MasterFormat /
//     DIN 276 / Arabic) and NEVER reads a rate, price or amount column;
//   * quantities a format states or measures (DXF, IFC, GAEB, a scaled PDF) are kept as they are;
//   * free text is read line by line through boqFromLines, AFTER every currency amount and "@ rate"
//     is stripped, so a price written in a sentence does not reach a competing supplier either;
//   * every string passes scrubIdentity (emails, URLs, UAE phones, company names).
// Text lines of a document are only read when none of its tables produced a line: a Word BOQ carries
// the same rows as table cells and as text, and reading both would count every item twice.
import type { Extracted } from '../_shared/doc_read/types.ts';
import { boqFromLines, scrubIdentity, type BoqItem } from './boq_from_text.ts';
import { boqFromRows, MAX_ROWS } from './boq_from_sheet.ts';

const CUR = '(?:AED|Dhs?\\.?|د\\.?\\s?إ\\.?|درهم|USD|US\\$|\\$|€|£|EUR|GBP|SAR|ريال)';
const PRICE = new RegExp(`${CUR}\\s*[\\d.,]+|[\\d.,]+\\s*${CUR}|(?:@|\\brate\\b[:\\s]*|\\bunit price\\b[:\\s]*|\\bprice\\b[:\\s]*|\\bamount\\b[:\\s]*|السعر[:\\s]*|المبلغ[:\\s]*)\\s*[\\d.,]+`, 'gi');
/** Remove every currency amount and "@ 85" / "rate 85" figure from a line of customer text. */
export const stripPrices = (s: string) => s.replace(PRICE, ' ').replace(/\s{2,}/g, ' ').trim();

export function boqFromExtracted(ex: Extracted, hint = '', ocrText = '') {
  const boq: BoqItem[] = [];
  const missing: string[] = [];
  const assumptions = new Set<string>(['Every line is exactly as written in the customer’s document; nothing was re-measured, and no price was read.']);
  const kinds: string[] = [];
  const layouts = new Set<string>();

  const fromText = (text: string, where: string, confidence?: 'low') => {
    const lines = text.split('\n').map(stripPrices).filter((t) => t.length > 2).map((t) => ({ page: 1, text: t }));
    for (const b of boqFromLines(lines)) {
      boq.push({ ...b, section: where, basis: b.basis.replace(/^printed on page \d+/, `written in ${where}`).replace(/^schedule row on page \d+/, `row in ${where}`), ...(confidence ? { confidence } : {}) });
    }
  };

  const visit = (e: Extracted, where: string) => {
    kinds.push(e.kind);
    let tableItems = 0;
    e.tables.forEach((t, i) => {
      const r = boqFromRows(t, `${where}, table ${i + 1}`);
      if (!r.boq.length) return;
      tableItems += r.boq.length;
      boq.push(...r.boq);
      r.assumptions.forEach((a) => assumptions.add(a));
      if ((r as { layout?: string }).layout) layouts.add(String((r as { layout?: string }).layout));
    });
    for (const q of e.quantities) {
      const d = scrubIdentity(q.description).slice(0, 200);
      if (!d) continue;
      boq.push({ section: scrubIdentity(q.section).slice(0, 80) || where, item: d.slice(0, 120), description: d, qty: q.qty, unit: q.unit, basis: scrubIdentity(q.basis).slice(0, 200), confidence: q.confidence });
    }
    if (!tableItems && e.text) fromText(e.text, where);
    for (const n of e.notes) missing.push(scrubIdentity(n));
    for (const c of e.children) visit(c.doc, `${where} › ${scrubIdentity(c.name).slice(0, 60) || 'attachment'}`);
  };
  visit(ex, ex.kind.toUpperCase());

  if (ocrText) {
    fromText(ocrText, 'OCR of the photo', 'low');
    assumptions.add('The photo was read by OCR in the customer’s browser; OCR can misread digits, so every quantity is marked low confidence.');
  }

  // One line per (description, qty, unit): a zip holding the same sheet twice should not double it.
  const seen = new Set<string>();
  const uniq = boq.filter((b) => { const k = `${b.description.toLowerCase()}|${b.qty}|${b.unit}`; if (seen.has(k)) return false; seen.add(k); return true; });
  const lines = uniq.slice(0, MAX_ROWS);
  if (uniq.length > MAX_ROWS) missing.push(`Only the first ${MAX_ROWS} lines were kept.`);
  if (!lines.length) missing.push('No line stating a quantity was found in the document.');
  const withQty = lines.filter((b) => b.qty != null).length;
  return {
    drawing_type: '', category: '', summary: scrubIdentity(hint).slice(0, 200), scale_detected: '',
    total_area_sqm: null as number | null, area_tags_sqm: [] as number[],
    boq: lines, keywords: [] as string[], assumptions: [...assumptions], missing_info: [...new Set(missing)],
    confidence: (lines.length && withQty === lines.length && lines.every((b) => b.confidence === 'medium') ? 'medium' : 'low') as 'low' | 'medium',
    method: 'document', kinds, layout: [...layouts].join(',') || null, rows_read: lines.length,
  };
}
