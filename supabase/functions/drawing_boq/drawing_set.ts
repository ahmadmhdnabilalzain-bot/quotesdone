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
import type { PdfPage, TextRun } from '../_shared/pdf_text_positions.ts';
import { redactText, stripSeeds, titleStrip, type Box } from '../_shared/anonymise.ts';
import { scrubIdentity } from './boq_from_text.ts';
import { DENSE_NOTE, LENGTHS_FAILED_NOTE, NO_LENGTHS_NOTE, PLAN_LENGTHS_NOTE } from './length_notes.ts';
import { feet, MAX_MEASURED_LINES, measureDucts, measurePipes, metres, scaleLabels, tooDense, type Measured } from './drawing_lengths.ts';

export type ScheduleTable = { page: number; bbox?: Box; rows: string[][]; conf?: number[][] };
export type SheetKind = 'plan' | 'demolition_plan' | 'schedule' | 'other';
export type Sheet = { page: number; number: string; title: string; scale: string; kind: SheetKind };
export type Status = 'new' | 'existing' | 'relocate' | 'demolish';
export type TakeoffLine = {
  section: string; item: string; description: string; qty: number | null; unit: string; basis: string;
  confidence: 'low' | 'medium'; qty_status?: 'read' | 'to_confirm'; estimate?: number | null; type: string;
  section_ar?: string; description_ar?: string;
  status: Status; sheets: string[];
};
export type Diffuser = { letter: string; neck: string; cfm: string; x: number; y: number; inferred?: boolean };
export type TagHit = { tag: string; type: string; status: Status; page: number; x: number; y: number };

// ── vocabulary ─────────────────────────────────────────────────────────────────────────────────
// Equipment: one unit per id. Names are the fallback when the drawing's own abbreviation table does
// not define the type.
const EQUIPMENT: Record<string, string> = {
  RTU: 'Rooftop unit', DOAS: 'Dedicated outdoor air unit', AHU: 'Air handling unit', AH: 'Air handling unit', FCU: 'Fan coil unit',
  EF: 'Exhaust fan', SF: 'Supply fan', RF: 'Return fan', TF: 'Transfer fan', CU: 'Condensing unit', ACCU: 'Air-cooled condensing unit',
  AC: 'Split air conditioning unit (indoor)', HP: 'Heat pump', ERV: 'Energy recovery ventilator', HRV: 'Heat recovery ventilator',
  MAU: 'Make-up air unit', UH: 'Unit heater', GUH: 'Gas unit heater', CUH: 'Cabinet unit heater', IRH: 'Infrared radiant tube heater',
  EWH: 'Electric wall heater', EUH: 'Electric unit heater', EBB: 'Electric baseboard heater', VAV: 'VAV terminal unit', FPB: 'Fan powered box',
  B: 'Boiler', CH: 'Chiller', CT: 'Cooling tower', P: 'Pump', WH: 'Water heater', DWH: 'Domestic water heater', HX: 'Heat exchanger',
  ET: 'Expansion tank', AS: 'Air separator', HUM: 'Humidifier', DH: 'Dehumidifier', FD_DAMPER: 'Fire damper',
};
// Plumbing fixtures and devices: counted per occurrence. A tag like FD-2 is a TYPE, not a unit.
const FIXTURE: Record<string, string> = {
  'WC/L': 'Combination water closet and lavatory', WC: 'Water closet', L: 'Lavatory', LAV: 'Lavatory', UR: 'Urinal', U: 'Urinal',
  S: 'Sink', SK: 'Sink', MS: 'Mop sink', MB: 'Mop basin', SH: 'Shower', FD: 'Floor drain', FS: 'Floor sink', HB: 'Hose bibb',
  WHY: 'Wall hydrant', EWC: 'Electric water cooler / drinking fountain', DF: 'Drinking fountain', FCO: 'Floor cleanout', CO: 'Cleanout',
  WCO: 'Wall cleanout', RD: 'Roof drain', OD: 'Overflow drain', TP: 'Trap primer', IW: 'Ice maker box', WB: 'Washer box', ES: 'Eyewash station',
  EW: 'Emergency eyewash', SS_SHOWER: 'Safety shower',
};
// Types written with no number are rare and specific; anything else needs a number to be a tag.
const NO_NUMBER_OK = new Set(['EWC', 'FCO', 'DF', 'WCO', 'CO']);
const SHEET_NO = /^[A-Z]{1,2}-?\d{1,2}\.\d{1,2}[A-Z]?$/;
const PREFIX = /^\((E|R|N|D|ER|EX)\)\s*/;
const statusOf = (p: string | undefined): Status => p === 'E' || p === 'EX' ? 'existing' : p === 'R' || p === 'ER' ? 'relocate' : p === 'D' ? 'demolish' : 'new';

const size = (r: TextRun) => r.vertical ? r.w : r.h;
const cx = (r: TextRun) => r.x + r.w / 2;
const cy = (r: TextRun) => r.y + r.h / 2;
const inBox = (r: TextRun, b: Box | null) => !!b && cx(r) >= b.x && cx(r) <= b.x + b.w && cy(r) >= b.y && cy(r) <= b.y + b.h;
const clip = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + '…' : s);

/** "EF-8", "(R)EWC", "WC/L-1", "RTU1-4-H" -> {type, tag, status} or null. */
export function parseTag(text: string): { type: string; tag: string; status: Status; kind: 'equipment' | 'fixture' | 'terminal' } | null {
  const t = text.trim().toUpperCase();
  const pm = PREFIX.exec(t); const body = pm ? t.slice(pm[0].length) : t; const status = statusOf(pm?.[1]);
  // VAV terminal named after its air handler: RTU1-4, RTU1-4-H (H = with reheat).
  let m = /^([A-Z]{2,4})(\d{1,2})-(\d{1,2})(-H)?$/.exec(body);
  if (m && EQUIPMENT[m[1]]) return { type: 'VAV', tag: `${m[1]}${m[2]}-${m[3]}${m[4] || ''}`, status, kind: 'terminal' };
  m = /^([A-Z]{1,4}(?:\/[A-Z]{1,3})?)(?:-?(\d{1,3}[A-Z]?))?$/.exec(body);
  if (!m) return null;
  const [, type, num] = m;
  if (FIXTURE[type] && (num || NO_NUMBER_OK.has(type))) return { type, tag: num ? `${type}-${num}` : type, status, kind: 'fixture' };
  if (EQUIPMENT[type] && num) return { type, tag: `${type}-${num}`, status, kind: 'equipment' };
  return null;
}

