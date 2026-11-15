// A LICENCE ACTIVITY IS ONE ELEMENT (15 Nov 2026, customer_support; the paid certification of 15 Nov 2026, run 1 J3 and run 2 J9:
// L3 JAFZA read as ONE activity "Building Materials Trading, Tiles and Ceramics Trading, Sanitary Ware Trading", L9 Dubai DET as
// "Interior Decoration Works, Building Maintenance"). The fix is at the reading (both prompts ask one element per activity); code's
// part is the grounded backstop of licence_activities.ts. Read against the certification's own fixtures
// (scripts/e2e/fixtures/registration: the text layer code extracts from each licence PDF, and expected.json, the judge's bar).
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/a_licence_activity_is_one_element.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { activitiesAsPrinted } from './licence_activities.ts';
import { checkLicenceRead, SYS_LICENSE } from './licence_extract.ts';
import { checkReading, profileReadSystem, type ReadDoc } from './supplier_profile_reading.ts';
import { modelReadText } from './supplier_doc_trades.ts';
import { pdfText } from './document_expiry.ts';
import EXPECTED from '../../../scripts/e2e/fixtures/registration/expected.json' with { type: 'json' };

const FIX = new URL('../../../scripts/e2e/fixtures/registration/', import.meta.url);
type Lic = { id: string; file: string; activities: string[] };
const LICS: Lic[] = (EXPECTED as { licences: { file: string; activities: string[] }[] }).licences.map((l) => ({ id: l.file.split('_')[0], file: l.file, activities: l.activities }));
/** the text layer code reads off the fixture (null for the photo and the image-only scan) */
const textOf = async (l: Lic) => (l.file.endsWith('.pdf') ? await pdfText(await Deno.readFile(new URL(l.file, FIX))) : null);
const joined = (a: string[]) => a.join(', ');
const L = (id: string) => LICS.find((l) => l.id === id)!;

Deno.test('both readers are asked for one element per licensed activity, a comma inside one activity kept', () => {
  assert(SYS_LICENSE.includes('ONE array element per activity'));
  assert(SYS_LICENSE.includes('each is an element of its own (here three)'));
  assert(SYS_LICENSE.includes('stays one element'));
  const sys = profileReadSystem([{ code: 'building_materials', label: 'Building materials' }]);
  assert(sys.includes('one element per activity, so a list printed in one line or cell and separated by commas or semicolons is one element per activity'));
  assert(sys.includes('an activity whose own printed name holds a comma stays one element'));
});

Deno.test('L3 and L9 as printed: one cell holds the whole list, so code has no evidence and never splits (the reading carries it)', async () => {
  for (const id of ['L3', 'L9']) {
    const t = await textOf(L(id));
    assert(t && t.includes(id === 'L3' ? 'Building Materials Trading, Tiles and Ceramics Trading, Sanitary' : 'Interior Decoration Works, Building Maintenance'), id);
    // the certification's failing answers stay as the reader gave them: code does not guess at commas
    assertEquals(activitiesAsPrinted([joined(L(id).activities)], t), [joined(L(id).activities)], id);
    // the right answer passes untouched
    assertEquals(activitiesAsPrinted(L(id).activities, t), L(id).activities, id);
  }
});

Deno.test('L3 and L9 read from a picture: the vision list is one to a line, so a joined element is split back as printed', () => {
  for (const id of ['L3', 'L9']) {
    const text = modelReadText('licence', L(id).activities)!;   // what a scan's licence text is (supplier_doc_trades)
    assertEquals(activitiesAsPrinted([joined(L(id).activities)], text), L(id).activities, id);
  }
});

Deno.test('the corpus (L1-L10): the right answer is never changed; a joined answer is split only where a text prints each on its own', async () => {
  for (const l of LICS) {
    const t = await textOf(l);
    assertEquals(activitiesAsPrinted(l.activities, t), l.activities, `${l.id}: right answer, own text`);
    // every licence of the corpus prints its list in one cell: no split from its own text
    if (t) assertEquals(activitiesAsPrinted([joined(l.activities)], t), [joined(l.activities)], `${l.id}: one cell, no evidence`);
    // the same activities printed one to a line (a picture's vision list, a table): split back exactly
    assertEquals(activitiesAsPrinted([joined(l.activities)], modelReadText('licence', l.activities)), l.activities, `${l.id}: one to a line`);
    // through license_extract's check, with the licence's own text layer: the reader's answer is kept as given
    if (t) assertEquals(checkLicenceRead({ license_number: 'ZZ-1', issue_date: null, expiry_date: null, activities: l.activities }, t).doc.activities, l.activities, l.id);
  }
});

