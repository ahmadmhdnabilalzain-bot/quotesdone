// bench.fixtures — the sales engineer's drawing bench: one fit-out job drawn the way real offices send it, with
// the answer key in fixtures/bench_truth.json written by hand BEFORE any reader ran (19 Oct 2026, sales_engineer;
// founder ledger 31, 580, 1177). Pure, no I/O. Every party is ZZ-prefixed, every address example.invalid, every
// phone a 000 number: nothing here can reach a real person.
//
// What makes it harder than zz_demo_drawings.fixtures.ts, because real CAD files do it:
//   * doors placed as DYNAMIC blocks: AutoCAD writes each flipped/stretched door as an anonymous *U block whose
//     BLOCK_RECORD carries XDATA AcDbBlockRepBTag -> the handle of the real block (DOOR-SGL);
//   * a row of windows placed as ONE MINSERT (4 columns x 1 row);
//   * sockets NESTED inside a typical-room block inserted 3 times;
//   * a legend with one sample of every symbol;
//   * identity in a paper-space title block (ATTRIBs), in MTEXT split by formatting codes, in an inline
//     "SITE:" note in model space, in a hyperlink in XDATA, in DWGPROPS and in header variables.
import { dxfFrom, dxfSection } from '../_shared/doc_read/cad.fixtures.ts';
// @deno-types="../_shared/vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';

type P = [number, string | number][];
const line = (layer: string, x1: number, y1: number, x2: number, y2: number): P => [[0, 'LINE'], [8, layer], [10, x1], [20, y1], [30, 0], [11, x2], [21, y2], [31, 0]];
const rect = (layer: string, x: number, y: number, w: number, h: number): P => [[0, 'LWPOLYLINE'], [8, layer], [90, 4], [70, 1], [10, x], [20, y], [10, x + w], [20, y], [10, x + w], [20, y + h], [10, x], [20, y + h]];
const text = (layer: string, x: number, y: number, h: number, s: string): P => [[0, 'TEXT'], [8, layer], [10, x], [20, y], [30, 0], [40, h], [1, s]];
const insert = (layer: string, name: string, x: number, y: number): P => [[0, 'INSERT'], [8, layer], [2, name], [10, x], [20, y], [30, 0]];
const attrib = (tag: string, x: number, y: number, s: string): P => [[0, 'ATTRIB'], [8, 'G-TTLB'], [67, 1], [10, x], [20, y], [30, 0], [40, 150], [1, s], [2, tag], [70, 0]];
const block = (name: string, body: P, handle?: string): P => [[0, 'BLOCK'], ...(handle ? [[5, handle]] as P : []), [8, '0'], [2, name], [70, name.startsWith('*') ? 1 : 0], [10, 0], [20, 0], [30, 0], [3, name], ...body, [0, 'ENDBLK'], [8, '0']];

export const BENCH_IDENTITY = ['Noor Holdings', 'Marina Heights', 'MHT-2291', 'Khalid Rahman', '+971 4 000 0199', '000 0199', 'pm@zz-noor.example.invalid', 'zz-noor.example.invalid', 'Plot 392-118', 'Crescent Design'];
export const BENCH_CUSTOMER = { name: 'ZZ Khalid Rahman', email: 'pm@zz-noor.example.invalid', phone: '+97140000199' };
export const BENCH_FILE = 'MHT-2291 Marina Heights GF fitout';

