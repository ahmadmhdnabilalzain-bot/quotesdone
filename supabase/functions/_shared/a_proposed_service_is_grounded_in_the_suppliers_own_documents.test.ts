// A PROPOSED SERVICE IS GROUNDED IN THE SUPPLIER'S OWN DOCUMENTS. Seat: customer_support. 11 Nov 2026, the PAID supplier
// registration certification (ruling 1620), 06:07-06:47 UTC, both runs: every company was offered absurd trades beside the right
// ones. Each absurd one is reproduced below from that run's own evidence (the line, the service, the trade), on the six ZZ DEMO
// profiles of scripts/e2e/fixtures/registration. Two causes, two rules:
//   1. profile_services.servicesOfText read a document's services by meaning WITHOUT the trade confirmation tradesOfText applies
//      (13 Oct 2026: a line stands only when it holds its trade's own name or alias), so a head word alone decided: "...with our
//      own team and equipment." -> Recording studio equipment (musical_pro_audio) for four unrelated companies.
//   2. proposedServicesOf proposed every service a document named, in ANY trade: Spectacle frames (optical_eyewear) for the joiner,
//      Office & warehouse leasing for the MEP contractor, Same-day delivery for the packaging maker, Equipment rental for the bus
//      company. A service now stands only in a trade the document itself named (the model's quoted choice, or code's confirmed
//      reading) or the licence's activities name.
// And the customer side: service_vocabulary.keysInTrades keeps a key read from a request's prose only in the request's own trades.
//
//   cd supabase/functions && deno test --no-lock --node-modules-dir=none _shared/a_proposed_service_is_grounded_in_the_suppliers_own_documents.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { proposedServicesOf, servicesOfText, type ServiceHit } from './profile_services.ts';
import { keysInTrades } from './service_vocabulary.ts';
import type { MeaningService } from './service_meaning.ts';
import EXPECTED from '../../../scripts/e2e/fixtures/registration/expected.json' with { type: 'json' };

const svc = (key: string, snippet: string, via: ServiceHit['via'] = 'meaning'): ServiceHit =>
  ({ key, trade: key.split('.')[0], label_en: key, via, phrase: snippet, snippet });
const t = (...codes: string[]) => codes.map((code) => ({ code }));

// Per profile: the trades the documents named in the paid run (the profile's model choice, proven by a quote; the licence's
// activities), the services read (the right ones and every absurd one that run proposed, with the line it was read from).
const CASES: Record<string, { profile: string[]; licence: string[]; services: ServiceHit[] }> = {
  P1: { profile: ['electrical', 'hvac', 'mep_general', 'plumbing'], licence: ['hvac', 'plumbing'], services: [
    svc('electrical.db_panels', 'Electrical installation: LV distribution boards'), svc('hvac.ducting', 'ductwork', 'exact_name'),
    svc('plumbing.sanitary_fixtures', 'sanitary installation', 'exact_name'),
    svc('infrastructure_utilities.water_drainage_networks', 'Plumbing and drainage: water supply, sanitary installation, booster pumps'),
    svc('musical_pro_audio.studio_equipment', 'facility managers and businesses across the Emirates with our own team and equipment.'),
    svc('real_estate_services.office_warehouse_leasing', 'Electrical fit-out of a 1,800 m2 office floor, Business Bay (2024)'),
    svc('cleaning.facility_management', 'facility managers')] },
  P2: { profile: ['joinery'], licence: ['doors', 'joinery'], services: [
    svc('joinery.kitchens', 'Kitchens', 'exact_name'), svc('doors.wooden_doors', 'veneered doors'),
    svc('musical_pro_audio.studio_equipment', 'facility managers and businesses across the Emirates with our own team and equipment.'),
    svc('optical_eyewear.spectacle_frames', 'Solid wood and veneered doors, frames and architraves'),
    svc('wallpaper.wall_panels', 'Wall panelling, reception counters and built-in furniture for offices'),
    svc('office_furniture.reception_counters', 'reception counters', 'exact_name')] },
  P3: { profile: ['building_materials'], licence: ['building_materials'], services: [
    svc('building_materials.cement_concrete', 'cement', 'exact_name'),
    svc('hospitality_supplies.room_accessories', '- Sanitary ware, taps and bathroom accessories'),
    svc('logistics_moving.site_delivery', '- Delivery to site across the UAE from our Jebel Ali warehouse')] },
  P4: { profile: ['hvac'], licence: ['hvac'], services: [
    svc('hvac.vrf_chiller', 'VRF air conditioning'), svc('cleaning.ac_duct', 'Duct cleaning, gas charging and preventive maintenance'),
    svc('ev_charging.dc_fast_chargers', 'gas charging'),
    svc('musical_pro_audio.studio_equipment', 'managers and businesses across the Emirates with our own team and equipment.')] },
  P5: { profile: ['corrugated_packaging', 'rigid_plastic_packaging'], licence: ['corrugated_packaging'], services: [
    svc('corrugated_packaging.regular_slotted_cartons', 'Corrugated cartons', 'exact_name'), svc('glass_containers.glass_jars', 'PET jars'),
    svc('courier_express.same_day_delivery', 'In-house design, printing and same-week delivery to Dubai and the Northern Emirates')] },
  P6: { profile: ['staff_transport'], licence: ['staff_transport'], services: [
    svc('staff_transport.staff_shuttles', 'Staff transport: daily pick-up'),
    svc('heavy_equipment.equipment_rental', 'Bus and coach rental with driver, 14 to 65 seats'),
    svc('musical_pro_audio.studio_equipment', 'managers and businesses across the Emirates with our own team and equipment.')] },
};

