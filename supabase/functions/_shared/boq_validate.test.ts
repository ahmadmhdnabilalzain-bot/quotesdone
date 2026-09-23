import { assertEquals } from 'jsr:@std/assert@1';
import { unitOf, validateBoq } from './boq_validate.ts';

// Synthetic ZZ DEMO lines only.
Deno.test('a clean ZZ DEMO bill has no findings', () => {
  assertEquals(validateBoq([
    { section: 'ZZ DEMO Flooring', description: 'Porcelain tiling', qty: 120, unit: 'sqm' },
    { section: 'ZZ DEMO Doors', description: 'Door D1', qty: 4, unit: 'nos' },
  ]), []);
});

Deno.test('missing, zero, negative and NaN quantities are each named', () => {
  const f = validateBoq([
    { description: 'ZZ DEMO a', qty: null, unit: 'm' }, { description: 'ZZ DEMO b', qty: 0, unit: 'm' },
    { description: 'ZZ DEMO c', qty: -2, unit: 'm' }, { description: 'ZZ DEMO d', qty: NaN, unit: 'm' },
  ]);
  assertEquals(f.map((x) => x.check), ['missing_qty', 'bad_qty', 'bad_qty', 'bad_qty']);
});

Deno.test('the same item stated twice with different amounts is a conflict; a unit change or rounding is not', () => {
  assertEquals(validateBoq([
    { section: 'ZZ DEMO', description: 'Floor tiling', qty: 120, unit: 'sqm' },
    { section: 'ZZ DEMO', description: 'Floor  Tiling', qty: 95, unit: 'm2' },
  ]).map((x) => [x.check, x.lines]), [['conflict', [0, 1]]]);
  assertEquals(validateBoq([
    { description: 'ZZ DEMO skirting', qty: 40, unit: 'm' }, { description: 'ZZ DEMO skirting', qty: 40000, unit: 'mm' },
    { description: 'ZZ DEMO screed', qty: 100, unit: 'sqm' }, { description: 'ZZ DEMO screed', qty: 100.2, unit: 'sqm' },
  ]), []);
});

Deno.test('the same item in a length and an area is a conflict of kind', () => {
  assertEquals(validateBoq([
    { description: 'ZZ DEMO partition', qty: 30, unit: 'm' }, { description: 'ZZ DEMO partition', qty: 90, unit: 'sqm' },
  ]).map((x) => x.check), ['conflict']);
});

Deno.test('the same words in two sections are two items, and an unknown unit is named', () => {
  const f = validateBoq([
    { section: 'ZZ DEMO L1', description: 'Paint', qty: 10, unit: 'sqm' }, { section: 'ZZ DEMO L2', description: 'Paint', qty: 20, unit: 'sqm' },
    { description: 'ZZ DEMO widget', qty: 3, unit: 'bananas' },
  ]);
  assertEquals(f.map((x) => x.check), ['unknown_unit']);
  assertEquals(unitOf('M²'), ['area', 1]);
  assertEquals(unitOf('No.'), ['count', 1]);
});

Deno.test('boqFromExtracted carries the findings: a ZZ DEMO IFC and its sheet disagreeing reach missing_info', async () => {
  const { boqFromExtracted } = await import('../drawing_boq/boq_from_document.ts');
  const { empty } = await import('./doc_read/types.ts');
  const q = (qty: number, basis: string) => ({ section: 'ZZ DEMO Level 1', description: 'IfcSlab NetArea', qty, unit: 'sqm', basis, confidence: 'medium' as const });
  const r = boqFromExtracted({ ...empty('ifc'), quantities: [q(120, 'model A'), q(95, 'model B')] });
  assertEquals(r.validation, [{ check: 'conflict', lines: [0, 1] }]);
  assertEquals(r.missing_info.some((m: string) => m.includes('different quantities')), true);
});

Deno.test('two schedule rows with one description but different item refs are two items (review of #docbar)', () => {
  assertEquals(validateBoq([
    { section: 'ZZ DEMO Doors', item: 'D1', description: 'Timber door', qty: 4, unit: 'nos' },
    { section: 'ZZ DEMO Doors', item: 'D2', description: 'Timber door', qty: 9, unit: 'nos' },
    { description: 'ZZ DEMO tile adhesive', qty: 12, unit: 'bag' }, { description: 'ZZ DEMO blockwork', qty: 30, unit: 'cft' },
  ]), []);
});
