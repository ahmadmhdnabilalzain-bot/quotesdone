// word_tables — rows and columns rebuilt from POSITIONED words, with no model (10 Nov 2026, sales_engineer;
// founder 10 Nov: a competitor's quotation a customer uploads is an inquiry, rebuilt in our template; a drawing's
// door / window / finish schedule is a table a real engineer reads).
//
// WHY. A PDF's text layer and a DXF's TEXT entities are words with positions, not tables. doc_read/pdf.ts handed
// boqFromExtracted the page as LINES, so a priced quotation row "1 Porcelain floor tile 600x600 m2 120 85.00
// 10,200.00" was read by the free-text reader, which took "600 m2" as the quantity and kept the price figures in the
// description. As a TABLE the same row goes through boqFromRows, which knows its header and never reads a rate,
// price or amount column. The drawing take-off (drawing_boq/architectural.ts) reads door, window and room-finish
// schedules drawn as CAD text through the same function.
//
// HOW. Words are grouped into rows by their vertical centre; a row's words are joined into CELLS where the gap
// between them is under one text height. The first row with three or more cells, two of them header words
// (HEADER_WORD: description, qty, unit, rate, amount, mark, width, room, floor ...), is a HEADER; its cells fix the
// columns. Each later cell lands in a column: text by its LEFT edge (a description runs to the right of its short
// heading), a number by the column it overlaps most (figures are right-aligned under "Qty" and "Amount"). A row
// holding only text in the first text column, close under a row that has a quantity, is that row's wrapped
// description. The table ends at a terms heading ("Payment terms:", "Validity:", "Bank details") or a gap of more
// than six rows. Nothing is summed, nothing is dropped here: the caller decides what a column means.
//
// WHAT IT NEVER DOES. Guess a column without a header, read a table with fewer than three columns, or merge two
// tables. A page without a header row gives no table.
import type { Cell } from './types.ts';

/** A word or a run of words with its box. `y` grows DOWN the page (a PDF run); a CAD caller flips its y first. */
export type PlacedWord = { s: string; x: number; y: number; w: number; h: number };

/** Header words of BOQs, quotations and drawing schedules (EN, AR, DE). Matched against a whole cell. */
export const HEADER_WORD = new RegExp(String.raw`^(?:s\.?\s*no\.?|sr\.?\s*no\.?|sl\.?\s*no\.?|no\.?|item(?:\s*no\.?)?|ref\.?|pos\.?|code|description|particulars|scope|item\s*description|` +
  String.raw`specifications?|spec\.?|make|brand|model|qty\.?|quantity|quantities|unit|uom|u\.o\.m\.?|rate|unit\s*(?:rate|price)|price|amount|total(?:\s*price|\s*amount)?|value|remarks?|` +
  String.raw`(?:aed|dhs|usd)|mark|tag|type|door\s*(?:no|mark|type)|window\s*(?:no|mark|type)|width|height|size|w\s*x\s*h|dimensions?|material|finish|frame|leaf|` +
  String.raw`ironmongery|hardware|fire\s*rating|room(?:\s*(?:name|no\.?))?|space|area|floor(?:\s*finish)?|walls?(?:\s*finish)?|ceiling(?:\s*(?:finish|height))?|skirting|` +
  String.raw`menge|einheit|beschreibung|kurztext|ep|gp|البند|الوصف|البيان|الكمية|الوحدة|السعر|المبلغ|الإجمالي|الملاحظات|المواصفات|النوع|العرض|الارتفاع|الغرفة|الأرضية|الجدران|السقف)\s*(?:\(.*\))?\s*[:.]?$`, 'i');
/** Where a quotation's table stops and its commercial terms begin. */
const TERMS = /^(?:terms(?:\s*(?:&|and)\s*conditions)?|conditions|payment(?:\s*terms)?|validity|bank(?:\s*details)?|notes?|exclusions|warranty|delivery(?:\s*(?:period|time|terms))?|lead\s*time|الشروط|شروط\s*الدفع|الدفع|الصلاحية|ملاحظات)\s*[:：]/i;
const NUMERIC = /^[-+(]?\s*(?:AED|Dhs?\.?|USD|\$)?\s*[\d٠-٩][\d٠-٩,.\s]*\)?\s*%?$/i;

type Row = { y: number; h: number; cells: PlacedWord[] };

/** Words -> visual rows (top to bottom), each row's words joined into cells (left to right). */
export function rowsOfWords(words: PlacedWord[]): Row[] {
  const ws = words.filter((w) => w.s && w.s.trim() && Number.isFinite(w.x) && Number.isFinite(w.y) && w.h > 0)
    .map((w) => ({ ...w, s: w.s.replace(/\s+/g, ' ').trim() })).sort((a, b) => (a.y + a.h / 2) - (b.y + b.h / 2));
  const rows: Row[] = [];
  for (const w of ws) {
    const c = w.y + w.h / 2;
    const r = rows.length ? rows[rows.length - 1] : null;
    if (r && Math.abs(r.y - c) <= Math.max(r.h, w.h) * 0.5) { r.cells.push(w); r.h = Math.max(r.h, w.h); }
    else rows.push({ y: c, h: w.h, cells: [w] });
  }
  for (const r of rows) {
    const sorted = r.cells.sort((a, b) => a.x - b.x);
    const merged: PlacedWord[] = [];
    for (const w of sorted) {
      const last = merged[merged.length - 1];
      // One phrase written as several runs joins; two headings never do ("S.No" beside "Description"), and a figure
      // joins the text before it only when they nearly touch (a quantity column right of a Brand column does not).
      const gap = last ? w.x - (last.x + last.w) : Infinity, hh = last ? Math.min(last.h, w.h) : 0;
      const bothHeads = !!last && HEADER_WORD.test(last.s) && HEADER_WORD.test(w.s);
      if (last && !bothHeads && gap < hh * (NUMERIC.test(w.s) || NUMERIC.test(last.s) ? 0.3 : 0.6)) {
        merged[merged.length - 1] = { s: `${last.s} ${w.s}`, x: last.x, y: Math.min(last.y, w.y), w: Math.max(last.x + last.w, w.x + w.w) - last.x, h: Math.max(last.h, w.h) };
      } else merged.push({ ...w });
    }
    r.cells = merged;
  }
  return rows;
}