for (const P of EXPECTED.profiles as { id: string; expect_trades: string[]; acceptable_trades: string[] }[]) {
  Deno.test(`${P.id}: his right trades are proposed, and none of the paid round's absurd ones`, () => {
    const c = CASES[P.id];
    const { proposed } = proposedServicesOf([
      { kind: 'licence', status: 'read', name: 'licence.pdf', activities: ['(as printed)'], trades: t(...c.licence) },
      { kind: 'profile', status: 'read', name: 'profile.pdf', trades: t(...c.profile), services: c.services },
    ]);
    const trades = [...new Set([...proposed.map((p) => p.trade), ...c.profile])];
    const absurd = trades.filter((x) => !P.expect_trades.includes(x) && !P.acceptable_trades.includes(x));
    assertEquals(absurd, [], `${P.id} still proposes ${absurd.join(', ')}`);
    assert(trades.some((x) => P.expect_trades.includes(x)), `${P.id} proposes none of its right trades`);
    // what was read in a grounded trade still reaches him, licence-covered or not (ledger 1573: never a rejection)
    for (const s of c.services) if (c.profile.includes(s.trade) || c.licence.includes(s.trade)) assert(proposed.some((p) => p.key === s.key), `${s.key} lost`);
  });
}

// Rule 1, on the vector rule itself: the line's nearest service is Recording studio equipment, and its head word ("equipment") is
// in the line. Without the trade confirmation that is enough; with it (the line names no audio or studio trade) it is not.
Deno.test('a document\'s service read by meaning needs its trade named in the line, as a trade does (the 13 Oct rule)', async () => {
  const studio: MeaningService = { trade_code: 'musical_pro_audio', code: 'studio_equipment', label_en: 'Recording studio equipment', label_ar: 'Recording studio equipment', aliases: [], vec: [1, 0, 0], vec_ml: null };
  const line = 'We serve contractors, developers, facility managers and businesses across the Emirates with our own team and equipment.';
  const deps = { services: [studio], embed: async () => [1, 0, 0], budget: { left: 10 } };
  const bare = await servicesOfText(line, deps);
  assertEquals(bare.services.map((s) => s.key), ['musical_pro_audio.studio_equipment'], 'the defect, reproduced without the confirmation');
  const guarded = await servicesOfText(line, { ...deps, budget: { left: 10 }, tradeLabels: { musical_pro_audio: 'Musical Instruments & Pro Audio' }, tradeAliases: { musical_pro_audio: ['pro audio', 'recording studio', 'musical instruments'] } });
  assertEquals(guarded.services, []);
});

Deno.test('the customer side: a key read from a request\'s prose stays only in the request\'s own trades', () => {
  assertEquals(keysInTrades(['doors.wooden_doors', 'optical_eyewear.spectacle_frames'], ['doors', 'joinery']), ['doors.wooden_doors']);
  assertEquals(keysInTrades(['doors.wooden_doors'], []), ['doors.wooden_doors'], 'nothing known to bound them by: kept as before');
  const op = Deno.readTextFileSync(new URL('../sales_engineer/actions/operator.ts', import.meta.url));
  assert(/serviceKeys = keysInTrades\(sk\.keys, /.test(op), 'dispatch no longer bounds the prose keys');
  const intake = Deno.readTextFileSync(new URL('../inquiry_intake/handle.ts', import.meta.url));
  assert(/keysInTrades\(\(await serviceKeysOf\(allText, [^\n]*\.keys, codesNow\)/.test(intake), 'the intake count no longer bounds them');
});