Deno.test('an activity whose own printed name holds a comma is never split, even inside a joined element', () => {
  const acTable = 'Licensed Activities\n1. Air-Conditioning, Ventilation & Air Filtration Systems Installation\n2. Plumbing and Sanitary Installation\n3. Building Cleaning Services';
  const ac = 'Air-Conditioning, Ventilation & Air Filtration Systems Installation';
  assertEquals(activitiesAsPrinted([ac], acTable), [ac]);
  assertEquals(activitiesAsPrinted([`${ac}, Plumbing and Sanitary Installation, Building Cleaning Services`], acTable),
    [ac, 'Plumbing and Sanitary Installation', 'Building Cleaning Services']);
  // printed in one cell: nothing to go on, kept whole
  assertEquals(activitiesAsPrinted([ac], `Activities: ${ac}`), [ac]);
  assertEquals(activitiesAsPrinted([ac], null), [ac]);
  // a table whose cells are spaced (a text layer read by rows): each cell is an activity of its own
  const rows = 'Activity Code    Activity Name\n4752006    Building Materials Trading\n4663011    Tiles and Ceramics Trading\n4663012    Sanitary Ware Trading';
  assertEquals(activitiesAsPrinted([joined(L('L3').activities)], rows), L('L3').activities);
  // one piece printed on its own is not enough: every piece must be
  assertEquals(activitiesAsPrinted(['Building Materials Trading, Tiles and Ceramics Trading'], 'Building Materials Trading\nTiles, Ceramics'), ['Building Materials Trading, Tiles and Ceramics Trading']);
});

Deno.test('the profile reading: a joined licence list is split where the licence text prints each, and left where it does not', async () => {
  const profile: ReadDoc = { path: 'p/P3', name: 'P3.docx', kind: 'profile', text: 'We supply building materials, tiles and sanitary ware to contractors.' };
  const answer = (acts: string[]) => JSON.stringify({ summary: 's', evidence: [], vague: [], also_ask: [], licence: { covers_profile: 'yes', note: '', activities: acts } });
  const codes = new Set(['building_materials']);
  // a scan of L3: its licence text is the vision model's list one to a line
  const scan: ReadDoc = { path: 'p/L3', name: 'L3.pdf', kind: 'licence', text: modelReadText('licence', L('L3').activities)! };
  const r1 = checkReading(answer([joined(L('L3').activities)]), [profile, scan], codes);
  assert(r1.ok); assertEquals(r1.reading.licence.activities, L('L3').activities);
  // L3 as printed (its text layer): no evidence in the document, the reading's answer stands as given
  const printed: ReadDoc = { path: 'p/L3', name: 'L3.pdf', kind: 'licence', text: (await textOf(L('L3')))! };
  const r2 = checkReading(answer([joined(L('L3').activities)]), [profile, printed], codes);
  assert(r2.ok); assertEquals(r2.reading.licence.activities, [joined(L('L3').activities)]);
  const r3 = checkReading(answer(L('L3').activities), [profile, printed], codes);
  assert(r3.ok); assertEquals(r3.reading.licence.activities, L('L3').activities);
});

// Review of 15 Nov 2026: a name wrapped right after its own comma, with another column on the same line, is not two rows.
Deno.test('a comma-holding activity wrapped after its comma beside another column is never split', () => {
  const joined = ['Air-Conditioning, Ventilation & Air Filtration Systems Installation'];
  const bilingual = 'Air-Conditioning,      تكييف الهواء\nVentilation & Air Filtration Systems Installation      والتهوية وتنقية الهواء';
  assertEquals(activitiesAsPrinted(joined, bilingual), joined);
  const tabbed = 'Activity\tCode\nAir-Conditioning,\t4329\nVentilation & Air Filtration Systems Installation\t01';
  assertEquals(activitiesAsPrinted(joined, tabbed), joined);
});

Deno.test('a split licence read keeps at most the 20 activities the licence doc holds', () => {
  const many = Array.from({ length: 30 }, (_, i) => `Activity number ${i + 1}`);
  const text = many.join('\n');
  const { doc } = checkLicenceRead({ license_number: '', issue_date: null, expiry_date: null, activities: [many.join(', ')] }, text);
  // deno-lint-ignore no-explicit-any
  const acts = (doc as any).activities as string[];
  assert(acts.length <= 20, `kept ${acts.length}`);
});
