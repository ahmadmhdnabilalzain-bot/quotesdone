// rules.test.ts — one test per rule family, on the gypsum rules file (the fixture IS the authored
// trade), plus the wiring into technicalComparison() and rankable() on the D958E1EA-shaped BOQ.
//   deno test --allow-read supabase/functions/_shared/line_specs/rules.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { approvalsFor, comparabilityFor, equivalenceOf, normUnit, priceFlag, ruleLine, rulesFromJson, scopeCheck } from './rules.ts';
import { rankable, technicalComparison } from './compare.ts';

const RULES = rulesFromJson(JSON.parse(await Deno.readTextFile(new URL('../rules/gypsum.json', import.meta.url))))!;
const AR = /[ء-ي]/;

const BOQ = 'Gypsum partitions and false ceiling for an office fit-out in Business Bay, Dubai \n Gypsum board partition, 100mm metal stud, both faces \n Suspended false ceiling, 600x600 mineral fibre tiles \n Gypsum bulkhead, 300mm drop, painted finish';
const COMPLIANT = 'Gypsum board partition 12.5mm Knauf standard board both faces on 100mm x 0.6mm GI studs at 600mm centres, 50mm rockwool 40kg/m3 insulation, taping, jointing compound and Q3 finish; Suspended ceiling 600x600 mineral fibre tiles 15mm on Knauf grid system with hangers and perimeter trim; bulkhead 12.5mm board on furring channels, painted; screws, corner beads and trims included; deflection head track; cut-outs 20 nos; debris removal included';
const CHEAP = 'Gypsum board partition 9.5mm standard board both faces on 100mm studs; 600x600 tiles; bulkhead';

Deno.test('rulesFromJson keeps only active rows and reads every family', () => {
  assertEquals(RULES.trade_code, 'gypsum');
  assertEquals([RULES.scope_lines.length, RULES.equivalence.length, RULES.price_flags.length, RULES.comparability.length, RULES.approvals.length], [13, 17, 5, 3, 4]);
  assert(RULES.equivalence.every((r) => r.value !== 'Gyproc'), 'an inactive (unverified) brand row leaked into the live rules');
  for (const fam of [RULES.scope_lines, RULES.equivalence, RULES.price_flags, RULES.comparability, RULES.approvals]) for (const r of fam) {
    assert(AR.test(r.rule_ar) && r.rule_en.length > 20 && r.citation && r.effective_date && ['law', 'practice', 'manufacturer_data'].includes(r.label), `row lacks the doctrine columns: ${JSON.stringify(r).slice(0, 80)}`);
  }
});

Deno.test('family 1: a quotation missing a mandatory scope line is held, naming the line in both languages', () => {
  const ok = scopeCheck(RULES, BOQ, COMPLIANT);
  assertEquals(ok.missing_mandatory, []);
  const bad = scopeCheck(RULES, BOQ, CHEAP);
  const keys = bad.missing_mandatory.map((r) => r.line_key).sort();
  assertEquals(keys, ['fixings_accessories', 'jointing_finish', 'suspension_grid']);
  assert(AR.test(ruleLine(bad.missing_mandatory[0], 'ar')) && !AR.test(ruleLine(bad.missing_mandatory[0], 'en')));
  // A partition-only request never demands a ceiling grid.
  assertEquals(scopeCheck(RULES, 'Gypsum board partition 100mm stud', CHEAP).missing_mandatory.map((r) => r.line_key).sort(), ['fixings_accessories', 'jointing_finish']);
});

Deno.test('family 2: commonly omitted lines absent from the quote are reported; present ones are not', () => {
  const bad = scopeCheck(RULES, BOQ, CHEAP).omitted.map((r) => r.line_key).sort();
  assertEquals(bad, ['access_panels', 'cutouts_for_services', 'debris_removal', 'deflection_head', 'insulation', 'painting_finish']);
  const ok = scopeCheck(RULES, BOQ, COMPLIANT).omitted.map((r) => r.line_key);
  assertEquals(ok, ['access_panels']);   // the one thing the compliant quote genuinely does not mention
  // Fire stopping is asked only of a fire-rated request.
  assert(!scopeCheck(RULES, BOQ, CHEAP).omitted.some((r) => r.line_key === 'fire_stopping'));
  assert(scopeCheck(RULES, BOQ + ' 60 min fire rated partition', CHEAP).omitted.some((r) => r.line_key === 'fire_stopping'));
});

