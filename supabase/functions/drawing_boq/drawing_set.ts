// drawing_set — the take-off of a CAD drawing SET read from its PDF text layer, with no model
// (21 Sep 2026, agent: sales_engineer; founder instruction 580: "make sure that he's doing the count
// properly. The elements inside.").
//
// MEASURED BEFORE THIS FILE. Two real US public bid sets (a mechanical permit set, 8 sheets, and a
// plumbing bid set, 5 sheets, every sheet 36x24 in and /Rotate 270) were run through production's
// path: 0 of 49 answer-key items found, 4 OCR-noise lines invented and marked ready. Two causes in
// the reader (pdf_text_positions: Form XObjects not followed, /Contents array objects not resolved)
// meant the plan sheets returned no text at all. With the reader fixed the text IS there — every tag
// on the plans is a text run with a position. What was missing is reading it the way an estimator
// does, which is this file:
//
//  * SHEETS. The sheet number (the largest "M1.0" / "P-1.01" run), its title (the drawing index on
//    the cover sheet, else the largest view title on the sheet), its scale ("SCALE: 1/8" = 1'-0"" or
//    1:100) and its kind: plan, demolition plan, schedule, other.
//  * EQUIPMENT TAGS — a unique id per unit (RTU-1, EF-8, IRH-2, VAV RTU1-4). Written either as one
//    run ("IRH-1") or as a tag bubble: the type over the number, two runs ("EF" above "8"). One unit
//    per distinct id across the set: the same fan drawn on the floor plan and the roof plan is one fan.
//  * FIXTURE / DEVICE TYPE TAGS (WC/L-1, FD-2, HB-1, (R)EWC) — counted per occurrence on each plan.
//    The same fixture is drawn on each system's plan (waste AND water), so the set's count is the
//    LARGEST count on any one new-work plan, never the sum.
//  * AIR DEVICES — a letter (A..G) beside its neck size and airflow ("A" / "8x8" / "180"). Only a
//    letter that has that stack beside it is a diffuser; grid bubbles and keynote letters are not.
//  * (E) existing / (R) relocate / (N) new / (D) demolish prefixes, and demolition sheets.
//  * KEYED NOTES — "4. DEMO AND REMOVE EXISTING LAV…" in the notes column, and every bubble on the
//    sheet carrying that number. Since 22 Sep 2026 a bubble is the number INSIDE a drawn outline (a
//    closed box, hexagon or circle, or four edges drawn one by one); those counts are printed, so 'read'.
//    A sheet whose bubbles have no outline falls back to the old test and stays 'to_confirm'.
//  * SIZES AND LENGTHS — duct sizes (28x20, 1" liner) and pipe sizes and services (3" SS, 2" V). When the
//    PDF carries its CAD layers, drawing_lengths.ts measures each run at the printed scale (22 Sep 2026:
//    the 7 length items of the 49-item key). Without layers the line keeps asking for the length.
//  * SCHEDULES — rows read by OCR in the customer's browser (ocrClient.ocrSchedules, cell by cell)
//    enrich the tag lines with make/model. Anything taken from OCR is 'to_confirm', never 'read'.
//
// WHAT IT NEVER DOES: invent a quantity. A line is 'read' only when every unit of it is printed on the
// drawing - a tag, an outlined keyed-note bubble - or is a length measured on the system's own CAD layer
// against a printed size and a printed scale; everything else is 'to_confirm' (our count from unoutlined
// bubbles or OCR, a single-line duct sized from the nearest label) or has qty null (not measured). No title-block text ever becomes a line (the title-block strip is
// excluded before anything is read — see _shared/anonymise.ts titleStrip).
export type { ScheduleTable, SheetKind, Sheet, Status, TakeoffLine, Diffuser, TagHit } from './drawing_set/types.ts';
export { parseTag } from './drawing_set/vocabulary.ts';
export { tagsOnSheet, unreadTagLike, keyedNotes, tagCounts } from './drawing_set/tags.ts';
export { takeoff } from './drawing_set/takeoff.ts';
export { normTag, scheduleRows } from './drawing_set/schedules.ts';
export { boqFromDrawingSet, countedCompletely, setBeforeModel } from './drawing_set/boq.ts';
export { lengthsForSet, mergeLengths } from './drawing_set/lengths.ts';
