// zz_demo_drawings.fixtures — ONE synthetic ZZ DEMO job drawn in every format a customer sends, with its
// true counts known by construction and its identity planted everywhere a real drawing carries it
// (24 Sep 2026, sales_engineer; founder instructions 31, 32, 580, 701, 703). Pure, no I/O, nothing real:
// every name is "ZZ DEMO", every address @example.invalid, every phone a reserved 5000000xx number.
//
// THE JOB. A ground-floor power and fire-alarm layout: three rooms (OFFICE 101, MEETING ROOM 102,
// STORE 103), two dimensions (6000, 4000), a legend, a note, and TAGGED ELEMENTS whose true count is:
//   CAD (DXF / binary DXF / DWG): block SD (smoke detector) x 7, block SKT (double socket) x 5 — plus one
//     SD and one SKT drawn as LEGEND samples, which an estimator does not count;
//   PDF (vector, single sheet and 3-sheet set): floor drains FD-1 x 7, water closets WC-1 x 5, and fan
//     coil units FCU-1 / FCU-2 / FCU-3 once each;
//   image: 7 red smoke-detector symbols and 3 blue manual call points, with their legend.
// THE IDENTITY, planted in the title block (as text, as ATTRIBs of a title-block INSERT, as the PDF's
// /Info metadata, as a DWG header variable, in paper space, in the file NAME) and OUTSIDE it (a contact
// line with an e-mail and a phone, a "CONSULTANT:" label with the firm beside it). Every string in
// IDENTITY must be gone from anything a supplier receives; every string in CONTENT must survive.
import { dxfBinaryFrom, dxfFrom, dxfSection } from './cad.fixtures.ts';
import type { DwgDb } from './dwg.ts';
import { textStrokes } from '../stroke_font.ts';

export const IDENTITY = ['ZZ DEMO', 'Rashid', 'Kareem', 'Harbour', 'ORBIT', 'ZZ-2026-0142', 'example.invalid', '0000017', '000 0017', 'Drafter', 'zz.site', 'zz.orbit'];
export const CONTENT = ['OFFICE 101', 'MEETING ROOM 102', 'STORE 103', '6000', '4000', 'LEGEND', 'SD - SMOKE DETECTOR', 'SKT - DOUBLE SOCKET OUTLET', 'NOTE: ALL SOCKETS AT 300 AFFL'];
/** The customer's own seed terms, as customer_api builds them (name, e-mail, phone, file name). */
export const CUSTOMER = { name: 'ZZ DEMO Rashid Kareem', email: 'rashid.kareem@zzdemo.example.invalid', phone: '+971500000017' };
export const FILE_NAME = 'ZZ DEMO Harbour Tower E-101 ZZ-2026-0142';
export const CAD_COUNTS = { SD: 7, SKT: 5 };
export const PDF_COUNTS = { 'FD-1': 7, 'WC-1': 5, FCU: 3 };
export const IMAGE_COUNTS = { smoke_detector: 7, manual_call_point: 3 };

type P = [number, string | number][];
const line = (layer: string, x1: number, y1: number, x2: number, y2: number): P => [[0, 'LINE'], [8, layer], [10, x1], [20, y1], [30, 0], [11, x2], [21, y2], [31, 0]];
const rect = (layer: string, x: number, y: number, w: number, h: number): P => [[0, 'LWPOLYLINE'], [8, layer], [90, 4], [70, 1], [10, x], [20, y], [10, x + w], [20, y], [10, x + w], [20, y + h], [10, x], [20, y + h]];
const text = (layer: string, x: number, y: number, h: number, s: string, center = false): P => center
  ? [[0, 'TEXT'], [8, layer], [10, x], [20, y], [30, 0], [40, h], [1, s], [72, 1], [11, x], [21, y], [31, 0]]
  : [[0, 'TEXT'], [8, layer], [10, x], [20, y], [30, 0], [40, h], [1, s]];
const insert = (layer: string, name: string, x: number, y: number): P => [[0, 'INSERT'], [8, layer], [2, name], [10, x], [20, y], [30, 0]];
const attrib = (tag: string, x: number, y: number, s: string): P => [[0, 'ATTRIB'], [8, 'ZZ-TITLE'], [10, x], [20, y], [30, 0], [40, 180], [1, s], [2, tag], [70, 0]];

const SD_AT: [number, number][] = [[1000, 1000], [3000, 700], [5000, 1000], [1000, 3200], [5000, 3200], [7000, 1000], [9000, 3200]];
const SKT_AT: [number, number][] = [[200, 500], [5800, 500], [6200, 3600], [9800, 3600], [11000, 300]];

