// bench_trades.fixtures — the drawing bench beyond MEP devices (10 Nov 2026, sales_engineer; founder 10 Nov: a
// customer's villa / shop / office drawing read "as if a real engineer saw it"; ruling 1586: every trade). Four CAD
// drawings authored the way AutoCAD writes them, each with a paper-space title block and an inline site note that name
// the ZZ DEMO parties (bench.fixtures.ts BENCH_IDENTITY). The answer key is fixtures/bench_truth.json, worked out by hand
// from the coordinates below BEFORE any reader ran. Pure, no I/O; nothing here can reach a real person.
//   archFinishesDxf  a villa ground floor: 4 rooms on A-AREA, a finish legend, a room finish schedule, a door and a
//                    window schedule, door / window blocks tagged on the plan, a general and a bathroom ceiling height
//   hvacDxf          supply 600x400 -> 400x300 with a 300x250 branch (double-line), return 500x300, a single-line
//                    exhaust Ø250 round a corner, an unlabelled 250 wide duct, CHW pipe, cable tray, conduit, devices
//   amenitiesDxf     two lift shafts with lift notes, a pool with shallow / deep depths, planting, turf, paving, palms
//   structureDxf     UB / IPE steel members labelled by section, and a scaffold run with its height note
import { dxfFrom, dxfSection } from '../_shared/doc_read/cad.fixtures.ts';

type P = [number, string | number][];
const line = (layer: string, x1: number, y1: number, x2: number, y2: number): P => [[0, 'LINE'], [8, layer], [10, x1], [20, y1], [30, 0], [11, x2], [21, y2], [31, 0]];
const poly = (layer: string, pts: [number, number][], closed: boolean): P => [[0, 'LWPOLYLINE'], [8, layer], [90, pts.length], [70, closed ? 1 : 0], ...pts.flatMap(([x, y]) => [[10, x], [20, y]] as P)];
const rect = (layer: string, x: number, y: number, w: number, h: number): P => poly(layer, [[x, y], [x + w, y], [x + w, y + h], [x, y + h]], true);
const text = (layer: string, x: number, y: number, h: number, s: string): P => [[0, 'TEXT'], [8, layer], [10, x], [20, y], [30, 0], [40, h], [1, s]];
const insert = (layer: string, name: string, x: number, y: number): P => [[0, 'INSERT'], [8, layer], [2, name], [10, x], [20, y], [30, 0]];
const block = (name: string, body: P): P => [[0, 'BLOCK'], [8, '0'], [2, name], [70, 0], [10, 0], [20, 0], [30, 0], [3, name], ...body, [0, 'ENDBLK'], [8, '0']];
const attrib = (tag: string, x: number, y: number, s: string): P => [[0, 'ATTRIB'], [8, 'G-TTLB'], [67, 1], [10, x], [20, y], [30, 0], [40, 150], [1, s], [2, tag], [70, 0]];
/** The parties, as bench.fixtures.ts plants them: a paper-space title block and a model-space site note. */
const parties = (x: number, y: number): P => [
  [0, 'MTEXT'], [8, 'A-ANNO'], [10, x], [20, y], [30, 0], [40, 160], [1, 'SITE: Plot 392-118, ZZ Marina Heights'],
  ...insert('G-TTLB', 'G-TITLE-A1', 90000, 0), [67, 1], [66, 1],
  ...attrib('CLIENT', 90100, 5500, 'ZZ Noor Holdings'), ...attrib('PROJECT', 90100, 5200, 'ZZ Marina Heights Tower B'),
  ...attrib('JOB_NO', 90100, 4900, 'MHT-2291'), ...attrib('DRAWN_BY', 90100, 4600, 'ZZ Khalid Rahman'),
  [0, 'SEQEND'], [8, 'G-TTLB'],
  [0, 'MTEXT'], [8, 'G-TTLB'], [67, 1], [10, 90100], [20, 3000], [30, 0], [40, 150], [1, 'ZZ Crescent Design Studio\\PTel +971 4 000 0199\\Ppm@zz-noor.example.invalid'],
];
const TITLE_BLOCK = block('G-TITLE-A1', rect('0', 0, 0, 3000, 6000));
const doc = (blocks: P, ents: P): Uint8Array => dxfFrom([
  ...dxfSection('HEADER', [[9, '$ACADVER'], [1, 'AC1027'], [9, '$INSUNITS'], [70, 4], [9, '$PROJECTNAME'], [1, 'ZZ Marina Heights']]),
  ...dxfSection('BLOCKS', [...TITLE_BLOCK, ...blocks]),
  ...dxfSection('ENTITIES', ents),
  [0, 'EOF'],
]);

