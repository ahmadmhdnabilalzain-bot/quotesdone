// drawing_takeoff_zz_demo_gen — writes the ZZ DEMO drawing take-off benchmark (28 Sep 2026, sales_engineer).
// Four SYNTHETIC drawings with their true quantities known by construction, and ground_truth.json beside
// them, into tests/fixtures/drawings/zz_demo/. Nothing real: every name is ZZ DEMO.
//   * two plain ASCII DXFs (mm, $INSUNITS 4): device and door BLOCK inserts, and pipe/conduit LINE and
//     LWPOLYLINE runs on their own layers, plus an A-WALL layer that is not scope (the reader lists it);
//   * two minimal vector-text PDFs (no PDF-writing library in the repo; its own fixtures write PDFs this
//     way): a plumbing plan with CAD-style tags and one pipe run on an optional-content layer at
//     1/4" = 1'-0", and a lighting/power plan with light, socket, door and detector tags.
// The counts live HERE and only here; ground_truth.json is written from the same constants.
//   deno run -A scripts/eval/drawing_takeoff_zz_demo_gen.ts
// Scored by scripts/eval/drawing_takeoff_benchmark.ts. No knowledge or spec checklist is built here.
const OUT = new URL('../../tests/fixtures/drawings/zz_demo/', import.meta.url);

// ── DXF ─────────────────────────────────────────────────────────────────────────────────────────
const g = (...pairs: (string | number)[]) => { let s = ''; for (let i = 0; i < pairs.length; i += 2) s += `${pairs[i]}\n${pairs[i + 1]}\n`; return s; };
const insert = (name: string, x: number, y: number, layer: string) => g(0, 'INSERT', 8, layer, 2, name, 10, x, 20, y, 30, 0);
const line = (x1: number, y1: number, x2: number, y2: number, layer: string) => g(0, 'LINE', 8, layer, 10, x1, 20, y1, 30, 0, 11, x2, 21, y2, 31, 0);
const lwpoly = (pts: [number, number][], layer: string) => g(0, 'LWPOLYLINE', 8, layer, 90, pts.length, 70, 0) + pts.map(([x, y]) => g(10, x, 20, y)).join('');
const text = (s: string, x: number, y: number) => g(0, 'TEXT', 8, 'A-ANNO', 10, x, 20, y, 30, 0, 40, 250, 1, s);
const repeat = (n: number, f: (i: number) => string) => Array.from({ length: n }, (_, i) => f(i)).join('');
const dxf = (ents: string) => g(0, 'SECTION', 2, 'HEADER', 9, '$INSUNITS', 70, 4) + g(0, 'ENDSEC') + g(0, 'SECTION', 2, 'ENTITIES') + ents + g(0, 'ENDSEC', 0, 'EOF');
const walls = line(0, 0, 20000, 0, 'A-WALL') + line(20000, 0, 20000, 12000, 'A-WALL') + line(20000, 12000, 0, 12000, 'A-WALL') + line(0, 12000, 0, 0, 'A-WALL');

const electricalDxf = dxf(text('ZZ DEMO GROUND FLOOR LIGHTING AND POWER', 500, 13000) + walls +
  repeat(12, (i) => insert('LIGHT_FITTING', 1500 + (i % 4) * 4500, 2000 + Math.floor(i / 4) * 4000, 'E-LIGHT')) +
  repeat(9, (i) => insert('DOUBLE_SOCKET', 300, 1000 + i * 1200, 'E-POWER')) +
  repeat(6, (i) => insert('SMOKE_DETECTOR', 3000 + i * 2500, 6000, 'FA')) +
  repeat(2, (i) => insert('MANUAL_CALL_POINT', 100 + i * 19800, 200, 'FA')) +
  repeat(5, (i) => insert('DOOR_SINGLE', 2000 + i * 3500, 0, 'A-DOOR')) +
  repeat(4, (i) => line(500, 1000 + i * 3000, 10100, 1000 + i * 3000, 'E-CONDUIT')));        // 4 x 9.6 m = 38.4 m

