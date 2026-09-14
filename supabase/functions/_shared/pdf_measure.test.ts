// pdf_measure — vector quantities from a scaled PDF drawing, no model.
// deno test --no-lock supabase/functions/_shared/pdf_measure.test.ts
//
// The fixture rectangle is 50 x 40 mm on paper; at the printed 1:100 that is 5 x 4 m: 20 sqm and an
// 18 m perimeter, within 1%. The sheet border drawn on every fixture must never be measured.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { detectScale, measurePdf } from './pdf_measure.ts';
import { ctmScaledRectPdf, scaledRectPdf, twoScalesPdf, unscaledRectPdf } from './pdf_measure.fixtures.ts';

const near = (got: number | null | undefined, want: number) => assert(got != null && Math.abs(got - want) <= want * 0.01, `${got} is not within 1% of ${want}`);
const q = (qs: { description: string; qty: number | null }[], d: string) => qs.find((x) => x.description === d)?.qty;

Deno.test('SCALE 1:100 and a 5 x 4 m rectangle: 20 sqm, 18 m, one shape, low confidence', async () => {
  const r = await measurePdf(scaledRectPdf());
  assertEquals(r.pages.length, 1);
  const p = r.pages[0];
  assertEquals(p.scale, '1:100');
  near(q(p.quantities, 'Stroked line length, all line weights'), 18);
  near(q(p.quantities, 'Closed shape area, total'), 20);
  assertEquals(q(p.quantities, 'Closed shapes'), 1);                        // the sheet border is not a shape
  assert(p.quantities.every((x) => x.confidence === 'low' && x.basis.includes('SCALE 1:100') && x.basis.includes('not-to-scale')));
});

Deno.test('no scale printed: no quantities, and a note that says why', async () => {
  const r = await measurePdf(unscaledRectPdf());
  assertEquals(r.pages[0].scale, null);
  assertEquals(r.pages[0].quantities, []);
  assert(r.notes[0].includes('no drawing scale'));
});

Deno.test('two scales on one sheet: nothing is measured', async () => {
  const r = await measurePdf(twoScalesPdf());
  assertEquals(r.pages[0].quantities, []);
  assert(r.notes[0].includes('1:20, 1:100'));
});

Deno.test('a 2x cm scales the path and its line width; l/h closes a second shape', async () => {
  const p = (await measurePdf(ctmScaledRectPdf())).pages[0];
  assertEquals(p.scale, '1:100');
  near(q(p.quantities, 'Closed shape area, total'), 40);
  assertEquals(q(p.quantities, 'Closed shapes'), 2);
  near(q(p.quantities, 'Stroked line length at 0.7 pt line weight'), 18);  // 0.35 w under 2x cm
  near(q(p.quantities, 'Stroked line length at 1.5 pt line weight'), 18);
  near(q(p.quantities, 'Stroked line length, all line weights'), 36);
});

Deno.test('scale wording in English, Arabic, German and sheet-size form; NTS is recognised', () => {
  assertEquals(detectScale('SCALE 1:100').scales, [100]);
  assertEquals(detectScale('Scale: 1/50').scales, [50]);
  assertEquals(detectScale('1:200 @ A1').scales, [200]);
  assertEquals(detectScale('مقياس 1:100').scales, [100]);
  assertEquals(detectScale('Maßstab 1:50').scales, [50]);
  assertEquals(detectScale('ROOM 1:2 RATIO').scales, []);                   // a bare ratio is not a scale
  assert(detectScale('SCALE: NTS').nts);
});

Deno.test('not a PDF: no pages, a note', async () => {
  const r = await measurePdf(new TextEncoder().encode('hello'));
  assertEquals(r.pages, []);
  assertEquals(r.notes.length, 1);
});
