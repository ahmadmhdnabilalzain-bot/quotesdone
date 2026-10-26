// The BOQ read in Arabic from REASONED section readings (decision point documents.boq_arabic). No model here:
// the readings are given, as boq_section_reading hands them to the inbox.
import { assertEquals } from 'jsr:@std/assert@1';
import { boqWithArabic, descriptionArabic, sectionArabic, sectionsToRead, type BoqLine } from './boq_arabic.ts';

const DEMO: { boq: BoqLine[] } = { boq: [
  { section: 'Partitions', description: 'Gypsum board partition, 100mm metal stud, both faces', qty: 320, unit: 'm2' },
  { section: 'Ceilings', description: 'Suspended false ceiling, 600x600 mineral fibre tiles', qty: 410, unit: 'm2' },
  { section: ' ceilings ', description: 'Gypsum bulkhead, 300mm drop, painted finish', qty: 64, unit: 'm' },
] };

Deno.test('a reasoned heading prints in Arabic; the line keeps the exact English the supplier prices', () => {
  const out = boqWithArabic(DEMO, { partitions: 'partitions', ceilings: 'ceilings' });
  assertEquals(out.boq[0].section_ar, 'القواطع والجدران الداخلية');
  assertEquals(out.boq[1].section_ar, 'الأسقف');
  assertEquals(out.boq[2].section_ar, 'الأسقف');
  assertEquals(out.boq[0].description_ar, null);
  assertEquals(out.boq[0].description, DEMO.boq[0].description);
  assertEquals(out.boq[0].qty, 320);
});

Deno.test('no reading (the hold) or a reasoned none: no heading is guessed, whatever words the section has', () => {
  // "Ceilings" is the plainest possible heading: without a reading it is still NOT labelled.
  assertEquals(sectionArabic('Ceilings', {}), null);
  assertEquals(sectionArabic('Miscellaneous items', { 'miscellaneous items': 'none' }), null);
  assertEquals(sectionArabic('Block A', { 'block a': 'not_a_heading_id' }), null);
  assertEquals(sectionArabic('', {}), null);
});

Deno.test('Arabic text is shown as written and never sent for a reading', () => {
  assertEquals(sectionArabic('الأسقف', {}), 'الأسقف');
  assertEquals(descriptionArabic('قواطع جبس'), 'قواطع جبس');
  assertEquals(sectionsToRead({ boq: [{ section: 'الأسقف' }, { section: 'Ceilings' }, { section: 'ceilings' }, { section: '' }] }), ['Ceilings']);
});

Deno.test('a BOQ without rows is returned untouched', () => {
  assertEquals(boqWithArabic({ assumptions: ['x'] } as unknown as { boq?: unknown }, {}), { assumptions: ['x'] } as unknown as { boq?: unknown });
  assertEquals(boqWithArabic(null as unknown as { boq?: unknown }, {}), null);
  assertEquals(sectionsToRead(null), []);
});