const plumbingDxf = dxf(text('ZZ DEMO FIRST FLOOR PLUMBING', 500, 13000) + walls +
  repeat(4, (i) => insert('WC', 1000 + i * 1500, 11000, 'P-FIXT')) +
  repeat(4, (i) => insert('WASH_BASIN', 1000 + i * 1500, 9500, 'P-FIXT')) +
  repeat(3, (i) => insert('FLOOR_DRAIN', 2000 + i * 3000, 8000, 'P-FIXT')) +
  lwpoly([[0, 0], [12000, 0], [12000, 8000], [19000, 8000]], 'P-DRAIN') +                     // 12 + 8 + 7 = 27 m
  line(0, 500, 10000, 500, 'P-COLD-WATER') + line(10000, 500, 10000, 8900, 'P-COLD-WATER')); // 10 + 8.4 = 18.4 m

// ── PDF ─────────────────────────────────────────────────────────────────────────────────────────
const W = 2592, H = 1728;                                            // 36 x 24 in sheet, unrotated
const esc = (s: string) => s.replace(/([()\\])/g, '\\$1');
const t = (x: number, y: number, size: number, s: string) => `BT /F1 ${size} Tf ${x} ${y} Td (${esc(s)}) Tj ET\n`;
const tags = (tag: string, n: number, x0: number, y: number) => repeat(n, (i) => t(x0 + i * 120, y, 9, tag));
function pdf(content: string, layers: string[]): string {
  const objs: string[] = [];
  const add = (s: string) => { objs.push(s); return objs.length; };
  const f = 5 + layers.length;
  add(`<< /Type /Catalog /Pages 2 0 R${layers.length ? ` /OCProperties << /OCGs [${layers.map((_, i) => `${i + 5} 0 R`).join(' ')}] >>` : ''} >>`);
  add('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /Font << /F1 ${f} 0 R >> /Properties << ${layers.map((_, i) => `/L${i + 1} ${i + 5} 0 R`).join(' ')} >> >> /Contents 4 0 R >>`);
  add(`<< /Length ${content.length} >>\nstream\n${content}\nendstream`);
  for (const l of layers) add(`<< /Type /OCG /Name (${l}) >>`);
  add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  let out = '%PDF-1.5\n';
  objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  return out + 'trailer\n<< /Root 1 0 R >>\n%%EOF\n';
}
const sheet = (title: string, scale: string, no: string) => t(900, 200, 22, title) + t(900, 175, 9, `SCALE: ${scale}`) + t(2300, 120, 30, no) + t(2300, 90, 9, 'ZZ DEMO');

// 3" SS on layer P-SANR: 360 pt at 1/4" = 1'-0" (2/3 real in per pt) = 240 in = 20 ft = 6.1 m.
const plumbingPdf = pdf(sheet('FIRST FLOOR PLUMBING PLAN', '1/4" = 1\'-0"', 'P1.01') +
  tags('WC-1', 5, 300, 1400) + tags('L-1', 5, 300, 1300) + tags('FD-1', 4, 300, 1200) + tags('FCO', 2, 300, 1100) +
  t(1500, 1400, 9, 'EF-1') + t(1500, 1300, 9, 'FCU-1') + t(1500, 1200, 9, 'FCU-2') +
  '/OC /L1 BDC q 1.68 w\n500 800 m 860 800 l S\nQ EMC\n' + t(660, 810, 9, '3" SS'), ['P-SANR']);

const electricalPdf = pdf(sheet('GROUND FLOOR LIGHTING AND POWER PLAN', '1/8" = 1\'-0"', 'E1.01') +
  tags('LT-1', 10, 300, 1400) + tags('DS-1', 8, 300, 1300) + tags('D-1', 4, 300, 1200) + tags('SD', 3, 300, 1100), []);

// ── ground truth ────────────────────────────────────────────────────────────────────────────────
// `match` is a case-insensitive regex tested against a BOQ line's "type description"; `unit` is the unit
// the quantity is known in (the scorer converts ft to m). A line that matches no item is a false positive.
type Item = { id: string; trade: string; match: string; qty: number; unit: 'nos' | 'm' };
const truth: Record<string, { format: 'dxf' | 'pdf'; items: Item[] }> = {
  'zz_demo_electrical_gf.dxf': { format: 'dxf', items: [
    { id: 'light_fitting', trade: 'electrical', match: 'LIGHT_FITTING', qty: 12, unit: 'nos' },
    { id: 'double_socket', trade: 'electrical', match: 'DOUBLE_SOCKET', qty: 9, unit: 'nos' },
    { id: 'smoke_detector', trade: 'fire_alarm', match: '^smoke_detector ', qty: 6, unit: 'nos' },
    { id: 'manual_call_point', trade: 'fire_alarm', match: '^manual_call_point ', qty: 2, unit: 'nos' },
    { id: 'door', trade: 'doors', match: 'DOOR_SINGLE', qty: 5, unit: 'nos' },
    { id: 'conduit_m', trade: 'electrical', match: 'layer E-CONDUIT', qty: 38.4, unit: 'm' },
  ] },
  'zz_demo_plumbing_ff.dxf': { format: 'dxf', items: [
    { id: 'water_closet', trade: 'plumbing', match: 'block WC$', qty: 4, unit: 'nos' },
    { id: 'wash_basin', trade: 'plumbing', match: 'WASH_BASIN', qty: 4, unit: 'nos' },
    { id: 'floor_drain', trade: 'plumbing', match: 'FLOOR_DRAIN', qty: 3, unit: 'nos' },
    { id: 'drain_pipe_m', trade: 'plumbing', match: 'layer P-DRAIN', qty: 27, unit: 'm' },
    { id: 'cold_water_pipe_m', trade: 'plumbing', match: 'layer P-COLD-WATER', qty: 18.4, unit: 'm' },
  ] },
  'zz_demo_plumbing_p101.pdf': { format: 'pdf', items: [
    { id: 'water_closet', trade: 'plumbing', match: 'water closet', qty: 5, unit: 'nos' },
    { id: 'lavatory', trade: 'plumbing', match: 'lavatory', qty: 5, unit: 'nos' },
    { id: 'floor_drain', trade: 'plumbing', match: 'floor drain', qty: 4, unit: 'nos' },
    { id: 'floor_cleanout', trade: 'plumbing', match: 'cleanout', qty: 2, unit: 'nos' },
    { id: 'exhaust_fan', trade: 'hvac', match: 'exhaust fan', qty: 1, unit: 'nos' },
    { id: 'fan_coil_unit', trade: 'hvac', match: 'fan coil', qty: 2, unit: 'nos' },
    { id: 'sanitary_pipe_m', trade: 'plumbing', match: '^pipe:', qty: 6.1, unit: 'm' },
  ] },
  'zz_demo_electrical_e101.pdf': { format: 'pdf', items: [
    { id: 'light_fitting', trade: 'electrical', match: 'light|LT-1', qty: 10, unit: 'nos' },
    { id: 'double_socket', trade: 'electrical', match: 'socket|DS-1', qty: 8, unit: 'nos' },
    { id: 'door', trade: 'doors', match: 'door|\\bD-1', qty: 4, unit: 'nos' },
    { id: 'smoke_detector', trade: 'fire_alarm', match: 'smoke', qty: 3, unit: 'nos' },
  ] },
};

const files: Record<string, string> = {
  'zz_demo_electrical_gf.dxf': electricalDxf, 'zz_demo_plumbing_ff.dxf': plumbingDxf,
  'zz_demo_plumbing_p101.pdf': plumbingPdf, 'zz_demo_electrical_e101.pdf': electricalPdf,
};
await Deno.mkdir(OUT, { recursive: true });
for (const [name, body] of Object.entries(files)) await Deno.writeTextFile(new URL(name, OUT), body);
await Deno.writeTextFile(new URL('ground_truth.json', OUT), JSON.stringify(truth, null, 2) + '\n');
console.log(`wrote ${Object.keys(files).length} drawings and ground_truth.json`);