/** A sheet's number, title, scale and kind. `index` is the drawing index read off the cover sheet. */
function sheetOf(p: PdfPage, pi: number, strip: Box | null, index: Map<string, string>): Sheet {
  const nums = p.runs.filter((r) => SHEET_NO.test(r.text.trim())).sort((a, b) => size(b) - size(a));
  const number = nums[0]?.text.trim() || `page ${pi + 1}`;
  const views = p.runs.filter((r) => !r.vertical && !inBox(r, strip) && r.h >= 0.012 && /[A-Z]{3,}/.test(r.text) && !/NOTES?:?$/.test(r.text.trim()))
    .sort((a, b) => b.h - a.h || a.y - b.y);
  const title = index.get(number) || views.map((r) => r.text.trim()).find((t) => /PLAN|SCHEDULE|DETAIL|DIAGRAM|SECTION|ELEVATION|LEGEND|SPECIFICATION/.test(t)) || views[0]?.text.trim() || '';
  const all = p.runs.map((r) => r.text).join(' ');
  const sc = /SCALE\s*:?\s*((?:\d+\/)?\d+"\s*=\s*\d+'\s*-?\s*\d*"?|1\s*[:\/]\s*\d{1,4})/i.exec(all);
  let scale = sc ? sc[1].replace(/\s+/g, ' ').trim() : '';
  if (!scale) { const i = p.runs.findIndex((r) => /^SCALE:?$/i.test(r.text.trim())); if (i >= 0) { const r0 = p.runs[i]; const nx = p.runs.filter((o) => Math.abs(cy(o) - cy(r0)) < r0.h && o.x > r0.x && o.x < r0.x + 0.06).sort((a, b) => a.x - b.x)[0]; if (nx) scale = nx.text.trim(); } }
  const T = title.toUpperCase();
  const kind: SheetKind = /DEMO/.test(T) ? 'demolition_plan' : /SCHEDULE/.test(T) ? 'schedule' : /PLAN/.test(T) ? 'plan' : 'other';
  return { page: pi + 1, number, title, scale, kind };
}

/** Drawing index on any sheet: a sheet-number run with a title run to its right on the same line. */
function drawingIndex(pages: PdfPage[]): Map<string, string> {
  const out = new Map<string, string>();
  for (const p of pages) for (const r of p.runs) {
    if (r.vertical || !SHEET_NO.test(r.text.trim())) continue;
    const right = p.runs.filter((o) => !o.vertical && o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.6 && o.x > r.x + r.w && o.x < r.x + r.w + 0.03 && /[A-Z]{3,}/.test(o.text))
      .sort((a, b) => a.x - b.x)[0];
    if (right && !out.has(r.text.trim())) out.set(r.text.trim(), right.text.trim());
  }
  return out;
}

/** Abbreviation table ("RTU  ROOFTOP UNIT"): the drawing's own names for its tag types. */
function abbreviations(pages: PdfPage[]): Map<string, string> {
  const out = new Map<string, string>();
  for (const p of pages) for (const r of p.runs) {
    const k = r.text.trim().replace(/\s*\([A-Z]+\)$/, '');
    if (r.vertical || !/^[A-Z]{1,5}$/.test(k) || !(EQUIPMENT[k] || FIXTURE[k])) continue;
    const right = p.runs.filter((o) => !o.vertical && o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.5 && o.x > r.x + r.w && o.x < r.x + r.w + 0.03 && /^[A-Z][A-Z ,\-\/]{4,}$/.test(o.text.trim()))
      .sort((a, b) => a.x - b.x)[0];
    if (right && !out.has(k)) out.set(k, right.text.trim());
  }
  return out;
}

type Consumed = Set<TextRun>;

