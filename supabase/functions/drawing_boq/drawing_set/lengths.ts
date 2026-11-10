import type { PdfPage } from '../../_shared/pdf_text_positions.ts';
import { redactText, stripSeeds, titleStrip } from '../../_shared/anonymise.ts';
import { scrubIdentity } from '../boq_from_text.ts';
import { DENSE_NOTE, LENGTHS_FAILED_NOTE, NO_LENGTHS_NOTE, PLAN_LENGTHS_NOTE } from '../length_notes.ts';
import { MAX_MEASURED_LINES, measureDucts, measurePipes, scaleLabels, tooDense, type Measured } from '../drawing_lengths.ts';
import { drawingIndex, sheetOf } from './vocabulary.ts';
import { lengthLinesOf } from './takeoff.ts';
import type { Sheet, TakeoffLine } from './types.ts';

// ── THE LENGTHS ARE A SECOND CALL (22 Sep 2026) ──────────────────────────────────────────────────────
// Measured locally, cold process: reading the layers and measuring them adds 0.3-0.5 s of CPU to the
// take-off (the real 8-sheet mechanical set 0.41 -> 0.69 s; the synthetic 8-sheet stress set 0.70 ->
// 1.20 s), and the edge kills an isolate past its CPU cap with no answer at all. So drawing_boq's first
// call reads WITHOUT layers - the take-off production already runs and answers 200 - and the lengths are
// a separate call (mode 'lengths') whose result is merged in. If that call dies, the customer keeps
// every counted line and is told in plain words that the lengths were not measured this time.

/** Only the length lines of a set, scrubbed of the title strip's names like every other line. */
export function lengthsForSet(pages: PdfPage[]): { lines: TakeoffLine[]; dense: string[] } {
  const index = drawingIndex(pages);
  const measured: { sheet: Sheet; m: Measured }[] = []; const dense: string[] = [];
  const seeds: string[] = [];
  pages.forEach((p, i) => {
    const strip = titleStrip(p); if (strip) seeds.push(...stripSeeds(p, strip));
    const sh = sheetOf(p, i, strip, index);
    if (sh.kind !== 'plan' || !p.layers) return;                              // new-work plans only
    if (tooDense(p, strip)) { dense.push(sh.number); return; }
    const sc = scaleLabels(p, strip);
    for (const m of [...measurePipes(p, strip, sc), ...measureDucts(p, strip, sc)]) measured.push({ sheet: sh, m });
  });
  const clean = (s: string) => scrubIdentity(redactText(s, [...new Set(seeds)]).text.replace(/█/g, '').replace(/\s{2,}/g, ' ').trim());
  return { lines: lengthLinesOf(measured).map((l) => ({ ...l, item: clean(l.item), description: clean(l.description), basis: clean(l.basis) })), dense };
}

type SetBoq = { boq: TakeoffLine[]; missing_info: string[] } & Record<string, unknown>;
/** The first call's BOQ with the measured lengths merged in: measured sizes replace the "to be measured"
 *  lines they cover; `null` (the lengths call failed or was killed) keeps every line and says so. */
export function mergeLengths<T extends SetBoq>(set: T, lengths: { lines: TakeoffLine[]; dense: string[] } | null): T {
  const missing = set.missing_info.filter((m) => m !== NO_LENGTHS_NOTE && m !== PLAN_LENGTHS_NOTE);
  const asked = set.boq.filter((l) => /^(duct|pipe):/.test(l.type) && l.qty === null);
  if (!lengths) {
    return asked.length ? { ...set, missing_info: [LENGTHS_FAILED_NOTE, ...missing] } : set;
  }
  if (!lengths.lines.length) return { ...set, missing_info: [...(lengths.dense.length ? [DENSE_NOTE(lengths.dense.join(', '), MAX_MEASURED_LINES.toLocaleString('en'))] : []), ...set.missing_info] };
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
  return { ...set, boq: [...keep, ...lengths.lines], missing_info: [still ? NO_LENGTHS_NOTE : PLAN_LENGTHS_NOTE, ...(lengths.dense.length ? [DENSE_NOTE(lengths.dense.join(', '), MAX_MEASURED_LINES.toLocaleString('en'))] : []), ...missing] };
}
