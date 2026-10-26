// dwg — the LibreDWG entity JSON goes through the DXF take-off unchanged; RVT and DGN say what they need.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/doc_read/dwg.test.ts
//
// Offline and deterministic: the entities below have the exact shape @mlightcad/libredwg-web 0.7.14
// returns (copied field-for-field from its output on LibreDWG's sample drawings, 22 Sep 2026). The
// real-DWG proof, which needs the network, is dwg_samples.check.ts, run as its own CI step.
import { assert, assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import { dwgToDxf, DWG_MAX_BYTES, lowerMemoryFloor, readDwg, type DwgDb } from './dwg.ts';
// @deno-types="../vendor/sheetjs-0.20.3/types/index.d.ts"
import { CFB } from '../vendor/sheetjs-0.20.3/xlsx.mjs';
import { readDxf } from './cad.ts';
import { dxfBinaryFrom } from './cad.fixtures.ts';
import { cadSupplierBoq } from '../cad_identity.ts';
import { boqFromExtracted } from '../../drawing_boq/boq_from_document.ts';
import { readDocument } from './index.ts';
import type { Extracted, ReadResult } from './types.ts';
// The notes are English at the source; the customer's and the supplier's screens show them in Arabic through
// src/lib/boqNotes.ts (founder instruction 586). Asserted here so an ask without its Arabic fails beside the reader.
import { boqNoteAr } from '../../../../src/lib/boqNotes.ts';

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
  assert(e.notes.some((n) => n.includes('DXF')), e.notes.join(' | '));
  for (const n of e.notes) assert(/[؀-ۿ]/.test(boqNoteAr(n) || ''), `no Arabic for: ${n}`);
});

Deno.test('the npm import and the pinned WASM URL name the same package version', () => {
  const src = Deno.readTextFileSync(new URL('./dwg.ts', import.meta.url));
  const pkg = src.match(/const PKG = '([^']+)'/)?.[1];
  assert(pkg && src.includes(`import('npm:${pkg}')`), `dynamic import must be the literal npm:${pkg}`);
});

Deno.test('a Revit model and a DGN v7 are recognised and told what to export, not read as a spreadsheet', async () => {
  const utf16 = (s: string) => new Uint8Array([...s].flatMap((c) => [c.charCodeAt(0), 0]));
  const c = CFB.utils.cfb_new();
  CFB.utils.cfb_add(c, '/BasicFileInfo', new Uint8Array([7, ...utf16('Worksharing: Not enabled\r\nFormat: 2024\r\n')]));
  CFB.utils.cfb_add(c, '/ProjectInformation', new Uint8Array(8));
  const r = good(await readDocument(new Uint8Array(CFB.write(c, { type: 'array' })), 'tower.rvt'));
  assertEquals([r.kind, r.needs, r.quantities.length], ['rvt', 'bim_conversion', 0]);
  assert(r.notes.some((n) => n.includes('File > Export > IFC')), r.notes.join(' | '));
  for (const n of r.notes) assert(/[؀-ۿ]/.test(boqNoteAr(n) || ''), `no Arabic for: ${n}`);

  const dgn = new Uint8Array(2048); dgn.set([0x08, 0x09, 0xfe, 0x02]);
  const g = good(await readDocument(dgn, 'site.dgn'));
  assertEquals([g.kind, g.needs, g.notes[0]], ['dgn', 'cad_conversion', 'This is a MicroStation DGN V7 (2D) file.']);
  assert(g.notes[1].includes('DWG or DXF') && g.notes[1].includes('PDF'), g.notes[1]);
  for (const n of g.notes) assert(/[؀-ۿ]/.test(boqNoteAr(n) || ''), `no Arabic for: ${n}`);
});