/** Every tag on one sheet, drawing area only (the title strip is excluded by the caller). */
export function tagsOnSheet(p: PdfPage, pi: number, strip: Box | null, airTypes: Iterable<string> = []): { hits: TagHit[]; diffusers: Diffuser[]; consumed: Consumed } {
  const runs = p.runs.filter((r) => !inBox(r, strip));
  const consumed: Consumed = new Set();
  const hits: TagHit[] = [];
  // 1. Single-run tags.
  for (const r of runs) {
    const t = parseTag(r.text); if (!t) continue;
    hits.push({ tag: t.tag, type: t.type, status: t.status, page: pi + 1, x: cx(r), y: cy(r) }); consumed.add(r);
  }
  // 2. Tag bubbles: a type code with its number directly below (same centre line, within 1.8 heights).
  for (const r of runs) {
    if (consumed.has(r)) continue;
    const code = r.text.trim().toUpperCase();
    if (!(EQUIPMENT[code] || FIXTURE[code]) || r.vertical) continue;
    const below = runs.filter((o) => !consumed.has(o) && o !== r && /^\d{1,3}[A-Z]?$/.test(o.text.trim()) && Math.abs(cx(o) - cx(r)) < Math.max(r.w, 0.004) && o.y > r.y && o.y - r.y < r.h * 1.8)
      .sort((a, b) => a.y - b.y)[0];
    if (!below) continue;
    const t = parseTag(`${code}-${below.text.trim()}`); if (!t) continue;
    hits.push({ tag: t.tag, type: t.type, status: t.status, page: pi + 1, x: cx(r), y: cy(r) }); consumed.add(r); consumed.add(below);
  }
  // 3. Air devices: letter, then (right) neck size over airflow.
  const diffusers: Diffuser[] = [];
  const NECK = /^(\d{1,2}\s*x\s*\d{1,2}|\d{1,2}"?\s*(?:Ø|DIA|RD))$/i, CFM = /^(\d{2,4}|--|-)$/;
  for (const r of runs) {
    if (consumed.has(r) || r.vertical || !/^[A-Z]$/.test(r.text.trim())) continue;
    const near = runs.filter((o) => o !== r && !consumed.has(o) && o.x >= r.x + r.w * 0.5 && o.x - (r.x + r.w) < 0.012 && Math.abs(cy(o) - cy(r)) < r.h * 1.2);
    const neck = near.find((o) => NECK.test(o.text.trim()) && cy(o) <= cy(r) + r.h * 0.2);
    const cfm = near.find((o) => CFM.test(o.text.trim()) && cy(o) >= cy(r) - r.h * 0.2);
    // A letter with its airflow below-right is a device even when the neck is not written (measured on
    // the mechanical set: type F carries "110" and no neck); a lone neck size is not enough.
    if (!cfm || (!neck && !/^\d{2,4}$/.test(cfm.text.trim()))) continue;
    diffusers.push({ letter: r.text.trim(), neck: neck ? neck.text.trim().replace(/\s+/g, '') : '', cfm: cfm.text.trim(), x: cx(r), y: cy(r) });
    consumed.add(r); if (neck) consumed.add(neck); consumed.add(cfm);
  }
  // 4. The same letters drawn bare (a return grille tagged "G" with no airflow beside it). Only a letter
  //    already known as an air device — seen with its stack on this sheet, or a row of the air device
  //    schedule — and only at the same text height as those tags, so a grid bubble or a damper "M" is not.
  //    A letter that only CONTINUES the series (G after A..F, measured on the mechanical set: six circled
  //    "G" return grilles, no airflow written, the schedule itself a raster) is counted as inferred, and
  //    the line says so and stays 'to_confirm' unless the schedule names that letter.
  const known = new Set([...diffusers.map((d) => d.letter), ...airTypes]);
  const top = known.size ? Math.max(...[...known].map((l) => l.charCodeAt(0))) : 0;
  const series = new Set(Array.from({ length: Math.max(0, top + 2 - 64) }, (_, i) => String.fromCharCode(65 + i)).filter((l) => !known.has(l) && l !== 'I' && l !== 'O'));
  const hs = diffusers.map((d) => runs.find((r) => cx(r) === d.x && cy(r) === d.y)?.h || 0).filter(Boolean).sort((a, b) => a - b);
  const hRef = hs.length ? hs[Math.floor(hs.length / 2)] : 0;
  if (hRef) for (const r of runs) {
    const t = r.text.trim();
    if (consumed.has(r) || r.vertical || !/^[A-Z]$/.test(t) || !(known.has(t) || series.has(t)) || Math.abs(r.h - hRef) > hRef * 0.15) continue;
    diffusers.push({ letter: t, neck: '', cfm: '', x: cx(r), y: cy(r), ...(series.has(t) ? { inferred: true } : {}) }); consumed.add(r);
  }
  return { hits, diffusers, consumed };
}

/** Keyed notes of a sheet ("4. DEMO AND REMOVE …", continuation lines joined) and the bubbles carrying each number. */
export function keyedNotes(p: PdfPage, strip: Box | null, consumed: Consumed): { n: number; text: string; bubbles: number; outlined: boolean }[] {
  const runs = p.runs.filter((r) => !inBox(r, strip) && !r.vertical);
  const heads = runs.filter((r) => /^\d{1,2}\.$/.test(r.text.trim()));
  if (!heads.length) return [];
  const notes = new Map<number, { text: string; x: number; y: number }>();
  const headSet = new Set(heads);
  for (const h of heads) {
    const n = Number(h.text.trim().slice(0, -1));
    const first = runs.find((o) => !headSet.has(o) && Math.abs(cy(o) - cy(h)) < h.h * 0.6 && o.x > h.x && o.x - (h.x + h.w) < 0.012);
    if (!first) continue;
    // continuation lines: same left edge, directly below, until the next numbered head
    const nextHead = heads.filter((o) => Math.abs(o.x - h.x) < 0.01 && o.y > h.y).sort((a, b) => a.y - b.y)[0];
    const cont = runs.filter((o) => !headSet.has(o) && o !== first && Math.abs(o.x - first.x) < 0.004 && o.y > first.y && o.y < (nextHead ? nextHead.y - h.h * 0.3 : first.y + 0.03))
      .sort((a, b) => a.y - b.y);
    if (!notes.has(n)) notes.set(n, { text: [first, ...cont].map((o) => o.text.trim()).join(' ').replace(/\s+/g, ' '), x: h.x, y: h.y });
  }
  if (!notes.size) return [];
  const colX = Math.min(...[...notes.values()].map((v) => v.x));
  const max = Math.max(...notes.keys());
  const count = new Map<number, number>();
  // A keyed-note BUBBLE is the number inside a small closed outline (a box, a hexagon, a circle). When
  // the PDF carries its drawn outlines (CAD layers), only an enclosed number counts. Measured 22 Sep
  // 2026: without the outline test a room number, a dimension or a tag digit that happens to equal a
  // note number was counted as a bubble, so every keyed-note line had to stay 'to_confirm'.
  const marks = (p.marks || []).filter((m) => !inBox({ x: m.x + m.w / 2, y: m.y + m.h / 2, w: 0, h: 0, text: '' }, strip));
  // The outline is a closed path (a mark) or four straight edges drawn one by one (a box built of lines).
  const edges = p.lines || [];
  const boxed = (r: TextRun) => {
    const x = cx(r), y = cy(r), s = size(r), reach = s * 2.5;
    const side = (f: (l: typeof edges[number]) => boolean) => edges.some(f);
    return side((l) => l.x1 === l.x2 && l.x1 < x && x - l.x1 < reach && l.y1 < y && l.y2 > y && l.y2 - l.y1 < s * 5)
      && side((l) => l.x1 === l.x2 && l.x1 > x && l.x1 - x < reach && l.y1 < y && l.y2 > y && l.y2 - l.y1 < s * 5)
      && side((l) => l.y1 === l.y2 && l.y1 < y && y - l.y1 < reach && l.x1 < x && l.x2 > x && l.x2 - l.x1 < s * 5)
      && side((l) => l.y1 === l.y2 && l.y1 > y && l.y1 - y < reach && l.x1 < x && l.x2 > x && l.x2 - l.x1 < s * 5);
  };
  const enclosed = (r: TextRun) => marks.some((m) => cx(r) > m.x && cx(r) < m.x + m.w && cy(r) > m.y && cy(r) < m.y + m.h && Math.max(m.w, m.h) < size(r) * 5 && Math.min(m.w, m.h) > size(r) * 0.8) || boxed(r);
  const candidates = runs.filter((r) => !consumed.has(r) && /^\d{1,2}$/.test(r.text.trim()) && notes.has(Number(r.text.trim())) && r.x < colX - 0.005);
  // Outlines decide only when the sheet draws them: a sheet whose bubbles are text alone falls back to
  // the word-beside test below, and its lines stay 'to_confirm'.
  const outlined = candidates.some(enclosed);
  for (const r of runs) {
    if (consumed.has(r)) continue;
    const t = r.text.trim(); if (!/^\d{1,2}$/.test(t)) continue;
    const n = Number(t); if (!notes.has(n) || n > max) continue;
    if (r.x >= colX - 0.005) continue;                                          // the notes column itself
    if (outlined) { if (enclosed(r)) count.set(n, (count.get(n) || 0) + 1); continue; }
    // A number with a word right beside it on its line is a dimension or a size, not a bubble.
    const beside = runs.some((o) => o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.5 && ((o.x > r.x + r.w && o.x - (r.x + r.w) < 0.003) || (o.x + o.w < r.x && r.x - (o.x + o.w) < 0.003)) && !/^\(TYP\)$/i.test(o.text.trim()));
    if (beside) continue;
    count.set(n, (count.get(n) || 0) + 1);
  }
  return [...notes.entries()].sort((a, b) => a[0] - b[0]).map(([n, v]) => ({ n, text: v.text, bubbles: count.get(n) || 0, outlined }));
}

// A keyed note is scope when it tells someone to do or supply something; "EXISTING … TO REMAIN" is not.
// That is REASONED (23 Sep 2026, founder_instruction 886-903; decision point drawing_boq.vocabulary): a verb
// list (PROVIDE, NEW, CAP, VALVE ...) decided it by spotting a word in the note. think() reads
// the notes (_shared/reasoned_intake.ts scopeNotes) and names, by '<sheet>:<n>', the ones that instruct work and
// the ones that remove or demolish. null (held): no keyed-note lines, and the BOQ says so.
export type NoteReading = { scope: Set<string>; demolish: Set<string> } | null;

/** Sizes of duct and pipe printed on the drawing, grouped. Lengths are not printed: qty stays null. */
function sizesOn(p: PdfPage, strip: Box | null, consumed: Consumed) {
  const duct = new Map<string, number>(); const pipe = new Map<string, { n: number; status: Status }>(); const louver = new Map<string, number>();
  for (const r of p.runs) {
    if (inBox(r, strip) || consumed.has(r)) continue;
    const t = r.text.trim().toUpperCase();
    let m = /^(\d{1,2})\s*X\s*(\d{1,2})\s+LOUVER$/.exec(t);
    if (m) { const k = `${m[1]}x${m[2]}`; louver.set(k, (louver.get(k) || 0) + 1); continue; }
    m = /^(\d{1,2})\s*"?\s*X\s*(\d{1,2})"?(\s*\(1"\s*LNR\))?(?:\s+(?:UP|DN|DOWN))?$/.exec(t);
    if (m) { const k = `${m[1]}x${m[2]}${m[3] ? ' (1" liner)' : ''}`; duct.set(k, (duct.get(k) || 0) + 1); continue; }
    m = /^(\d{1,2})\s*"\s*Ø$/.exec(t);
    if (m) { const k = `${m[1]}" round`; duct.set(k, (duct.get(k) || 0) + 1); continue; }
    m = /^(?:\((E|R|N|D)\))?\s*(\d+(?:\s?\d\/\d)?|\d\/\d)"\s*(SS|SAN|V|VENT|W|CW|HW|HWR|TW|G|GAS|ST|RD|CD)$/.exec(t);
    if (m) { const st = statusOf(m[1]); const k = `${m[2]}" ${m[3]}|${st}`; const g = pipe.get(k) || { n: 0, status: st }; g.n++; pipe.set(k, g); }
  }
  return { duct, pipe, louver };
}

// Arabic names of the systems, for the measured length lines (22 Sep 2026; every user-facing string EN + AR).
const SERVICE_AR: Record<string, string> = { SS: 'صرف صحي', V: 'تهوية الصرف', CW: 'مياه باردة', HW: 'مياه ساخنة', HWR: 'راجع المياه الساخنة', G: 'غاز', ST: 'تصريف أمطار', CD: 'تصريف التكثيف', REF: 'تبريد', CHW: 'مياه مبردة', HHW: 'مياه تدفئة', CA: 'هواء مضغوط' };
const SERVICE: Record<string, string> = { SS: 'sanitary sewer (waste)', SAN: 'sanitary sewer (waste)', V: 'vent', VENT: 'vent', W: 'waste', CW: 'domestic cold water', HW: 'domestic hot water', HWR: 'hot water return', TW: 'tempered water', G: 'gas', GAS: 'gas', ST: 'storm', RD: 'roof drain leader', CD: 'condensate drain' };

/** The whole set. `schedules` are OCR tables from the portal: they enrich lines and never make one 'read'. */
export function takeoff(pages: PdfPage[], schedules: ScheduleTable[] = [], reading: NoteReading = null) {
  const index = drawingIndex(pages);
  const abbr = abbreviations(pages);
  const strips = pages.map((p) => titleStrip(p));
  const sheets = pages.map((p, i) => sheetOf(p, i, strips[i], index));
  const lines: TakeoffLine[] = [];
  const nameOf = (type: string) => {
    const a = abbr.get(type);
    const base = EQUIPMENT[type] || FIXTURE[type] || type;
    return a ? a.charAt(0) + a.slice(1).toLowerCase() : base;
  };
  const sched = scheduleRows(schedules);
  const airLetters = [...sched.keys()].filter((k) => /^[A-Z]$/.test(k));

  // ── equipment & terminals: distinct ids across the set; fixtures: per sheet, max over plans ──
  const ids = new Map<string, { type: string; status: Status; sheets: Set<string>; demoOnly: boolean }>();
  const fixtures = new Map<string, { type: string; status: Status; perSheet: Map<string, number>; demo: boolean }>();
  const diffusers = new Map<string, { n: number; necks: Map<string, number>; cfm: number; cfmKnown: number; sheets: Set<string>; inferred: boolean }>();
  const notes: { sheet: Sheet; n: number; text: string; bubbles: number; outlined: boolean }[] = [];
  const measured: { sheet: Sheet; m: Measured }[] = []; const dense: string[] = [];
  const sizes: { sheet: Sheet; duct: Map<string, number>; pipe: Map<string, { n: number; status: Status }>; louver: Map<string, number> }[] = [];
  pages.forEach((p, i) => {
    const sh = sheets[i];
    // Only PLANS are counted. A cover sheet's legend and abbreviation table ("CO2 CARBON DIOXIDE", a
    // legend "A") and a detail sheet's callouts are not items: measured 21 Sep 2026, counting every
    // sheet added a phantom CO-2 and a 13th type-A diffuser from the mechanical cover sheet.
    if (sh.kind !== 'plan' && sh.kind !== 'demolition_plan') { sizes.push({ sheet: sh, duct: new Map(), pipe: new Map(), louver: new Map() }); return; }
    const { hits, diffusers: dfs, consumed } = tagsOnSheet(p, i, strips[i], airLetters);
    const demoSheet = sh.kind === 'demolition_plan';
    for (const h of hits) {
      const k = parseTag(h.tag)!;
      if (k.kind === 'fixture') {
        const status: Status = demoSheet && h.status === 'new' ? 'demolish' : h.status;
        const key = `${h.tag}|${status}`;
        const f = fixtures.get(key) || { type: h.type, status, perSheet: new Map(), demo: demoSheet };
        f.perSheet.set(sh.number, (f.perSheet.get(sh.number) || 0) + 1); fixtures.set(key, f);
      } else {
        const e = ids.get(h.tag) || { type: h.type, status: h.status, sheets: new Set(), demoOnly: true };
        e.sheets.add(sh.number); if (!demoSheet) e.demoOnly = false; if (h.status !== 'new') e.status = h.status; ids.set(h.tag, e);
      }
    }
    for (const d of dfs) {
      const g = diffusers.get(d.letter) || { n: 0, necks: new Map(), cfm: 0, cfmKnown: 0, sheets: new Set(), inferred: false };
      if (d.inferred) g.inferred = true;
      g.n++; if (d.neck) g.necks.set(d.neck, (g.necks.get(d.neck) || 0) + 1); if (/^\d+$/.test(d.cfm)) { g.cfm += Number(d.cfm); g.cfmKnown++; } g.sheets.add(sh.number); diffusers.set(d.letter, g);
    }
    for (const n of keyedNotes(p, strips[i], consumed)) notes.push({ sheet: sh, ...n });
    sizes.push({ sheet: sh, ...sizesOn(p, strips[i], consumed) });
    // Lengths from the CAD layers, new-work plans only (a demolition plan's runs are removals).
    if (!demoSheet && p.layers) {
      if (tooDense(p, strips[i])) { dense.push(sh.number); return; }
      const sc = scaleLabels(p, strips[i]);
      for (const m of [...measurePipes(p, strips[i], sc), ...measureDucts(p, strips[i], sc)]) measured.push({ sheet: sh, m });
    }
  });

  const specFor = (tag: string) => sched.get(tag.toUpperCase());
  for (const [tag, e] of [...ids.entries()].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))) {
    const status: Status = e.demoOnly ? 'demolish' : e.status;
    if (status === 'existing') continue;                                       // existing to remain is not scope
    const spec = specFor(tag);
    const what = e.type === 'VAV' ? (tag.endsWith('-H') ? 'VAV terminal unit with electric reheat' : 'VAV terminal unit') : nameOf(e.type);
    lines.push({
      section: status === 'demolish' ? 'Demolition' : e.type === 'VAV' ? 'HVAC terminal units' : 'Equipment', type: `tag:${tag}`, status,
      item: `${tag} ${what}`, description: `${tag} — ${what}${spec ? ` — ${spec}` : ''}${status === 'relocate' ? ' (relocate)' : ''}`,
      qty: 1, unit: 'nos', qty_status: 'read', confidence: 'medium', sheets: [...e.sheets],
      basis: `tag ${tag} printed on ${[...e.sheets].join(', ')}; one unit per tag id${spec ? '; make/model from the schedule read by OCR — to confirm' : ''}`,
    });
  }
  // A VAV tag and its "-H" twin are the same box drawn with its reheat coil: keep one line per box.
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i]; if (!l.type.endsWith('-H')) continue;
    const base = lines.find((o) => o.type === l.type.slice(0, -2));
    if (base) { base.description = base.description.replace('VAV terminal unit', 'VAV terminal unit with electric reheat'); base.item = base.item.replace('VAV terminal unit', 'VAV terminal unit with electric reheat'); base.basis += `; reheat tag ${l.type.slice(4)} beside it`; lines.splice(i, 1); }
  }
  for (const [key, f] of [...fixtures.entries()].sort()) {
    if (f.status === 'existing') continue;                                     // (E) existing to remain is not scope
    const tag = key.split('|')[0];
    const per = [...f.perSheet.entries()];
    const qty = Math.max(...per.map(([, n]) => n));
    const spec = specFor(tag.replace(/^\((E|R|N|D)\)/, ''));
    const verb = f.status === 'demolish' ? 'remove' : f.status === 'relocate' ? 'relocate / reuse' : '';
    lines.push({
      section: f.status === 'demolish' ? 'Demolition' : 'Plumbing fixtures', type: `tag:${tag}:${f.status}`, status: f.status,
      item: `${tag} ${nameOf(f.type)}`, description: `${tag} — ${nameOf(f.type)}${spec ? ` — ${spec}` : ''}${verb ? ` (${verb})` : ''}`,
      qty, unit: 'nos', qty_status: 'read', confidence: 'medium', sheets: per.map(([s]) => s),
      basis: `tag ${tag} drawn ${per.map(([s, n]) => `${n}x on ${s}`).join(', ')}; the same fixture appears on each system's plan, so the count is the largest on one sheet, not the sum`,
    });
  }
  for (const [letter, g] of [...diffusers.entries()].sort()) {
    const spec = specFor(letter);
    const necks = [...g.necks.entries()].sort((a, b) => b[1] - a[1]).map(([k, n]) => `${n}x ${k}`).join(', ');
    lines.push({
      section: 'Air devices', type: `air_device:${letter}`, status: 'new',
      item: `Air device type ${letter}`, description: `Air device type ${letter}${spec ? ` — ${spec}` : ''}${necks ? ` (necks ${necks})` : ''}`,
      ...(g.inferred && !spec ? { qty: g.n, estimate: g.n, qty_status: 'to_confirm' as const, confidence: 'low' as const } : { qty: g.n, qty_status: 'read' as const, confidence: 'medium' as const }),
      unit: 'nos', sheets: [...g.sheets],
      basis: g.inferred && !spec
        ? `${g.n} "${letter}" tag(s) on ${[...g.sheets].join(', ')} drawn like the other air-device tags; "${letter}" continues the A.. series and no schedule row confirms it — to confirm`
        : `each "${letter}" tag counted on ${[...g.sheets].join(', ')}; ${g.cfmKnown ? `${g.cfm} cfm total over ${g.cfmKnown} devices` : 'airflow not stated'}`,
    });
  }
  // Louvers: size + word on the plan; read.
  const louv = new Map<string, number>();
  for (const s of sizes) for (const [k, n] of s.louver) louv.set(k, Math.max(louv.get(k) || 0, n));
  for (const [k, n] of louv) lines.push({ section: 'Equipment', type: `louver:${k}`, status: 'new', item: `Louver ${k}`, description: `Louver ${k} in`, qty: n, unit: 'nos', qty_status: 'read', confidence: 'medium', sheets: sizes.filter((s) => s.louver.has(k)).map((s) => s.sheet.number), basis: `"${k} LOUVER" printed on the plan` });
  // Keyed notes that are scope: our bubble count, to confirm.
  // A note no bubble points at is a general note, not a counted item. The same demolition drawn on the
  // waste plan AND the water plan ("DEMO AND REMOVE EXISTING LAV" on P-1.00 and P-2.00, measured
  // 21 Sep 2026) is one lavatory removed, so notes with the same first sentence merge at the larger count.
  const byItem = new Map<string, TakeoffLine>();
  for (const n of notes) {
    const nk = `${n.sheet.number}:${n.n}`;
    if (!n.bubbles || !reading || !reading.scope.has(nk)) continue;
    const demo = n.sheet.kind === 'demolition_plan' || reading.demolish.has(nk);
    const first = n.text.split(/(?<=\.)\s+/)[0];
    const key = (demo ? 'demo|' : 'note|') + first.toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();
    const prev = byItem.get(key);
    // Only the SAME note on ANOTHER sheet merges. Measured 22 Sep 2026: on M1.0 notes 7 and 8 share their
    // first sentence ("4"Ø RADIANT TUBE HEATER AIR VENT.") but one ends at a sidewall and one at a roof
    // gooseneck, and notes 1 and 2 are two intakes for two fans; merging them lost an item each.
    if (prev && !prev.sheets.includes(n.sheet.number)) {
      prev.sheets.push(n.sheet.number);
      prev.basis += `; also keyed note ${n.n} on ${n.sheet.number} (${n.bubbles} bubble(s))`;
      if (n.bubbles > (prev.qty || 0)) { prev.qty = n.bubbles; if (prev.qty_status === 'to_confirm') prev.estimate = n.bubbles; }
      continue;
    }
    const line: TakeoffLine = {
      section: demo ? 'Demolition' : 'Keyed notes', type: `note:${n.sheet.number}:${n.n}`, status: demo ? 'demolish' : 'new',
      item: clip(first, 120), description: clip(n.text, 240),
      // An outlined bubble is printed on the drawing, so its count is read, one location per bubble.
      ...(n.outlined
        ? { qty: n.bubbles, unit: 'nos', qty_status: 'read' as const, confidence: 'medium' as const, basis: `keyed note ${n.n} on ${n.sheet.number}; ${n.bubbles} bubble(s) numbered ${n.n} drawn on the sheet, one per location` }
        : { qty: n.bubbles, estimate: n.bubbles, unit: 'nos', qty_status: 'to_confirm' as const, confidence: 'low' as const, basis: `keyed note ${n.n} on ${n.sheet.number}; ${n.bubbles} bubble(s) numbered ${n.n} counted on the sheet — our count, to confirm` }),
      sheets: [n.sheet.number],
    };
    byItem.set(key, line); lines.push(line);
  }
  // Duct and pipe: sizes read, lengths to be measured at the sheet's scale.
  const ductAll = new Map<string, { n: number; sheets: Set<string>; scale: string }>();
  const pipeAll = new Map<string, { n: number; sheets: Set<string>; scale: string; status: Status }>();
  for (const s of sizes) {
    for (const [k, n] of s.duct) { const g = ductAll.get(k) || { n: 0, sheets: new Set(), scale: s.sheet.scale }; g.n += n; g.sheets.add(s.sheet.number); ductAll.set(k, g); }
    for (const [k, v] of s.pipe) { const g = pipeAll.get(k) || { n: 0, sheets: new Set(), scale: s.sheet.scale, status: v.status }; g.n += v.n; g.sheets.add(s.sheet.number); pipeAll.set(k, g); }
  }
  // Lengths measured from the CAD layers replace the "to be measured" lines for what they cover.
  const measuredDuct = measured.some((x) => x.m.kind === 'duct');
  const lengthLines = lengthLinesOf(measured);
  const agg = new Set(lengthLines.map((l) => l.type));
  lines.push(...lengthLines);
  if (ductAll.size && !measuredDuct) {
    const ks = [...ductAll.keys()].sort((a, b) => a.localeCompare(b, 'en', { numeric: true }));
    const rect = ks.filter((k) => /x/.test(k)), round = ks.filter((k) => /round/.test(k));
    const sc = [...new Set([...ductAll.values()].map((g) => g.scale).filter(Boolean))].join(', ');
    const sh = [...new Set([...ductAll.values()].flatMap((g) => [...g.sheets]))].join(', ');
    if (rect.length) lines.push({ section: 'Ductwork', type: 'duct:rectangular', status: 'new', item: 'Rectangular ductwork', description: `Rectangular ductwork, sizes ${rect.join(', ')}`, qty: null, unit: 'm', confidence: 'low', sheets: sh.split(', '), basis: `sizes printed on ${sh}; lengths are not printed — to be measured from the plan at ${sc || 'the printed scale'}` });
    if (round.length) lines.push({ section: 'Ductwork', type: 'duct:round', status: 'new', item: 'Round ductwork', description: `Round ductwork, sizes ${round.join(', ')}`, qty: null, unit: 'm', confidence: 'low', sheets: sh.split(', '), basis: `sizes printed on ${sh}; lengths are not printed — to be measured at ${sc || 'the printed scale'}` });
  }
  for (const [k, g] of [...pipeAll.entries()].sort()) {
    if (g.status !== 'new' || agg.has('pipe:' + k.split('|')[0])) continue;     // existing pipe is not scope; a measured size has its line
    const [sz, svc] = k.split('|')[0].split(' ');
    lines.push({ section: 'Piping', type: `pipe:${k.split('|')[0]}`, status: 'new', item: `${sz} ${SERVICE[svc] || svc} pipe`, description: `${sz} ${SERVICE[svc] || svc} piping, new`, qty: null, unit: 'm', confidence: 'low', sheets: [...g.sheets], basis: `"${k.split('|')[0]}" labelled ${g.n}x on ${[...g.sheets].join(', ')}; length is not printed — to be measured at ${g.scale || 'the printed scale'}` });
  }
  // Schedule rows that no plan tag matched: OCR-only, so the quantity is ours to confirm.
  const tagged = new Set(lines.map((l) => l.type.replace(/^tag:|^air_device:/, '').split(':')[0].toUpperCase()));
  for (const [tag, spec] of sched) {
    if (tagged.has(tag)) continue;
    const t = parseTag(tag); if (!t && !/^[A-Z]$/.test(tag)) continue;
    lines.push({ section: 'From the schedule (not found on a plan)', type: `sched:${tag}`, status: 'new', item: `${tag} ${t ? nameOf(t.type) : 'air device'}`, description: `${tag} — ${spec}`, qty: 1, estimate: 1, unit: 'nos', qty_status: 'to_confirm', confidence: 'low', sheets: [], basis: 'row of a schedule read by OCR; no plan tag carries it — quantity and model to confirm' });
  }
  // The keyed notes a bubble points at, for the reasoning (drawingSetNotes): '<sheet>:<n>' and the note's words.
  const keyed = notes.filter((n) => n.bubbles).map((n) => ({ key: `${n.sheet.number}:${n.n}`, text: n.text }));
  return { sheets, lines, strips, dense, keyed };
}

