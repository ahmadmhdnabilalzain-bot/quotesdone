// A SERVICE IS LISTED IN THE TRADE OF ITS LINE (16 Nov 2026, sales_engineer; paid certification of 16 Nov 2026, run 2: "the proposals are
// his trades, nothing absurd" FAILED on J1, industrial_pumps, and J9, masonry_blockwork; the same journeys passed in run 1 and at 15:00).
// The fixtures are right (their documents' own words, scripts/e2e/registration_fixtures.mjs):
//   P1 (MEP contractor) prints "Plumbing and drainage: water supply, sanitary installation, booster pumps". The booster pumps of a building's
//      water supply are plumbing work (plumbing.heaters_pumps "Water heaters & pumps", which run 1 listed); Industrial pumps is a goods trade
//      under the oilfield umbrella, and nothing in P1 or its licence L1 says the company supplies or repairs pumps.
//   P7 (decoration company) prints "Wall painting, stucco and decorative paint finishes". Stucco there is a decorative wall finish (painting.
//      decorative, which run 1 listed); "Masonry, blockwork & plastering" is civil work under the civil_works umbrella, and nothing in P7 or
//      its licence L9 ("Interior Decoration Works", "Building Maintenance") names blockwork or masonry.
// Run 2 listed industrial_pumps.booster_sets and masonry_blockwork.plastering from those very lines, beside the line's own trade's services.
// The quote rule let them through because it proves the words, not the trade (supplier_profile_reading.checkLineTrades). These tests give
// the REAL two steps (readInTwoSteps: checkReading, the mapping's checks, checkLineTrades) and proposalOf the answers of both runs.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/a_service_is_listed_in_the_trade_of_its_line.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { profileReadSystem, proposalOf, readInTwoSteps, type ReadDoc, type Taxonomy } from './supplier_profile_reading.ts';

// The catalogue rows these readings touch, as production holds them (taxonomy_trade, taxonomy_trade_service, taxonomy_trade_adjacent; read
// 16 Nov 2026): industrial_pumps sits under oilfield and has no adjacent trade; masonry_blockwork sits under civil_works, adjacent to gypsum.
const TAX: Taxonomy = {
  trades: [
    { code: 'plumbing', label: 'Plumbing & sanitary', umbrella_code: null, services: [['drainage', 'Drainage & sewerage'], ['heaters_pumps', 'Water heaters & pumps'], ['sanitary_fixtures', 'Sanitary fixtures installation'], ['water_supply', 'Water supply piping']].map(([k, label]) => ({ key: `plumbing.${k}`, label })) },
    { code: 'oilfield', label: 'Oil & gas services', umbrella_code: null, services: [{ key: 'oilfield.service', label: 'Oilfield services' }] },
    { code: 'industrial_pumps', label: 'Industrial pumps', umbrella_code: 'oilfield', services: [['booster_sets', 'Booster sets'], ['centrifugal_pumps', 'Centrifugal pumps'], ['submersible_sewage_pumps', 'Submersible & sewage pumps']].map(([k, label]) => ({ key: `industrial_pumps.${k}`, label })) },
    { code: 'electrical', label: 'Electrical', umbrella_code: null, services: [{ key: 'electrical.db_panels', label: 'Distribution boards & switchgear' }] },
    { code: 'painting', label: 'Painting & finishes', umbrella_code: null, services: [['decorative', 'Decorative finishes'], ['interior', 'Interior painting'], ['exterior', 'Exterior painting']].map(([k, label]) => ({ key: `painting.${k}`, label })) },
    { code: 'gypsum', label: 'Gypsum, partitions & ceilings', umbrella_code: null, services: [['false_ceiling', 'False ceilings'], ['decorative', 'Decorative gypsum'], ['plastering', 'Plastering']].map(([k, label]) => ({ key: `gypsum.${k}`, label })) },
    { code: 'civil_works', label: 'Civil works', umbrella_code: null, services: [{ key: 'civil_works.concrete', label: 'Concrete works' }] },
    { code: 'masonry_blockwork', label: 'Masonry, blockwork & plastering', umbrella_code: 'civil_works', services: [['blockwork', 'Blockwork'], ['plastering', 'Plastering']].map(([k, label]) => ({ key: `masonry_blockwork.${k}`, label })) },
    { code: 'curtains_blinds', label: 'Curtains & blinds', umbrella_code: null, services: [{ key: 'curtains_blinds.curtains', label: 'Curtains & sheers' }] },
    { code: 'upholstery', label: 'Upholstery', umbrella_code: null, services: [['curtains', 'Curtains'], ['sofa', 'Sofa & majlis upholstery']].map(([k, label]) => ({ key: `upholstery.${k}`, label })) },
  ],
  adjacent: [['gypsum', 'masonry_blockwork'], ['civil_works', 'masonry_blockwork'], ['curtains_blinds', 'upholstery']],
};

