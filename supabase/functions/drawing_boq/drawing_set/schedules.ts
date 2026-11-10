import { clip, parseTag } from './vocabulary.ts';
import type { ScheduleTable } from './types.ts';

/** An OCR'd tag cell as the plan writes it. Measured 21 Sep 2026 on the mechanical schedules read cell
 *  by cell: "RTU 1" (the hyphen lost), "Cc" (a letter read twice), "RTU-3 (DOAS)" (a service note). */
export function normTag(cell: string): string {
  let t = String(cell || '').toUpperCase().replace(/\s*\([^)]*\)\s*$/, '').trim();
  t = t.replace(/^([A-Z]{1,4}(?:\/[A-Z]{1,3})?)\s+(\d{1,3}[A-Z]?)$/, '$1-$2');
  if (/^([A-Z])\1$/.test(t)) t = t[0];
  return t;
}

/** OCR schedule tables -> tag -> "make model, key data". The tag column is the one whose cells parse as tags. */
export function scheduleRows(tables: ScheduleTable[]): Map<string, string> {
  const out = new Map<string, string>();
  for (const t of tables) {
    const rows = (t.rows || []).map((r) => (r || []).map((c) => String(c ?? '').replace(/\s+/g, ' ').trim()));
    if (rows.length < 2) continue;
    const cols = Math.max(...rows.map((r) => r.length));
    let best = -1, bestN = 0;
    for (let c = 0; c < cols; c++) { const n = rows.filter((r) => r[c] && (parseTag(normTag(r[c])) || /^[A-G]$/.test(normTag(r[c])))).length; if (n > bestN) { best = c; bestN = n; } }
    if (best < 0 || bestN < 1) continue;
    const header = rows.find((r) => r.some((c) => /MANUF|MODEL|MAKE|TYPE|DESCRIPTION/i.test(c))) || [];
    const want = header.map((h, i) => (/MANUF|MAKE|MODEL|DESCRIPTION|SERVICE|CFM|MBH|TONS?|TYPE|SIZE/i.test(h) ? i : -1)).filter((i) => i >= 0 && i !== best);
    for (const r of rows) {
      const tag = normTag(r[best] || '');
      if (!tag || !(parseTag(tag) || /^[A-G]$/.test(tag))) continue;
      // Cells under 3 characters are OCR crumbs of a size column ("2", "or", "gr" measured on the fixture schedule).
      const cells = (want.length ? want.map((i) => r[i]) : r.filter((_, i) => i !== best)).filter((c) => c && c.length >= 3 && c.length <= 60);
      // The make/model came from OCR, so the words say so wherever the line is shown (the quantity is
      // still the tag count read from the plan): never presented as read off the drawing.
      const spec = cells.length ? clip(cells.slice(0, 6).join(', '), 150) + ' (schedule read by OCR — to confirm)' : '';
      // A row that says only numbers (an air-balance table: "EF-9 | 400") names no product.
      if (spec && /[A-Z]{2,}/i.test(spec) && !out.has(tag)) out.set(tag, spec);
    }
  }
  return out;
}
