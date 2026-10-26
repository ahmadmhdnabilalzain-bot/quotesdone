// The spec model: every trade in the catalogue resolves, every trade has a mandatory core, and the
// deterministic readers fill what English and Arabic quotation lines actually state.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/model.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import cats from '../../../../src/content/categories.json' with { type: 'json' };
import { COMPOSITE, installApplies, TRADES, tradeOfCategory, warrantyApplies } from './model.ts';

// public.category_specs → fn_quote_spec_group, read from production 14 Sep 2026. The two categories
// the database maps to no group are the ones this model adds (consultancy, manufacturing).
const MEASURED: Record<string, string> = { 'acrylic': 'acrylic', 'aluminium': 'glazing', 'av-systems': 'avsystems', 'blinds-curtains': 'upholstery', 'carpentry': 'joinery', 'carpentry-joinery': 'joinery', 'carpets': 'carpet', 'cleaning': 'cleaning', 'combined-mep': 'mep', 'commercial-retail-fitout': 'fitout', 'custom-furniture': 'joinery', 'demolition': 'demolition', 'electrical': 'electrical', 'elevators': 'elevators', 'epoxy-flooring': 'flooring', 'facade-cleaning': 'facade', 'fitout': 'fitout', 'flooring': 'flooring', 'garage-doors': 'shutters', 'general': 'general', 'general-building-contracting': 'general', 'general-services-other': 'general', 'generators': 'generators', 'glass': 'glazing', 'gypsum': 'gypsum', 'hvac': 'hvac', 'insulation': 'insulation', 'interior-design': 'interiordesign', 'it-networking': 'networking', 'kitchens': 'joinery', 'landscaping': 'landscaping', 'marble-granite': 'tiling', 'masonry': 'masonry', 'mep': 'mep', 'movers': 'movers', 'painting': 'painting', 'pest': 'pestcontrol', 'plumbing': 'plumbing', 'roofing': 'roofing', 'safety': 'fire', 'scaffolding': 'scaffolding', 'security': 'security', 'signage': 'signage', 'smart-home': 'smarthome', 'solar': 'solar', 'steel': 'steel', 'structural-steel-fabrication': 'steel', 'swimming-pools': 'pools', 'tents-and-shade-structures': 'shade', 'tiling': 'tiling', 'upholstery': 'upholstery', 'wallpaper': 'wallpaper', 'water-tank-cleaning': 'watertank', 'waterproofing': 'waterproofing' };

Deno.test('every category on the site and in category_specs resolves to a trade this model knows', () => {
  const codes = (cats as { items: { code: string }[] }).items.map((i) => i.code);
  assertEquals(codes.length, 54);
  for (const c of [...codes, 'general', 'carpentry']) { const t = tradeOfCategory(c); assert(TRADES[t] || COMPOSITE.has(t), `${c} -> ${t}`); }
  for (const [c, g] of Object.entries(MEASURED)) assertEquals(tradeOfCategory(c), g, c);
  assertEquals(tradeOfCategory('engineering-and-architectural-consultancies'), 'consultancy');
  assertEquals(tradeOfCategory('job-shop-manufacturing'), 'manufacturing');
});

Deno.test('every trade has a mandatory core, and every attribute is labelled in both languages', () => {
  for (const t of Object.values(TRADES)) {
    assert(t.attrs.some((a) => a.mandatory), t.code);
    for (const a of t.attrs) assert(a.en && /[؀-ۿ]/.test(a.ar), `${t.code}.${a.code}`);
  }
});

