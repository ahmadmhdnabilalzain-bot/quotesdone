// An inquiry in the WHOLE taxonomy (inquiry_trades.ts; founder ledger 1586: every trade in the UAE but food and beverage).
// Offline, a spread across all twelve taxonomy groups (at least two trades in each, staff transport and vehicle leasing,
// packaging, lifts, pools and scaffolding among them): for each, a typical opening, the trade code the reasoning places it
// in, and what the conversation is then driven by — that trade's spec checklist (what an exact quote must state), its
// services (what matching gates on), its verified location rules and any authority every job needs. The packs and the
// services are read from the repository (knowledge/packs/<trade>.json, the scripts/sql taxonomy seeds): the same sources
// scripts/kb/load_trade_spec_checklists.mjs and the taxonomy seeds load into production.
// Run: deno test --no-lock --node-modules-dir=none --allow-read supabase/functions/_shared/inquiry_trades.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { AUTHORITY, CHECKLIST_REQUIRED, checklistFields, GROUP_LABEL, taxonomyBlock, tradeBlock, validCodes, validServiceKeys,
  type TaxTrade, type TradeContext, type TradeService } from './inquiry_trades.ts';
import { problemsFor } from './solution_catalogue.ts';

const ROOT = new URL('../../../', import.meta.url);
// [group, trade code, a typical opening (any language), a spec a supplier of it needs stated, authority_required]
const SPREAD: [string, string, string, RegExp, string[]][] = [
  ['construction_building', 'scaffolding', 'need scaffolding for a G+2 facade repaint, 3 weeks', /height|access|duration|load/i, []],
  ['construction_building', 'swimming_pools', 'أبي مسبح في الفيلا، كم العمق المسموح؟', /depth|dimensions/i, []],
  ['construction_building', 'wallpaper', 'cover my MDF partition with PVC panels', /./, []],
  ['energy_environment', 'solar', 'solar panels on my warehouse roof', /./, []],
  ['energy_environment', 'waste_management', 'construction waste skips for a site in Al Quoz', /./, []],
  ['facilities_property', 'pest_control', 'عندنا صراصير في المطبخ', /./, []],
  ['facilities_property', 'facilities_management', 'FM contract for a 12-storey building', /./, []],
  ['furniture_hospitality_consumer', 'commercial_kitchen', 'equipment for a new cafe kitchen', /./, []],
  ['furniture_hospitality_consumer', 'office_furniture', '40 workstations and chairs for our office', /./, []],
  ['health_lab_safety', 'medical_equipment', 'an ultrasound machine for a clinic', /./, []],
  ['health_lab_safety', 'safety_equipment', 'PPE for 200 site workers', /./, []],
  ['industrial_manufacturing', 'cnc_machining', 'machine 500 aluminium brackets from our drawing', /./, []],
  ['industrial_manufacturing', 'industrial_pumps', 'replace a transfer pump at our plant', /./, []],
  ['marketing_media_events', 'exhibition_stands', 'a 36 sqm stand at GITEX', /./, []],
  ['marketing_media_events', 'signage', 'illuminated sign for my shop', /./, []],
  ['materials_packaging', 'corrugated_packaging', 'cartons for our e-commerce orders, printed with our logo', /dimension|flute|grade/i, []],
  ['materials_packaging', 'labels_sleeves', 'shrink sleeves for juice bottles', /./, []],
  ['mep_building_systems', 'elevators', 'an escalator for a mall extension', /./, []],
  ['mep_building_systems', 'electrical', 'rewire my villa', /./, ['electrical_utility']],
  ['mep_building_systems', 'fire_fighting', 'Civil Defence wants a sprinkler upgrade', /./, ['civil_defence']],
  ['mep_building_systems', 'security_systems', 'CCTV for a jewellery shop in Dubai', /./, ['sira']],
  ['professional_business', 'engineering_consultancy', 'stamped drawings for a villa extension', /./, []],
  ['professional_business', 'translation_interpretation', 'legal translation of 30 pages to Arabic', /./, []],
  ['technology_telecom', 'it_services', 'network and Wi-Fi for a new office', /./, []],
  ['technology_telecom', 'software_development', 'a booking app for our clinic', /./, []],
  ['transport_mobility', 'staff_transport', 'bus rental: 40 staff, Sharjah to JAFZA, morning and evening, luxury coach', /passengers|seating|vehicle type/i, []],
  ['transport_mobility', 'vehicle_leasing', 'lease 5 pickups for 2 years', /./, []],
];

