// trade_glossary_ar.test.ts — the deterministic English → Arabic trade glossary.
// deno test --no-lock supabase/functions/_shared/trade_glossary_ar.test.ts
//
// What it proves: every trade on the site has an Arabic (and English) name; a representative
// supplier phrase from EVERY trade translates with no English left over; brands, standards and
// codes stay as written; a word the glossary does not know is reported, never guessed.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import cats from '../../../src/content/categories.json' with { type: 'json' };
import { arTrade, isProperToken, CATEGORY_AR, CATEGORY_EN, GLOSSARY_SIZE, arAttr } from './trade_glossary_ar.ts';

// One supplier-style phrase per trade code in src/content/categories.json.
const PHRASES: Record<string, string> = {
  'acrylic': 'Acrylic sheet, clear, 10mm',
  'aluminium': 'Aluminium sliding window, powder coated, double glazed',
  'av-systems': 'Ceiling speakers with amplifier and projector',
  'blinds-curtains': 'Motorised roller blinds, blackout fabric',
  'carpentry-joinery': 'Built-in wardrobe carcass 18mm moisture resistant MDF, Egger HPL finish, 1mm PVC edge band, Blum soft close hinges',
  'carpets': 'Carpet tiles with underlay',
  'cleaning': 'Deep cleaning of apartment',
  'combined-mep': 'Electrical, plumbing and HVAC works',
  'commercial-retail-fitout': 'Shop fit-out with gypsum ceiling and LED lighting',
  'custom-furniture': 'Custom made table, solid walnut',
  'demolition': 'Demolition works and debris removal',
  'electrical': 'Distribution board with circuit breaker and earthing',
  'elevators': 'Passenger lift, 4 stops, machine room less',
  'engineering-and-architectural-consultancies': 'Structural design and authority approvals',
  'epoxy-flooring': 'Self levelling epoxy flooring, anti-slip',
  'facade-cleaning': 'Facade cleaning by rope access',
  'fitout': 'Interior fit-out works including false ceiling and painting',
  'flooring': 'Engineered wood flooring, oak, 14mm',
  'garage-doors': 'Roller shutter with motor and remote control',
  'general-building-contracting': 'Construction of villa, concrete and blockwork',
  'general-services-other': 'Maintenance and repair works',
  'generators': 'Diesel generator 100 kVA with soundproof canopy and ATS',
  'glass': 'Frameless tempered glass partition 12mm',
  'gypsum': 'Gypsum ceiling with access panels',
  'hvac': 'Gree ducted split unit 5 TR, R410A, inverter',
  'insulation': 'Thermal insulation, rock wool 50mm',
  'interior-design': 'Interior design, concept design and 3D visualisation',
  'it-networking': 'Structured cabling with Cat6 data points and access points',
  'job-shop-manufacturing': 'CNC machining and laser cutting of stainless steel',
  'kitchens': 'Kitchen cabinets with quartz worktop and soft close hinges',
  'landscaping': 'Artificial grass with drip irrigation',
  'marble-granite': 'Polished marble flooring, 20mm',
  'masonry': 'Hollow block walls, 200mm, with plaster',
  'mep': 'MEP works: plumbing, drainage and electrical',
  'movers': 'Packing, moving and assembly of furniture',
  'painting': 'Interior emulsion paint, 2 coats with primer',
  'pest': 'Pest control with gel treatment',
  'plumbing': 'Wall hung WC with concealed cistern and mixer',
  'roofing': 'Roof waterproofing with bituminous membrane',
  'safety': 'Addressable fire alarm system with smoke detectors',
  'scaffolding': 'Scaffolding for facade works',
  'security': 'IP cameras, 4MP, with NVR and hard disk',
  'signage': 'Backlit 3D letters, acrylic, stainless steel',
  'smart-home': 'Smart lighting and smart lock with home automation',
  'solar': 'On-grid solar system, 10 kWp, with inverter',
  'steel': 'Mild steel gate, powder coated',
  'structural-steel-fabrication': 'Structural steel beams and columns, welded, galvanised',
  'swimming-pools': 'Swimming pool filtration system with filter pump',
  'tents-and-shade-structures': 'Car parking shade, tensile fabric, HDPE',
  'tiling': 'Porcelain tiles 600 x 600 mm with tile adhesive and grout',
  'upholstery': 'Upholstered chairs, leather',
  'wallpaper': 'Wallpaper supply and installation',
  'water-tank-cleaning': 'Water tank cleaning and disinfection',
  'waterproofing': 'Cementitious waterproofing for bathrooms',
};
/** Latin words in an Arabic string that are not a brand, standard or code. */
export function latinLeaks(s: string): string[] {
  const t = s.replace(/المورّد [A-Z]{1,2}\b/g, '').replace(/\bQD-[A-Z0-9-]+\b/g, '').replace(/https?:\S+/g, '').replace(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, '');
  return (t.match(/[A-Za-z][A-Za-z0-9'’\-/.+]*/g) || []).filter((w) => !w.split(/[-/]/).filter(Boolean).every(isProperToken));
}

Deno.test('every trade on the site has an Arabic and an English name', () => {
  // deno-lint-ignore no-explicit-any
  const items = (cats as any).items as Array<{ code: string; en: string; ar: string }>;
  assert(items.length >= 50, 'categories.json shrank: ' + items.length);
  for (const c of items) {
    assert(CATEGORY_AR[c.code], 'no Arabic trade name for ' + c.code);
    assertEquals(CATEGORY_EN[c.code], c.en, 'English trade name for ' + c.code);
  }
});

Deno.test('a supplier phrase from every trade translates with no English left over', () => {
  // deno-lint-ignore no-explicit-any
  const codes = ((cats as any).items as Array<{ code: string }>).map((c) => c.code);
  for (const code of codes) assert(PHRASES[code], 'no test phrase for trade ' + code);
  const bad: string[] = [];
  for (const [code, en] of Object.entries(PHRASES)) {
    const r = arTrade(en);
    if (!r.complete || !r.ar || latinLeaks(r.ar).length) bad.push(`${code}: "${en}" → "${r.ar}" unknown=${JSON.stringify(r.unknown)} leaks=${JSON.stringify(latinLeaks(r.ar))}`);
  }
  assertEquals(bad, []);
  assert(GLOSSARY_SIZE > 1000, 'glossary carries ' + GLOSSARY_SIZE + ' terms');
});

Deno.test('noun groups read head-first; materials follow their object; units and counts are Arabic', () => {
  assertEquals(arTrade('Programmable wall thermostat').ar, 'ثرموستات جداري قابل للبرمجة');
  assertEquals(arTrade('GI ductwork with 25mm insulation').ar, 'مجاري هواء من الحديد المجلفن مع عزل 25 مم');
  assertStringIncludes(arTrade('Built-in wardrobe carcass 18mm moisture resistant MDF').ar, 'من MDF مقاوم للرطوبة 18 مم');
  assertEquals(arTrade('Solid oak veneer entrance door').ar, 'باب مدخل من قشرة البلوط الطبيعي');
  assertEquals(arTrade('2 years — parts and labour').ar, 'سنتان — القطع والعمالة');
  assertEquals(arTrade('Site access 8am-6pm.').ar, 'الوصول إلى الموقع 8 ص - 6 م.');
  assertEquals(arTrade('Price valid for listed quantities only.').ar, 'السعر ساري للكميات المذكورة فقط.');
});

Deno.test('brands, standards and codes stay as written; unknown words are reported, not guessed', () => {
  const r = arTrade('Mitsubishi Electric ducted split unit 2 TR per ASHRAE sizing');
  assert(r.complete, JSON.stringify(r));
  assertStringIncludes(r.ar, 'Mitsubishi Electric'); assertStringIncludes(r.ar, 'ASHRAE');
  const u = arTrade('Wardrobe 2400 x 600 mm frobnicated widget');
  assertEquals(u.complete, false);
  assertEquals(u.unknown, ['frobnicated', 'widget']);
  assertEquals(latinLeaks(u.ar), [], 'the Arabic of the known parts carries no English: ' + u.ar);
  assert(isProperToken('R410A') && isProperToken('BS') && isProperToken('Blum') && !isProperToken('widget'));
});

Deno.test('mixed Arabic text keeps its Arabic and translates the English inside it', () => {
  const r = arTrade('المورّد A: soft close hinges');
  assert(r.complete); assertStringIncludes(r.ar, 'مفصلات بإغلاق هادئ');
  assertEquals(arAttr('fire_rating'), 'مقاومة الحريق');
  assertEquals(arAttr('Edge band'), 'شريط الحواف');
});