/** The DXF, as group-code pairs (so the same drawing can be written ASCII or binary). */
export function zzDxfPairs(): P {
  const blocks: P = [
    [0, 'BLOCK'], [8, '0'], [2, 'SD'], [70, 0], [10, 0], [20, 0], [30, 0],
    [0, 'CIRCLE'], [8, '0'], [10, 0], [20, 0], [30, 0], [40, 150],
    ...text('0', 0, 0, 90, 'SD', true), [0, 'ENDBLK'], [8, '0'],
    [0, 'BLOCK'], [8, '0'], [2, 'SKT'], [70, 0], [10, 0], [20, 0], [30, 0],
    ...rect('0', -100, -50, 200, 100), ...line('0', -100, 0, 100, 0), [0, 'ENDBLK'], [8, '0'],
    // The consultant's title block: a frame, a logo image, the firm, its contacts, the sheet's own words.
    [0, 'BLOCK'], [8, '0'], [2, 'ZZ_TITLEBLOCK_A1'], [70, 2], [10, 0], [20, 0], [30, 0],
    ...rect('0', 0, 0, 3000, 7500),
    ...text('0', 150, 7100, 180, 'ZZ DEMO ORBIT CONSULTING ENGINEERS LLC'),
    ...text('0', 150, 6800, 150, 'TEL +971 4 000 0017'),
    ...text('0', 150, 6550, 150, 'zz.orbit@example.invalid'),
    ...text('0', 150, 1200, 150, 'SCALE 1:100'),
    ...text('0', 150, 900, 150, 'GROUND FLOOR POWER AND FIRE ALARM LAYOUT'),
    [0, 'ENDBLK'], [8, '0'],
    // The sheet frame: its lines are the page border, its words are a plot stamp.
    [0, 'BLOCK'], [8, '0'], [2, 'BORDER_A1'], [70, 0], [10, 0], [20, 0], [30, 0],
    ...rect('0', 0, 0, 17500, 8500), ...text('0', 100, 100, 120, 'PLOTTED FOR ZZ DEMO HARBOUR TOWER'), [0, 'ENDBLK'], [8, '0'],
    // A dimension's own block, the way AutoCAD writes one.
    [0, 'BLOCK'], [8, '0'], [2, '*D1'], [70, 1], [10, 0], [20, 0], [30, 0],
    ...line('0', 0, -600, 6000, -600), ...line('0', 0, -450, 0, -750), ...line('0', 6000, -450, 6000, -750),
    [0, 'MTEXT'], [8, '0'], [10, 3000], [20, -450], [30, 0], [40, 200], [71, 8], [1, '6000'],
    [0, 'ENDBLK'], [8, '0'],
  ];
  const ents: P = [
    ...rect('A-WALL', 0, 0, 6000, 4000), ...rect('A-WALL', 6000, 0, 4000, 4000), ...rect('A-WALL', 10000, 0, 2000, 4000),
    ...text('A-ANNO', 3000, 2000, 250, 'OFFICE 101', true), ...text('A-ANNO', 8000, 2000, 250, 'MEETING ROOM 102', true), ...text('A-ANNO', 11000, 2000, 200, 'STORE 103', true),
    [0, 'DIMENSION'], [8, 'A-DIMS'], [2, '*D1'], [10, 6000], [20, -600], [30, 0], [11, 3000], [21, -450], [31, 0], [70, 32], [1, ''], [42, 6000],
    [0, 'DIMENSION'], [8, 'A-DIMS'], [10, -700], [20, 0], [30, 0], [11, -700], [21, 2000], [31, 0], [70, 32], [1, '4000'], [53, 90],
    ...SD_AT.flatMap(([x, y]) => insert('E-FIRE', 'SD', x, y)),
    ...SKT_AT.flatMap(([x, y]) => insert('E-POWR', 'SKT', x, y)),
    // The legend: a sample of each symbol beside its description. Not work anyone prices twice.
    ...text('A-ANNO', 0, -1500, 200, 'LEGEND'),
    ...insert('E-FIRE', 'SD', 200, -1900), ...text('A-ANNO', 600, -1980, 160, 'SD - SMOKE DETECTOR'),
    ...insert('E-POWR', 'SKT', 200, -2300), ...text('A-ANNO', 600, -2380, 160, 'SKT - DOUBLE SOCKET OUTLET'),
    ...text('A-ANNO', 6000, -1500, 160, 'NOTE: ALL SOCKETS AT 300 AFFL'),
    // Identity OUTSIDE the title block: a contact line, and a label with the firm on the same line.
    ...text('A-ANNO', 0, -2800, 150, 'SITE CONTACT zz.site@example.invalid +971 50 000 0017'),
    ...text('A-ANNO', 6000, -2800, 150, 'CONSULTANT:'), ...text('A-ANNO', 7600, -2800, 150, 'ZZ DEMO ORBIT'),
    // The title block, with the project's parties as attributes.
    ...insert('ZZ-TITLE', 'ZZ_TITLEBLOCK_A1', 12500, -3000), [66, 1],
    ...attrib('CLIENT', 12650, 3900, 'ZZ DEMO Rashid Kareem'), ...attrib('PROJECT', 12650, 3500, 'ZZ DEMO Harbour Tower'),
    ...attrib('DWG_NO', 12650, 3100, 'ZZ-2026-0142'), ...attrib('DRAWN_BY', 12650, 2700, 'ZZ Demo Drafter'),
    [0, 'SEQEND'], [8, 'ZZ-TITLE'],
    ...insert('0', 'BORDER_A1', -1500, -3500),
    // A logo pasted as an image, and a sheet layout in paper space.
    [0, 'IMAGE'], [8, 'ZZ-LOGO'], [10, 12600], [20, 4000], [30, 0],
    [0, 'TEXT'], [8, 'A-ANNO'], [67, 1], [10, 0], [20, 0], [30, 0], [40, 300], [1, 'ZZ DEMO SHEET LAYOUT HARBOUR TOWER'],
  ];
  return [
    ...dxfSection('HEADER', [[9, '$ACADVER'], [1, 'AC1027'], [9, '$INSUNITS'], [70, 4], [9, '$PROJECTNAME'], [1, 'ZZ DEMO Harbour Tower'], [9, '$LASTSAVEDBY'], [1, 'ZZ Demo Drafter']]),
    ...dxfSection('BLOCKS', blocks),
    ...dxfSection('ENTITIES', ents),
    [0, 'EOF'],
  ];
}
export const zzDxf = (): Uint8Array => dxfFrom(zzDxfPairs());
export const zzDxfBinary = (): Uint8Array => dxfBinaryFrom(zzDxfPairs());

