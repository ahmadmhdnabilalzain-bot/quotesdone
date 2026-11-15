// A LINE THAT LISTS SERVICES AFTER A HEADING IS ONE ITEM FOR EACH (15 Nov 2026, customer_support; the paid certification of 15 Nov
// 2026, run 2 J1, "the services shown are his": FAIL, "must not shown: electrical.db_panels" = a service the fixture says he must be
// shown was NOT shown). The fixture is right: P1 (scripts/e2e/fixtures/registration/P1_mep_contractor.pdf) prints, under "What we do",
//   "Electrical installation: LV distribution boards, cabling, lighting and small power"
// Run 1 read that line as three items (distribution boards, lighting, wiring) and listed electrical.db_panels; run 2 read it as one
// ("electrical installation") and listed only electrical.wiring_install, 6 rows against run 1's 11 (VRF and sanitary went the same way).
// Nothing in code dropped it (no rejected claim): the reading read fewer items. The reading's rule 1 now says such a line is one item
// for each thing listed, never one for the heading (supplier_profile_reading.profileReadSystem). This test holds code's half: every
// item quoting the one line is kept, mapped and listed, and the prompt carries the rule. The model's half is the paid run's.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/a_line_that_lists_services_is_one_item_for_each.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { profileReadSystem, proposalOf, type ReadDoc } from './supplier_profile_reading.ts';
import { fakeReader, fakeTaxonomy } from './supplier_profile_reading.test_reader.ts';

const LINE = 'Electrical installation: LV distribution boards, cabling, lighting and small power';
const P1: ReadDoc = { path: 'p/P1', name: 'P1_mep_contractor.pdf', kind: 'profile', text: `What we do\n${LINE}\nPlumbing and drainage: water supply, sanitary installation, booster pumps\nHVAC: ducted split, VRF and chilled-water fan coil installation, ductwork\nAnnual maintenance contracts for MEP systems in villas and offices` };
const TAX = fakeTaxonomy(['electrical'], ['electrical.wiring_install', 'electrical.db_panels', 'electrical.lighting', 'electrical.lighting_poles']);

Deno.test('the reading is told: a heading with a list after it is one item for each thing listed', () => {
  const sys = profileReadSystem([{ code: 'electrical', label: 'Electrical' }]);
  assert(sys.includes('is one item for EACH thing listed (distribution boards, cabling, lighting, small power), never one item for the heading alone'));
  assert(sys.includes('a line naming three services is three items, each quoting that line'));
});

Deno.test('P1: one item for each thing on the line -> distribution boards listed; one item for the heading -> it is not (run 2)', async () => {
  const each = await fakeReader(() => ({ trades: [{ code: 'electrical', quote: LINE, services: [
    { key: 'electrical.db_panels', quote: LINE }, { key: 'electrical.wiring_install', quote: LINE }, { key: 'electrical.lighting', quote: LINE }] }] }), { taxonomy: TAX })([P1], 'ZZ DEMO Saker Electromechanical Contracting LLC');
  assert(each.ok);
  const listed = proposalOf(each.reading, TAX, []).tick.map((t) => t.key).sort();
  assertEquals(listed, ['electrical.db_panels', 'electrical.lighting', 'electrical.wiring_install'], 'every item quoting the one line is kept');
  assertEquals(each.reading.rejected, []);
  // the run-2 shape: the heading read as the one item; code cannot invent what was not read, and lists only wiring
  const heading = await fakeReader(() => ({ trades: [{ code: 'electrical', quote: LINE, services: [{ key: 'electrical.wiring_install', quote: LINE }] }] }), { taxonomy: TAX })([P1], null);
  assert(heading.ok);
  assertEquals(proposalOf(heading.reading, TAX, []).tick.map((t) => t.key), ['electrical.wiring_install']);
});