/** Measured runs -> BOQ lines, one per system and size across the set. */
function lengthLinesOf(measured: { sheet: Sheet; m: Measured }[]): TakeoffLine[] {
  const out: TakeoffLine[] = [];
  const agg = new Map<string, { m: Measured; sheets: Set<string>; realIn: number; single: number }>();
  for (const { sheet, m } of measured) {
    const k = `${m.kind}:${m.key}`;
    const g = agg.get(k) || { m, sheets: new Set<string>(), realIn: 0, single: 0 };
    g.realIn += m.realIn; g.single += m.single || 0; g.sheets.add(sheet.number); agg.set(k, g);
  }
  for (const [k, g] of [...agg.entries()].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))) {
    const m = g.m, sh = [...g.sheets], qty = metres(g.realIn);
    if (qty < 0.3) continue;                                                    // under a foot: a fitting edge, not a run
    const layers = [...m.layers].join(', ');
    const where = `measured along layer ${layers} on ${sh.join(', ')} at ${m.scale}: ${feet(g.realIn)} ft (${qty} m) in plan; risers and drops are not in plan and are not included`;
    if (m.kind === 'pipe') {
      const [sz, svc] = m.labelled ? m.key.split(' ') : ['', m.svc];
      const what = `${sz ? sz + ' ' : ''}${SERVICE[svc] || svc} pipe`;
      out.push({ section: 'Piping', section_ar: 'الأنابيب', type: `pipe:${m.key}`, status: 'new', item: what, description: `${what}, new${m.labelled ? '' : ' (size not labelled on the plan)'}`,
        description_ar: `أنابيب ${SERVICE_AR[svc] || svc}${sz ? ' مقاس ' + sz : ''}، جديدة${m.labelled ? '' : ' (المقاس غير مكتوب على المخطط)'}`,
        qty, unit: 'm', ...(m.labelled ? { qty_status: 'read' as const, confidence: 'medium' as const } : { estimate: qty, qty_status: 'to_confirm' as const, confidence: 'low' as const }), sheets: sh, basis: where });
    } else {
      // A duct stretch is 'read' when both walls are drawn and the gap matches a printed size; a
      // single-line run takes its size from the nearest label, so that length is ours to confirm.
      const sure = m.labelled && g.single === 0;
      const what = m.labelled ? (/round/.test(m.key) ? `Round ductwork ${m.key.replace(' round', ' dia')}` : `Rectangular ductwork ${m.key}`) : `Ductwork, ${m.key}`;
      const whatAr = m.labelled ? (/round/.test(m.key) ? `مجاري هواء دائرية قطر ${m.key.replace(' round', '')}` : `مجاري هواء مستطيلة ${m.key.replace(' (1" liner)', ' (بطانة 1 إنش)')}`) : `مجاري هواء، ${m.key.replace(' wide (size not labelled)', ' عرض (المقاس غير مكتوب)').replace('single-line duct (size not labelled)', 'خط مفرد (المقاس غير مكتوب)')}`;
      out.push({ section: 'Ductwork', section_ar: 'مجاري الهواء', type: `duct:${m.key}`, status: 'new', item: what, description: what, description_ar: whatAr, qty, unit: 'm',
        ...(sure ? { qty_status: 'read' as const, confidence: 'medium' as const } : { estimate: qty, qty_status: 'to_confirm' as const, confidence: 'low' as const }), sheets: sh,
        basis: `${where}${g.single ? `; ${feet(g.single)} ft of it is drawn single-line and sized from the nearest label — to confirm` : ''}${m.labelled ? '' : '; no printed size matches this width — to confirm'}` });
    }
  }
  return out;
}

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