const DOOR = [...line('0', 0, 0, 900, 0), [0, 'ARC'], [8, '0'], [10, 0], [20, 0], [30, 0], [40, 900], [50, 0], [51, 90]] as P;
export function benchDxfPairs(): P {
  const blocks: P = [
    ...block('DOOR-SGL', DOOR),
    ...block('*U7', DOOR),                                           // the dynamic door, flipped
    ...block('WIN-1200', rect('0', 0, 0, 1200, 150)),
    ...block('SKT', [...rect('0', -100, -50, 200, 100), ...line('0', -100, 0, 100, 0)]),
    ...block('WC', [[0, 'CIRCLE'], [8, '0'], [10, 0], [20, 0], [30, 0], [40, 250]]),
    ...block('ROOM-TYP', [...rect('A-WALL', 0, 0, 3000, 3000), ...insert('E-POWR', 'SKT', 200, 1500), ...insert('E-POWR', 'SKT', 2800, 1500)]),
    ...block('G-TITLE-A1', [...rect('0', 0, 0, 3000, 6000),
      [0, 'ATTDEF'], [8, '0'], [10, 100], [20, 5500], [30, 0], [40, 150], [1, ''], [3, 'Client'], [2, 'CLIENT'], [70, 0]]),
  ];
  const tables: P = [
    [0, 'TABLE'], [2, 'BLOCK_RECORD'], [70, 3],
    [0, 'BLOCK_RECORD'], [5, '1F'], [100, 'AcDbSymbolTableRecord'], [100, 'AcDbBlockTableRecord'], [2, 'DOOR-SGL'],
    [0, 'BLOCK_RECORD'], [5, '2A'], [100, 'AcDbSymbolTableRecord'], [100, 'AcDbBlockTableRecord'], [2, '*U7'],
    [1001, 'AcDbBlockRepBTag'], [1070, 1], [1005, '1F'],
    [0, 'BLOCK_RECORD'], [5, '2B'], [100, 'AcDbSymbolTableRecord'], [100, 'AcDbBlockTableRecord'], [2, 'WIN-1200'],
    [0, 'ENDTAB'],
  ];
  const ents: P = [
    ...rect('A-WALL', 0, 0, 20000, 12000),
    ...text('A-ANNO', 2000, 6000, 250, 'OPEN OFFICE G01'), ...text('A-ANNO', 14000, 6000, 250, 'PANTRY G02'),
    // doors: 3 plain + 2 dynamic (*U7) = 5
    ...insert('A-DOOR', 'DOOR-SGL', 1000, 0), ...insert('A-DOOR', 'DOOR-SGL', 6000, 0), ...insert('A-DOOR', 'DOOR-SGL', 11000, 0),
    ...insert('A-DOOR', '*U7', 15000, 0), ...insert('A-DOOR', '*U7', 18000, 0),
    // windows: one MINSERT of 4 columns x 1 row + 2 plain = 6
    [0, 'MINSERT'], [8, 'A-GLAZ'], [2, 'WIN-1200'], [10, 1000], [20, 12000], [30, 0], [70, 4], [71, 1], [44, 2000], [45, 0],
    ...insert('A-GLAZ', 'WIN-1200', 12000, 12000), ...insert('A-GLAZ', 'WIN-1200', 16000, 12000),
    // sockets: 4 loose + 3 typical rooms x 2 = 10
    ...insert('E-POWR', 'SKT', 500, 3000), ...insert('E-POWR', 'SKT', 500, 9000), ...insert('E-POWR', 'SKT', 19500, 3000), ...insert('E-POWR', 'SKT', 19500, 9000),
    ...insert('A-ROOM', 'ROOM-TYP', 3000, 8000), ...insert('A-ROOM', 'ROOM-TYP', 7000, 8000), ...insert('A-ROOM', 'ROOM-TYP', 11000, 8000),
    // WCs: 3
    ...insert('P-SANR', 'WC', 14500, 2000), ...insert('P-SANR', 'WC', 15500, 2000), ...insert('P-SANR', 'WC', 16500, 2000),
    // the legend: one sample of each, description beside it
    ...text('A-ANNO', 0, -1500, 200, 'LEGEND'),
    ...insert('A-ANNO', 'DOOR-SGL', 200, -1900), ...text('A-ANNO', 1300, -1980, 160, 'SINGLE LEAF DOOR 900'),
    ...insert('A-ANNO', 'WIN-1200', 200, -2300), ...text('A-ANNO', 1600, -2380, 160, 'WINDOW 1200 x 1500'),
    ...insert('A-ANNO', 'SKT', 200, -2700), ...text('A-ANNO', 600, -2780, 160, 'TWIN SOCKET OUTLET'),
    ...insert('A-ANNO', 'WC', 200, -3100), ...text('A-ANNO', 600, -3180, 160, 'WALL HUNG WC'),
    // identity outside the title block: an inline site note, and a hyperlink on a wall
    [0, 'MTEXT'], [8, 'A-ANNO'], [10, 6000], [20, -1500], [30, 0], [40, 160], [1, 'SITE: Plot 392-118, ZZ Marina Heights\\PALL SOCKETS AT 450 AFFL'],
    ...line('A-WALL', 0, 12000, 20000, 12000), [1001, 'PE_URL'], [1000, 'https://zz-noor.example.invalid/mht-2291'],
    // the paper-space title block, its attributes, and the designer's stamp in formatted MTEXT
    ...insert('G-TTLB', 'G-TITLE-A1', 21000, 0), [67, 1], [66, 1],
    ...attrib('CLIENT', 21100, 5500, 'ZZ Noor Holdings'), ...attrib('PROJECT', 21100, 5200, 'ZZ Marina Heights Tower B'),
    ...attrib('JOB_NO', 21100, 4900, 'MHT-2291'), ...attrib('DRAWN_BY', 21100, 4600, 'ZZ Khalid Rahman'),
    [0, 'SEQEND'], [8, 'G-TTLB'],
    [0, 'MTEXT'], [8, 'G-TTLB'], [67, 1], [10, 21100], [20, 3000], [30, 0], [40, 150],
    [3, '{\\fArial|b1;ZZ Cres}cent Design Studio\\PTel +971 4 000 0199\\Ppm@zz-noor'], [1, '.example.invalid'],
  ];
  const objects: P = [
    [0, 'DICTIONARY'], [5, 'C'], [3, 'DWGPROPS'], [350, '3F'],
    [0, 'XRECORD'], [5, '3F'], [1, 'DWGPROPS COOKIE'], [2, 'ZZ Marina Heights GF'], [3, 'Fit-out'], [4, 'ZZ Khalid Rahman'], [6, 'MHT-2291'],
  ];
  return [
    ...dxfSection('HEADER', [[9, '$ACADVER'], [1, 'AC1027'], [9, '$INSUNITS'], [70, 4], [9, '$PROJECTNAME'], [1, 'ZZ Marina Heights'], [9, '$LASTSAVEDBY'], [1, 'ZZ Khalid Rahman']]),
    ...dxfSection('TABLES', tables),
    ...dxfSection('BLOCKS', blocks),
    ...dxfSection('ENTITIES', ents),
    ...dxfSection('OBJECTS', objects),
    [0, 'EOF'],
  ];
}
export const benchDxf = (): Uint8Array => dxfFrom(benchDxfPairs());