/** The same drawing as LibreDWG's JSON (the shape @mlightcad/libredwg-web 0.7.14 returns: radians, flag 512
 *  = closed, model and paper space together in `entities`, a title INSERT's ATTRIBs listed after it). */
export function zzDwgDb(): DwgDb {
  const pt = (x: number, y: number) => ({ x, y, z: 0 });
  const room = (x: number, y: number, w: number, h: number) => ({ type: 'LWPOLYLINE', layer: 'A-WALL', flag: 512, vertices: [{ x, y, bulge: 0 }, { x: x + w, y, bulge: 0 }, { x: x + w, y: y + h, bulge: 0 }, { x, y: y + h, bulge: 0 }] });
  const txt = (layer: string, x: number, y: number, h: number, s: string, extra: Record<string, unknown> = {}) => ({ type: 'TEXT', layer, text: s, startPoint: pt(x, y), textHeight: h, rotation: 0, ...extra });
  const ins = (layer: string, name: string, x: number, y: number, attribs: unknown[] = []) => ({ type: 'INSERT', layer, name, insertionPoint: pt(x, y), xScale: 1, yScale: 1, rotation: 0, attribs });
  const att = (tag: string, x: number, y: number, s: string) => ({ type: 'ATTRIB', layer: 'ZZ-TITLE', tag, flags: 0, text: { text: s, startPoint: pt(x, y), textHeight: 180, rotation: 0 } });
  const attribs = [att('CLIENT', 12650, 3900, 'ZZ DEMO Rashid Kareem'), att('PROJECT', 12650, 3500, 'ZZ DEMO Harbour Tower'), att('DWG_NO', 12650, 3100, 'ZZ-2026-0142'), att('DRAWN_BY', 12650, 2700, 'ZZ Demo Drafter')];
  return {
    header: { INSUNITS: 4, PROJECTNAME: 'ZZ DEMO Harbour Tower', LASTSAVEDBY: 'ZZ Demo Drafter' },
    tables: { BLOCK_RECORD: { entries: [
      { name: '*Model_Space', flags: 0, basePoint: pt(0, 0), entities: [] },
      { name: 'SD', flags: 0, basePoint: pt(0, 0), entities: [{ type: 'CIRCLE', layer: '0', center: pt(0, 0), radius: 150 }, txt('0', -60, -45, 90, 'SD')] },
      { name: 'SKT', flags: 0, basePoint: pt(0, 0), entities: [room(-100, -50, 200, 100), { type: 'LINE', layer: '0', startPoint: pt(-100, 0), endPoint: pt(100, 0) }] },
      { name: 'ZZ_TITLEBLOCK_A1', flags: 2, basePoint: pt(0, 0), entities: [room(0, 0, 3000, 7500), txt('0', 150, 7100, 180, 'ZZ DEMO ORBIT CONSULTING ENGINEERS LLC'), txt('0', 150, 6800, 150, 'TEL +971 4 000 0017'), txt('0', 150, 6550, 150, 'zz.orbit@example.invalid'), txt('0', 150, 1200, 150, 'SCALE 1:100')] },
    ] } },
    entities: [
      room(0, 0, 6000, 4000), room(6000, 0, 4000, 4000), room(10000, 0, 2000, 4000),
      txt('A-ANNO', 2400, 1900, 250, 'OFFICE 101'), txt('A-ANNO', 6900, 1900, 250, 'MEETING ROOM 102'), txt('A-ANNO', 10300, 1900, 200, 'STORE 103'),
      { type: 'DIMENSION', layer: 'A-DIMS', text: '6000', measurement: 6000, textPoint: { x: 3000, y: -450 } },
      { type: 'DIMENSION', layer: 'A-DIMS', text: '4000', measurement: 4000, textPoint: { x: -700, y: 2000 } },
      ...SD_AT.map(([x, y]) => ins('E-FIRE', 'SD', x, y)),
      ...SKT_AT.map(([x, y]) => ins('E-POWR', 'SKT', x, y)),
      txt('A-ANNO', 0, -1500, 200, 'LEGEND'),
      ins('E-FIRE', 'SD', 200, -1900), txt('A-ANNO', 600, -1980, 160, 'SD - SMOKE DETECTOR'),
      ins('E-POWR', 'SKT', 200, -2300), txt('A-ANNO', 600, -2380, 160, 'SKT - DOUBLE SOCKET OUTLET'),
      txt('A-ANNO', 6000, -1500, 160, 'NOTE: ALL SOCKETS AT 300 AFFL'),
      txt('A-ANNO', 0, -2800, 150, 'SITE CONTACT zz.site@example.invalid +971 50 000 0017'),
      txt('A-ANNO', 6000, -2800, 150, 'CONSULTANT:'), txt('A-ANNO', 7600, -2800, 150, 'ZZ DEMO ORBIT'),
      ins('ZZ-TITLE', 'ZZ_TITLEBLOCK_A1', 12500, -3000, attribs), ...attribs,
      { ...txt('A-ANNO', 0, 0, 300, 'ZZ DEMO SHEET LAYOUT HARBOUR TOWER'), isInPaperSpace: true },
    ],
  } as DwgDb;
}

