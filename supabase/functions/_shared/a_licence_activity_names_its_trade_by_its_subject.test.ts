// A LICENCE ACTIVITY NAMES ITS TRADE BY ITS SUBJECT, DECIDED EXACTLY. Seat: customer_support. 11 Nov 2026, supplier
// registration certification (ruling 1620), finding 5.
//
// Measured in the free round: a building-materials trader (fixture L3, JAFZA: "Building Materials Trading", "Tiles and
// Ceramics Trading", "Sanitary Ware Trading") was proposed plumbing only. The exact path asked fn_norm_trades about the whole
// activity, and "building materials trading" is no code; the trade the licence prints was never read. With meaning off,
// code alone proposed NOTHING from any of the eight certification licences. trade_resolve.ts now sets the activity's FORM
// aside (trading, contracting, works...) and decides the SUBJECT exactly: by fn_norm_trades, or by the trade's own English
// name. The live codes, intake slugs and labels below are production's (11 Nov 2026), so the exact rule here is the real one.
//
//   cd supabase/functions && deno test --no-lock --node-modules-dir=none _shared/a_licence_activity_names_its_trade_by_its_subject.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { activitySubjects, englishNameHeads, tradesOfText, type TradeResolveDeps } from './trade_resolve.ts';
import EXPECTED from '../../../scripts/e2e/fixtures/registration/expected.json' with { type: 'json' };

// production's taxonomy_trade (code -> label), the slice these licences and their neighbours touch
const LABELS: Record<string, string> = {
  building_materials: 'Building & Construction Materials', plumbing: 'Plumbing & sanitary', hvac: 'HVAC & air conditioning',
  joinery: 'Joinery & carpentry', doors: 'Doors & windows', flooring: 'Flooring', marble_stone: 'Marble, granite & natural stone',
  steel: 'Steel & metal fabrication', steel_stock: 'Steel stock & trading', non_ferrous_metals: 'Aluminium, copper & non-ferrous metals',
  aluminium: 'Aluminium & cladding', painting: 'Painting & finishes', cleaning: 'Cleaning & facility services',
  facilities_management: 'Facilities management (hard & soft FM)', staff_transport: 'Staff transport & bus rental',
  corrugated_packaging: 'Corrugated boxes & cartons', packaging: 'Packaging & Printing Supplies', mep_general: 'MEP (combined)',
  electrical: 'Electrical', glazing: 'Glass & glazing', landscaping: 'Landscaping & pools', general_contracting: 'General building contracting',
};
const SLUGS: Record<string, string[]> = { carpentry: ['joinery'], glass: ['glazing'], tiling: ['flooring'], mep: ['mep_general'] };
// fn_norm_trades: fn_trade_code equality with a live code or an intake slug (fn_taxonomy_trades_for)
const code = (s: string) => s.trim().toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '_').replace(/^_+|_+$/g, '');
const normTrades = async (phrases: string[]) => {
  const out: Record<string, string[]> = {};
  for (const p of phrases) { const c = code(p); const cs = [...new Set([...(LABELS[c] ? [c] : []), ...(SLUGS[c] ?? [])])]; if (cs.length) out[p] = cs; }
  return out;
};
// code only: no meaning (the free round's state), so what is proposed is what the exact rules decide
const deps = (o: Partial<TradeResolveDeps> = {}): TradeResolveDeps => ({ normTrades, services: [], embed: async () => null, budget: { left: 0 }, tradeLabels: LABELS, ...o });
const codes = (r: { trades: { code: string }[] }) => r.trades.map((t) => t.code).sort();

type Lic = { id: string; activities: string[] };
type Prof = { licence: string; expect_trades: string[]; acceptable_trades: string[] };
const LIC = EXPECTED.licences as Lic[];
const PROF = EXPECTED.profiles as Prof[];

Deno.test('L3: "Building Materials Trading" proposes building materials, the trade the licence prints', async () => {
  const L = LIC.find((l) => l.id === 'L3')!;
  const r = await tradesOfText(L.activities.join('\n'), deps(), { activities: true });
  assertEquals(codes(r), ['building_materials']);
  assertEquals(r.trades[0].snippet, 'Building Materials Trading', 'the evidence is the activity as printed');
});

Deno.test('every certification licence: each code-read trade is right or acceptable, and seven of eight name a right one', async () => {
  let named = 0;
  for (const L of LIC) {
    const got = codes(await tradesOfText(L.activities.join('\n'), deps(), { activities: true }));
    const P = PROF.find((p) => p.licence === L.id);
    if (P) {
      const outside = got.filter((c) => !P.expect_trades.includes(c) && !P.acceptable_trades.includes(c));
      assertEquals(outside, [], `${L.id} proposed a trade outside its right and acceptable lists`);
      if (got.some((c) => P.expect_trades.includes(c))) named++;
    } else if (got.length) named++;
  }
  // L5's activities ("Manufacture of Corrugated Cartons and Boxes") are no code and no whole part of a trade's name: meaning's work
  assert(named >= 7, `only ${named} of 8 licences named a trade by code`);
});

Deno.test('the form is set aside, the subject is offered whole and by its parts, and a bare form offers nothing', () => {
  assertEquals(activitySubjects('Building Materials Trading'), ['Building Materials']);
  assertEquals(activitySubjects('Iron and Steel Trading'), ['Iron and Steel', 'Iron', 'Steel']);
  assertEquals(activitySubjects('Manufacture of Corrugated Cartons and Boxes'), ['Corrugated Cartons and Boxes', 'Corrugated Cartons', 'Boxes']);
  assertEquals(activitySubjects('Electromechanical Equipment Installation and Maintenance'), ['Electromechanical Equipment Installation', 'Electromechanical Equipment']);
  assertEquals(activitySubjects('General Trading'), []);
  assertEquals(activitySubjects('Import and Export'), []);
});

Deno.test('a trade\'s own name decides only whole: a part of two words or more, never one word, never a shared part', () => {
  const heads = englishNameHeads(LABELS);
  assertEquals(heads.get('air conditioning'), 'hvac');
  assertEquals(heads.get('bus rental'), 'staff_transport');
  assertEquals(heads.get('plumbing and sanitary'), 'plumbing');
  assertEquals(heads.get('windows'), undefined, 'a one-word part is the code\'s job, never the name\'s');
  assertEquals(heads.get('trading'), undefined, 'a part that is only a form word names nothing');
});

Deno.test('a trade is never guessed: a subject that is no code and no whole name proposes nothing, and Facilities Management stays whole', async () => {
  for (const a of ['Sanitary Ware Trading', 'Tiles and Ceramics Trading', 'Building Cleaning Services', 'General Trading', 'Building and Road Contracting']) {
    assertEquals(codes(await tradesOfText(a, deps(), { activities: true })), [], a);
  }
  assertEquals(codes(await tradesOfText('Facilities Management', deps(), { activities: true })), ['facilities_management']);
});

Deno.test('only a licence\'s activities are read by subject: the same words in a profile line are not', async () => {
  assertEquals(codes(await tradesOfText('Building Materials Trading', deps())), []);
});

Deno.test('the document reader reads a licence\'s activities this way, and only a licence\'s', () => {
  const src = Deno.readTextFileSync(new URL('./supplier_doc_trades.ts', import.meta.url));
  assert(/doc\.kind === 'licence' \? await tradesOfText\(text, deps, \{ names, activities: true \}\)/.test(src), 'supplier_doc_trades.ts no longer reads a licence by its activities\' subjects');
});