// ── vector PDF ──────────────────────────────────────────────────────────────────────────────────────
const PW = 2592, PH = 1728;
const esc = (s: string) => s.replace(/([()\\])/g, '\\$1');
const t = (a: number, b: number, size: number, s: string) => `BT /F1 ${size} Tf 1 0 0 1 ${(a * PW).toFixed(1)} ${((1 - b) * PH).toFixed(1)} Tm (${esc(s)}) Tj ET\n`;
const l = (a1: number, b1: number, a2: number, b2: number) => `${(a1 * PW).toFixed(1)} ${((1 - b1) * PH).toFixed(1)} m ${(a2 * PW).toFixed(1)} ${((1 - b2) * PH).toFixed(1)} l S\n`;
export const BENCH_PDF_TITLE = ['ZZ CRESCENT DESIGN STUDIO', 'TEL +971 4 000 0199', 'pm@zz-noor.example.invalid', 'CLIENT: ZZ Noor Holdings', 'PROJECT: ZZ Marina Heights Tower B', 'SITE: Plot 392-118', 'JOB NO: MHT-2291', 'DRAWN: ZZ Khalid Rahman'];
export function pdfFrom(pages: string[], info: Record<string, string>): Uint8Array {
  const objs: string[] = [];
  const add = (s: string) => { objs.push(s); return objs.length; };
  add('<< /Type /Catalog /Pages 2 0 R >>'); add('');
  const font = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  const kids = pages.map((body) => { const c = add(`<< /Length ${body.length} >>\nstream\n${body}\nendstream`); return add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PW} ${PH}] /Resources << /Font << /F1 ${font} 0 R >> >> /Contents ${c} 0 R >>`); });
  objs[1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(' ')}] /Count ${kids.length} >>`;
  const infoAt = add(`<< ${Object.entries(info).map(([k, v]) => `/${k} (${esc(v)})`).join(' ')} >>`);
  let out = '%PDF-1.4\n';
  objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  return new TextEncoder().encode(out + `trailer\n<< /Root 1 0 R /Info ${infoAt} 0 R >>\n%%EOF\n`);
}
const grid = (n: number, a0: number, b0: number, da: number, db: number, per: number): [number, number][] => Array.from({ length: n }, (_, i) => [a0 + (i % per) * da, b0 + Math.floor(i / per) * db]);
export function benchPdf(): Uint8Array {
  let s = l(0.04, 0.08, 0.80, 0.08) + l(0.80, 0.08, 0.80, 0.60) + l(0.80, 0.60, 0.04, 0.60) + l(0.04, 0.60, 0.04, 0.08);
  s += t(0.30, 0.05, 28, 'GROUND FLOOR FIT-OUT PLAN') + t(0.15, 0.30, 16, 'OPEN OFFICE G01') + t(0.60, 0.30, 16, 'PANTRY G02');
  for (const [a, b] of grid(5, 0.08, 0.59, 0.12, 0, 5)) s += t(a, b, 9, 'D1');
  for (const [a, b] of grid(6, 0.08, 0.10, 0.11, 0, 6)) s += t(a, b, 9, 'W1');
  for (const [a, b] of grid(10, 0.10, 0.20, 0.13, 0.25, 5)) s += t(a, b, 9, 'SKT');
  for (const [a, b] of grid(3, 0.62, 0.40, 0.04, 0, 3)) s += t(a, b, 9, 'WC-1');
  s += t(0.05, 0.66, 14, 'LEGEND');
  [['D1', 'SINGLE LEAF DOOR 900'], ['W1', 'WINDOW 1200 x 1500'], ['SKT', 'TWIN SOCKET OUTLET'], ['WC-1', 'WALL HUNG WC']].forEach(([k, d], i) => { s += t(0.05, 0.69 + i * 0.025, 10, k) + t(0.09, 0.69 + i * 0.025, 10, d); });
  s += t(0.40, 0.66, 10, 'NOTE: ALL SOCKETS AT 450 AFFL');
  s += l(0.855, 0.02, 0.855, 0.98) + BENCH_PDF_TITLE.map((x, i) => t(0.865, 0.06 + i * 0.05, 11, x)).join('') + t(0.865, 0.85, 11, 'SCALE 1:100') + t(0.90, 0.93, 28, 'A-101');
  return pdfFrom([s], { Title: 'ZZ Marina Heights GF', Author: 'ZZ Khalid Rahman', Subject: 'MHT-2291' });
}