// ── PDF ───────────────────────────────────────────────────────────────────────────────────────────
// A 36 x 24 in sheet (2592 x 1728 pt), unrotated; positions as (a, b) = fraction across, fraction down.
const PW = 2592, PH = 1728;
const esc = (s: string) => s.replace(/([()\\])/g, '\\$1');
const t = (a: number, b: number, size: number, s: string) => `BT /F1 ${size} Tf 1 0 0 1 ${(a * PW).toFixed(1)} ${((1 - b) * PH).toFixed(1)} Tm (${esc(s)}) Tj ET\n`;
const l = (a1: number, b1: number, a2: number, b2: number) => `${(a1 * PW).toFixed(1)} ${((1 - b1) * PH).toFixed(1)} m ${(a2 * PW).toFixed(1)} ${((1 - b2) * PH).toFixed(1)} l S\n`;
const box = (a: number, b: number, w: number, h: number) => l(a, b, a + w, b) + l(a + w, b, a + w, b + h) + l(a + w, b + h, a, b + h) + l(a, b + h, a, b);

/** Title-block strings on the PDF sheet (all in the right-hand strip). */
export const PDF_TITLE = ['ZZ DEMO ORBIT CONSULTING ENGINEERS LLC', 'TEL +971 4 000 0017', 'zz.orbit@example.invalid', 'CLIENT: ZZ DEMO Rashid Kareem', 'PROJECT: ZZ DEMO Harbour Tower', 'DRAWING NO: ZZ-2026-0142', 'DRAWN BY: ZZ Demo Drafter'];

