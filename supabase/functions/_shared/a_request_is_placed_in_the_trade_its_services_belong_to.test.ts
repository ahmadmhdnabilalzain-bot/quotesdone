// A REQUEST IS PLACED IN THE TRADE ITS SERVICES BELONG TO (sales_engineer; evidence run of 10 Nov 2026, ledger 1604,
// finding b1; rulings 1579/1586: every example applies to every trade).
// The PVC wall-panel job was placed as [interior_fitout, joinery] while its chosen services were two wall-panel services,
// a refurbishment and a wood panelling. The placement is now decided in code from the service keys and the taxonomy, with
// the model's trade list as input. Pure: no database, no model.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/a_request_is_placed_in_the_trade_its_services_belong_to.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { isWholeScopeTrade, placeTrades, slugOfTrade } from './inquiry_trades.ts';
import { parseReading } from './inquiry_reading.ts';

const SLUGS = ['wallpaper', 'hvac', 'swimming-pools', 'fitout', 'interior-design', 'carpentry-joinery', 'gypsum', 'electrical', 'general-services-other'];
const place = (model: string[], keys: string[]) => { const p = placeTrades(model, keys); return { codes: p.codes, multi: p.multi, keys: p.keys, slug: slugOfTrade(p.primary, SLUGS) }; };

Deno.test('RFQ 164464: PVC wall panels on an MDF partition are the wall-panel trade, one trade, not a fit-out and joinery', () => {
  const p = place(['interior_fitout', 'joinery'], ['wallpaper.wall_cladding', 'wallpaper.wall_panels', 'interior_fitout.refurbishment', 'joinery.wood_panelling']);
  assertEquals(p, { codes: ['wallpaper'], multi: false, keys: ['wallpaper.wall_cladding', 'wallpaper.wall_panels'], slug: 'wallpaper' });
});

Deno.test('every group: transport, MEP, outdoor works, packaging — the services\' own trade, one supplier type', () => {
  assertEquals(place(['vehicle_rental', 'staff_transport'], ['staff_transport.bus_with_driver', 'staff_transport.daily_shuttle', 'vehicle_rental.bus_rental']).codes, ['staff_transport']);
  assertEquals(place(['hvac', 'electrical'], ['hvac.maintenance_amc', 'hvac.ducting']), { codes: ['hvac'], multi: false, keys: ['hvac.maintenance_amc', 'hvac.ducting'], slug: 'hvac' });
  const pool = place(['landscaping', 'swimming_pools', 'civil_works'], ['swimming_pools.pool_construction', 'swimming_pools.filtration_equipment', 'civil_works.excavation']);
  assertEquals([pool.codes, pool.slug], [['swimming_pools'], 'swimming-pools']);
  assertEquals(place(['packaging', 'corrugated_packaging'], ['corrugated_packaging.regular_slotted_cartons', 'corrugated_packaging.printed_shipping_cartons', 'packaging.flexible_packaging']).codes, ['corrugated_packaging']);
});

Deno.test('a genuine fit-out of a whole office stays a fit-out, multi-trade, even when one specialist names two services', () => {
  const p = place(['interior_fitout', 'gypsum', 'electrical', 'hvac'], ['interior_fitout.office_fitout', 'gypsum.partitions', 'gypsum.false_ceiling', 'electrical.wiring_install', 'hvac.ducting']);
  assertEquals(p.codes, ['interior_fitout', 'gypsum', 'electrical', 'hvac']);
  assertEquals(p.multi, true);
  assertEquals(p.keys.length, 5, 'every service of a placed trade is kept');
});

Deno.test('two co-equal specialist scopes stay two trades (the customer chooses one contractor or separate quotes)', () => {
  assertEquals(place(['hvac'], ['hvac.ducting', 'electrical.db_panels']).codes, ['hvac', 'electrical']);
});

Deno.test('with no chosen service the model\'s trades stand; whole-scope is an exact mapping, never the "general" fallback', () => {
  assertEquals(placeTrades(['interior_fitout', 'joinery'], []).codes, ['interior_fitout', 'joinery']);
  assertEquals(['interior_fitout', 'mep_general', 'general_contracting', 'staff_transport', 'corrugated_packaging', 'wallpaper'].map(isWholeScopeTrade), [true, true, true, false, false, false]);
});

Deno.test('the portal and WhatsApp reading places the same way as the request chat', () => {
  const taxonomy = ['interior_fitout', 'joinery', 'wallpaper'].map((code) => ({ code, label: code, group_code: 'construction_building' }));
  const services = [['wallpaper', 'wall_cladding'], ['wallpaper', 'wall_panels'], ['interior_fitout', 'refurbishment'], ['joinery', 'wood_panelling']].map(([trade_code, code]) => ({ trade_code, code, label_en: code }));
  const r = parseReading(JSON.stringify({ trade_codes: ['interior_fitout', 'joinery'], service_keys: ['wallpaper.wall_cladding', 'wallpaper.wall_panels', 'interior_fitout.refurbishment', 'joinery.wood_panelling'] }), { taxonomy, services });
  assertEquals([r?.trade_codes, r?.service_keys], [['wallpaper'], ['wallpaper.wall_cladding', 'wallpaper.wall_panels']]);
});

Deno.test('a whole fit-out is said by the placement (the composer preselects one contractor only then, finding c)', () => {
  assertEquals(placeTrades(['interior_fitout', 'gypsum', 'electrical', 'hvac'], ['interior_fitout.office_fitout', 'gypsum.partitions', 'electrical.wiring_install', 'hvac.ducting']).whole, true);
  assertEquals(placeTrades(['interior_fitout', 'joinery'], ['wallpaper.wall_cladding', 'wallpaper.wall_panels', 'interior_fitout.refurbishment', 'joinery.wood_panelling']).whole, false);
  assertEquals(placeTrades(['hvac'], ['hvac.ducting', 'electrical.db_panels']).whole, false, 'two specialist scopes: separate quotes are preselected');
});
