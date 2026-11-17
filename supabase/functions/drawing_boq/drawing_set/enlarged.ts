import type { PdfPage } from '../../_shared/pdf_text_positions.ts';
import type { Box } from '../../_shared/anonymise.ts';
import { parseScale, type Measured } from '../drawing_lengths.ts';
import { clip, inBox } from './vocabulary.ts';
import type { Sheet } from './types.ts';

// ── AN ENLARGED PLAN IS NOT MEASURED TWICE (17 Nov 2026, sales_engineer; duct-fix review) ─────────────────────────────────
// The length take-off summed every new-work plan by size, so an ENLARGED plan of an area the main plan already shows was
// counted again: the reviewer's built set (main plan + "ENLARGED MECHANICAL PLAN" + a second-floor plan, one 15.2 m 26x18
// run each) gave 45.7 m for 30.5 m drawn, and a supplier prices the quantity. What tells an estimator a sheet is an
// enlargement, and what this reads, per sheet (READ, from the sets in a_drawing_area_is_measured_once.test.ts):
//   * its title - the drawing index's, its own largest view title, a title-strip line with PLAN in it - saying ENLARGED,
//     ENLARGEMENT, BLOW-UP, DETAIL(ED) PLAN or ZOOM, or another sheet naming it ("SEE ENLARGED PLAN M4.1");
//   * a PART / PARTIAL plan drawn at a LARGER scale than its discipline's usual plan scale. "PARTIAL PLAN" alone is not
//     enough: the e2e's 8-sheet set (16,432.9 m key) is eight PARTIAL PLANs of eight different areas at one scale;
//   * a larger scale alone is weak evidence (a plant room is often drawn only at 1/4").
// and, for each sheet that might be an enlargement, whether every run on it is ALSO on the discipline's ordinary plans
// (every size it measures at least 90% as long there). Only both - the sheet calls itself an enlargement AND carries
// nothing the other plans do not - drop it from the sum, and the line's basis names it. Anything less certain is still
// counted and the line says so ("may include an enlarged plan — please confirm", qty_status 'to_confirm'): a sheet
// titled ENLARGED that carries runs no other plan has (the main plan says "see enlarged plan" and leaves the room
// empty), or an ordinary-titled sheet at a larger scale whose runs are all on the other plans. Nothing is dropped silently.

const ENLARGED = /\bENLARGE(?:D|MENT)\b|\bBLOW[- ]?UP\b|\bDETAIL(?:ED)?\s+PLAN\b|\bZOOM(?:ED)?\b/;
const PART = /\bPART(?:IAL)?\b/;
const SHEET_REF = /\b[A-Z]{1,2}-?\d{1,2}\.\d{1,2}[A-Z]?\b/g;
/** A size on a candidate sheet is "also on the other plans" when they carry at least this share of its length. */
const COVERED = 0.9;

/** What a sheet says of itself (its own title and its title strip's PLAN lines) and which sheets it calls enlarged. */
export type SheetWords = { number: string; titles: string[]; names: string[] };

/** The words of one sheet that decide whether it is an enlargement. `own` is the number and title the sheet prints itself (sheetOf). */
export function sheetWords(p: PdfPage, strip: Box | null, own: { number: string; title: string }): SheetWords {
  const titles = own.title ? [clip(own.title.toUpperCase(), 120)] : []; const names: string[] = [];
  for (const r of p.runs) {
    const t = r.text.trim().toUpperCase();
    if (titles.length < 6 && strip && inBox(r, strip) && /PLAN/.test(t) && !titles.includes(t)) titles.push(clip(t, 120));
    if (names.length < 8 && /ENLARGE/.test(t)) for (const m of t.matchAll(SHEET_REF)) if (!names.includes(m[0])) names.push(m[0]);
  }
  return { number: own.number, titles, names };
}

/** How one measured sheet enters the length sum. */
export type PlanRole = { counted: boolean; flag: boolean; why: string };

const discipline = (n: string) => /^[A-Z]+/.exec(n)?.[0] ?? '';