function titleStrip(sheetNo: string, title: string): string {
  return l(0.855, 0.02, 0.855, 0.98) + PDF_TITLE.map((s, i) => t(0.865, 0.06 + i * 0.05, 11, s)).join('') + t(0.865, 0.80, 11, title) + t(0.865, 0.85, 11, 'SCALE 1:100') + t(0.90, 0.93, 28, sheetNo);
}
function plan(view: string, fd: [number, number][], wc: [number, number][], fcu: string[], rooms: [number, number, string][]): string {
  let s = box(0.05, 0.10, 0.30, 0.40) + box(0.35, 0.10, 0.25, 0.40) + box(0.60, 0.10, 0.20, 0.40) + t(0.30, 0.58, 28, view);
  for (const [a, b, n] of rooms) s += t(a, b, 16, n);
  s += t(0.18, 0.54, 11, '6000') + t(0.02, 0.30, 11, '4000');
  for (const [a, b] of fd) s += t(a, b, 9, 'FD-1');
  for (const [a, b] of wc) s += t(a, b, 9, 'WC-1');
  fcu.forEach((f, i) => { s += t(0.40 + i * 0.1, 0.45, 9, f); });
  s += t(0.05, 0.62, 14, 'LEGEND') + t(0.05, 0.65, 10, 'FD - FLOOR DRAIN') + t(0.05, 0.67, 10, 'WC - WATER CLOSET');
  s += t(0.40, 0.62, 10, 'NOTE: ALL SOCKETS AT 300 AFFL');
  // Identity outside the strip: a contact line and a label with the firm beside it.
  s += t(0.05, 0.90, 9, 'SITE CONTACT zz.site@example.invalid +971 50 000 0017') + t(0.45, 0.90, 9, 'CONSULTANT:') + t(0.52, 0.90, 9, 'ZZ DEMO ORBIT');
  return s;
}
function pdfOf(pages: string[], info: Record<string, string>, imagePage = false): Uint8Array {
  const objs: string[] = [];
  const add = (s: string) => { objs.push(s); return objs.length; };
  const stream = (dict: string, body: string) => `<< ${dict} /Length ${body.length} >>\nstream\n${body}\nendstream`;
  add('<< /Type /Catalog /Pages 2 0 R >>');
  const kidsAt = add('');                                      // 2: filled below
  const font = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  // A "scan": one gray image per page, painted over the whole sheet, and no text at all.
  const scan = imagePage ? add(stream('/Type /XObject /Subtype /Image /Width 4 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8', '\xff\xe0\xff\x20\xff\xff\x40\xff')) : 0;
  const kids: number[] = [];
  for (const body of pages) {
    const content = add(stream('', imagePage ? `q ${PW} 0 0 ${PH} 0 0 cm /Im1 Do Q` : body));
    const res = imagePage ? `<< /XObject << /Im1 ${scan} 0 R >> >>` : `<< /Font << /F1 ${font} 0 R >> >>`;
    kids.push(add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PW} ${PH}] /Resources ${res} /Contents ${content} 0 R >>`));
  }
  objs[kidsAt - 1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(' ')}] /Count ${kids.length} >>`;
  const infoAt = add(`<< ${Object.entries(info).map(([k, v]) => `/${k} (${esc(v)})`).join(' ')} >>`);
  let out = '%PDF-1.4\n';
  objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  out += `trailer\n<< /Root 1 0 R /Info ${infoAt} 0 R >>\n%%EOF\n`;
  return new TextEncoder().encode(out);
}
const INFO = { Title: 'ZZ DEMO Harbour Tower E-101', Author: 'ZZ DEMO Orbit Consulting', Subject: 'ZZ-2026-0142', Creator: 'ZZ Demo Drafter' };
const ROOMS: [number, number, string][] = [[0.15, 0.30, 'OFFICE 101'], [0.40, 0.30, 'MEETING ROOM 102'], [0.65, 0.30, 'STORE 103']];
const FD7: [number, number][] = [[0.08, 0.15], [0.12, 0.20], [0.20, 0.15], [0.28, 0.40], [0.45, 0.20], [0.55, 0.40], [0.70, 0.20]];
const WC5: [number, number][] = [[0.08, 0.45], [0.25, 0.45], [0.50, 0.15], [0.66, 0.45], [0.75, 0.40]];

/** One sheet: FD-1 x 7, WC-1 x 5, FCU-1..3. */
export const zzPdfSheet = () => pdfOf([plan('GROUND FLOOR PLUMBING AND HVAC PLAN', FD7, WC5, ['FCU-1', 'FCU-2', 'FCU-3'], ROOMS) + titleStrip('P-1.01', 'GROUND FLOOR PLUMBING AND HVAC PLAN')], INFO);
/**
 * The same floor as a 3-sheet set, the way consultants issue it: the plumbing plan (FD-1 x 7, WC-1 x 5,
 * FCU-1), the mechanical plan of the SAME floor (FCU-2, FCU-3, and the five WCs drawn again for
 * coordination), and a notes sheet. An estimator counts the WCs once: 5, not 10.
 */