// ── architectural finishes plan ─────────────────────────────────────────────────────────────────────
/** Schedules drawn as CAD text: a row every 400 mm, columns at the given x. */
const table = (x0: number, y0: number, cols: number[], rows: string[][]): P => rows.flatMap((r, i) => r.flatMap((c, k) => (c ? text('A-ANNO-SCHD', x0 + cols[k], y0 - i * 400, 150, c) : [])));
export function archFinishesDxf(): Uint8Array {
  const blocks = [
    ...block('DOOR-900', [...line('0', 0, 0, 900, 0)]),
    ...block('DOOR-800', [...line('0', 0, 0, 800, 0)]),
    ...block('WIN-1500', [...rect('0', 0, -75, 1500, 150)]),
  ];
  const ents: P = [
    // walls (never a room) and the four rooms on A-AREA
    ...rect('A-WALL', -200, -200, 10400, 9400),
    ...rect('A-AREA', 0, 0, 6000, 5000), ...text('A-AREA-IDEN', 2000, 2500, 250, 'LIVING'),
    ...rect('A-AREA', 6000, 0, 4000, 3500), ...text('A-AREA-IDEN', 7200, 1700, 250, 'KITCHEN'),
    ...rect('A-AREA', 0, 5000, 4000, 4000), ...text('A-AREA-IDEN', 800, 7000, 250, 'BEDROOM 1'),
    ...rect('A-AREA', 4000, 5000, 2500, 2000), ...text('A-AREA-IDEN', 4600, 6000, 250, 'BATH'),
    ...text('A-ANNO', 4500, 5400, 120, 'CLG HT 2700'),
    // doors (tagged) and windows (tagged), on the room outlines
    ...insert('A-DOOR', 'DOOR-900', 3000, 0), ...text('A-ANNO', 3000, 400, 150, 'D1'),
    ...insert('A-DOOR', 'DOOR-900', 6000, 1500), ...text('A-ANNO', 5500, 1500, 150, 'D1'),
    ...insert('A-DOOR', 'DOOR-900', 2000, 5000), ...text('A-ANNO', 2000, 4500, 150, 'D1'),
    ...insert('A-DOOR', 'DOOR-800', 4000, 6000), ...text('A-ANNO', 3500, 6300, 150, 'D2'),
    ...insert('A-GLAZ', 'WIN-1500', 8000, 0), ...text('A-ANNO', 8000, 400, 150, 'W1'),
    ...insert('A-GLAZ', 'WIN-1500', 0, 7000), ...text('A-ANNO', 400, 7600, 150, 'W1'),
    // notes, the finish legend, the room finish schedule, the door / window schedule (beside the plan, x >= 14000)
    ...text('A-ANNO', 0, -1500, 150, 'CLG HT 3000 UNLESS NOTED OTHERWISE'),
    ...text('A-ANNO', 14000, 9000, 200, 'FINISHES LEGEND'),
    ...text('A-ANNO', 14000, 8500, 150, 'F1 - PORCELAIN TILE 600x600'), ...text('A-ANNO', 14000, 8100, 150, 'F2 - ANTI-SLIP CERAMIC TILE 300x300'),
    ...text('A-ANNO', 14000, 7700, 150, 'W1 - EMULSION PAINT 3 COATS'), ...text('A-ANNO', 14000, 7300, 150, 'W2 - CERAMIC WALL TILE 300x600'),
    ...text('A-ANNO', 14000, 6900, 150, 'C1 - GYPSUM BOARD CEILING'), ...text('A-ANNO', 14000, 6500, 150, 'C2 - MOISTURE RESISTANT GYPSUM BOARD CEILING'),
    ...text('A-ANNO', 14000, 6100, 150, 'SK1 - PORCELAIN SKIRTING 100MM'),
    ...table(14000, 5000, [0, 2500, 3700, 4900, 6300], [['ROOM', 'FLOOR', 'WALL', 'CEILING', 'SKIRTING'], ['LIVING', 'F1', 'W1', 'C1', 'SK1'], ['KITCHEN', 'F2', 'W2', 'C2', ''], ['BEDROOM 1', 'F1', 'W1', 'C1', 'SK1'], ['BATH', 'F2', 'W2', 'C2', '']]),
    ...table(14000, 2000, [0, 1500, 6500, 8000, 9500], [['MARK', 'TYPE', 'WIDTH', 'HEIGHT', 'QTY'], ['D1', 'SOLID CORE TIMBER DOOR', '900', '2100', '3'], ['D2', 'FLUSH DOOR WITH LOUVRE', '800', '2100', '1'], ['W1', 'ALUMINIUM SLIDING WINDOW', '1500', '1200', '2']]),
    ...parties(0, -2500),
  ];
  return doc(blocks, ents);
}

