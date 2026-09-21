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
//    sheet carrying that number. The bubble count is OUR count, so the line is 'to_confirm'.
//  * SIZES — duct sizes (28x20, 1" liner) and pipe sizes and services (3" SS, 2" V, (E)4" SS). Their
//    lengths are not printed and are not measured here: the line says so and asks for measurement.
//  * SCHEDULES — rows read by OCR in the customer's browser (ocrClient.ocrSchedules, cell by cell)
//    enrich the tag lines with make/model. Anything taken from OCR is 'to_confirm', never 'read'.
//
// WHAT IT NEVER DOES: invent a quantity. A line is 'read' only when every unit of it is a tag printed
// on the drawing; everything else is 'to_confirm' (our count from bubbles or OCR) or has qty null
// (a length that must be measured). No title-block text ever becomes a line (the title-block strip is
// excluded before anything is read — see _shared/anonymise.ts titleStrip).
import type { PdfPage, TextRun } from '../_shared/pdf_text_positions.ts';
import { redactText, stripSeeds, titleStrip, type Box } from '../_shared/anonymise.ts';
import { scrubIdentity } from './boq_from_text.ts';

export type ScheduleTable = { page: number; bbox?: Box; rows: string[][]; conf?: number[][] };
export type SheetKind = 'plan' | 'demolition_plan' | 'schedule' | 'other';
export type Sheet = { page: number; number: string; title: string; scale: string; kind: SheetKind };
export type Status = 'new' | 'existing' | 'relocate' | 'demolish';
export type TakeoffLine = {
  section: string; item: string; description: string; qty: number | null; unit: string; basis: string;
  confidence: 'low' | 'medium'; qty_status?: 'read' | 'to_confirm'; estimate?: number | null; type: string;
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
export function keyedNotes(p: PdfPage, strip: Box | null, consumed: Consumed): { n: number; text: string; bubbles: number }[] {
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
  for (const r of runs) {
    if (consumed.has(r)) continue;
    const t = r.text.trim(); if (!/^\d{1,2}$/.test(t)) continue;
    const n = Number(t); if (!notes.has(n) || n > max) continue;
    if (r.x >= colX - 0.005) continue;                                          // the notes column itself
    // A number with a word right beside it on its line is a dimension or a size, not a bubble.
    const beside = runs.some((o) => o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.5 && ((o.x > r.x + r.w && o.x - (r.x + r.w) < 0.003) || (o.x + o.w < r.x && r.x - (o.x + o.w) < 0.003)) && !/^\(TYP\)$/i.test(o.text.trim()));
    if (beside) continue;
    count.set(n, (count.get(n) || 0) + 1);
  }
  return [...notes.entries()].sort((a, b) => a[0] - b[0]).map(([n, v]) => ({ n, text: v.text, bubbles: count.get(n) || 0 }));
}

// A keyed note is scope when it tells someone to do or supply something; "EXISTING … TO REMAIN" is not.
const SCOPE_NOTE = /\b(PROVIDE|INSTALL|REMOVE|DEMO(?:LISH)?|RELOCATE|REPLACE|CONNECT|ROUTE|FURNISH|EXTEND|CAP|NEW|TERMINATION|LOUVER|DAMPER|VALVE|MAN\s+BARS?|GOOSENECK|SOLENOID|FLUSH\s+VALVE)\b/;
const NOT_SCOPE = /\bTO REMAIN\b|\bCONTINUED\b|\bFIELD VERIFY\b(?!.*\bPROVIDE\b)/;

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

const SERVICE: Record<string, string> = { SS: 'sanitary sewer (waste)', SAN: 'sanitary sewer (waste)', V: 'vent', VENT: 'vent', W: 'waste', CW: 'domestic cold water', HW: 'domestic hot water', HWR: 'hot water return', TW: 'tempered water', G: 'gas', GAS: 'gas', ST: 'storm', RD: 'roof drain leader', CD: 'condensate drain' };

/** The whole set. `schedules` are OCR tables from the portal: they enrich lines and never make one 'read'. */
export function takeoff(pages: PdfPage[], schedules: ScheduleTable[] = []) {
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
  const notes: { sheet: Sheet; n: number; text: string; bubbles: number }[] = [];
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
    if (!n.bubbles || !SCOPE_NOTE.test(n.text) || NOT_SCOPE.test(n.text)) continue;
    const demo = n.sheet.kind === 'demolition_plan' || /^\s*(DEMO|REMOVE)\b/.test(n.text);
    const first = n.text.split(/(?<=\.)\s+/)[0];
    const key = (demo ? 'demo|' : 'note|') + first.toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();
    const prev = byItem.get(key);
    if (prev) {
      prev.sheets.push(n.sheet.number);
      prev.basis += `; also keyed note ${n.n} on ${n.sheet.number} (${n.bubbles} bubble(s))`;
      if (n.bubbles > (prev.qty || 0)) { prev.qty = n.bubbles; prev.estimate = n.bubbles; }
      continue;
    }
    const line: TakeoffLine = {
      section: demo ? 'Demolition' : 'Keyed notes', type: `note:${n.sheet.number}:${n.n}`, status: demo ? 'demolish' : 'new',
      item: clip(first, 120), description: clip(n.text, 240),
      qty: n.bubbles, estimate: n.bubbles, unit: 'nos', qty_status: 'to_confirm', confidence: 'low', sheets: [n.sheet.number],
      basis: `keyed note ${n.n} on ${n.sheet.number}; ${n.bubbles} bubble(s) numbered ${n.n} counted on the sheet — our count, to confirm`,
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
  if (ductAll.size) {
    const ks = [...ductAll.keys()].sort((a, b) => a.localeCompare(b, 'en', { numeric: true }));
    const rect = ks.filter((k) => /x/.test(k)), round = ks.filter((k) => /round/.test(k));
    const sc = [...new Set([...ductAll.values()].map((g) => g.scale).filter(Boolean))].join(', ');
    const sh = [...new Set([...ductAll.values()].flatMap((g) => [...g.sheets]))].join(', ');
    if (rect.length) lines.push({ section: 'Ductwork', type: 'duct:rectangular', status: 'new', item: 'Rectangular ductwork', description: `Rectangular ductwork, sizes ${rect.join(', ')}`, qty: null, unit: 'm', confidence: 'low', sheets: sh.split(', '), basis: `sizes printed on ${sh}; lengths are not printed — to be measured from the plan at ${sc || 'the printed scale'}` });
    if (round.length) lines.push({ section: 'Ductwork', type: 'duct:round', status: 'new', item: 'Round ductwork', description: `Round ductwork, sizes ${round.join(', ')}`, qty: null, unit: 'm', confidence: 'low', sheets: sh.split(', '), basis: `sizes printed on ${sh}; lengths are not printed — to be measured at ${sc || 'the printed scale'}` });
  }
  for (const [k, g] of [...pipeAll.entries()].sort()) {
    if (g.status !== 'new') continue;                                           // existing pipe is not scope
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
  return { sheets, lines, strips };
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
  'Duct and pipe LENGTHS are not printed on the drawing and were not measured: those lines carry the sizes and ask for the length at the printed scale.',
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
    ], missing_info: missing, confidence: 'low' as const, method: 'drawing_set', pages_read: pages.length,
    sheets: t.sheets.map((s) => ({ number: s.number, title: clean(s.title), scale: s.scale, kind: s.kind })),
  };
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