export const zzPdfSet = () => pdfOf([
  plan('GROUND FLOOR PLUMBING PLAN', FD7, WC5, ['FCU-1'], ROOMS) + titleStrip('P-1.01', 'GROUND FLOOR PLUMBING PLAN'),
  plan('GROUND FLOOR MECHANICAL PLAN', [], WC5, ['FCU-2', 'FCU-3'], ROOMS) + titleStrip('M-1.01', 'GROUND FLOOR MECHANICAL PLAN'),
  t(0.05, 0.10, 28, 'GENERAL NOTES') + t(0.05, 0.14, 10, '1. ALL WORK TO LOCAL AUTHORITY REQUIREMENTS.') + titleStrip('G-0.01', 'GENERAL NOTES'),
], INFO);
/** A scanned sheet: the same /Info metadata, one image, no text layer. */
export const zzPdfScan = () => pdfOf(['scan'], INFO, true);

// ── a SCANNED sheet ─────────────────────────────────────────────────────────────────────────────────
// The same job as a raster with no text layer: rooms, dimensions and a legend on the plan, the ZZ DEMO title
// block down the right-hand side, drawn with the stroke font, turned by a slight angle and speckled, the way a
// scanner returns a sheet. `titleNoise` smears the title block alone, to make a page OCR cannot read there.
export const SCAN_TITLE = ['ZZ DEMO ORBIT CONSULTING ENGINEERS LLC', 'TEL +971 4 000 0017', 'ZZ.ORBIT@EXAMPLE.INVALID', 'CLIENT: ZZ DEMO RASHID KAREEM', 'PROJECT: ZZ DEMO HARBOUR TOWER', 'DRAWING NO: ZZ-2026-0142', 'DRAWN BY: ZZ DEMO DRAFTER'];
export const SCAN_CONTENT = ['OFFICE 101', 'MEETING ROOM 102', 'STORE 103', '6000', '4000', 'LEGEND'];
export function zzScanRgba(o: { rotateDeg?: number; noise?: number; titleNoise?: number; noTitle?: boolean; leftFirm?: boolean; seed?: number } = {}): { w: number; h: number; rgba: Uint8ClampedArray } {
  const w = 2600, h = 1400, rgba = new Uint8ClampedArray(w * h * 4).fill(255);
  let s = o.seed ?? 7; const rnd = () => ((s = (s * 1103515245 + 12345) >>> 0) / 4294967296);
  const th = (o.rotateDeg ?? 0) * Math.PI / 180, cx = w / 2, cy = h / 2;
  const turn = (x: number, y: number): [number, number] => [cx + (x - cx) * Math.cos(th) - (y - cy) * Math.sin(th), cy + (x - cx) * Math.sin(th) + (y - cy) * Math.cos(th)];
  const dot = (x: number, y: number, v = 20) => { for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const X = Math.round(x) + dx, Y = Math.round(y) + dy; if (X >= 0 && Y >= 0 && X < w && Y < h) { const k = (Y * w + X) * 4; rgba[k] = rgba[k + 1] = rgba[k + 2] = v; } } };
  const seg = (x0: number, y0: number, x1: number, y1: number) => { const [a, b] = turn(x0, y0), [c, d] = turn(x1, y1); const n = Math.max(1, Math.ceil(Math.hypot(c - a, d - b))); for (let i = 0; i <= n; i++) dot(a + (c - a) * i / n, b + (d - b) * i / n); };
  const rect = (x: number, y: number, rw: number, rh: number) => { seg(x, y, x + rw, y); seg(x + rw, y, x + rw, y + rh); seg(x + rw, y + rh, x, y + rh); seg(x, y + rh, x, y); };
  const text = (x: number, y: number, size: number, str: string) => { for (const st of textStrokes(str).strokes) for (let i = 0; i + 1 < st.length; i++) seg(x + st[i][0] * size, y - st[i][1] * size, x + st[i + 1][0] * size, y - st[i + 1][1] * size); };
  // The plan.
  rect(100, 150, 700, 500); rect(800, 150, 500, 500); rect(1300, 150, 350, 500);
  text(260, 420, 34, 'OFFICE 101'); text(850, 420, 34, 'MEETING ROOM 102'); text(1360, 420, 34, 'STORE 103');
  seg(100, 720, 800, 720); text(390, 705, 28, '6000'); text(20, 430, 28, '4000');
  text(100, 900, 32, 'LEGEND'); text(100, 960, 26, 'SD - SMOKE DETECTOR'); text(100, 1010, 26, 'SKT - DOUBLE SOCKET OUTLET');
  // The title block, down the right-hand edge.
  rect(40, 40, 2520, 1320);
  if (!o.noTitle) seg(1940, 40, 1940, 1360);
  if (!o.noTitle) SCAN_TITLE.forEach((t, i) => text(1970, 140 + i * 90, 15, t));
  if (!o.noTitle) { text(1970, 1000, 20, 'SCALE 1:100'); text(1970, 1200, 40, 'E-1.01'); }
  // The review's case (#967): the firm printed LEFT of the title column, on the DRAWN BY row, outside the ruled box.
  if (o.leftFirm) text(1660, 680, 15, 'ZZ ORBIT ENGINEERING');
  // The scanner's speckle, and (for the low-confidence case) a smeared title block.
  for (let i = 0; i < w * h * (o.noise ?? 0); i++) { const k = (Math.floor(rnd() * h) * w + Math.floor(rnd() * w)) * 4; rgba[k] = rgba[k + 1] = rgba[k + 2] = rnd() < 0.5 ? 0 : 255; }
  if (o.titleNoise) for (let y = 40; y < 1360; y++) for (let x = 1945; x < 2560; x++) if (rnd() < o.titleNoise) { const k = (y * w + x) * 4; rgba[k] = rgba[k + 1] = rgba[k + 2] = rnd() < 0.5 ? 0 : 160; }
  return { w, h, rgba };
}

