// takeoff_rules — the rules behind the engineer's CAD take-off (linear_services.ts, region_takeoff.ts), one by one, and
// the founder's rule that what the drawing does not state becomes an assumption or a line to confirm, never silence
// (10 Nov 2026, sales_engineer; ruling 1586). The whole drawings are scored in drawing_bench.test.ts.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_boq/takeoff_rules.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { measureServices, serviceOf, sizeLabels } from './linear_services.ts';
import { regionOf, regionTakeoff } from './region_takeoff.ts';
import type { CadGeometry } from '../_shared/doc_read/types.ts';

const geo = (g: Partial<CadGeometry>): CadGeometry => ({ toM: 0.001, unitStated: true, unitName: 'mm', segs: {}, closed: [], words: [], inserts: [], capped: false, ...g });
const rect = (layer: string, x: number, y: number, w: number, h: number) => ({ layer, pts: [[x, y], [x + w, y], [x + w, y + h], [x, y + h]] as [number, number][], area: w * h, perim: 2 * (w + h) });
const word = (s: string, x: number, y: number, h = 150) => ({ s, x, y, h, layer: 'A-ANNO' });

Deno.test('the layer says the service: busway, conduit and condensate are never ductwork; annotation is never a run', () => {
  const k = (l: string) => { const s = serviceOf(l); return s ? `${s.kind}:${s.system}` : null; };
  assertEquals([k('E-BUS-DUCT'), k('E-CONDUIT'), k('M-COND'), k('M-HVAC-SUPP'), k('M-DUCT-RETN'), k('M-HVAC-EXHS'), k('M-KITCHEN-EXH'), k('M-FRESH AIR')],
    ['busway:busway', 'conduit:conduit', 'pipe:CD', 'duct:supply air', 'duct:return air', 'duct:exhaust air', 'duct:kitchen exhaust', 'duct:fresh air']);
  assertEquals([k('F-SPRK-PIPE'), k('M-CHWS'), k('P-SANR'), k('P-DOMW-CW'), k('E-TRAY'), k('E-CABLE LADDER'), k('S-BEAM'), k('L-FENCE')],
    ['pipe:SPR', 'pipe:CHW', 'pipe:SS', 'pipe:CW', 'tray:tray', 'ladder:ladder', 'steel:steel', 'member:fence']);
  assertEquals([k('M-HVAC-ANNO'), k('M-DUCT-EXIST'), k('M-HVAC-DIFF'), k('A-WALL'), k('S-GRID')], [null, null, null, null, null]);
});

Deno.test('size labels: duct, round, DN, inch, tray, conduit and steel sections', () => {
  const t = (s: string) => sizeLabels(s).map((l) => `${l.kind}:${l.text}${l.kgm ? '@' + l.kgm : ''}`);
  assertEquals(t('600x400 SA'), ['rect:600x400']);
  assertEquals(t('Ø250'), ['round:Ø250']);
  assertEquals(t('%%c160 EA'), ['round:Ø160']);
  assertEquals(t('DN50 CW'), ['dn:DN50']);
  assertEquals(t('2" SS'), ['round:2"']);
  assertEquals(t('CT 300x50'), ['rect:300x50']);
  assertEquals(t('25mm PVC CONDUIT'), ['round:25mm']);
  assertEquals(t('UB 406x178x60'), ['section:UB 406x178x60@60']);
  assertEquals(t('IPE 200'), ['section:IPE 200']);
});

Deno.test('a duct label that matches only by its depth does not size the branch beside it', () => {
  // A 300 wide branch leaves a 400x300 main; the 400x300 label sits nearer the branch than the branch's own 300x250.
  const walls = (x1: number, y1: number, x2: number, y2: number, w: number) => { const L = Math.hypot(x2 - x1, y2 - y1), nx = -(y2 - y1) / L * w / 2, ny = (x2 - x1) / L * w / 2; return [x1 + nx, y1 + ny, x2 + nx, y2 + ny, x1 - nx, y1 - ny, x2 - nx, y2 - ny]; };
  const g = geo({ segs: { 'M-HVAC-SUPP': [...walls(10000, 0, 16000, 0, 400), ...walls(13000, 200, 13000, 6200, 300)] }, words: [word('400x300', 13000, 400), word('300x250', 13300, 3000)] });
  assertEquals(measureServices(g).lines.map((l) => [l.description, l.qty]).sort(), [['Rectangular duct 300x250 mm (supply air)', 6], ['Rectangular duct 400x300 mm (supply air)', 6]]);
});

Deno.test('no unit stated: every length is our measurement to confirm, never read', () => {
  const g = geo({ unitStated: false, segs: { 'M-CHW-SUPP': [0, 0, 12000, 0] }, words: [word('Ø100 CHWS', 6000, 150)] });
  const l = measureServices(g).lines[0];
  assertEquals([l.qty, l.qty_status, l.estimate], [12, 'to_confirm', 12]);
});

