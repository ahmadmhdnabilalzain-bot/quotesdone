import type { PdfPage } from '../../_shared/pdf_text_positions.ts';
import { redactText, stripSeeds, titleStrip } from '../../_shared/anonymise.ts';
import { scrubIdentity } from '../boq_from_text.ts';
import { DENSE_NOTE, LENGTHS_FAILED_NOTE, NO_LENGTHS_NOTE, PLAN_LENGTHS_NOTE, lengthsToConfirm } from '../length_notes.ts';
import { MAX_MEASURED_LINES, measureDucts, measurePipes, scaleLabels, tooDense, type Measured } from '../drawing_lengths.ts';
import { drawingIndex, kindOf, sheetOf } from './vocabulary.ts';
import { lengthLinesOf } from './takeoff.ts';
import { sheetWords } from './enlarged.ts';
import type { Sheet, TakeoffLine } from './types.ts';

// ── THE LENGTHS ARE A SECOND CALL (22 Sep 2026) ──────────────────────────────────────────────────────
// Measured locally, cold process: reading the layers and measuring them adds 0.3-0.5 s of CPU to the
// take-off (the real 8-sheet mechanical set 0.41 -> 0.69 s; the synthetic 8-sheet stress set 0.70 ->
// 1.20 s), and the edge kills an isolate past its CPU cap with no answer at all. So drawing_boq's first
// call reads WITHOUT layers - the take-off production already runs and answers 200 - and the lengths are
// a separate call (mode 'lengths') whose result is merged in. If that call dies, the customer keeps
// every counted line and is told in plain words that the lengths were not measured this time.

// ── SHEET BY SHEET (17 Nov 2026, sales_engineer; paid proof 14173f94) ───────────────────────────────────────
// MEASURED, LOCAL, cold process, the 8-sheet e2e set (scripts/e2e/drawing_reaches_suppliers.mjs stressSetPdf(8)): the one
// 'lengths' call took 2,030-2,106 ms of CPU (the layered parse of all 8 sheets ~0.5 s, measureDucts ~1.4 s) - past the
// edge's 2 s cap. On production (SELECT, function logs, 17 Nov 14:4x UTC) it answered 500 in 1.2 s on the worker that had
// just run the take-off (shutdown EarlyDrop, CPU ~1.8 s); customer_api queued the CAD worker only on a 546 or no answer,
// so the 16,432.9 m of 26x18 duct reached the inquiry as "Rectangular ductwork, sizes 26x18" with no quantity.
// Now each call reads and measures a few sheets (`lengthsPart`, one by default) and a last call puts the parts together
// (`lengthsOfParts`) exactly as the whole-set read did: the drawing index and the title-strip names are the WHOLE set's,
// gathered from every part, and the runs are summed in page order (drawing_lengths.test.ts proves the parts equal the
// whole set and the answer key). A sheet's kind needs the whole set's index, so a part measures every layered sheet it
// reads and the merge keeps the plans. One difference, deliberate: the parser's operation budget is per call, not per file.

/** The JSON of one measured run group (`Measured` with its layer set as a list). */
export type MeasuredJson = Omit<Measured, 'layers'> & { layers: string[] };
/** One sheet as a lengths part reads it: what the merge needs to decide, with the whole set, whether it is a plan. */
export type LengthSheet = { page: number; number: string; own_title: string; index: [string, string][]; seeds: string[]; dense: boolean; measured: MeasuredJson[];
  /** enlarged.ts sheetWords: its title-strip PLAN lines and the sheets it calls enlarged (optional: a part from before 17 Nov). */
  titles?: string[]; names?: string[] };
/** The sheets [from, from + sheets.length) of a set of `pages` sheets. */
export type LengthsPart = { pages: number; from: number; sheets: LengthSheet[] };