// ── BOQ documents ───────────────────────────────────────────────────────────────────────────────────
export const BENCH_BOQ_ROWS: (string | number)[][] = [
  ['ZZ Noor Holdings - ZZ Marina Heights Tower B'], ['Job MHT-2291   QS: ZZ Khalid Rahman  +971 4 000 0199  pm@zz-noor.example.invalid'], [],
  ['Item', 'Description', 'Unit', 'Qty', 'Rate', 'Amount'],
  ['1.01', 'Single leaf timber door 900x2100', 'nr', 5, '', ''],
  ['1.02', 'Aluminium window 1200x1500', 'nr', 6, '', ''],
  ['2.01', '13A twin switched socket outlet', 'nr', 10, '', ''],
  ['3.01', 'Wall hung WC complete', 'nr', 3, '', ''],
];
export function benchBoqXlsx(): Uint8Array {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(BENCH_BOQ_ROWS), 'BOQ');
  return new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
}
export function benchBoqPdf(): Uint8Array {
  const pw = 595, ph = 842;
  const tt = (x: number, y: number, s: string) => `BT /F1 10 Tf 1 0 0 1 ${x} ${ph - y} Tm (${esc(s)}) Tj ET\n`;
  let s = '';
  BENCH_BOQ_ROWS.forEach((r, i) => { [40, 90, 330, 380, 430, 490].forEach((x, k) => { if (r[k] !== undefined && r[k] !== '') s += tt(x, 60 + i * 18, String(r[k])); }); });
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [4 0 R] /Count 1 >>', '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pw} ${ph}] /Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>`, `<< /Length ${s.length} >>\nstream\n${s}\nendstream`];
  let out = '%PDF-1.4\n';
  objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  return new TextEncoder().encode(out + 'trailer\n<< /Root 1 0 R >>\n%%EOF\n');
}
/** The BOQ as an SVG table, rendered to a picture by the bench (a phone photo of a printed BOQ). */
export function benchBoqSvg(): string {
  const rows = BENCH_BOQ_ROWS.map((r, i) => [40, 110, 520, 590, 650, 720].map((x, k) => r[k] !== undefined && r[k] !== '' ? `<text x="${x}" y="${60 + i * 34}">${String(r[k]).replace(/&/g, '&amp;')}</text>` : '').join('')).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="360"><rect width="100%" height="100%" fill="white"/><g font-family="Arial" font-size="20" fill="black">${rows}</g></svg>`;
}
