// dwg — the LibreDWG entity JSON goes through the DXF take-off unchanged; RVT and DGN say what they need.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/doc_read/dwg.test.ts
//
// Offline and deterministic: the entities below have the exact shape @mlightcad/libredwg-web 0.7.14
// returns (copied field-for-field from its output on LibreDWG's sample drawings, 22 Sep 2026). The
// real-DWG proof, which needs the network, is dwg_samples.check.ts, run as its own CI step.
import { assert, assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import { dwgToDxf, DWG_MAX_BYTES, readDwg, type DwgDb } from './dwg.ts';
import { readDxf } from './cad.ts';
import { readDocument } from './index.ts';
import type { Extracted, ReadResult } from './types.ts';

const ctx = { filename: 'plan.dwg', depth: 0 };
const good = (r: ReadResult): Extracted => { if (!r.ok) throw new Error(r.error); return r; };
const q = (e: Extracted, unit: string, section: string) => e.quantities.find((x) => x.unit === unit && x.section === section);
const takeoff = async (db: DwgDb) => good(await readDxf(new TextEncoder().encode(dwgToDxf(db).dxf), ctx));

// A 5 x 4 m room drawn in millimetres, the way LibreDWG hands it over.
const room: DwgDb = {
  header: { INSUNITS: 4 },
  entities: [
    // DWG flag 512 = closed. (DWG bit 1 is "has extrusion", not closed.)
    { type: 'LWPOLYLINE', layer: 'FLOOR', flag: 512, vertices: [
      { id: 0, x: 0, y: 0, bulge: 0 }, { id: 1, x: 5000, y: 0, bulge: 0 }, { id: 2, x: 5000, y: 4000, bulge: 0 }, { id: 3, x: 0, y: 4000, bulge: 0 }] },
    { type: 'LWPOLYLINE', layer: 'OPEN', flag: 1, vertices: [{ id: 0, x: 0, y: 0, bulge: 0 }, { id: 1, x: 2000, y: 0, bulge: 0 }] },
    { type: 'LINE', layer: 'WALLS', startPoint: { x: 0, y: 0, z: 0 }, endPoint: { x: 3000, y: 0, z: 0 } },
    // Angles in RADIANS: a quarter arc of radius 1000 mm is 1.571 m.
    { type: 'ARC', layer: 'WALLS', center: { x: 0, y: 0, z: 0 }, radius: 1000, startAngle: 0, endAngle: Math.PI / 2 },
    { type: 'CIRCLE', layer: 'COLS', center: { x: 0, y: 0, z: 0 }, radius: 500 },
    // A heavy 2D polyline: two half-circle bulges make a 2 m diameter disc.
    { type: 'POLYLINE2D', layer: 'TANK', flag: 1, vertices: [{ x: 0, y: 0, z: 0, bulge: 1 }, { x: 2000, y: 0, z: 0, bulge: 1 }] },
    { type: 'INSERT', layer: 'DOORS', name: 'D-900', insertionPoint: { x: 1, y: 1, z: 0 }, attribs: [] },
    { type: 'INSERT', layer: 'DOORS', name: 'D-900', insertionPoint: { x: 2, y: 1, z: 0 }, attribs: [] },
    { type: 'INSERT', layer: 'DIMS', name: '*D3', insertionPoint: { x: 0, y: 0, z: 0 }, attribs: [] },
    { type: 'TEXT', layer: 'ANNO', text: 'LIVING ROOM' },
    { type: 'MTEXT', layer: 'ANNO', text: 'غرفة المعيشة\\Psecond line' },
    { type: 'ATTRIB', layer: 'ANNO', text: { text: 'TAG D-900' } },
    { type: 'DIMENSION', layer: 'DIMS', text: '', measurement: 3000 },
    { type: 'DIMENSION', layer: 'DIMS', text: '', measurement: 0 },
    { type: 'SPLINE', layer: 'X' }, { type: 'SPLINE', layer: 'X' }, { type: 'HATCH', layer: 'X' },
  ],
};

Deno.test('LibreDWG entities -> the DXF take-off: areas, lengths, blocks, text', async () => {
  const e = await takeoff(room);
  assertEquals(q(e, 'sqm', 'layer FLOOR')?.qty, 20);
  assertEquals(q(e, 'm', 'layer FLOOR')?.qty, 18);
  assertEquals(q(e, 'sqm', 'layer OPEN'), undefined);            // flag 1 is extrusion, not closed
  assertEquals(q(e, 'm', 'layer OPEN')?.qty, 2);
  assertAlmostEquals(q(e, 'm', 'layer WALLS')!.qty!, 3 + Math.PI / 2, 0.01);
  assertAlmostEquals(q(e, 'm', 'layer COLS')!.qty!, Math.PI, 0.01);
  assertAlmostEquals(q(e, 'sqm', 'layer TANK')!.qty!, Math.PI, 0.01);
  const d = e.quantities.find((x) => x.unit === 'nos');
  assertEquals([d?.description, d?.qty], ['block D-900', 2]);
  assert(e.notes.some((n) => n.includes('1 anonymous block')));
  assert(e.quantities.every((x) => x.confidence === 'medium'));   // $INSUNITS carried over
  for (const t of ['LIVING ROOM', 'غرفة المعيشة', 'second line', 'TAG D-900', 'DIM 3000']) assert(e.text.includes(t), t);
  assert(!e.text.includes('DIM 0'));
});

Deno.test('what is not measured is counted by type, never dropped silently', () => {
  const { skipped } = dwgToDxf(room);
  assertEquals(Object.fromEntries(skipped), { SPLINE: 2, HATCH: 1 });
});

Deno.test('no INSUNITS in the DWG: the DXF reader guesses and says so', async () => {
  const e = await takeoff({ entities: [{ type: 'LINE', layer: 'W', startPoint: { x: 0, y: 0 }, endPoint: { x: 3000, y: 0 } }] });
  assertEquals(q(e, 'm', 'layer W')?.qty, 3);
  assertEquals(q(e, 'm', 'layer W')?.confidence, 'low');
});

Deno.test('readDwg: not a DWG is refused; past the edge ceiling it says what to send, in Arabic too', async () => {
  assertEquals((await readDwg(new TextEncoder().encode('hello world'), ctx)).ok, false);
  const big = new Uint8Array(DWG_MAX_BYTES + 1); big.set(new TextEncoder().encode('AC1032'));
  const e = good(await readDwg(big, ctx));                       // refused before any WASM is loaded
  assertEquals([e.kind, e.needs], ['dwg', 'cad_conversion']);
  assert(e.notes[0].includes('DXF') && e.notes[0].includes('احفظ الرسم'), e.notes[0]);
});

Deno.test('the npm import and the pinned WASM URL name the same package version', () => {
  const src = Deno.readTextFileSync(new URL('./dwg.ts', import.meta.url));
  const pkg = src.match(/const PKG = '([^']+)'/)?.[1];
  assert(pkg && src.includes(`import('npm:${pkg}')`), `dynamic import must be the literal npm:${pkg}`);
});

Deno.test('a Revit model and a DGN v7 are recognised and told what to export, not read as a spreadsheet', async () => {
  const utf16 = (s: string) => new Uint8Array([...s].flatMap((c) => [c.charCodeAt(0), 0]));
  const rvt = new Uint8Array(4096);
  rvt.set([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]); rvt.set(utf16('BasicFileInfo'), 1024);
  const r = good(await readDocument(rvt, 'tower.rvt'));
  assertEquals([r.kind, r.needs], ['rvt', 'bim_conversion']);
  assert(r.notes[0].includes('IFC') && r.notes[0].includes('ريفيت'), r.notes[0]);

  const dgn = new Uint8Array(2048); dgn.set([0x08, 0x09, 0xfe, 0x02]);
  const g = good(await readDocument(dgn, 'site.dgn'));
  assertEquals([g.kind, g.needs], ['dgn', 'cad_conversion']);
  assert(g.notes[0].includes('DWG or DXF') && g.notes[0].includes('مايكروستيشن'), g.notes[0]);
});
