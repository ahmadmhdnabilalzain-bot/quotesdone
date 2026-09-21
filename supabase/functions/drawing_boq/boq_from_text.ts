// boq_from_text — a DRAFT bill of quantities read off a PDF's TEXT LAYER, with no model (14 Sep 2026).
//
// WHY. drawing_boq read quantities only through a vision model, and every route is held, so a
// customer who attached a drawing got ok:false and the drawing never informed the brief. Drawings
// exported from CAD or a PDF writer carry their schedules, area tags and notes as real text
// ("LIVING ROOM 32.5 m2", "D1 SINGLE DOOR 900x2100 6 NOS"). That text is data and can be read.
//
// WHAT IT READS. Lines of text rebuilt from positioned runs (same page, same baseline). A line that
// states a number with a recognised unit becomes a line item at confidence 'medium' — the quantity is
// printed on the drawing, only our reading of what it refers to is uncertain. A schedule row that is a
// tag (D1, W03, FCU-2) followed by a trailing integer becomes an item counted in 'nos' at confidence
// 'low' — the trailing number might be a count, a size or a reference, and we cannot tell which.
//
// WHAT IT NEVER DOES. It does not measure geometry, apply a scale, or add anything up across items.
// A drawing with no text layer (a scan, or CAD exported as vectors) yields an EMPTY boq with the
// reason in missing_info — never a guess. Identity (emails, URLs, phones, company names) is scrubbed
// from every item because this output is shown to competing suppliers.
import type { PdfPage } from '../_shared/pdf_text_positions.ts';
import { LICENCE_NO, TRN_BARE, TRN_LABELLED } from '../_shared/identity_numbers.ts';

export type BoqItem = { section: string; item: string; description: string; qty: number | null; unit: string; basis: string; confidence: 'low' | 'medium'; specification?: string };

const UNIT: [string, RegExp][] = [
  ['sqm', /^(?:sqm|sq\.?\s?m|m2|m²)$/i], ['sqft', /^(?:sqft|sq\.?\s?ft|ft2)$/i], ['m3', /^(?:m3|m³|cum)$/i],
  ['lm', /^(?:lm|rm|r\.m\.?|l\.m\.?)$/i], ['m', /^(?:m|mtr|mtrs)$/i], ['nos', /^(?:nos?\.?|pcs|each|ea|units?|sets?)$/i],
  ['kg', /^kg$/i], ['ton', /^(?:tons?|t)$/i], ['lot', /^(?:lot|ls|l\.s\.)$/i], ['kw', /^kw$/i], ['tr', /^tr$/i],
];
const unitOf = (s: string) => { for (const [u, re] of UNIT) if (re.test(s)) return u; return null; };