/** Sheets [from, to) of `pages` (pdfPages WITH layers; the other pages may be the parser's empty stubs). */
export function lengthsPart(pages: PdfPage[], from: number, to: number): LengthsPart {
  const sheets: LengthSheet[] = [];
  for (let i = from; i < Math.min(to, pages.length); i++) {
    const p = pages[i];
    const strip = titleStrip(p);
    const own = sheetOf(p, i, strip, new Map());                              // the title the sheet prints itself
    const w = sheetWords(p, strip, own);
    const sheet: LengthSheet = { page: i, number: own.number, own_title: own.title, index: [...drawingIndex([p])], seeds: strip ? stripSeeds(p, strip) : [], dense: false, measured: [], titles: w.titles, names: w.names };
    if (p.layers) {
      if (tooDense(p, strip)) sheet.dense = true;
      else {
        const sc = scaleLabels(p, strip);
        sheet.measured = [...measurePipes(p, strip, sc), ...measureDucts(p, strip, sc)].map((m) => ({ ...m, layers: [...m.layers] }));
      }
    }
    sheets.push(sheet);
  }
  return { pages: pages.length, from, sheets };
}

const isStrs = (v: unknown): v is string[] => Array.isArray(v) && v.every((x) => typeof x === 'string');
const num = (v: unknown) => typeof v === 'number' && Number.isFinite(v);
const measuredOk = (m: any): m is MeasuredJson => !!m && typeof m.key === 'string' && typeof m.svc === 'string' && (m.kind === 'pipe' || m.kind === 'duct')
  && num(m.pt) && num(m.realIn) && typeof m.labelled === 'boolean' && typeof m.scale === 'string' && isStrs(m.layers) && num(m.runs) && (m.single === undefined || num(m.single));
const sheetOk = (s: any, page: number): s is LengthSheet => !!s && s.page === page && typeof s.number === 'string' && typeof s.own_title === 'string'
  && Array.isArray(s.index) && s.index.every((e: unknown) => Array.isArray(e) && e.length === 2 && isStrs(e)) && isStrs(s.seeds)
  && typeof s.dense === 'boolean' && Array.isArray(s.measured) && s.measured.every(measuredOk)
  && (s.titles === undefined || isStrs(s.titles)) && (s.names === undefined || isStrs(s.names));

/** The parts put together as the whole-set read made them; null unless they cover every sheet of one set exactly once. */
export function lengthsOfParts(parts: unknown[]): { lines: TakeoffLine[]; dense: string[] } | null {
  if (!Array.isArray(parts) || !parts.length) return null;
  const ps = [...parts as LengthsPart[]].sort((a, b) => (a?.from ?? 0) - (b?.from ?? 0));
  const n = ps[0]?.pages;
  if (!Number.isInteger(n) || n < 0) return null;
  const sheets: LengthSheet[] = [];
  for (const p of ps) {
    if (!p || p.pages !== n || p.from !== sheets.length || !Array.isArray(p.sheets)) return null;
    for (const s of p.sheets) { if (!sheetOk(s, sheets.length)) return null; sheets.push(s); }
  }
  if (sheets.length !== n) return null;
  // drawingIndex over the whole set: pages in order, the first sheet number met keeps its title.
  const index = new Map<string, string>();
  for (const s of sheets) for (const [k, v] of s.index) if (!index.has(k)) index.set(k, v);
  const measured: { sheet: Sheet; m: Measured }[] = []; const dense: string[] = [];
  // Each physical run once (enlarged.ts): what every sheet says of itself and of the others, plans or not.
  const words = new Map(sheets.map((s) => [s.page + 1, { number: s.number, titles: s.titles || (s.own_title ? [s.own_title.toUpperCase()] : []), names: s.names || [] }]));
  for (const s of sheets) {
    const title = index.get(s.number) || s.own_title;
    if (kindOf(title) !== 'plan') continue;                                   // new-work plans only
    if (s.dense) { dense.push(s.number); continue; }
    const sheet: Sheet = { page: s.page + 1, number: s.number, title, scale: '', kind: 'plan' };
    for (const m of s.measured) measured.push({ sheet, m: { ...m, layers: new Set(m.layers) } });
  }
  const seeds = [...new Set(sheets.flatMap((s) => s.seeds))];
  const clean = (s: string) => scrubIdentity(redactText(s, seeds).text.replace(/█/g, '').replace(/\s{2,}/g, ' ').trim());
  return { lines: lengthLinesOf(measured, words).map((l) => ({ ...l, item: clean(l.item), description: clean(l.description), basis: clean(l.basis) })), dense };
}