const find = (trade: string, text: string) => Object.fromEntries(TRADES[trade].attrs.map((a) => [a.code, a.find(text)]).filter(([, v]) => v));
const CASES: [string, string, Record<string, string>][] = [
  ['joinery', 'Wardrobe carcass 18mm MR MDF, HPL finish, 1mm PVC edge band', { material: 'Moisture-resistant MDF', thickness_mm: '18', finish: 'HPL' }],
  ['joinery', 'خزانة ملابس خشب ام دي اف سماكة 18 ملم تشطيب فورمايكا', { material: 'MDF', thickness_mm: '18', finish: 'HPL' }],
  ['joinery', 'Solid oak door leaf 45mm thick, lacquer finish', { material: 'Solid wood', species: 'Oak', thickness_mm: '45', finish: 'Lacquer' }],
  ['gypsum', 'False ceiling 12.5mm moisture resistant gypsum board on 0.6mm GI studs, Knauf', { board_type: 'Moisture-resistant board', thickness_mm: '12.5', frame: '0.6mm GI studs', brand: 'Knauf' }],
  ['gypsum', 'سقف معلق جبس بورد مقاوم للرطوبة سماكة 12.5 ملم قطاعات مجلفنة 0.5 ملم', { board_type: 'Moisture-resistant board', thickness_mm: '12.5' }],
  ['flooring', 'SPC flooring 1220x180mm, 5mm thick, 0.5mm wear layer, AC4, Brand: Tarkett', { material: 'SPC', dimensions: '1220x180 mm', thickness_mm: '5', wear_layer_mm: '0.5', grade: 'AC4', brand: 'Tarkett' }],
  ['tiling', 'Porcelain tiles 600x600mm, 10mm thick, matt, RAK Ceramics', { material: 'Porcelain', dimensions: '600x600 mm', thickness_mm: '10', finish: 'Matt', brand: 'RAK Ceramics' }],
  ['electrical', 'Cable 4C x 16mm2 XLPE/SWA/PVC armoured, Ducab', { cable_type: 'XLPE/SWA/PVC armoured', size_mm2: '16', brand: 'Ducab' }],
  ['electrical', 'كابل 4 × 16 مم² مسلح دوكاب', { cable_type: 'XLPE/SWA/PVC armoured', size_mm2: '16', brand: 'Ducab' }],
  ['hvac', 'Ducted split unit 2.5 TR, Daikin model FDMRN30, R410A, SEER 16', { brand: 'Daikin', model: 'FDMRN30', capacity_tr: '2.5', refrigerant: 'R-410A', efficiency: 'SEER 16' }],
  ['hvac', 'مكيف سبليت دايكن 2 طن غاز R32 موديل FTKM50', { brand: 'Daikin', model: 'FTKM50', capacity_tr: '2', refrigerant: 'R-32' }],
  ['hvac', 'Split AC 24000 BTU Gree', { brand: 'Gree', capacity_tr: '2' }],
  ['painting', 'Jotun Fenomastic Pure Colors emulsion, 2 coats, matt finish', { brand: 'Jotun', product: 'Fenomastic', coats: '2', sheen: 'Matt' }],
  ['painting', 'دهان جوتن فينوماستك طبقتين مطفي', { brand: 'Jotun', product: 'Fenomastic', coats: '2', sheen: 'Matt' }],
  ['plumbing', 'PPR pipe PN20 25mm, Cosmoplast', { pipe_material: 'PPR', pipe_class: 'PN20', size: '25mm', brand: 'Cosmoplast' }],
  ['plumbing', 'مواسير PPR ضغط PN16 قطر 32 مم كوزموبلاست', { pipe_material: 'PPR', pipe_class: 'PN16', size: '32 مم', brand: 'Cosmoplast' }],
  ['glazing', 'Aluminium window Schuco AWS 70, 6+12+6mm double glazed low-e glass, RAL 9016 powder coated', { glass_type: 'Double-glazed unit', glass_thickness: '6+12+6mm', profile_system: 'Schuco AWS 70', finish: 'RAL 9016' }],
  ['steel', 'Steel beam UB 305x165x40, S355JR, hot-dip galvanised', { grade: 'S355JR', section: 'UB 305x165x40', finish: 'Hot-dip galvanised' }],
  ['concrete', 'RCC slab concrete C40/50 with SRC cement, B500B rebar', { grade: 'C40/50', cement: 'SRC (sulphate resisting)', rebar: 'B500B' }],
  ['cleaning', 'Deep cleaning of villa using Diversey products', { method: 'Deep cleaning', products: 'Diversey' }],
  ['generators', 'Diesel generator 500 kVA Cummins, silent canopy', { capacity_kva: '500', brand: 'Cummins', fuel: 'Diesel', enclosure: 'Silent / canopy' }],
];
for (const [trade, text, want] of CASES) {
  Deno.test(`${trade} reads: ${text}`, () => { const got = find(trade, text); for (const [k, v] of Object.entries(want)) assertEquals(got[k], v, `${trade}.${k} in "${text}"`); });
}

Deno.test('a value nobody stated is never invented, and a vague one is not a value', () => {
  assertEquals(find('joinery', 'Wardrobe, finish as per approved sample'), {});
  assertEquals(TRADES.joinery.attrs.find((a) => a.code === 'thickness_mm')!.find('Wardrobe MDF thickness TBD'), null);
  assertEquals(TRADES.painting.attrs.find((a) => a.code === 'brand')!.find('Paint, Brand: TBD'), null);
});

Deno.test('installation and warranty applicability is decided per trade, never guessed', () => {
  assert(installApplies('joinery') && installApplies('hvac') && installApplies('glazing'));
  assert(!installApplies('cleaning') && !installApplies('painting') && !installApplies('movers') && !installApplies('consultancy'));
  assert(warrantyApplies('hvac', '') && warrantyApplies('painting', ''));
  assert(!warrantyApplies('cleaning', '') && !warrantyApplies('movers', '') && !warrantyApplies('interiordesign', ''));
  assert(warrantyApplies('pestcontrol', 'Pre-construction termite treatment') && !warrantyApplies('pestcontrol', 'Cockroach gel treatment'));
});