export function scrubIdentity(s: string): string {
  return String(s || '')
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '')
    .replace(/\b(?:https?:\/\/|www\.)\S+/gi, '')
    .replace(/(?:\+?971|00971|\b0)[\s-]?\d{1,2}[\s-]?\d{3}[\s-]?\d{4}\b/g, '')
    .replace(/\b[\w&.' -]{2,40}\s(?:L\.?L\.?C|FZ-?LLC|FZE|FZCO|Est\.?|Establishment|Consultants?|Contracting|Architects?|Engineering\s+Consultants?)\b\.?/gi, '')
    // TRNs and licence / registration numbers identify a company as surely as its phone (14 Sep 2026).
    .replace(TRN_LABELLED, '').replace(TRN_BARE, '').replace(LICENCE_NO, '')
    .replace(/\s{2,}/g, ' ').trim();
}

/** Rebuild visual lines: runs on the same page whose baselines are within half a text height. */
export function linesOf(pages: PdfPage[]): { page: number; text: string }[] {
  const out: { page: number; text: string }[] = [];
  pages.forEach((p, pi) => {
    const runs = [...p.runs].sort((a, b) => (a.y + a.h) - (b.y + b.h) || a.x - b.x);
    let cur: typeof runs = [];
    const flush = () => { if (cur.length) out.push({ page: pi + 1, text: cur.sort((a, b) => a.x - b.x).map((r) => r.text).join(' ').replace(/\s+/g, ' ').trim() }); cur = []; };
    for (const r of runs) {
      const base = r.y + r.h;
      if (cur.length && Math.abs((cur[0].y + cur[0].h) - base) > Math.max(r.h, cur[0].h) * 0.5) flush();
      cur.push(r);
    }
    flush();
  });
  return out.filter((l) => l.text);
}

export function boqFromLines(lines: { page: number; text: string }[]): BoqItem[] {
  const items: BoqItem[] = [];
  const seen = new Set<string>();
  for (const { page, text } of lines) {
    if (text.length > 160) continue;                                        // a note paragraph, not a quantity
    const clean = scrubIdentity(text);
    if (!clean) continue;
    // 1) "<description> <qty> <unit>" or "<qty> <unit> <description>"
    const m = clean.match(/(\d+(?:[.,]\d+)?)\s*(sq\.?\s?m|sqm|m2|m²|sq\.?\s?ft|sqft|ft2|m3|m³|cum|lm|rm|r\.m\.?|l\.m\.?|mtrs?|m|nos?\.?|pcs|each|ea|units?|sets?|kg|tons?|lot|ls|kw|tr)(?![a-z0-9])/i);
    if (m) {
      const unit = unitOf(m[2].replace(/\s/g, ''));
      const qty = Number(m[1].replace(',', '.'));
      const desc = (clean.slice(0, m.index) + ' ' + clean.slice(m.index! + m[0].length)).replace(/[:=\-–|]+\s*$/, '').replace(/\s+/g, ' ').trim();
      // A bare dimension ("3000 m" inside "3000 mm"-less notes) or a desc-less number teaches nothing.
      if (unit && Number.isFinite(qty) && qty > 0 && desc.length >= 3 && /[A-Za-z؀-ۿ]/.test(desc)) {
        const key = `${desc.toLowerCase()}|${qty}|${unit}`;
        if (!seen.has(key)) { seen.add(key); items.push({ section: 'Read from drawing text', item: desc.slice(0, 120), description: desc.slice(0, 120), qty, unit, basis: `printed on page ${page}: "${clean.slice(0, 80)}"`, confidence: 'medium' }); }
        continue;
      }
    }
    // 2) schedule row: TAG ... <integer>
    const s = clean.match(/^([A-Z]{1,4}-?\d{1,3}[A-Z]?)\s+(.{3,100}?)\s+(\d{1,4})$/);
    if (s && /[A-Za-z]{3,}/.test(s[2])) {
      const key = `${s[1]}|${s[2].toLowerCase()}`;
      if (!seen.has(key)) { seen.add(key); items.push({ section: 'Schedule', item: `${s[1]} ${s[2]}`.slice(0, 120), description: `${s[1]} ${s[2]}`.slice(0, 120), qty: Number(s[3]), unit: 'nos', basis: `schedule row on page ${page}; the trailing number was read as a count and may be a size or reference`, confidence: 'low' }); }
    }
  }
  return items.slice(0, 120);
}

export function boqFromPages(pages: PdfPage[], hint = '') {
  const lines = linesOf(pages);
  const boq = boqFromLines(lines);
  const sqm = boq.filter((b) => b.unit === 'sqm').map((b) => b.qty || 0);
  const scale = lines.map((l) => l.text.match(/\bscale\s*[:=]?\s*(1\s*[:\/]\s*\d{1,4})/i)).find(Boolean);
  const missing: string[] = ['Read from the PDF text layer only: no drawing geometry was measured and no scale was applied.'];
  if (!pages.length) missing.push('The file is not a PDF we could open (encrypted, damaged or not a PDF).');
  else if (!lines.length) missing.push('The PDF has no readable text layer (a scan, or CAD exported as lines), so no quantities could be read without the drawing reader.');
  else if (!boq.length) missing.push('Text was found, but no line stated a quantity with a unit or looked like a schedule row.');
  missing.push('Items are exactly as printed; totals, wastage and anything drawn but not written are not included.');
  return {
    drawing_type: '', category: '', summary: scrubIdentity(hint).slice(0, 200),
    scale_detected: scale ? scale[1].replace(/\s/g, '') : '',
    // Not summed from area tags: two tags can describe the same room on two sheets.
    total_area_sqm: null as number | null,
    area_tags_sqm: sqm,
    boq, keywords: [] as string[], assumptions: [] as string[], missing_info: missing,
    confidence: 'low' as const, method: 'pdf_text_layer', pages_read: pages.length, text_lines: lines.length,
  };
}
