// The spec model: every category resolves to a trade exactly, every trade has a mandatory core, and the
// catalogue is data that reads nothing (23 Sep 2026: what a line states is read by reasoning, reasoned_matching.ts).
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/model.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import cats from '../../../../src/content/categories.json' with { type: 'json' };
import { attrsOf, COMPOSITE, lineTradeOptions, TRADES, tradeOfCategory } from './model.ts';

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


// 23 SEP 2026 (decision point 29): the catalogue decides nothing from words. No attribute carries a reader,
// no trade a keyword pattern; which attributes apply to only some lines is marked, and the reading decides.
Deno.test('the catalogue is data: no reader, no keyword pattern, the conditional attributes marked', () => {
  for (const t of Object.values(TRADES)) {
    assertEquals(Object.keys(t).sort(), ['ar', 'attrs', 'code', 'en'], t.code);
    for (const a of t.attrs) for (const v of Object.values(a)) assert(typeof v !== 'function' && !(v instanceof RegExp), `${t.code}.${a.code}`);
  }
  const cond = (tr: string) => TRADES[tr].attrs.filter((a) => a.conditional).map((a) => a.code).sort();
  assertEquals(cond('gypsum'), ['dimensions', 'frame', 'thickness_mm']);
  assertEquals(cond('hvac'), ['brand', 'capacity_tr', 'model', 'refrigerant']);
  assertEquals(lineTradeOptions('joinery'), ['joinery']);
  assert(lineTradeOptions('fitout').includes('gypsum') && lineTradeOptions('mep').includes('hvac') && !lineTradeOptions('mep').includes('joinery'));
  assertEquals(attrsOf('joinery').length, TRADES.joinery.attrs.length);
});

Deno.test('a category resolves EXACTLY: a word inside a key decides nothing', () => {
  assertEquals(tradeOfCategory('safety_equipment'), 'general', 'PPE is not fire fighting because its key contains "safety"');
  assertEquals(tradeOfCategory('Hvac '), 'hvac');
  assertEquals(tradeOfCategory('air conditioning for my villa'), 'general', 'free text is not a category');
  assertEquals(tradeOfCategory(null), 'general');
});

// THE TAXONOMY TRADES OF 23 SEP 2026 (founder instructions 895/899/900). An exact new code is decided by
// taxonomy_trades.ts: a hotel-furniture quote is not held on joinery's board thickness, and a pump quote is
// held until each line states its brand and model.
Deno.test('a new taxonomy code resolves exactly: branded goods on brand + model, the rest on no line attribute', () => {
  assertEquals(tradeOfCategory('industrial_pumps'), 'branded_goods');
  assertEquals(tradeOfCategory('vehicles_fleet'), 'branded_goods');
  assertEquals(tradeOfCategory('pest_control'), 'pestcontrol');
  assertEquals(tradeOfCategory('tents_shades'), 'shade');
  for (const c of ['hotel_furniture', 'cleaning_chemicals', 'corrugated_packaging', 'legal_services']) {
    assertEquals(tradeOfCategory(c), c, c);
    assert(!TRADES[c] && !COMPOSITE.has(c), `${c} must not borrow another trade's attributes`);
  }
  assertEquals(TRADES.branded_goods.attrs.filter((a) => a.mandatory).map((a) => a.code).sort(), ['brand', 'model']);
});
