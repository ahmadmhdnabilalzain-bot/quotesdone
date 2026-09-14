// ifc — STEP tokeniser, element counts and model-stated quantities.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/doc_read/ifc.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { decodeStepString, parseStepData, readIfc } from './ifc.ts';
import { IFC_FIXTURE_TEXT, ifcFixture } from './ifc.fixtures.ts';
import type { Extracted, ReadResult } from './types.ts';

const ctx = { filename: 'model.ifc', depth: 0 };
const good = (r: ReadResult): Extracted => { if (!r.ok) throw new Error(r.error + ' ' + r.detail); return r; };
const find = (e: Extracted, d: string) => e.quantities.find((q) => q.description === d);

Deno.test('fixture: two walls counted per type and storey, NetSideArea and Length summed and converted', async () => {
  const e = good(await readIfc(ifcFixture(), ctx));
  const n = find(e, 'IfcWall · Basic Wall 200mm');
  assertEquals([n?.section, n?.qty, n?.unit], ['Level 1', 2, 'nos']);
  const a = find(e, 'IfcWall · Basic Wall 200mm · NetSideArea');
  assertEquals([a?.section, a?.qty, a?.unit, a?.confidence], ['Level 1', 27.5, 'sqm', 'medium']);
  const l = find(e, 'IfcWall · Basic Wall 200mm · Length');
  assertEquals([l?.qty, l?.unit], [9, 'm']);                 // 9000 mm stated, MILLI METRE unit
  assertEquals(find(e, 'IfcSpace · (untyped)')?.qty, 1);
  for (const t of ['ZZ DEMO Villa', "Architect's issue", 'Level 1', 'Basic Wall 200mm', 'غرفة 1']) assert(e.text.includes(t), t);
});

Deno.test('string encodings', () => {
  // \X2\ UTF-16, \X\ one ISO-8859-1 byte, \S\ high-half char (i + 128 = é), \\ a backslash.
  assertEquals(decodeStepString('\\X2\\00E9\\X0\\t\\X\\E9 \\S\\i a\\\\b'), 'été é a\\b');
  assertEquals(decodeStepString('\\X2\\063A06310641\\X0\\'), 'غرف');
});

Deno.test('a model without base quantities gives counts and says areas are missing', async () => {
  const src = IFC_FIXTURE_TEXT.replace(/#7[67]=.*\n/g, '');
  const e = good(await readIfc(new TextEncoder().encode(src), ctx));
  assertEquals(find(e, 'IfcWall · Basic Wall 200mm')?.qty, 2);
  assert(!e.quantities.some((q) => q.unit === 'sqm'));
  assert(e.notes.some((x) => x.includes('no IfcElementQuantity')));
});

Deno.test('malformed: no header refused; a broken instance skipped, the rest read', async () => {
  assertEquals((await readIfc(new TextEncoder().encode('DATA;#1=IFCWALL();ENDSEC;'), ctx)).ok, false);
  const src = IFC_FIXTURE_TEXT.replace('#50=IFCWALLTYPE(', '#50=IFCWALLTYPE((');
  const e = good(await readIfc(new TextEncoder().encode(src), ctx));
  assert(e.notes.some((x) => x.includes('1 malformed')));
  assertEquals(find(e, 'IfcWall · Basic Wall:Basic Wall 200mm')?.qty, 2); // falls back to ObjectType
});

Deno.test('entity cap stops the tokeniser and says counts are partial', async () => {
  const p = parseStepData(IFC_FIXTURE_TEXT, 3);
  assertEquals([p.insts.size, p.capped], [3, true]);
  const e = good(await readIfc(ifcFixture(), ctx, 10));
  assert(e.notes.some((x) => x.includes('more than 10 instances')));
});
