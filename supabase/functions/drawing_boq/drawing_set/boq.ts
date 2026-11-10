import type { PdfPage } from '../../_shared/pdf_text_positions.ts';
import { redactText, stripSeeds } from '../../_shared/anonymise.ts';
import { scrubIdentity } from '../boq_from_text.ts';
import { DENSE_NOTE, NO_LENGTHS_NOTE, PLAN_LENGTHS_NOTE } from '../length_notes.ts';
import { MAX_MEASURED_LINES } from '../drawing_lengths.ts';
import { EQUIPMENT } from './vocabulary.ts';
import { takeoff } from './takeoff.ts';
import type { ScheduleTable } from './types.ts';

const HVAC_TYPES = new Set(Object.keys(EQUIPMENT));
const MISSING_ALWAYS = [
  'Symbols drawn without a tag (an untagged grille, a valve symbol) are not counted; only tags, keyed-note bubbles and labelled sizes are.',
];

/** drawing_boq's response shape for a PDF drawing set: the take-off when it finds anything, with every
 *  string scrubbed of the title strip's names and of any contact detail. `null` = nothing drawn to count. */
export function boqFromDrawingSet(pages: PdfPage[], hint = '', schedules: ScheduleTable[] = []) {
  const t = takeoff(pages, schedules);
  if (!t.lines.length) return null;
  // Names printed in any sheet's title strip never leave in a line (a keynote can repeat the project name).
  const seeds = [...new Set(pages.flatMap((p, i) => (t.strips[i] ? stripSeeds(p, t.strips[i]!) : [])))];
  const clean = (s: string) => scrubIdentity(redactText(s, seeds).text.replace(/█/g, '').replace(/\s{2,}/g, ' ').trim());
  const boq = t.lines.map((l) => ({ ...l, item: clean(l.item), description: clean(l.description), basis: clean(l.basis), section: clean(l.section) }));
  const plans = t.sheets.filter((s) => s.kind === 'plan' || s.kind === 'demolition_plan');
  const hvac = boq.filter((l) => /^tag:/.test(l.type) && HVAC_TYPES.has(l.type.slice(4).replace(/-.*$/, '').replace(/\d+$/, '')) || l.type.startsWith('air_device') || l.type.startsWith('duct')).length;
  const plumb = boq.filter((l) => l.section === 'Plumbing fixtures' || l.type.startsWith('pipe')).length;
  const scales = [...new Set(plans.map((s) => s.scale).filter(Boolean))];
  const missing = [...MISSING_ALWAYS];
  const lengthLines = boq.filter((l) => /^(duct|pipe):/.test(l.type));
  if (lengthLines.length) missing.unshift(lengthLines.some((l) => l.qty === null) ? NO_LENGTHS_NOTE : PLAN_LENGTHS_NOTE);
  if (t.dense.length) missing.unshift(DENSE_NOTE(t.dense.join(', '), MAX_MEASURED_LINES.toLocaleString('en')));
  const noPlan = t.sheets.filter((s) => s.kind === 'schedule');
  if (noPlan.length && !schedules.length) missing.push(`Schedule sheet(s) ${noPlan.map((s) => s.number).join(', ')} were not read (their tables are images); make and model are therefore not on the lines.`);
  if (boq.some((l) => l.qty_status === 'to_confirm')) missing.push('Lines marked "to confirm" are our own count (keyed-note bubbles, a letter continuing a series, or a schedule read by OCR); they are shown to you to confirm before suppliers price them.');
  return {
    drawing_type: plans.length ? `${plans.length} plan sheet(s): ${plans.map((s) => `${s.number} ${s.title}`).join('; ')}`.slice(0, 200) : 'drawing set',
    category: hvac >= plumb ? (hvac ? 'mep_hvac' : '') : 'mep_plumbing',
    summary: scrubIdentity(redactText(hint, seeds).text.replace(/█/g, '')).slice(0, 200),
    scale_detected: scales.join(', '),
    total_area_sqm: null as number | null, area_tags_sqm: [] as number[],
    boq, keywords: [...new Set(boq.map((l) => l.section.toLowerCase()))].slice(0, 10), assumptions: [
      'Counted from the drawing set\'s own text: one unit per equipment tag id; fixtures at their largest count on one plan (the same fixture is drawn on each system\'s plan); air devices by their tag letters.',
    ], missing_info: missing, confidence: 'low' as const, method: 'drawing_set', pages_read: pages.length, coverage: t.coverage,
    sheets: t.sheets.map((s) => ({ number: s.number, title: clean(s.title), scale: s.scale, kind: s.kind })),
  };
}

// ── THE COVERAGE FLOOR OF THE EARLY PATH (27 Oct 2026, sales_engineer; founder ledger 580) ──────────────────────────
// drawing_boq answers a PDF set with boqFromDrawingSet BEFORE the vision model is asked (set_before_model.test.ts). An
// independent review found the hole in that: a set where code reads a few tags and misses most (a type the vocabulary
// has no word for: IDU-1..IDU-12 of a VRF system beside two EF fans) would return 2 lines and never reach the model;
// only the customer's confirm step stood between that and an under-counted inquiry. So the early path answers only
// when the count is plausibly complete; otherwise the model drafts exactly as before.
//
// THE SIGNAL is what the text layer itself exposes: on every plan sheet, the runs SHAPED like a tag (unreadTagLike)
// that the reader did not read. THE FLOOR is all of them read (share 1.0, i.e. 0 unread) and at least one tag read.
// MEASURED 27 Oct 2026 on every PDF drawing fixture in the repository, reader as it stands:
//   drawing_set.fixtures sheetPdf          8 read / 0 unread     bench.fixtures benchPdf             24 read / 0 unread
//   zz_demo_drawings zzPdfSet             20 read / 0 unread     zz_demo_drawings zzPdfSheet         15 read / 0 unread
//   drawing_reaches_suppliers stressSetPdf(8), the ledger-580 set the model got 2/7 on:     5 read / 0 unread
//   drawing_lengths.fixtures layeredSetPdf  0 read / 0 unread (sizes and keyed notes only, no tag: nothing to judge,
//                                                               so it goes to the model, as it did before this path)
// No fixture has a single unread tag-shaped run that was rightly left out, so any allowance above 0 would be a number
// with nothing under it. The two errors are not equal either: falling through costs only the pre-27-Oct behaviour (the
// model drafts; boqFromDrawingSet still answers if the model refuses), while a wrong early return under-counts with
// only the confirm step behind it. A real set with a stray tag-shaped run (a room "G01" the vocabulary reads as nothing)
// therefore goes to the model; that is the safe side. Independent review, same day: the signal also counts an unread
// SERIES (one letter prefix with two or more numbers, any spelling: IDU-GF-01, IDU 1, IDU-1001, VRF-IDU-1) and the
// tagged runs of a sheet whose title does not say PLAN ("AC LAYOUT"); the fixtures above still read 0 unread with both.
// Not measured by this floor: a single unread tag in a spelling TAG_SHAPE does not know, and air devices drawn with
// no letter.
export function countedCompletely(set: { coverage: { tags_read: number; tag_like_unread: number } } | null): boolean {
  return !!set && set.coverage.tags_read > 0 && set.coverage.tag_like_unread === 0;
}
/** The early answer drawing_boq gives before the model: the coded set when countedCompletely, else null (the model drafts). */
export function setBeforeModel(pages: PdfPage[], hint = '', schedules: ScheduleTable[] = []) {
  const set = boqFromDrawingSet(pages, hint, schedules);
  return countedCompletely(set) ? set : null;
}