/** Each measured plan's role, keyed by its page: counted, counted and flagged, or not counted again (an enlargement). */
export function planRoles(measured: { sheet: Sheet; m: Measured }[], words: Map<number, SheetWords>): Map<number, PlanRole> {
  type P = { sheet: Sheet; len: Map<string, number>; inPerPt: number | null; long: number };
  const pages = new Map<number, P>();
  for (const { sheet, m } of measured) {
    const p = pages.get(sheet.page) || { sheet, len: new Map(), inPerPt: null, long: -1 };
    const k = `${m.kind}:${m.key}`; p.len.set(k, (p.len.get(k) || 0) + m.realIn);
    if (m.pt > p.long) { p.long = m.pt; p.inPerPt = parseScale(m.scale); }                // the sheet's scale: its longest group's
    pages.set(sheet.page, p);
  }
  const roles = new Map<number, PlanRole>();
  if (pages.size < 2) { for (const pg of pages.keys()) roles.set(pg, { counted: true, flag: false, why: '' }); return roles; }
  // Sheets another sheet calls enlarged ("SEE ENLARGED PLAN M4.1").
  const named = new Map<string, string>();
  for (const w of words.values()) for (const n of w.names) if (n !== w.number && !named.has(n)) named.set(n, w.number);
  // A discipline's usual plan scale: the one most of its measured sheets use (a tie goes to the smaller drawing scale).
  const base = new Map<string, number>();
  const tally = new Map<string, Map<number, number>>();
  for (const p of pages.values()) if (p.inPerPt) {
    const d = discipline(p.sheet.number); const t = tally.get(d) || new Map<number, number>();
    const k = Math.round(p.inPerPt * 1e6) / 1e6; t.set(k, (t.get(k) || 0) + 1); tally.set(d, t);
  }
  for (const [d, t] of tally) base.set(d, [...t.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0][0]);
  const score = new Map<number, { s: number; what: string }>();
  for (const p of pages.values()) {
    const titles = [p.sheet.title.toUpperCase(), ...(words.get(p.sheet.page)?.titles || [])];
    const b = base.get(discipline(p.sheet.number));
    const finer = !!(p.inPerPt && b && p.inPerPt < b * 0.99);
    const title = titles.find((t) => ENLARGED.test(t));
    const by = named.get(p.sheet.number);
    const s = title ? { s: 2, what: `its title says ${/DETAIL/.test(title) ? 'detail plan' : /BLOW/.test(title) ? 'blow-up' : /ZOOM/.test(title) ? 'zoom' : 'enlarged'}` } : by ? { s: 2, what: `named as an enlarged plan on ${by}` }
      : finer && titles.some((t) => PART.test(t)) ? { s: 2, what: 'a part plan drawn at a larger scale than the other plans' }
      : finer ? { s: 1, what: 'drawn at a larger scale than the other plans' } : { s: 0, what: '' };
    score.set(p.sheet.page, s);
  }
  for (const p of pages.values()) {
    const sc = score.get(p.sheet.page)!;
    if (!sc.s) { roles.set(p.sheet.page, { counted: true, flag: false, why: '' }); continue; }
    // Is every size on it also on the discipline's ordinary plans?
    const areas = [...pages.values()].filter((o) => o !== p && !score.get(o.sheet.page)!.s && discipline(o.sheet.number) === discipline(p.sheet.number));
    const on = new Set<string>();
    const covered = p.len.size > 0 && [...p.len.entries()].every(([k, v]) => {
      const there = areas.filter((o) => (o.len.get(k) || 0) > 0);
      there.forEach((o) => on.add(o.sheet.number));
      return there.reduce((a, o) => a + o.len.get(k)!, 0) >= v * COVERED;
    });
    if (sc.s === 2 && covered) roles.set(p.sheet.page, { counted: false, flag: false, why: `${p.sheet.number} is an enlarged plan (${sc.what}) and every run on it is also measured on ${[...on].join(', ')}, so it is not counted again` });
    else if (sc.s === 2) roles.set(p.sheet.page, { counted: true, flag: true, why: `${p.sheet.number} looks like an enlarged plan (${sc.what}) but carries runs the other plans do not show, so it is counted` });
    else if (covered) roles.set(p.sheet.page, { counted: true, flag: true, why: `${p.sheet.number} is ${sc.what} and every run on it is also on ${[...on].join(', ')}, so it may be an enlarged plan of the same area; it is counted` });
    else roles.set(p.sheet.page, { counted: true, flag: false, why: '' });
  }
  return roles;
}