// THE 1 GB MEMORY FLOOR (22 Sep 2026): every DWG died on production with "Memory limit exceeded" because
// the .wasm asked for 1 GB before reading a byte. Prevented by this test (the rewrite itself) and by
// dwg_samples.check.ts (the real .wasm, after the rewrite, declares WASM_MIN_PAGES and still reads).
Deno.test('lowerMemoryFloor rewrites the memory minimum in place, same width, nothing else moves', () => {
  // magic+version, a type section (id 1, 4 bytes), memory section (id 5): 1 memory, flags 1, min 16384 (3-byte LEB), max 65536 (3-byte LEB)
  const wasm = new Uint8Array([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, 1, 4, 1, 0x60, 0, 0, 5, 8, 1, 1, 0x80, 0x80, 0x01, 0x80, 0x80, 0x04]);
  const before = wasm.slice();
  assertEquals(lowerMemoryFloor(wasm, 256), { from: 16384, to: 256 });
  assertEquals(wasm.length, before.length);
  assertEquals([...wasm.subarray(18, 21)], [0x80, 0x82, 0x00]);                 // 256, padded to 3 bytes
  assertEquals([...wasm.subarray(0, 18)], [...before.subarray(0, 18)]);
  assertEquals([...wasm.subarray(21)], [...before.subarray(21)]);               // the maximum is untouched
  assert(WebAssembly.validate(wasm), 'still a valid module');
  assertEquals(new WebAssembly.Memory({ initial: 1 }).buffer.byteLength, 65536);  // sanity: pages are 64 KB
  assertEquals(lowerMemoryFloor(wasm, 256), { from: 256, to: 256 });            // a rerun changes nothing
});

// THE REDACTION AUDIT (22 Sep 2026, #827): a CAD file's title-block names reached suppliers through the
// take-off. Every CAD reader here now hands back the DXF text it measured (dxf_text), and drawing_boq and
// the CAD worker pass it to cad_identity.cadSupplierBoq. This fails if a DWG's or a binary DXF's own job
// names reach a BOQ line again.
Deno.test('a DWG and a binary DXF: nothing the file says about its own job reaches a BOQ line', async () => {
  const db: DwgDb = { header: { INSUNITS: 6, PROJECTNAME: 'ZZ HARBOUR TOWER' }, entities: [
    { type: 'INSERT', layer: 'ZZORBIT-TITLE', name: 'ZZORBIT_TITLEBLOCK_A1', insertionPoint: { x: 0, y: 0 } },
    { type: 'ATTRIB', layer: 'ZZORBIT-TITLE', text: { text: 'ZZ ORBIT CONSULTING ENGINEERS' }, tag: 'CONSULTANT' },
    { type: 'LINE', layer: 'ZZORBIT-M-DUCT', startPoint: { x: 0, y: 0 }, endPoint: { x: 12, y: 0 } },
    { type: 'INSERT', layer: 'M-HVAC', name: 'FCU', insertionPoint: { x: 1, y: 1 } },
  ] };
  const dwg = good(await readDxf(new TextEncoder().encode(dwgToDxf(db).dxf), ctx));
  const pairs: [number, string | number][] = [
    [0, 'SECTION'], [2, 'HEADER'], [9, '$INSUNITS'], [70, 6], [9, '$PROJECTNAME'], [1, 'ZZ HARBOUR TOWER'], [0, 'ENDSEC'],
    [0, 'SECTION'], [2, 'ENTITIES'],
    [0, 'INSERT'], [8, 'ZZORBIT-TITLE'], [2, 'ZZORBIT_TITLEBLOCK_A1'], [10, 0], [20, 0],
    [0, 'LINE'], [8, 'ZZORBIT-M-DUCT'], [10, 0], [20, 0], [11, 12], [21, 0],
    [0, 'INSERT'], [8, 'M-HVAC'], [2, 'FCU'], [10, 1], [20, 1],
    [0, 'TEXT'], [8, 'ZZORBIT-TITLE'], [1, 'CLIENT: ZZ HARBOUR TOWER'],
    [0, 'ENDSEC'], [0, 'EOF'],
  ];
  const bin = good(await readDxf(dxfBinaryFrom(pairs), ctx));
  for (const e of [dwg, bin]) {
    assert(e.dxf_text && e.dxf_text.includes('ZZ HARBOUR TOWER'), 'the reader hands back the text it measured');
    const out = JSON.stringify(cadSupplierBoq(boqFromExtracted(e, '', '', {}), e.dxf_text));
    for (const bad of [/ZZORBIT/i, /ZZ ORBIT/i, /HARBOUR/i, /TITLEBLOCK/i]) assert(!bad.test(out), `${bad} reached the BOQ: ${out.slice(0, 300)}`);
    assert(/FCU/.test(out) && /M-DUCT/.test(out), `the work is still there: ${out.slice(0, 300)}`);
  }
});