// the loader's own spec code (scripts/kb/load_trade_spec_checklists.mjs specCode)
const specCode = (label: string) => 'spec_' + String(label).toLowerCase().split(/[(:,;]/)[0].replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
type Pack = { trade: string; entries: { kind: string; required_specs?: string[]; body_en?: string }[] };
const pack = (code: string): Pack => JSON.parse(Deno.readTextFileSync(new URL(`knowledge/packs/${code}.json`, ROOT)));
// the taxonomy seeds: ('trade','code','Label EN','Label AR', n)
const SERVICES: TradeService[] = [];
for (const e of Deno.readDirSync(new URL('scripts/sql/', ROOT))) {
  if (!e.name.endsWith('.sql')) continue;
  for (const m of Deno.readTextFileSync(new URL('scripts/sql/' + e.name, ROOT)).matchAll(/\(\s*'([a-z0-9_]+)'\s*,\s*'([a-z0-9_]+)'\s*,\s*'((?:[^']|'')+)'\s*,\s*'[^']*'\s*,\s*\d+\s*\)/g)) {
    if (!SERVICES.some((s) => s.trade_code === m[1] && s.code === m[2])) SERVICES.push({ trade_code: m[1], code: m[2], label_en: m[3] });
  }
}
const TAX: TaxTrade[] = SPREAD.map(([g, code, , , auth]) => ({ code, label: code.replace(/_/g, ' '), group_code: g, authority_required: auth }));
function contextOf(code: string): TradeContext {
  const p = pack(code);
  const specs = [...new Map(p.entries.filter((e) => e.kind === 'spec_checklist').flatMap((e) => e.required_specs ?? []).map((l) => [specCode(l), { code: specCode(l), label_en: l }])).values()];
  const std = p.entries.find((e) => e.kind === 'standard')?.body_en ?? '';
  return { codes: [code], trades: TAX.filter((t) => t.code === code), services: SERVICES.filter((s) => s.trade_code === code), specs: { [code]: specs }, approvals: std ? { [code]: std.slice(0, 700) } : {} };
}

Deno.test('the spread covers all twelve groups, at least two trades each, with the trades the founder named', () => {
  const by = new Map<string, number>();
  for (const [g] of SPREAD) by.set(g, (by.get(g) ?? 0) + 1);
  assertEquals([...by.keys()].sort(), Object.keys(GROUP_LABEL).sort());
  for (const [g, n] of by) assert(n >= 2, g);
  for (const c of ['staff_transport', 'vehicle_leasing', 'corrugated_packaging', 'elevators', 'swimming_pools', 'scaffolding']) assert(SPREAD.some((s) => s[1] === c), c);
});

for (const [group, code, opening, wanted, auth] of SPREAD) {
  Deno.test(`${GROUP_LABEL[group]}: "${opening}" -> ${code}: its checklist, services and location rules drive the questions`, () => {
    const ctx = contextOf(code);
    // placed in the whole taxonomy: the code is listed under its group, and a code the model names is kept only if it exists
    assert(taxonomyBlock(TAX).includes(`${GROUP_LABEL[group]}: `) && taxonomyBlock(TAX).includes(code));
    assertEquals(validCodes([code, 'made_up_trade', code.toUpperCase()], TAX), [code]);
    // the spec checklist of THAT trade (every trade has one, ledger 1586) is what the conversation asks
    const specs = ctx.specs[code];
    assert(specs.length >= 3, `${code}: ${specs.length} specs in its pack`);
    assert(specs.some((s) => wanted.test(s.label_en)), `${code}: ${specs.map((s) => s.label_en).join('; ')}`);
    const block = tradeBlock(ctx);
    assert(block.includes(`[${code}]`) && block.includes('WHAT A SUPPLIER OF THIS TRADE NEEDS STATED') && specs.every((s) => block.includes(s.label_en)), block.slice(0, 400));
    // a request no category_specs slug covers runs this checklist: the core specs required, the rest optional
    const fields = checklistFields(specs);
    assertEquals(fields.filter((f) => f.required).length, Math.min(CHECKLIST_REQUIRED, specs.length));
    assertEquals(fields.map((f) => f.key), specs.map((s) => s.code));
    // the services of the trade are the keys matching gates on, and only real ones are kept
    assert(ctx.services.length >= 1, `${code} has no seeded service`);
    const key = `${ctx.services[0].trade_code}.${ctx.services[0].code}`;
    assert(block.includes(key));
    assertEquals(validServiceKeys([key, code + '.not_a_service'], ctx.services), [key]);
    // the location rules (the trade's verified approvals entry) ride with it when the pack has one
    if (ctx.approvals[code]) assert(block.includes('LOCATION RULES'), code);
    // an authority every job of the trade needs is said in words
    for (const a of auth) assert(block.includes('APPROVAL ALWAYS NEEDED') && block.includes(AUTHORITY[a]), code + ' ' + a);
    // the catalogue is seed knowledge, not the boundary: a trade it does not cover still gets all of the above
    if (!problemsFor({ codes: [code] }).length) assert(block.length > 200, code);
  });
}

Deno.test('nothing to place: no block; a bus rental has no catalogue problem and still gets its pack', () => {
  assertEquals(tradeBlock(null), '');
  assertEquals(tradeBlock({ codes: [], trades: [], services: [], specs: {}, approvals: {} }), '');
  assertEquals(problemsFor({ codes: ['staff_transport'] }).length, 0);
  assert(tradeBlock(contextOf('staff_transport')).includes('number of passengers and routes'));
  assertEquals(validCodes('staff_transport', TAX), []);
  assertEquals(validCodes(['staff_transport'], null), []);
});