Deno.test('no ceiling height written: wall areas use 3.0 m, say so, and are to confirm', () => {
  const g = geo({ closed: [rect('A-AREA', 0, 0, 4000, 4000)], words: [word('BEDROOM', 1000, 2000, 250)] });
  const t = regionTakeoff(g);
  const wall = t.lines.find((l) => /^Wall finish/.test(l.description))!;
  assertEquals([wall.qty, wall.qty_status], [48, 'to_confirm']);
  assert(t.assumptions.some((a) => /No ceiling height is written for 1 room/.test(a)));
  assertEquals(t.lines.find((l) => /^Floor finish/.test(l.description))?.description, 'Floor finish, finish not specified');
  assertEquals(t.disciplines.architecture.assumed.some((a) => /wall height 3 m/.test(a)), true);
});

Deno.test('no room layer: a closed outline holding exactly one room name is a room; one holding two is not', () => {
  const g = geo({ closed: [rect('0', 0, 0, 3000, 3000), rect('0', -100, -100, 9000, 6000)], words: [word('STORE', 1000, 1500, 200), word('OFFICE', 5000, 1500, 200)] });
  const t = regionTakeoff(g);
  assertEquals(t.rooms.map((r) => [r.name, r.floor_sqm]), [['STORE', 9]]);
  assert(t.assumptions.some((a) => /No room layer is drawn/.test(a)));
});

Deno.test('a pool with no depth written, and a lift with no notes: assumptions and questions, never silence', () => {
  const t = regionTakeoff(geo({ closed: [rect('L-POOL', 0, 0, 8000, 4000), rect('A-LIFT', 10000, 0, 2000, 2000)] }));
  const vol = t.lines.find((l) => /water volume/.test(l.description))!;
  assertEquals([vol.qty, vol.qty_status], [44.8, 'to_confirm']);
  assert(t.assumptions.some((a) => /No pool depth is written/.test(a)));
  assertEquals(t.lines.find((l) => /Passenger lift/.test(l.description))?.qty, 1);
  assert(t.missing.some((m) => /The lift notes do not state: capacity, speed, stops, travel, pit depth, overhead/.test(m)));
});

Deno.test('regions by layer: every trade row, and a wall or a door layer is never a region', () => {
  const r = (l: string) => regionOf(l)?.en ?? null;
  assertEquals([r('L-PLNT'), r('L-TURF'), r('L-PAVE'), r('POOL'), r('A-LIFT-SHAFT'), r('SCAFFOLD'), r('WH-RACKING'), r('A-WATERPROOFING'), r('S-SLAB'), r('A-ROOF'), r('A-CLNG-ZONE'), r('A-AREA')],
    ['Planting bed (softscape)', 'Turf / lawn', 'Paving (hardscape)', 'Swimming pool', 'Lift', 'Scaffolding', 'Racking zone', 'Waterproofing', 'Slab', 'Roof area', 'False ceiling zone', 'Room']);
  assertEquals([r('A-WALL'), r('A-DOOR'), r('A-ANNO'), r('G-TTLB')], [null, null, null, null]);
});

Deno.test('a closed outline on a layer no row names, holding one label, is a labelled area to confirm', () => {
  const t = regionTakeoff(geo({ closed: [rect('X-CUSTOM', 0, 0, 5000, 2000)], words: [word('EPOXY COATING', 1000, 1000)] }));
  const l = t.lines.find((x) => x.type === 'area:labelled')!;
  assertEquals([l.description, l.qty, l.qty_status], ['Area: EPOXY COATING', 10, 'to_confirm']);
});

Deno.test('a dense drawing is measured inside the edge budget (2,000 rooms, 20,000 duct walls, 10,000 words)', () => {
  // The edge kills an isolate at about 2 s of CPU (doc_read/pdf.ts). Measured on this synthetic sheet, 10 Nov 2026.
  const closed = [], words = [], segs: number[] = [];
  for (let i = 0; i < 2000; i++) { const x = (i % 50) * 5000, y = Math.floor(i / 50) * 5000; closed.push(rect('A-AREA', x, y, 4000, 4000)); words.push(word('OFFICE', x + 1000, y + 2000, 200), word('CLG HT 2700', x + 500, y + 500)); }
  for (let i = 0; i < 10000; i++) { const y = i * 1000; segs.push(0, y, 20000, y, 0, y + 400, 20000, y + 400); words.push(word('600x400', 5000 + (i % 7) * 1000, y + 500)); }
  const g = geo({ closed, words, segs: { 'M-HVAC-SUPP': segs } });
  const t0 = performance.now();
  const r = regionTakeoff(g), s = measureServices(g);
  const ms = performance.now() - t0;
  assertEquals(r.rooms.length, 2000);
  assertEquals(s.lines.find((l) => /600x400/.test(l.description))?.qty, 200000);
  assert(ms < 1500, `took ${Math.round(ms)} ms`);
  console.log(`dense drawing: ${Math.round(ms)} ms`);
});