// ── HVAC duct layout ────────────────────────────────────────────────────────────────────────────────
const walls = (layer: string, x1: number, y1: number, x2: number, y2: number, w: number): P => {
  const L = Math.hypot(x2 - x1, y2 - y1), nx = -(y2 - y1) / L * w / 2, ny = (x2 - x1) / L * w / 2;
  return [...line(layer, x1 + nx, y1 + ny, x2 + nx, y2 + ny), ...line(layer, x1 - nx, y1 - ny, x2 - nx, y2 - ny)];
};
export function hvacDxf(): Uint8Array {
  const blocks = [...block('DIFFUSER_SQ_600', rect('0', -300, -300, 600, 600)), ...block('RETURN_GRILLE', rect('0', -300, -150, 600, 300)), ...block('FCU', rect('0', -500, -300, 1000, 600))];
  const ents: P = [
    ...walls('M-HVAC-SUPP', 0, 0, 10000, 0, 600), ...text('M-HVAC-ANNO', 5000, 500, 150, '600x400'),
    ...walls('M-HVAC-SUPP', 10000, 0, 16000, 0, 400), ...text('M-HVAC-ANNO', 13000, 400, 150, '400x300'),
    ...walls('M-HVAC-SUPP', 13000, 200, 13000, 6200, 300), ...text('M-HVAC-ANNO', 13300, 3000, 150, '300x250'),
    ...walls('M-HVAC-SUPP', 20000, 0, 24000, 0, 250),
    ...walls('M-HVAC-RETN', 0, 3000, 8000, 3000, 500), ...text('M-HVAC-ANNO', 4000, 3400, 150, '500x300'),
    ...poly('M-HVAC-EXHS', [[0, 8000], [6000, 8000], [6000, 10000]], false), ...text('M-HVAC-ANNO', 3000, 8200, 150, 'Ø250'),
    ...line('M-CHW-SUPP', 0, -3000, 12000, -3000), ...text('M-HVAC-ANNO', 6000, -2850, 150, 'Ø100 CHWS'),
    ...walls('E-TRAY', 0, -6000, 15000, -6000, 300), ...text('E-ANNO', 7000, -5700, 150, 'CT 300x50'),
    ...line('E-CNDT', 0, -9000, 20000, -9000), ...text('E-ANNO', 10000, -8850, 150, '25mm PVC CONDUIT'),
    ...insert('M-HVAC-DIFF', 'DIFFUSER_SQ_600', 2000, 1500), ...insert('M-HVAC-DIFF', 'DIFFUSER_SQ_600', 6000, 1500), ...insert('M-HVAC-DIFF', 'DIFFUSER_SQ_600', 11000, 1500), ...insert('M-HVAC-DIFF', 'DIFFUSER_SQ_600', 15000, 1500),
    ...insert('M-HVAC-DIFF', 'RETURN_GRILLE', 2000, 4000), ...insert('M-HVAC-DIFF', 'RETURN_GRILLE', 6000, 4000),
    ...insert('M-EQPM', 'FCU', -1500, 0), ...insert('M-EQPM', 'FCU', -1500, 3000),
    ...parties(0, -12000),
  ];
  return doc(blocks, ents);
}

