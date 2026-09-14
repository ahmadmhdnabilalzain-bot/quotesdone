// cad — ASCII DXF quantities and text.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/cad.test.ts
import { assert, assertAlmostEquals, assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { readDxf, redactDxf, stripMtext } from './cad.ts';
import { dxfFixture, dxfFrom, dxfSection, dxfTitleBlockFixture } from './cad.fixtures.ts';
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

Deno.test('binary DXF needs cad_conversion; garbage refused', async () => {
  const bin = new TextEncoder().encode('AutoCAD Binary DXF\r\n\x1a\x00\x00\x00');
  const e = good(await readDxf(bin, ctx));
  assertEquals(e.needs, 'cad_conversion');
  assertEquals((await readDxf(new TextEncoder().encode('hello world'), ctx)).ok, false);
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

Deno.test('MTEXT formatting codes', () => {
  assertEquals(stripMtext('{\\H2.5;\\C1;A}\\PB\\LC\\l \\S1^2; %%d'), 'A\nBC 1/2 °');
});
