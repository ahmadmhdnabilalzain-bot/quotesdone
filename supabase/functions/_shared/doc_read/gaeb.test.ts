// gaeb — GAEB DA XML items, sections and units; prices never read.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/gaeb.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readGaeb } from './gaeb.ts';
import { GAEB_PRICES, gaebFixture, gaebX84Fixture } from './gaeb.fixtures.ts';
import type { Extracted, ReadResult } from './types.ts';

const ctx = { filename: 'boq.x83', depth: 0 };
const good = (r: ReadResult): Extracted => { if (!r.ok) throw new Error(r.error); return r; };

Deno.test('X83: three items with quantities, units, category sections and ordinals', async () => {
  const e = good(await readGaeb(gaebFixture(), ctx));
  assertEquals(e.quantities.map((q) => [q.section, q.qty, q.unit, q.basis]), [
    ['Earthworks', 120.5, 'm3', 'GAEB item 01.0010'],
    ['Earthworks', 80, 'm3', 'GAEB item 01.0020'],
    ['أعمال البلاط / Tiling', 250.75, 'm2', 'GAEB item 02.0010'],
  ]);
  assertEquals(e.quantities[0].description, 'Excavation for footings (01.0010)');
  assert(e.quantities[2].description.includes('بلاط أرضيات بورسلين'));
  assert(e.text.includes('Backfilling in layers') && e.text.includes('ZZ DEMO Villa fit-out'));
  assertEquals(e.notes[0], 'X83 bid request.');
});

Deno.test('X84: prices present in the file never appear anywhere in the result', async () => {
  const e = good(await readGaeb(gaebX84Fixture(), { ...ctx, filename: 'bid.x84' }));
  const json = JSON.stringify(e);
  for (const p of GAEB_PRICES) assert(!json.includes(p), `price ${p} leaked`);
  assertEquals(e.quantities.length, 3);
  assertEquals(e.notes[0], 'X84 bid: prices present in the file were not read.');
});

Deno.test('not GAEB XML is refused', async () => {
  assertEquals((await readGaeb(new TextEncoder().encode('<root><Item/></root>'), ctx)).ok, false);
  assertEquals((await readGaeb(new TextEncoder().encode('00 GAEB 90 text'), ctx)).ok, false);
});