/** Only the length lines of a set, scrubbed of the title strip's names like every other line (the CAD worker's whole-set read). */
export function lengthsForSet(pages: PdfPage[]): { lines: TakeoffLine[]; dense: string[] } {
  return lengthsOfParts([lengthsPart(pages, 0, pages.length)])!;
}

type SetBoq = { boq: TakeoffLine[]; missing_info: string[] } & Record<string, unknown>;
/** The first call's BOQ with the measured lengths merged in: measured sizes replace the "to be measured"
 *  lines they cover; `null` (the lengths call failed or was killed) keeps every line and says so. */
export function mergeLengths<T extends SetBoq>(set: T, lengths: { lines: TakeoffLine[]; dense: string[] } | null): T {
  const missing = set.missing_info.filter((m) => m !== NO_LENGTHS_NOTE && m !== PLAN_LENGTHS_NOTE);
  const asked = set.boq.filter((l) => /^(duct|pipe):/.test(l.type) && l.qty === null);
  if (!lengths) {
    return asked.length ? { ...set, boq: lengthsToConfirm(set.boq), missing_info: [LENGTHS_FAILED_NOTE, ...missing] } : set;
  }
  if (!lengths.lines.length) return { ...set, boq: lengthsToConfirm(set.boq), missing_info: [...(lengths.dense.length ? [DENSE_NOTE(lengths.dense.join(', '), MAX_MEASURED_LINES.toLocaleString('en'))] : []), ...set.missing_info] };
  const got = new Set(lengths.lines.map((l) => l.type));
  const anyDuct = lengths.lines.some((l) => l.type.startsWith('duct:'));
  // THE MODEL'S OWN LINE FOR A MEASURED SIZE (10 Nov 2026). Since 3 Nov the model reads the set first (cross_check.ts) and
  // its lines join code's; a model line "Supply ductwork 26x18" with no length stayed beside the measured "Rectangular
  // ductwork 26x18 16,433.2 m", so the size read as unmeasured. A line with no type of its own (the model's) that names a
  // measured duct or pipe size is that measurement; it goes, and the measured line stands.
  const sizes = lengths.lines.map((l) => l.type.replace(/^(duct|pipe):/, '').replace(/ \(1" liner\)$/, '').toLowerCase()).filter((z) => /\d/.test(z));
  const namesMeasured = (l: TakeoffLine) => !l.type && /duct|pipe/i.test(`${l.description} ${l.item}`) && sizes.some((z) => {
    const m = /^(\d+)x(\d+)$/.exec(z);
    return m ? new RegExp(`(^|[^\\d])${m[1]}\\s*[x×]\\s*${m[2]}([^\\d]|$)`, 'i').test(`${l.description} ${l.item}`) : false;
  });
  const keep = set.boq.filter((l) => !namesMeasured(l) && !(l.qty === null && ((anyDuct && (l.type === 'duct:rectangular' || l.type === 'duct:round')) || (l.type.startsWith('pipe:') && got.has(l.type)))));
  const still = keep.some((l) => /^(duct|pipe):/.test(l.type) && l.qty === null);
  return { ...set, boq: lengthsToConfirm([...keep, ...lengths.lines]), missing_info: [still ? NO_LENGTHS_NOTE : PLAN_LENGTHS_NOTE, ...(lengths.dense.length ? [DENSE_NOTE(lengths.dense.join(', '), MAX_MEASURED_LINES.toLocaleString('en'))] : []), ...missing] };
}
