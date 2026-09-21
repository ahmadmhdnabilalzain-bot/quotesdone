// The founder-demo BOQ (inquiry 151767, measured 21 Sep 2026) read in Arabic without a model.
import { assertEquals } from 'jsr:@std/assert@1';
import { boqWithArabic, sectionArabic, descriptionArabic, type BoqLine } from './boq_arabic.ts';
import type { ServiceTerm } from './service_rewrite.ts';
import aliases from './service_aliases.json' with { type: 'json' };

// The same vocabulary shape serviceVocab() reads from taxonomy_trade_service: the seed's aliases with
// the labels the seed migration gives them.
const LABELS: Record<string, [string, string]> = {
  'gypsum.false_ceiling': ['False ceilings', 'أسقف مستعارة'],
  'gypsum.partitions': ['Gypsum partitions', 'قواطع جبس'],
  'gypsum.acoustic_ceiling': ['Acoustic ceilings', 'أسقف صوتية'],
  'gypsum.decorative': ['Decorative gypsum', 'جبس ديكور'],
  'painting.interior': ['Interior painting', 'دهانات داخلية'],
};
const VOCAB: ServiceTerm[] = Object.entries(LABELS).map(([key, [en, ar]]) => {
  const [trade_code, code] = key.split('.');
  const a = (aliases as Record<string, { en: string[]; ar: string[] }>)[key] || { en: [], ar: [] };
  return { trade_code, code, label_en: en, label_ar: ar, aliases: [...a.en, ...a.ar] };
});

const DEMO: { boq: BoqLine[] } = { boq: [
  { section: 'Partitions', description: 'Gypsum board partition, 100mm metal stud, both faces', qty: 320, unit: 'm2' },
  { section: 'Ceilings', description: 'Suspended false ceiling, 600x600 mineral fibre tiles', qty: 410, unit: 'm2' },
  { section: 'Ceilings', description: 'Gypsum bulkhead, 300mm drop, painted finish', qty: 64, unit: 'm' },
] };

Deno.test('the demo BOQ sections and service-naming lines read in Arabic', () => {
  const out = boqWithArabic(DEMO, VOCAB);
  assertEquals(out.boq[0].section_ar, 'القواطع والجدران الداخلية');
  assertEquals(out.boq[1].section_ar, 'الأسقف');
  assertEquals(out.boq[0].description_ar, 'قواطع جبس');
  assertEquals(out.boq[1].description_ar, 'أسقف مستعارة');
  // Nothing else on the row changes: the supplier still prices the exact English line.
  assertEquals(out.boq[0].description, DEMO.boq[0].description);
  assertEquals(out.boq[0].qty, 320);
});

Deno.test('a line that names no service gets no guessed Arabic (exact or none)', () => {
  // "Gypsum bulkhead, 300mm drop" names no alias in the seed; a guess here would be a wrong quotation.
  assertEquals(descriptionArabic('Gypsum bulkhead, 300mm drop, painted finish', VOCAB), null);
  assertEquals(descriptionArabic('', VOCAB), null);
});

Deno.test('a section the glossary does not name falls back to the services its words match, else null', () => {
  assertEquals(sectionArabic('Suspended ceiling package', VOCAB), 'الأسقف');
  assertEquals(sectionArabic('Drywall', VOCAB), 'القواطع والجدران الداخلية');
  assertEquals(sectionArabic('Fire alarm — devices (from the legend)', VOCAB), 'إنذار الحريق');
  assertEquals(sectionArabic('Miscellaneous items', VOCAB), null);
  assertEquals(sectionArabic('الأسقف', VOCAB), 'الأسقف');
});

Deno.test('a BOQ without rows is returned untouched', () => {
  assertEquals(boqWithArabic({ assumptions: ['x'] } as unknown as { boq?: unknown }, VOCAB), { assumptions: ['x'] } as unknown as { boq?: unknown });
  assertEquals(boqWithArabic(null as unknown as { boq?: unknown }, VOCAB), null);
});
