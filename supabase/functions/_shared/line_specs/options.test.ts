// Two options are two quotations: split deterministically, shared lines and totals handled.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/options.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { optionAmount, optionLabel, optionNumber, splitOptions } from './options.ts';

const LINES = [
  { description: 'Preliminaries and mobilisation', amount: 500 },
  { description: 'Option 1 - Daikin' },
  { description: 'Ducted split 2.5 TR Daikin', amount: 10000 },
  { description: 'Option 2 - Gree' },
  { description: 'Ducted split 2.5 TR Gree', amount: 8000 },
];

Deno.test('headings split a submission into options; lines above the first heading belong to every option', () => {
  const o = splitOptions(LINES);
  assertEquals(o.map((x) => x.option_no), [1, 2]);
  assertEquals(o[0].lines.map((l) => l.description), ['Preliminaries and mobilisation', 'Ducted split 2.5 TR Daikin']);
  assertEquals(o[1].lines.map((l) => l.description), ['Preliminaries and mobilisation', 'Ducted split 2.5 TR Gree']);
  assertEquals(optionAmount(o[0]), 10500);
  assertEquals(optionAmount(o[1]), 8500);
});

Deno.test('a total stated for an option wins over the sum of its lines', () => {
  const o = splitOptions(LINES, { '1': 11000, '2': 9000 });
  assertEquals([optionAmount(o[0]), optionAmount(o[1])], [11000, 9000]);
});

Deno.test('Arabic, lettered and "alternative" headings are read', () => {
  assertEquals([optionNumber('الخيار 1', 0), optionNumber('الخيار الثاني', 0), optionNumber('البديل ٣', 0), optionNumber('Option B', 0), optionNumber('Alternative 2:', 0), optionNumber('Option two', 0)], [1, 2, 3, 2, 2, 2]);
  const ar = splitOptions([{ description: 'الخيار الأول' }, { description: 'مكيف دايكن', amount: 100 }, { description: 'الخيار الثاني' }, { description: 'مكيف جري', amount: 90 }]);
  assertEquals(ar.map((x) => [x.option_no, x.lines.length]), [[1, 1], [2, 1]]);
  assertEquals([optionLabel(2, 'en'), optionLabel(2, 'ar')], ['Option 2', 'الخيار 2']);
});

Deno.test('a line keyed with an option by the document reader is split the same way', () => {
  const o = splitOptions([{ description: 'A', amount: 1, option: 1 }, { description: 'B', amount: 2, option: 2 }, { description: 'C', amount: 3 }]);
  assertEquals(o.map((x) => x.lines.map((l) => l.description)), [['C', 'A'], ['C', 'B']]);
});

Deno.test('no second option, no split', () => {
  assertEquals(splitOptions([{ description: 'Ducted split', amount: 5 }]).map((x) => [x.option_no, x.lines.length]), [[1, 1]]);
  assertEquals(splitOptions([{ description: 'Option 1' }, { description: 'Ducted split', amount: 5 }]).map((x) => [x.option_no, x.lines.length]), [[1, 1]]);
});