const isHeader = (r: Row) => r.cells.length >= 3 && r.cells.filter((c) => HEADER_WORD.test(c.s)).length >= 2;

/** Every table on a page of positioned words: [header, ...rows] as cells in header-column order. */
export function tablesFromWords(words: PlacedWord[], maxRows = 600, boxes?: { x0: number; y0: number; x1: number; y1: number }[]): Cell[][][] {
  const rows = rowsOfWords(words);
  const tables: Cell[][][] = [];
  for (let i = 0; i < rows.length; i++) {
    if (!isHeader(rows[i])) continue;
    // The header is its heading words and what lies between them (a plan's words on the same row are not columns).
    const hc = rows[i].cells, hi0 = hc.findIndex((c) => HEADER_WORD.test(c.s)), hi1 = hc.length - 1 - [...hc].reverse().findIndex((c) => HEADER_WORD.test(c.s));
    const head = hc.slice(hi0, hi1 + 1);
    const n = head.length;
    if (n < 3) continue;
    // Column bands: between consecutive headings, half-way across the gap.
    const cut = head.slice(0, -1).map((c, k) => (c.x + c.w + head[k + 1].x) / 2);
    const colOfX = (x: number) => { let k = 0; while (k < cut.length && x >= cut[k]) k++; return k; };
    const overlapCol = (c: PlacedWord) => {
      let best = colOfX(c.x + c.w / 2), most = -1;
      head.forEach((hd, k) => { const lo = k ? cut[k - 1] : -Infinity, hi = k < cut.length ? cut[k] : Infinity; const o = Math.min(c.x + c.w, hi) - Math.max(c.x, lo); if (o > most) { most = o; best = k; } });
      return best;
    };
    // A table drawn BESIDE a plan shares its rows with the plan's own words: only words over the table's width count.
    const hl = head[n - 1], left = head[0].x - 3 * head[0].h, right = hl.x + hl.w + Math.max(3 * hl.h, 0.5 * (hl.x + hl.w - head[0].x));
    const firstText = head.findIndex((c) => /desc|particular|scope|spec|item\s*desc|room|space|البيان|الوصف/i.test(c.s));
    const textCol = firstText >= 0 ? firstText : 1;
    const out: Cell[][] = [head.map((c) => c.s)];
    let lastY = rows[i].y, lastH = rows[i].h, prevHasNumber = false;
    for (let j = i + 1; j < rows.length && out.length <= maxRows; j++) {
      const r = { ...rows[j], cells: rows[j].cells.filter((c) => c.x + c.w >= left && c.x <= right) };
      if (!r.cells.length) continue;
      if (r.y - lastY > Math.max(lastH, r.h) * 6) break;                       // a gap of six rows: the table is over
      if (isHeader(r)) break;                                                  // the next table
      if (r.cells.length && TERMS.test(r.cells[0].s)) break;                   // the commercial terms
      const cells: string[] = Array(n).fill('');
      for (const c of r.cells) {
        const k = NUMERIC.test(c.s) ? overlapCol(c) : colOfX(c.x + Math.min(c.w, c.h) / 2);
        cells[k] = cells[k] ? `${cells[k]} ${c.s}` : c.s;
      }
      const filled = cells.map((v, k) => (v ? k : -1)).filter((k) => k >= 0);
      // A wrapped description: text only in the description column, within two rows of a priced/quantified row.
      if (filled.length === 1 && filled[0] === textCol && prevHasNumber && r.y - lastY <= Math.max(lastH, r.h) * 2.2 && out.length > 1) {
        const prev = out[out.length - 1];
        prev[textCol] = `${prev[textCol] || ''} ${cells[textCol]}`.trim();
        lastY = r.y; lastH = r.h; continue;
      }
      out.push(cells);
      prevHasNumber = cells.some((v, k) => k !== textCol && NUMERIC.test(v));
      lastY = r.y; lastH = r.h;
    }
    if (out.length > 1) {
      tables.push(out);
      // Where the table sits (header top to last row bottom, across its columns), for a caller that must not read
      // the schedule's own marks as tags on the plan.
      boxes?.push({ x0: left, y0: rows[i].y - rows[i].h, x1: right, y1: lastY + lastH });
    }
    // Skip past the rows this table consumed so a header is not re-read.
    while (i + 1 < rows.length && rows[i + 1].y <= lastY) i++;
  }
  return tables;
}