/**
 * Words drawn onto a scanned page (zzScanRgba) at an angle, optionally speckled round them: the second review's
 * (#967, 25 Sep 2026) stamps and body notes. `deg` turns the text about its start, clockwise on the page.
 */
export function zzScanText(img: { w: number; h: number; rgba: Uint8ClampedArray }, x: number, y: number, size: number, s: string, deg = 0, noise = 0): void {
  const th = deg * Math.PI / 180, c = Math.cos(th), sn = Math.sin(th);
  const dot = (px: number, py: number) => { for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const X = Math.round(px) + dx, Y = Math.round(py) + dy; if (X >= 0 && Y >= 0 && X < img.w && Y < img.h) { const k = (Y * img.w + X) * 4; img.rgba[k] = img.rgba[k + 1] = img.rgba[k + 2] = 20; } } };
  let minx = Infinity, maxx = -Infinity, miny = Infinity, maxy = -Infinity;
  for (const st of textStrokes(s).strokes) for (let i = 0; i + 1 < st.length; i++) {
    const [u0, v0] = st[i], [u1, v1] = st[i + 1];
    const n = Math.ceil(Math.hypot(u1 - u0, v1 - v0) * size) + 1;
    for (let j = 0; j <= n; j++) {
      const u = (u0 + (u1 - u0) * j / n) * size, v = (v0 + (v1 - v0) * j / n) * size;
      const px = x + u * c + v * sn, py = y + u * sn - v * c;
      dot(px, py); minx = Math.min(minx, px); maxx = Math.max(maxx, px); miny = Math.min(miny, py); maxy = Math.max(maxy, py);
    }
  }
  if (!noise) return;
  let r = 3; const rnd = () => ((r = (r * 1103515245 + 12345) >>> 0) / 4294967296);
  for (let yy = Math.floor(miny) - 3; yy < maxy + 3; yy++) for (let xx = Math.floor(minx) - 3; xx < maxx + 3; xx++) {
    if (rnd() < noise) { const k = (yy * img.w + xx) * 4; img.rgba[k] = img.rgba[k + 1] = img.rgba[k + 2] = rnd() < 0.5 ? 0 : 255; }
  }
}