Deno.test('family 3: equivalence classes decide before sameValue', () => {
  const d = equivalenceOf(RULES, 'board_type', 'Standard gypsum board', 'Moisture-resistant board')!;
  assertEquals([d.flag, d.rule?.label], ['differs', 'practice']);
  assert(AR.test(d.rule!.rule_ar));
  assertEquals(equivalenceOf(RULES, 'board_type', 'Standard gypsum board', 'Fire-rated board')!.rule!.label, 'law');
  assertEquals(equivalenceOf(RULES, 'board_type', 'Standard gypsum board', 'Mineral fibre tile')!.flag, 'differs');
  assertEquals(equivalenceOf(RULES, 'board_type', 'Moisture-resistant board', 'Moisture-resistant board')!.flag, 'match');
  assertEquals(equivalenceOf(RULES, 'thickness_mm', '9.5 mm', '12.5')!.flag, 'differs');
  assertEquals(equivalenceOf(RULES, 'thickness_mm', '12.5mm', '12.5')!.flag, 'match');
  assertEquals(equivalenceOf(RULES, 'frame', '0.5mm GI studs', '0.6 mm')!.flag, 'differs');
  // Brands: a member matches; an unclassified brand is unclassified (never a match); an unknown request says nothing.
  assertEquals(equivalenceOf(RULES, 'brand', 'Knauf FireShield', 'Knauf')!.flag, 'match');
  assertEquals(equivalenceOf(RULES, 'brand', 'Gyproc', 'Knauf')!.flag, 'unclassified');
  assertEquals(equivalenceOf(RULES, 'brand', 'Knauf', 'Acme Boards'), null);
});

Deno.test('family 4: a unit rate under the annotated band is a red flag with the reason in both languages', () => {
  assertEquals([normUnit('m2'), normUnit('sqm'), normUnit('م²'), normUnit('nos'), normUnit('lm')], ['sqm', 'sqm', 'sqm', 'each', 'm']);
  const low = priceFlag(RULES, 'Gypsum board partition 9.5mm', 320, 'm2', 320 * 38)!;
  assertEquals([low.verdict, low.rate, low.rule.benchmark_id], ['below', 38, 84]);
  assert(AR.test(low.rule.rule_ar));
  assertEquals(priceFlag(RULES, 'Gypsum board partition 12.5mm', 320, 'm2', 320 * 95)!.verdict, 'within');
  assertEquals(priceFlag(RULES, 'Suspended false ceiling, 600x600 mineral fibre tiles', 410, 'm2', null, 68)!.rule.benchmark_id, 83);
  assertEquals(priceFlag(RULES, 'Gypsum bulkhead 300mm drop', 64, 'm', 64 * 40), null);   // no band is per metre: no guess
  assertEquals(priceFlag(RULES, 'Light cut-outs', 20, 'nos', 20 * 120)!.verdict, 'above');
});

Deno.test('family 5: comparability keys name the attributes both quotes must state', () => {
  assertEquals(comparabilityFor(RULES, 'Gypsum board partition, 100mm metal stud')!.required_attrs, ['board_type', 'thickness_mm', 'frame']);
  assertEquals(comparabilityFor(RULES, 'Suspended false ceiling, 600x600 mineral fibre tiles')!.line_type, 'tile_ceiling');
  assertEquals(comparabilityFor(RULES, 'Painting of walls'), null);
});

Deno.test('family 6: approvals for the inquiry emirate, triggered by the request', () => {
  const dubai = approvalsFor(RULES, 'Dubai', BOQ).map((a) => a.authority);
  assertEquals(dubai, ['Dubai Municipality / Trakhees / DDA (by plot jurisdiction)', 'Department of Economy (trade licence)']);
  assert(approvalsFor(RULES, 'Dubai', BOQ + ' fire rated').some((a) => a.authority === 'Dubai Civil Defence' && a.label === 'law'));
  assertEquals(approvalsFor(RULES, 'Sharjah', BOQ).map((a) => a.authority), ['Department of Economy (trade licence)']);
});

// The wiring: the D958E1EA-shaped inquiry with a compliant quote and a substituted, incomplete, under-priced one.
const REQ_LINES = [
  { line_no: 1, description: 'Gypsum board partition, 100mm metal stud, both faces', qty: 320, unit: 'm2' },
  { line_no: 2, description: 'Suspended false ceiling, 600x600 mineral fibre tiles', qty: 410, unit: 'm2' },
  { line_no: 3, description: 'Gypsum bulkhead, 300mm drop, painted finish', qty: 64, unit: 'm' },
];
const REQ = { version: 1, warranty: { required: 'yes' }, installation: { required: 'yes' }, materials: [{ component: 'partitions', choice: 'Moisture-resistant board' }] };
const terms = (price: number) => ({ lead_time: '3 weeks', warranty: '12 months on materials and workmanship', scope: 'Supply and installation included: site measurement, fixing and finishing', price_ex_vat: price });
const GOOD = { quote_id: 'good', label_en: 'Supplier A', label_ar: 'المورّد أ', supplier_letter: 'A', option_no: 1, terms: terms(60000), lines: [
  { line_no: 1, description: 'Gypsum board partition 12.5mm moisture-resistant Knauf board both faces on 100mm x 0.6mm GI studs at 600mm centres, 50mm rockwool insulation, taping, jointing and Q3 finish', qty: 320, unit: 'm2', unit_price: 95, amount: 30400 },
  { line_no: 2, description: 'Suspended ceiling 600x600 mineral fibre tiles 15mm on Knauf grid system with hangers and perimeter trim', qty: 410, unit: 'm2', unit_price: 68, amount: 27880 },
  { line_no: 3, description: 'Gypsum bulkhead 12.5mm standard board on furring channels, painted, screws, beads and trims, deflection head track, cut-outs, debris removal', qty: 64, unit: 'm', unit_price: 27, amount: 1728 } ] };
