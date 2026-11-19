// A PAPER-SPACE BLOCK IS NOT COUNTED AS WORK (19 Nov 2026, sales_engineer; agent "sales_engineer drawing-count auditor";
// founder ledger 31 and 580: "count the elements properly").
//
// MEASURED BEFORE THE FIX (origin/main 4c3af02): the drawing bench's own DXF (bench.fixtures.ts benchDxf, a fit-out plan
// with its title block G-TITLE-A1 inserted in PAPER space, group code 67 = 1) came out of readDxf + boqFromExtracted with a
// BOQ line "Blocks | block G-TITLE-A1 | 1" — the sheet's frame and title block, sent to suppliers as an item to price.
// cad.ts kept paper-space inserts out of the geometry (geo.inserts) but still added them to the block counts. Paper
// space is the layout: title blocks, north arrows, key-plan symbols, a layout legend. Nothing in it is built.
// A sheet drawn ONLY in paper space (no model-space entity at all) is still counted, so such a file does not read empty.
//   deno test --no-lock --node-modules-dir=none --allow-read supabase/functions/drawing_boq/a_paper_space_block_is_not_counted_as_work.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDxf } from '../_shared/doc_read/cad.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { benchDxf } from './bench.fixtures.ts';

const CTX = { filename: 'zz-demo.dxf', depth: 0, readChild: () => Promise.reject(new Error('none')) } as never;
type Q = { section: string; description: string; qty: number };
type B = { section: string; item: string; qty: number | null; type?: string };

Deno.test('the bench plan: its paper-space title block is not a BOQ line, and the model-space counts are unchanged', async () => {
  const r = await readDxf(benchDxf(), CTX) as unknown as { ok: true; quantities: Q[]; notes: string[] };
  assertEquals(r.ok, true);
  const blocks = Object.fromEntries(r.quantities.filter((q) => q.section === 'Blocks').map((q) => [q.description, q.qty]));
  assertEquals(blocks['block G-TITLE-A1'], undefined, `paper-space title block counted: ${JSON.stringify(blocks)}`);
  // the answer key (fixtures/bench_truth.json dxf_realistic): doors 5, windows 6, sockets 10, WC 3
  assertEquals([blocks['block DOOR-SGL'], blocks['block WIN-1200'], blocks['block SKT'], blocks['block WC']], [5, 6, 10, 3]);
  const boq = boqFromExtracted(r as never).boq as B[];
  assert(!boq.some((b) => /TITLE/i.test(`${b.item} ${b.section}`)), `a title block reached the BOQ: ${JSON.stringify(boq.map((b) => b.item))}`);
  assert(r.notes.some((n) => /paper space/i.test(n)), 'what was set aside is said in the notes');
});

const ins = (name: string, x: number, paper: boolean) => `0\nINSERT\n8\nFA\n${paper ? '67\n1\n' : ''}2\n${name}\n10\n${x}\n20\n0\n30\n0\n`;
const dxf = (body: string[]) => new TextEncoder().encode(['0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n4\n0\nENDSEC\n', '0\nSECTION\n2\nENTITIES\n', ...body, '0\nENDSEC\n0\nEOF\n'].join(''));

Deno.test('a smoke detector symbol in the layout (paper space) is not a fourth detector', async () => {
  const r = await readDxf(dxf([ins('SMOKE_DETECTOR', 1000, false), ins('SMOKE_DETECTOR', 2000, false), ins('SMOKE_DETECTOR', 3000, false), ins('SMOKE_DETECTOR', 50, true), ins('NORTH_ARROW', 80, true)]), CTX) as unknown as { ok: true; quantities: Q[] };
  const boq = boqFromExtracted(r as never).boq as B[];
  assertEquals(boq.find((b) => b.type === 'smoke_detector')?.qty, 3);
  assert(!boq.some((b) => /NORTH/i.test(b.item)), 'the north arrow is not an item');
});

Deno.test('a sheet drawn only in paper space is still counted, not read empty', async () => {
  const r = await readDxf(dxf([ins('SMOKE_DETECTOR', 10, true), ins('SMOKE_DETECTOR', 20, true)]), CTX) as unknown as { ok: true; quantities: Q[] };
  assertEquals(r.quantities.find((q) => q.description === 'block SMOKE_DETECTOR')?.qty, 2);
});