// ── the review's leak cases (#967, 24 Sep 2026) ─────────────────────────────────────────────────────
// Every party here reached a supplier's page through the first CAD renderer: an ATTRIB tagged CLIENT_NAME in a block
// called ISO_A1, firm names with no label, a dimension override, a licence number, the customer's name letter-spaced.
// Rooms, a room tag and a dimension sit beside them and must still be drawn. (The name split one letter per TEXT
// now HOLDS the sheet as glyph_per_text; that case is zzGlyphSheetDxf and cad_render.test.ts.)
export function zzLeakyDxf(): Uint8Array {
  type P = [number, string | number][];
  const txt = (x: number, y: number, s: string, h = 200): P => [[0, 'TEXT'], [8, 'A-ANNO'], [10, x], [20, y], [30, 0], [40, h], [1, s]];
  return dxfFrom([
    ...dxfSection('HEADER', [[9, '$INSUNITS'], [70, 4]]),
    ...dxfSection('BLOCKS', [[0, 'BLOCK'], [8, '0'], [2, 'ISO_A1'], [70, 2], [10, 0], [20, 0], [30, 0], [0, 'LINE'], [8, '0'], [10, 0], [20, 0], [11, 3000], [21, 0], [0, 'ENDBLK'], [8, '0']]),
    ...dxfSection('ENTITIES', [
      [0, 'LWPOLYLINE'], [8, 'A-WALL'], [90, 4], [70, 1], [10, 0], [20, 0], [10, 12000], [20, 0], [10, 12000], [20, 8000], [10, 0], [20, 8000],
      ...txt(2000, 6000, 'OFFICE 101'), ...txt(6000, 6000, 'MEETING ROOM 102'), ...txt(9000, 6000, 'CORRIDOR'), ...txt(3000, 500, '6000'),
      [0, 'INSERT'], [8, 'A-ANNO'], [2, 'ISO_A1'], [10, 13000], [20, 0], [30, 0], [66, 1],
      [0, 'ATTRIB'], [8, 'A-ANNO'], [10, 13100], [20, 400], [30, 0], [40, 150], [1, 'ZZ HARBOUR HOLDINGS'], [2, 'CLIENT_NAME'], [70, 0],
      [0, 'ATTRIB'], [8, 'A-ANNO'], [10, 13100], [20, 700], [30, 0], [40, 150], [1, 'SHEET 4 OF 9'], [2, 'SHEET_NO'], [70, 0],
      // A value that reads as drawing content under a neutral tag: withheld only because its INSERT carries a party tag.
      [0, 'ATTRIB'], [8, 'A-ANNO'], [10, 13100], [20, 1000], [30, 0], [40, 150], [1, 'GROUND FLOOR'], [2, 'LINE2'], [70, 0],
      [0, 'SEQEND'], [8, 'A-ANNO'],
      ...txt(500, 3000, 'ZZ ORBIT ENGINEERING'), ...txt(500, 2500, 'ORBIT HOLDINGS'), ...txt(500, 2000, 'DM LIC 123456'),
      [0, 'DIMENSION'], [8, 'A-DIMS'], [10, 0], [20, 1000], [30, 0], [11, 6000], [21, 1200], [31, 0], [70, 32], [1, 'BY ZZ ORBIT'],
      ...txt(500, 1500, 'R A S H I D   K A R E E M', 180),
    ]),
    [0, 'EOF'],
  ]);
}

// ── the second review's sheet (#967, 25 Sep 2026) ───────────────────────────────────────────────────
// A PDF converted to DWG writes every glyph as its own TEXT on layer 0, with no title layer or block: the renderer
// used to draw "CLIENT: ZZ OMEGA", "CONSULTANT: ZZ ORBIT ENGINEERING", "TEL 04 123 4567" and "DWG NO E-101" from it.
// `lines` lets a test put any words on such a sheet; the rooms are ordinary TEXT beside it.
export function zzGlyphSheetDxf(lines = ['CLIENT: ZZ OMEGA', 'CONSULTANT: ZZ ORBIT ENGINEERING', 'TEL 04 123 4567', 'PROJECT: ZZ HARBOUR TOWER', 'DWG NO E-101']): Uint8Array {
  type P = [number, string | number][];
  const A = 5.2 / 6;
  const txt = (x: number, y: number, s: string, h = 200, layer = 'A-ANNO'): P => [[0, 'TEXT'], [8, layer], [10, x], [20, y], [30, 0], [40, h], [1, s]];
  const glyphs = lines.flatMap((l, i) => [...l].flatMap((c, k) => (c === ' ' ? [] : txt(14500 + k * 200 * A, 5000 - i * 400, c, 200, '0'))));
  return dxfFrom([
    ...dxfSection('ENTITIES', [
      [0, 'LWPOLYLINE'], [8, 'A-WALL'], [90, 4], [70, 1], [10, 0], [20, 0], [10, 20000], [20, 0], [10, 20000], [20, 14000], [10, 0], [20, 14000],
      ...txt(1000, 12500, 'KITCHEN'), ...txt(1000, 10000, 'OFFICE 101'), ...glyphs,
    ]),
    [0, 'EOF'],
  ]);
}
