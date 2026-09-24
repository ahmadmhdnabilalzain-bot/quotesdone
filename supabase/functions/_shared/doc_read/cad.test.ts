// cad — ASCII DXF quantities and text.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/cad.test.ts
import { assert, assertAlmostEquals, assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { binaryDxfToAscii, readDxf, redactDxf, stripMtext } from './cad.ts';
import { dxfBinaryFrom, dxfFixture, dxfFixturePairs, dxfFrom, dxfSection, dxfTitleBlockFixture } from './cad.fixtures.ts';
import type { Extracted, ReadResult } from './types.ts';

const ctx = { filename: 'plan.dxf', depth: 0 };
const good = (r: ReadResult): Extracted => { if (!r.ok) throw new Error(r.error); return r; };
const q = (e: Extracted, unit: string, section: string) => e.quantities.find((x) => x.unit === unit && x.section === section);

Deno.test('fixture: FLOOR 20.00 sqm, WALLS 9.00 m, D-900 x3, text read, blocks section not counted', async () => {
  const e = good(await readDxf(dxfFixture(), ctx));
  assertEquals(q(e, 'sqm', 'layer FLOOR')?.qty, 20);
  assertEquals(q(e, 'm', 'layer FLOOR')?.qty, 18);
  assertEquals(q(e, 'm', 'layer WALLS')?.qty, 9);          // the 900 mm line inside BLOCKS is not added
  const d = e.quantities.find((x) => x.unit === 'nos');
  assertEquals([d?.description, d?.qty, d?.basis], ['block D-900', 3, 'block D-900 inserted 3 times']);
  assert(e.quantities.every((x) => x.confidence === 'medium'));
  assert(e.text.includes('LIVING ROOM'));
  assert(e.text.includes('غرفة المعيشة') && e.text.includes('المطبخ Ø50'), e.text);
  assert(!e.text.includes('\\f') && !e.text.includes('{'));
});

Deno.test('bulge arcs: two half-circle segments make a unit circle (area pi, perimeter 2 pi)', async () => {
  const e = good(await readDxf(dxfFrom([
    ...dxfSection('HEADER', [[9, '$INSUNITS'], [70, 6]]),
    ...dxfSection('ENTITIES', [[0, 'LWPOLYLINE'], [8, 'TANK'], [90, 2], [70, 1], [10, 0], [20, 0], [42, 1], [10, 2], [20, 0], [42, 1]]),
    [0, 'EOF'],
  ]), ctx));
  assertAlmostEquals(q(e, 'sqm', 'layer TANK')!.qty!, Math.PI, 0.01);
  assertAlmostEquals(q(e, 'm', 'layer TANK')!.qty!, 2 * Math.PI, 0.01);
});

Deno.test('no $INSUNITS: mm assumed from coordinates, confidence low, note says so', async () => {
  const e = good(await readDxf(dxfFrom([
    ...dxfSection('ENTITIES', [[0, 'LINE'], [8, 'W'], [10, 0], [20, 0], [11, 3000], [21, 0]]),
    [0, 'EOF'],
  ]), ctx));
  assertEquals(q(e, 'm', 'layer W')?.qty, 3);
  assertEquals(q(e, 'm', 'layer W')?.confidence, 'low');
  assert(e.notes.some((n) => n.includes('millimetres were assumed')));
});

// 22 Sep 2026: binary DXF is READ (it was answered needs:'cad_conversion'). Prevented from regressing by
// these three tests and by dwg_samples.check.ts (LibreDWG's real .dxfb files against their ASCII DXF).
Deno.test('binary DXF, R13+ and R12 codes: the same take-off and text as the ASCII fixture', async () => {
  const asc = good(await readDxf(dxfFixture(), ctx));
  for (const wide of [true, false]) {
    const bin = good(await readDxf(dxfBinaryFrom(dxfFixturePairs(), wide), ctx));
    assertEquals([bin.kind, bin.needs], ['dxf', null]);
    assertEquals(bin.quantities, asc.quantities);
    assertEquals(bin.text, asc.text);
    assert(/^Read from binary DXF: \d+ group-code pairs\.$/.test(bin.notes[0]), bin.notes[0]);
  }
});

Deno.test('hostile binary DXF: truncated, unknown code, unterminated string, a lone sentinel - refused, never thrown', async () => {
  const full = dxfBinaryFrom(dxfFixturePairs());
  const bad = [
    full.subarray(0, full.length - 5),                                                    // a real cut mid-value
    new Uint8Array([...full.subarray(0, 22), 0x39, 0x30, 1, 2, 3]),                       // code 12345: no value type
    new Uint8Array([...full.subarray(0, 22), 0, 0, 0x53, 0x45, 0x43]),                    // "SEC" with no NUL
    new TextEncoder().encode('AutoCAD Binary DXF\r\n\x1a\x00\x00\x00'),
  ];
  for (const b of bad) {
    const r = await readDxf(b, ctx);
    if (r.ok) assertEquals(r.quantities.length, 0, 'a lone sentinel reads as an empty drawing, nothing invented');
    else assertEquals(r.error, 'dxf_unreadable');
  }
  assertEquals((await readDxf(new TextEncoder().encode('hello world'), ctx)).ok, false);
});

Deno.test('binary DXF: the pair cap stops a hostile file and the note says the totals are partial', () => {
  const r = binaryDxfToAscii(dxfBinaryFrom(dxfFixturePairs()), 10);
  assertEquals([r.pairs, r.capped], [10, true]);
});

Deno.test('entity cap stops reading and says the totals are partial', async () => {
  const e = good(await readDxf(dxfFixture(), ctx, 2));
  assert(e.notes.some((n) => n.includes('more than 2 entities')));
  assertEquals(e.quantities.find((x) => x.unit === 'nos'), undefined);
});

Deno.test('redactDxf: the client is gone from every string, geometry and quantities unchanged', async () => {
  const src = dxfTitleBlockFixture();
  const before = good(await readDxf(src, ctx));
  assert(before.text.includes('CLIENT: Ahmed Al Mansoori'));          // the fixture really carries him
  const r = redactDxf(src, (s) => s.replace(/Ahmed|Al Mansoori|Mansoori/gi, '[client]'));
  const out = new TextDecoder().decode(r.bytes);
  for (const bad of [/mansoori/i, /ahmed/i, /Projects/, /site\.dwg/]) {
    assert(!bad.test(r.residualCheck), `residual ${bad}`);
    assert(!bad.test(out), `output ${bad}`);
  }
  assert(r.changed >= 9, `changed ${r.changed}`);
  assert(r.residualCheck.includes('[client] VILLA') && r.residualCheck.includes('LIVING ROOM'));
  const after = good(await readDxf(r.bytes, ctx));
  const shape = (e: Extracted) => e.quantities.map((x) => `${x.qty} ${x.unit}`).sort();
  assertEquals(shape(after), shape(before));
  assertEquals(q(after, 'm', 'layer [client] VILLA')?.qty, 2);
  assertEquals(q(after, 'sqm', 'layer FLOOR')?.qty, 20);
  assertThrows(() => redactDxf(new TextEncoder().encode('AutoCAD Binary DXF\r\n\x1a\x00'), (s) => s));
});

Deno.test('redactDxf on a BINARY DXF: the supplier gets a redacted ASCII DXF with the same take-off', async () => {
  const pairs = dxfFixturePairs();
  pairs.splice(pairs.length - 2, 0, [0, 'TEXT'], [8, 'TITLE'], [10, 0], [20, -500], [40, 100], [1, 'CLIENT: Ahmed Al Mansoori']);
  const bin = dxfBinaryFrom(pairs);
  const r = redactDxf(bin, (s) => s.replace(/Ahmed|Al Mansoori/gi, '[client]'));
  const out = new TextDecoder().decode(r.bytes);
  assert(!/mansoori|ahmed/i.test(out) && !out.startsWith('AutoCAD Binary'), 'identity gone, output is ASCII');
  const shape = (e: Extracted) => e.quantities.map((x) => `${x.qty} ${x.unit}`).sort();
  assertEquals(shape(good(await readDxf(r.bytes, ctx))), shape(good(await readDxf(bin, ctx))));
  assertThrows(() => redactDxf(bin.subarray(0, bin.length - 5), (s) => s));   // cannot follow it -> never passed on
});

Deno.test('MTEXT formatting codes', () => {
  assertEquals(stripMtext('{\\H2.5;\\C1;A}\\PB\\LC\\l \\S1^2; %%d'), 'A\nBC 1/2 °');
});

// Review of #967 (24 Sep 2026): the legend window scaled with the heading's height, so a 250 mm LEGEND heading
// opened a 10 m x 20 m window and five real detectors beside CORRIDOR tags were dropped as "samples". The window
// is now bounded in real units, a sample needs a legend-style description, and it must stand in the column.
Deno.test('legend samples: a big heading does not swallow real detectors beside room tags', async () => {
  const ins = (x: number, y: number): [number, string | number][] => [[0, 'INSERT'], [8, 'E-FIRE'], [2, 'SD'], [10, x], [20, y], [30, 0]];
  const txt = (x: number, y: number, h: number, s: string): [number, string | number][] => [[0, 'TEXT'], [8, 'A-ANNO'], [10, x], [20, y], [30, 0], [40, h], [1, s]];
  const real: [number, number][] = [[2000, -2500], [4500, -4000], [7000, -6000], [3000, -9000], [8500, -12000]];
  // And one 5 m below the heading whose neighbour even reads like a legend entry: 4.6 m past the legend's last row
  // (more than a row's gap), it is work.
  const described: [number, number] = [300, -5000];
  const src = dxfFrom([
    [0, 'SECTION'], [2, 'HEADER'], [9, '$INSUNITS'], [70, 4], [0, 'ENDSEC'],
    [0, 'SECTION'], [2, 'ENTITIES'],
    ...txt(0, 0, 250, 'LEGEND'),
    ...ins(100, -400), ...txt(500, -450, 160, 'SD - SMOKE DETECTOR'),
    ...real.flatMap(([x, y]) => [...ins(x, y), ...txt(x + 400, y - 50, 160, 'CORRIDOR')]),
    ...ins(described[0], described[1]), ...txt(described[0] + 400, described[1] - 50, 160, 'SD - NORTH WALL'),
    [0, 'ENDSEC'], [0, 'EOF'],
  ]);
  const r = await readDxf(src, { filename: 'plan.dxf', depth: 0 });
  if (!r.ok) throw new Error(r.error);
  assertEquals(r.quantities.find((q) => q.description === 'block SD')?.qty, 6);
  assert(r.notes.some((n) => n.startsWith('1 block insert(s) drawn as legend samples')), r.notes.join(' | '));
});

// Second review of #967 (25 Sep 2026): a hard 3 m stop under the heading counted the last rows of a real legend as
// work - a 10-row legend at 600 mm pitch (6 mm on paper at 1:100) runs 6 m down. The window now walks down the
// legend's column while its description rows continue, and stops at the first gap wider than a row.
Deno.test('legend samples: a 10-row legend at 400 and 600 mm pitch is set aside whole; the plan counts 4 of each', async () => {
  const ins = (b: string, x: number, y: number): [number, string | number][] => [[0, 'INSERT'], [8, 'E-DEV'], [2, b], [10, x], [20, y], [30, 0]];
  const txt = (x: number, y: number, h: number, s: string): [number, string | number][] => [[0, 'TEXT'], [8, 'A-ANNO'], [10, x], [20, y], [30, 0], [40, h], [1, s]];
  const syms = ['SD', 'HD', 'MCP', 'SKT', 'DSKT', 'SW1', 'SW2', 'DL', 'EL', 'FCU'];
  for (const pitch of [400, 600]) {
    const src = dxfFrom([[0, 'SECTION'], [2, 'HEADER'], [9, '$INSUNITS'], [70, 4], [0, 'ENDSEC'], [0, 'SECTION'], [2, 'ENTITIES'],
      ...txt(30000, 0, 350, 'LEGEND'),
      ...syms.flatMap((s, i) => [...ins(s, 30100, -600 - i * pitch), ...txt(30600, -650 - i * pitch, 200, `${s} - DESCRIPTION ${i}`)]),
      ...syms.flatMap((s, i) => [0, 1, 2, 3].flatMap((k) => ins(s, 2000 + k * 3000, 2000 + i * 1500))),
      [0, 'ENDSEC'], [0, 'EOF']]);
    const r = await readDxf(src, { filename: 'plan.dxf', depth: 0 });
    if (!r.ok) throw new Error(r.error);
    assertEquals(syms.map((s) => r.quantities.find((q) => q.description === 'block ' + s)?.qty), syms.map(() => 4), `pitch ${pitch} mm`);
    assert(r.notes.some((n) => n.startsWith('10 block insert(s) drawn as legend samples')), r.notes.join(' | '));
  }
});