const HVAC_TYPES = new Set(Object.keys(EQUIPMENT));
const MISSING_ALWAYS = [
  'Symbols drawn without a tag (an untagged grille, a valve symbol) are not counted; only tags, keyed-note bubbles and labelled sizes are.',
];

/** drawing_boq's response shape for a PDF drawing set: the take-off when it finds anything, with every
 *  string scrubbed of the title strip's names and of any contact detail. `null` = nothing drawn to count. */
/** The keyed notes of a set, for the reasoning to read (scopeNotes) before the take-off counts them. */
export function drawingSetNotes(pages: PdfPage[]): { key: string; text: string }[] { return takeoff(pages).keyed; }

export function boqFromDrawingSet(pages: PdfPage[], hint = '', schedules: ScheduleTable[] = [], reading: NoteReading = null) {
  const t = takeoff(pages, schedules, reading);
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
  if (!reading && t.keyed.length) missing.push(`The drawing's ${t.keyed.length} keyed note(s) were not turned into lines this time: which of them are work to be done is read by the sales engineer, and that reading was not available. Describe that work, or it is asked.`);
  if (boq.some((l) => l.qty_status === 'to_confirm')) missing.push('Lines marked "to confirm" are our own count (keyed-note bubbles, a letter continuing a series, or a schedule read by OCR); they are shown to you to confirm before suppliers price them.');
  return {
    drawing_type: plans.length ? `${plans.length} plan sheet(s): ${plans.map((s) => `${s.number} ${s.title}`).join('; ')}`.slice(0, 200) : 'drawing set',
    category: hvac >= plumb ? (hvac ? 'mep_hvac' : '') : 'mep_plumbing',
    summary: scrubIdentity(redactText(hint, seeds).text.replace(/█/g, '')).slice(0, 200),
    scale_detected: scales.join(', '),
    total_area_sqm: null as number | null, area_tags_sqm: [] as number[],
    boq, keywords: [...new Set(boq.map((l) => l.section.toLowerCase()))].slice(0, 10), assumptions: [
      'Counted from the drawing set\'s own text: one unit per equipment tag id; fixtures at their largest count on one plan (the same fixture is drawn on each system\'s plan); air devices by their tag letters.',
    ], missing_info: missing, confidence: 'low' as const, method: 'drawing_set', pages_read: pages.length,
    sheets: t.sheets.map((s) => ({ number: s.number, title: clean(s.title), scale: s.scale, kind: s.kind })),
  };
}

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
  const keep = set.boq.filter((l) => !(l.qty === null && ((anyDuct && (l.type === 'duct:rectangular' || l.type === 'duct:round')) || (l.type.startsWith('pipe:') && got.has(l.type)))));
  const still = keep.some((l) => /^(duct|pipe):/.test(l.type) && l.qty === null);
  return { ...set, boq: [...keep, ...lengths.lines], missing_info: [still ? NO_LENGTHS_NOTE : PLAN_LENGTHS_NOTE, ...(lengths.dense.length ? [DENSE_NOTE(lengths.dense.join(', '), MAX_MEASURED_LINES.toLocaleString('en'))] : []), ...missing] };
}

/** Tag counts that must survive redaction: identical on the original and on what the supplier sees. */
export function tagCounts(pages: PdfPage[], keep: (pageIndex: number, r: TextRun) => boolean = () => true): Record<string, number> {
  const out: Record<string, number> = {};
  pages.forEach((p, i) => {
    const strip = titleStrip(p);
    const q = { ...p, runs: p.runs.filter((r) => keep(i, r)) };
    const { hits, diffusers } = tagsOnSheet(q, i, strip);
    for (const h of hits) out[h.tag] = (out[h.tag] || 0) + 1;
    for (const d of diffusers) out['air:' + d.letter] = (out['air:' + d.letter] || 0) + 1;
  });
  return out;
}