const BAD = { quote_id: 'bad', label_en: 'Supplier B', label_ar: 'المورّد ب', supplier_letter: 'B', option_no: 1, terms: { ...terms(31000), scope: 'Supply and installation included: site measurement and fixing' }, lines: [
  { line_no: 1, description: 'Gypsum board partition 9.5mm standard gypsum board both faces on 100mm studs', qty: 320, unit: 'm2', unit_price: 38, amount: 12160 },
  { line_no: 2, description: 'Suspended ceiling 600x600 ceiling tiles 12mm on exposed T-grid 24mm profiles with hangers and perimeter trim', qty: 410, unit: 'm2', unit_price: 42, amount: 17220 },
  { line_no: 3, description: 'Gypsum bulkhead 12.5mm standard board on furring channels, screws and beads', qty: 64, unit: 'm', unit_price: 25, amount: 1600 } ] };

Deno.test('wiring: rankable holds the quote missing a mandatory scope line and names it', () => {
  const r = rankable([GOOD, BAD], 'gypsum', REQ, RULES, BOQ);
  assertEquals(r.rankable.map((q) => q.quote_id), ['good']);
  assertEquals(r.held, 1);
  assertEquals(r.held_by_rule[0].lines.map((l) => l.line_key), ['jointing_finish']);
  // Without rules the same pair ranks as before (BAD states every line attribute the model asks for).
  assertEquals(rankable([GOOD, BAD], 'gypsum', REQ).rankable.length, 2);
});

Deno.test('wiring: technicalComparison flags the substitution, the omissions, the under-market price, the not-comparable line and the approvals', () => {
  const t = technicalComparison({ category: 'gypsum', request_lines: REQ_LINES, requirements: REQ, quotes: [GOOD, BAD], on_hold: 0, now: new Date('2026-09-21'), rules: RULES, request_text: BOQ, emirate: 'Dubai' });
  assertEquals(t.rules_applied?.trade_code, 'gypsum');
  const partition = t.lines[0];
  const bt = partition.attributes.find((a) => a.code === 'board_type')!;
  const badCell = bt.cells.find((c) => c.quote_id === 'bad')!, goodCell = bt.cells.find((c) => c.quote_id === 'good')!;
  assertEquals([goodCell.flag, badCell.flag, badCell.marker], ['match', 'differs', '≠']);
  assert(badCell.note_en!.includes('NOT equivalent') && AR.test(badCell.note_ar!));
  const thk = partition.attributes.find((a) => a.code === 'thickness_mm')!.cells.find((c) => c.quote_id === 'bad')!;
  assertEquals([thk.flag, thk.note_en], ['differs', undefined]);   // the BOQ wording yields a 100 mm baseline for every quote; no equivalence class knows it, so sameValue decides as before, with no rule note
  // The tile line: BAD states no brand, so the line is not comparable and its brand cell carries ≁.
  const tile = t.lines[1];
  assertEquals(tile.comparable, false);
  assertEquals(tile.comparability?.missing, [{ quote_id: 'bad', attrs: ['brand'] }]);
  assertEquals(tile.attributes.find((a) => a.code === 'brand')!.cells.map((c) => [c.quote_id, c.flag, c.marker]), [['good', 'stated', ''], ['bad', 'not_comparable', '≁']]);
  assertEquals(partition.comparable, true);
  // Omissions, prices, approvals.
  const badOm = t.omissions!.find((o) => o.quote_id === 'bad')!.lines.map((l) => l.line_key).sort();
  assertEquals(badOm, ['access_panels', 'cutouts_for_services', 'debris_removal', 'deflection_head', 'insulation', 'painting_finish']);
  assertEquals(t.omissions!.find((o) => o.quote_id === 'good')!.lines.map((l) => l.line_key), ['access_panels']);
  assertEquals(t.holds!.map((h) => [h.quote_id, h.lines.map((l) => l.line_key)]), [['bad', ['jointing_finish']]]);   // reported, never dropped: rankable() is the gate
  const badPrices = t.prices!.filter((p) => p.quote_id === 'bad').map((p) => [p.quote_line_no, p.verdict]);
  assertEquals(badPrices, [[1, 'below'], [2, 'within']]);
  assertEquals(t.prices!.filter((p) => p.quote_id === 'good').map((p) => p.verdict), ['within', 'within']);
  assertEquals(t.approvals!.map((a) => a.stage), ['before_works', 'supplier_licence']);
  // Without rules: no flags of these kinds at all, and the substitution reads as a plain ≠ with no note.
  const t0 = technicalComparison({ category: 'gypsum', request_lines: REQ_LINES, requirements: REQ, quotes: [GOOD, BAD], on_hold: 0, now: new Date('2026-09-21') });
  assertEquals([t0.rules_applied, t0.omissions, t0.prices, t0.approvals, t0.lines[1].comparable], [null, [], [], [], null]);
  assertEquals(t0.lines[0].attributes.find((a) => a.code === 'board_type')!.cells.find((c) => c.quote_id === 'bad')!.note_en, undefined);
});
