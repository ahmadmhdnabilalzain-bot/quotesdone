// Two options are two quotations: split by STRUCTURE (each line's option key), shared lines and totals handled.
// No line's words decide an option (decision point line_specs.options_derive_vat).
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/options.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { optionAmount, optionLabel, splitOptions } from './options.ts';

// As the document reader writes them: a heading row keyed with its option, then that option's lines.
const LINES = [
  { description: 'Preliminaries and mobilisation', amount: 500 },
  { description: 'Option 1 - Daikin', option: 1 },
  { description: 'Ducted split 2.5 TR Daikin', amount: 10000, option: 1 },
  { description: 'Option 2 - Gree', option: 2 },
  { description: 'Ducted split 2.5 TR Gree', amount: 8000, option: 2 },
];

Deno.test('keyed lines split a submission into options; unkeyed lines belong to every option; the heading row is not a line', () => {
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

Deno.test('a lettered key is a format (A is 1); labels in both languages', () => {
  const o = splitOptions([{ description: 'x', amount: 1, option: 'A' }, { description: 'y', amount: 2, option: 'b' }]);
  assertEquals(o.map((x) => x.option_no), [1, 2]);
  assertEquals([optionLabel(2, 'en'), optionLabel(2, 'ar')], ['Option 2', 'الخيار 2']);
});

Deno.test('a heading\'s WORDS split nothing: unkeyed "Option 1 / Option 2" rows are one quotation', () => {
  // Each of these descriptions once opened an option through a word list.
  const o = splitOptions([{ description: 'الخيار الأول' }, { description: 'مكيف دايكن', amount: 100 }, { description: 'Alternative 2:' }, { description: 'مكيف جري', amount: 90 }]);
  assertEquals(o.map((x) => [x.option_no, x.lines.length]), [[1, 4]]);
});

Deno.test('no second option, no split', () => {
  assertEquals(splitOptions([{ description: 'Ducted split', amount: 5 }]).map((x) => [x.option_no, x.lines.length]), [[1, 1]]);
});