const PLUMBING = 'Plumbing and drainage: water supply, sanitary installation, booster pumps';
const P1: ReadDoc = { path: 'p/P1', name: 'P1_mep_contractor.pdf', kind: 'profile', text: ['What we do', 'Electrical installation: LV distribution boards, cabling, lighting and small power', PLUMBING, 'HVAC: ducted split, VRF and chilled-water fan coil installation, ductwork'].join('\n') };
const PAINT = 'Wall painting, stucco and decorative paint finishes';
const P7: ReadDoc = { path: 'p/P7', name: 'P7_decoration_pools_partner.pdf', kind: 'profile', text: ['Inside the home', 'Gypsum ceilings, cornices and feature walls', PAINT, 'Wallpaper and decorative wall panels', 'Curtains, blinds and upholstery of majlis seating'].join('\n') };
const L1: ReadDoc = { path: 'l/L1', name: 'L1_dubai_det_bilingual.pdf', kind: 'licence', text: 'Activities: Electromechanical Equipment Installation and Maintenance, Plumbing and Sanitary Installation, Air Conditioning and Ventilation Systems Installation' };

type Item = { words: string; quote: string; trade: string; keys: string[]; basis?: string };
/** Step A answers `items` (words, quote, trade); step B maps each phrase to the item's keys. Through the real two steps. */
async function read(docs: ReadDoc[], items: Item[]) {
  const evidence = items.map((x) => ({ words: x.words, quote: x.quote, basis: x.basis ?? 'stated', trade: x.trade, licence: 'covered' }));
  const r = await readInTwoSteps(docs, 'ZZ DEMO', TAX, (step, _sys, text) => {
    if (step === 'read') return Promise.resolve({ ok: true as const, content: JSON.stringify({ summary: 's', evidence, vague: [], also_ask: [], licence: { covers_profile: 'yes', note: '' } }) });
    const map = [...text.matchAll(/^(\d+)\. (.+?) {2}\[trade/gm)].map((m) => ({ i: Number(m[1]), keys: items.find((x) => x.words === m[2])?.keys ?? [] }));
    return Promise.resolve({ ok: true as const, content: JSON.stringify({ map }) });
  });
  assert(r.ok, !r.ok ? r.error : '');
  return { reading: r.reading, proposal: proposalOf(r.reading, TAX, []) };
}
const tradesListed = (p: ReturnType<typeof proposalOf>) => [...new Set([...p.tick, ...p.partner, ...p.shown].map((x) => x.trade))].sort();

Deno.test('the reading is told: an item\'s trade is the trade of its line\'s work, never one whose name shares a word', () => {
  const sys = profileReadSystem(TAX.trades);
  assert(sys.includes('the trade of the line it is quoted from whenever that trade does this work, never a trade picked because its name shares a word with the item (booster pumps in a plumbing line are plumbing, stucco in a painting line is painting)'));
});

Deno.test('P1 run 2: "booster pumps" read as Industrial pumps from the plumbing line -> not listed, kept in his words, recorded', async () => {
  const { reading, proposal } = await read([P1, L1], [
    { words: 'Water supply', quote: PLUMBING, trade: 'plumbing', keys: ['plumbing.water_supply'] },
    { words: 'Sanitary installation', quote: PLUMBING, trade: 'plumbing', keys: ['plumbing.sanitary_fixtures'] },
    { words: 'Booster pumps', quote: PLUMBING, trade: 'industrial_pumps', keys: ['industrial_pumps.booster_sets'] },
  ]);
  assertEquals(tradesListed(proposal), ['plumbing']);
  assertEquals(proposal.tick.map((x) => x.key).sort(), ['plumbing.sanitary_fixtures', 'plumbing.water_supply']);
  assertEquals(proposal.own_words.map((w) => [w.words, w.trade]), [['Booster pumps', null]], 'his words kept, under no trade (the line is not about industrial pumps)');
  assert(!proposal.questions.some((q) => q.about.trade === 'industrial_pumps'), 'no card asks him about industrial pumps');
  assert(reading.rejected.some((x) => x.what === 'industrial_pumps.booster_sets' && /which is about plumbing; industrial_pumps is named by no other line/.test(x.why)));
});

Deno.test('P1 run 1: "booster pumps" read as plumbing -> listed as plumbing.heaters_pumps, nothing rejected', async () => {
  const { reading, proposal } = await read([P1, L1], [
    { words: 'Water supply', quote: PLUMBING, trade: 'plumbing', keys: ['plumbing.water_supply'] },
    { words: 'Sanitary installation', quote: PLUMBING, trade: 'plumbing', keys: ['plumbing.sanitary_fixtures'] },
    { words: 'Booster pumps', quote: PLUMBING, trade: 'plumbing', keys: ['plumbing.heaters_pumps'] },
  ]);
  assertEquals(proposal.tick.map((x) => x.key).sort(), ['plumbing.heaters_pumps', 'plumbing.sanitary_fixtures', 'plumbing.water_supply']);
  assertEquals(reading.rejected, []);
});

Deno.test('P7 run 2: "stucco" mapped to masonry_blockwork.plastering from the painting line -> dropped, though masonry is adjacent to gypsum on ANOTHER line', async () => {
  for (const trade of ['painting', 'masonry_blockwork']) {   // whichever trade step A gave it: the mapping's key is checked
    const { reading, proposal } = await read([P7], [
      { words: 'Gypsum ceilings', quote: 'Gypsum ceilings, cornices and feature walls', trade: 'gypsum', keys: ['gypsum.false_ceiling'] },
      { words: 'Wall painting', quote: PAINT, trade: 'painting', keys: ['painting.interior'] },
      { words: 'Stucco finishes', quote: PAINT, trade, keys: ['masonry_blockwork.plastering'] },
      { words: 'Decorative paint finishes', quote: PAINT, trade: 'painting', keys: ['painting.decorative'] },
    ]);
    assertEquals(tradesListed(proposal), ['gypsum', 'painting'], trade);
    assertEquals(proposal.own_words.map((w) => [w.words, w.trade]), [['Stucco finishes', trade === 'painting' ? 'painting' : null]]);
    assert(reading.rejected.some((x) => x.what === 'masonry_blockwork.plastering'));
  }
  // an item mapped to its line's key AND the off-line one keeps only its line's key
  const both = await read([P7], [
    { words: 'Wall painting', quote: PAINT, trade: 'painting', keys: ['painting.interior'] },
    { words: 'Stucco finishes', quote: PAINT, trade: 'painting', keys: ['painting.decorative', 'masonry_blockwork.plastering'] },
  ]);
  assertEquals(both.proposal.tick.map((x) => x.key).sort(), ['painting.decorative', 'painting.interior']);
});

Deno.test('what the check leaves alone: a line of one trade, a related trade, a trade named elsewhere, an even line, prose', async () => {
  // a pump company's own line: every item is industrial pumps
  const pumps = 'Booster sets, centrifugal and submersible pumps';
  const a = await read([{ path: 'p/X', name: 'x.pdf', kind: 'profile', text: pumps }], [
    { words: 'Booster sets', quote: pumps, trade: 'industrial_pumps', keys: ['industrial_pumps.booster_sets'] },
    { words: 'Centrifugal pumps', quote: pumps, trade: 'industrial_pumps', keys: ['industrial_pumps.centrifugal_pumps'] }]);
  assertEquals(a.reading.rejected, []);
  // curtains beside upholstery: curated adjacent trades
  const cur = 'Curtains, blinds and upholstery of majlis seating';
  const b = await read([P7], [
    { words: 'Curtains', quote: cur, trade: 'curtains_blinds', keys: ['curtains_blinds.curtains'] },
    { words: 'Majlis upholstery', quote: cur, trade: 'upholstery', keys: ['upholstery.sofa'] },
    { words: 'Upholstered curtains', quote: cur, trade: 'upholstery', keys: ['upholstery.curtains'] }]);
  assertEquals(b.reading.rejected, []);
  // industrial pumps named by another line of the documents too: his own statement, not one word of a plumbing list
  const c = await read([{ ...P1, text: P1.text + '\nSupply and repair of centrifugal pumps' }], [
    { words: 'Water supply', quote: PLUMBING, trade: 'plumbing', keys: ['plumbing.water_supply'] },
    { words: 'Sanitary installation', quote: PLUMBING, trade: 'plumbing', keys: ['plumbing.sanitary_fixtures'] },
    { words: 'Booster pumps', quote: PLUMBING, trade: 'industrial_pumps', keys: ['industrial_pumps.booster_sets'] },
    { words: 'Centrifugal pump supply', quote: 'Supply and repair of centrifugal pumps', trade: 'industrial_pumps', keys: ['industrial_pumps.centrifugal_pumps'] }]);
  assertEquals(c.reading.rejected, []);
  // one item each: not outweighed (the 12 Nov recording's H06 line, 2 of 3 items read as industrial pumps, is the same: kept, KNOWN wrong)
  const d = await read([P1], [
    { words: 'Water supply', quote: PLUMBING, trade: 'plumbing', keys: ['plumbing.water_supply'] },
    { words: 'Booster pumps', quote: PLUMBING, trade: 'industrial_pumps', keys: ['industrial_pumps.booster_sets'] }]);
  assertEquals(d.reading.rejected, []);
  // a quote of part of a line (prose) is no list item and is not checked
  const prose = 'Our crews carry out plumbing works, water supply and sanitary installation, and booster pumps for towers';
  const e = await read([{ path: 'p/Y', name: 'y.pdf', kind: 'profile', text: prose }], [
    { words: 'Water supply', quote: 'water supply and sanitary installation', trade: 'plumbing', keys: ['plumbing.water_supply'] },
    { words: 'Sanitary installation', quote: 'water supply and sanitary installation', trade: 'plumbing', keys: ['plumbing.sanitary_fixtures'] },
    { words: 'Booster pumps', quote: 'booster pumps for towers', trade: 'industrial_pumps', keys: ['industrial_pumps.booster_sets'] }]);
  assertEquals(e.reading.rejected, []);
});