// ── lifts, pool, landscape ──────────────────────────────────────────────────────────────────────────
export function amenitiesDxf(): Uint8Array {
  const blocks = [...block('POOL_LIGHT', rect('0', -100, -100, 200, 200)), ...block('SKIMMER', rect('0', -150, -150, 300, 300)), ...block('PALM_TREE', [[0, 'CIRCLE'], [8, '0'], [10, 0], [20, 0], [30, 0], [40, 1500]])];
  const ents: P = [
    ...rect('A-LIFT-SHAFT', 0, 0, 2000, 2200), ...rect('A-LIFT-SHAFT', 2300, 0, 2000, 2200),
    ...text('A-ANNO', 0, -800, 150, 'PASSENGER LIFT 8 PERSONS / 630 KG'), ...text('A-ANNO', 0, -1100, 150, 'SPEED 1.0 M/S'),
    ...text('A-ANNO', 0, -1400, 150, 'STOPS: 5'), ...text('A-ANNO', 0, -1700, 150, 'TRAVEL 16.0 M'),
    ...text('A-ANNO', 0, -2000, 150, 'PIT DEPTH 1500'), ...text('A-ANNO', 0, -2300, 150, 'OVERHEAD 4200'),
    ...rect('L-POOL', 10000, 0, 10000, 5000), ...text('L-ANNO', 10500, 4000, 150, 'SHALLOW END 1.2 M'), ...text('L-ANNO', 18000, 1000, 150, 'DEEP END 1.8 M'),
    ...insert('L-POOL-EQPM', 'POOL_LIGHT', 12000, 300), ...insert('L-POOL-EQPM', 'POOL_LIGHT', 16000, 300), ...insert('L-POOL-EQPM', 'POOL_LIGHT', 12000, 4700), ...insert('L-POOL-EQPM', 'POOL_LIGHT', 16000, 4700),
    ...insert('L-POOL-EQPM', 'SKIMMER', 10300, 2500), ...insert('L-POOL-EQPM', 'SKIMMER', 19700, 2500),
    ...rect('L-PLNT', 0, 8000, 8000, 2000), ...rect('L-TURF', 10000, 8000, 12000, 6000), ...rect('L-PAVE', 0, 12000, 6000, 4000),
    ...[0, 2000, 4000, 6000, 8000, 10000].flatMap((x) => insert('L-PLNT-SYMB', 'PALM_TREE', 23000, 8000 + x)),
    ...parties(0, -4000),
  ];
  return doc(blocks, ents);
}

// ── structural steel and scaffolding ────────────────────────────────────────────────────────────────
export function structureDxf(): Uint8Array {
  const ents: P = [
    ...[0, 4000, 8000].flatMap((y) => [...line('S-BEAM', 0, y, 8000, y), ...text('S-ANNO', 3000, y + 200, 150, 'UB 406x178x60')]),
    ...[10000, 14000].flatMap((x) => [...line('S-BEAM', x, 0, x, 6000), ...text('S-ANNO', x + 200, 3000, 150, 'UB 305x165x40')]),
    ...[12000, 13000, 14000, 15000].flatMap((y) => [...line('S-PURL', 0, y, 10000, y), ...text('S-ANNO', 5000, y + 150, 120, 'IPE 200')]),
    ...poly('SCAFFOLD', [[0, 20000], [30000, 20000], [30000, 32000], [0, 32000]], false), ...text('A-ANNO', 2000, 33000, 200, 'SCAFFOLD HEIGHT 18 M'),
    ...parties(0, -3000),
  ];
  return doc([], ents);
}
