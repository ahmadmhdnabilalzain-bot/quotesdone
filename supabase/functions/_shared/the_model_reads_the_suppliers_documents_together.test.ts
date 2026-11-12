// THE MODEL READS THE SUPPLIER'S DOCUMENTS TOGETHER; CODE ONLY CHECKS (11 Nov 2026, customer_support; founder ruling 1627).
// "It's not word matching only ... when a human reads that, he will understand what services they will do ... So it has to be read."
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/the_model_reads_the_suppliers_documents_together.test.ts
//
// The paid registration certification of 11 Nov 2026 proposed services nobody does (Recording studio equipment for an MEP
// contractor, from "our own team and equipment"): code proposed them, by gte-small meaning with one head word
// (profile_services.servicesOfText) and by the licence's activities (trade_resolve.activitySubjects). Both are deleted.
// This file proves the design that replaced them, offline:
//   1. THE SIX PAID CASES: the six ZZ DEMO profiles of the certification, each with its licence, are read by code exactly as an
//      upload reads them, and the reader model's answers recorded live (two readings each, the fixture says when and at what
//      cost) are replayed through code's checks and readTogether. Since 12 Nov 2026 (ruling 1647) the reader is two steps
//      (supplier_profile_reading.ts): the recorded claims are given back through supplier_profile_reading.test_reader.fakeReader,
//      so they pass the real checkReading, the real mapping checks and proposalOf. Every reading names a right
//      trade and nothing absurd, against scripts/e2e/fixtures/registration/expected.json, the certification's own judge.
//   2. THE HARD CASE: the MEP contractor's profile under a licence that says only "General Trading". The trades and services come
//      from the profile; every service is judged not covered by that licence, so the sales engineer checks it (licence_scope_check).
//   3. CODE ONLY CHECKS: a key outside our catalogue, a service of another trade, a quote the documents do not hold, and a trade
//      or service quoted only from the licence are dropped, never repaired. The paid round's absurd service (studio equipment
//      under an MEP trade) cannot be proposed: a service is only ever one of its own trade's keys.
//   4. NO MODEL, NO GUESS: nothing is proposed, the documents say they are still being read, and the sign-up trade stands
//      (supplier_services.preparedTrades; registration defect 4).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { modelReadText, readDocForTrades, readTogether, servicesAndLicence, withReading, type DocEvidence, type TradeResolveDeps } from './supplier_doc_trades.ts';
import { fakeReader } from './supplier_profile_reading.test_reader.ts';
import type { Taxonomy } from './supplier_profile_reading.ts';
import FX from './the_model_reads_the_suppliers_documents_together.fixtures.json' with { type: 'json' };

const FIX = new URL('../../../scripts/e2e/fixtures/registration/', import.meta.url);
const EXP = JSON.parse(await Deno.readTextFile(new URL('expected.json', FIX)));
const TAX: Taxonomy = { trades: FX.defs.map((d) => ({ code: d.code, label: d.label, services: d.serviceKeys })), adjacent: [] };
type Reading = (typeof FX.readings)[number];
const MIME: Record<string, string> = { pdf: 'application/pdf', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' };

/** The two documents of a case, read by code as an upload reads them (text only; the model is asked by readTogether). */
async function docsOf(id: string): Promise<{ docs: DocEvidence[]; P: Record<string, any> }> {
  const P = EXP.profiles.find((p: { id: string }) => p.id === (id === 'GT' ? 'P1' : id));
  const L = EXP.licences.find((l: { id: string }) => l.id === P.licence);
  const activities = id === 'GT' ? FX.gt_licence_activities : L.activities;
  const names = [P.company, L.legal_name];
  const lic = await readDocForTrades({ path: `l/${L.file}`, name: L.file, kind: 'licence', photo_text: modelReadText('licence', activities), names }, {}, { textOnly: true });
  const prof = P.code_readable
    ? await readDocForTrades({ path: `p/${P.file}`, name: P.file, kind: 'profile', bytes: await Deno.readFile(new URL(P.file, FIX)), mime: MIME[P.file.split('.').pop()] ?? 'application/pdf', names }, {}, { textOnly: true })
    // the image-only brochure: the lines the vision reader transcribes off its pages
    : await readDocForTrades({ path: `p/${P.file}`, name: P.file, kind: 'profile', photo_text: FX.p5_printed_lines.join('\n'), names }, {}, { textOnly: true });
  return { docs: [lic, prof], P };
}
/** The recorded answer, given back as the model gave it, through the two steps and code's checks. `licence`: the model's judgement of
 *  the profile against the licence (reader @5 judges the whole profile; @4's per-service judgements were recorded alike for each). */
const replay = (r: { trades: Reading['trades'] }, seen: string[] = [], licence?: 'yes' | 'no'): TradeResolveDeps => ({
  readProfile: fakeReader(() => ({ trades: r.trades.map((t) => ({ code: t.code, quote: t.quotes[0], quotes: t.quotes, services: t.services.map((s) => ({ key: s.key, quote: s.quote, licence: s.licence })) })),
    licence: licence ?? (r.trades.flatMap((t) => t.services).every((s) => s.licence === 'not_covered') ? 'no' : r.trades.flatMap((t) => t.services).every((s) => s.licence === 'covered') ? 'yes' : 'partly') }),
  { seen, taxonomy: TAX }),
});
const judge = (P: Record<string, any>, trades: string[]) => ({
  right: trades.filter((t) => P.expect_trades.includes(t)),
  absurd: trades.filter((t) => !P.expect_trades.includes(t) && !P.acceptable_trades.includes(t)),
});

for (const R of FX.readings) {
  Deno.test(`${R.id} reading ${R.run}: the model's answer, checked by code, names a right trade and nothing absurd`, async () => {
    const { docs, P } = await docsOf(R.id);
    const seen: string[] = [];
    const r = await readTogether(docs, replay(R, seen), P.company);
    assert(r.ok, JSON.stringify(r));
    // both documents were given to the model, together, each under its own header, the profile before the licence
    assertEquals(seen.length, 1);
    assert(seen[0].indexOf('=== profile: ') === 0 && seen[0].includes('=== licence: '), seen[0].slice(0, 120));
    const trades = [...new Set(r.trades.map((t) => t.code))].sort();
    const { right, absurd } = judge(P, trades);
    assert(right.length > 0, `${R.id}: no expected trade (${trades})`);
    assertEquals(absurd, [], `${R.id}: absurd trades`);
    // every recorded line was found in the documents: code dropped nothing of what the model said
    assertEquals(r.rejected, [], JSON.stringify(r.rejected));
    // every service is one of its own trade's keys, quoted from the profile (never the licence)
    for (const s of r.services) {
      assert(s.key.startsWith(s.trade + '.') && trades.includes(s.trade), s.key);
      assertEquals(s.doc, P.file);
      assert(docs[1].text!.replace(/\s+/g, ' ').toLowerCase().includes(s.snippet.replace(/\s+/g, ' ').toLowerCase().slice(0, 30)), s.snippet);
    }
  });
}

Deno.test('the six paid cases: across the twelve readings the RIGHT set of each is the same in both readings', () => {
  for (const id of ['P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'GT']) {
    const sets = FX.readings.filter((r) => r.id === id).map((r) => {
      const P = EXP.profiles.find((p: { id: string }) => p.id === (id === 'GT' ? 'P1' : id));
      return judge(P, r.trades.map((t) => t.code)).right.sort().join('+');
    });
    assertEquals(sets.length, 2, id);
    assertEquals(sets[0], sets[1], `${id}: the right set changed between readings`);
  }
});

Deno.test('the hard case: a "General Trading" licence over an MEP profile: the services come from the profile and each is put to the sales engineer', async () => {
  const { docs, P } = await docsOf('GT');
  assertEquals(docs[0].activities, ['General Trading']);
  for (const R of FX.readings.filter((r) => r.id === 'GT')) {
    const r = await readTogether(docs, replay(R), P.company);
    assert(r.ok);
    assertEquals([...new Set(r.trades.map((t) => t.code))].sort(), ['electrical', 'hvac', 'mep_general', 'plumbing']);
    assert(r.services.length >= 8, `${r.services.length} services`);
    assert(r.services.every((s) => s.doc === P.file), 'a service was taken from the licence');
    assert(r.services.every((s) => s.licence === 'not_covered'), JSON.stringify(r.services.map((s) => [s.key, s.licence])));
    const { licence_check } = servicesAndLicence(r, docs);
    assertEquals([licence_check.read, licence_check.activities], [true, ['General Trading']]);
    assertEquals(licence_check.not_covered.length, r.services.length, 'every service the licence does not cover goes to licence_scope_check');
  }
  // and under its real licence the same profile's services are judged covered
  const { docs: real } = await docsOf('P1');
  const r1 = await readTogether(real, replay(FX.readings.find((r) => r.id === 'P1' && r.run === 2)!), P.company);
  assert(r1.ok && r1.services.every((s) => s.licence === 'supported'), JSON.stringify(r1));
});

Deno.test('code only checks: an invented key, another trade\'s service, an invented line and the paid round\'s absurd answers are dropped', async () => {
  const { docs, P } = await docsOf('P1');
  const R = FX.readings.find((r) => r.id === 'P1' && r.run === 1)!;
  const bad = { trades: [...R.trades.map((t) => t.code !== 'electrical' ? t : { ...t, services: [...t.services,
      { key: 'musical_pro_audio.studio_equipment', quote: 'Electrical installation: LV distribution boards, cabling, lighting and small power', licence: 'covered' },   // another trade's
      { key: 'electrical.solar_farms', quote: 'Electrical installation: LV distribution boards, cabling, lighting and small power', licence: 'covered' },             // not ours
      { key: 'electrical.cable_tray', quote: 'Cable trays and containment for data centres', licence: 'covered' },                                                       // not in the documents
    ] }),
    // the paid round's absurd answer (Recording studio equipment for an MEP contractor) as a trade: no line of the documents says it.
    // (A model that names a trade that is not ours from a REAL line has it read as none: a phrase kept in his words, never a trade,
    // supplier_profile_reading.checkReading. Code checks keys, trades and quotes only, ruling 1627.)
    { code: 'musical_pro_audio', quotes: ['Recording studio equipment supply'], reason: 'equipment', services: [{ key: 'musical_pro_audio.studio_equipment', quote: 'Recording studio equipment supply', licence: 'unclear' }] },
    { code: 'recording_studios', quotes: ['Electrical installation: LV distribution boards, cabling, lighting and small power'], reason: 'r', services: [] },
  ] };
  const r = await readTogether(docs, replay(bad as never), P.company);
  assert(r.ok);
  assertEquals([...new Set(r.trades.map((t) => t.code))].sort(), ['electrical', 'hvac', 'mep_general', 'plumbing']);
  for (const k of ['musical_pro_audio.studio_equipment', 'electrical.solar_farms', 'electrical.cable_tray']) assert(!r.services.some((s) => s.key === k), k);
  const dropped = r.rejected.map((x) => x.code).sort();
  // reader @5: a quote the documents do not hold, a key that is not ours, and a key of a trade the mapping was not shown are refused;
  // a trade code that is not ours is no trade (recording_studios: kept in his words, proposing nothing)
  for (const k of ['electrical.cable_tray', 'electrical.solar_farms', 'musical_pro_audio.studio_equipment']) assert(dropped.includes(k), `${k} not dropped: ${dropped}`);
  assert(!r.trades.some((t) => t.code === 'recording_studios' || t.code === 'musical_pro_audio'));
});

Deno.test('a trade or service quoted only from the licence is dropped: a licence says what the company may do, not what it does', async () => {
  const { docs, P } = await docsOf('P2');   // licence: Carpentry and Joinery Works; Wooden Doors and Windows Manufacturing; Wooden Furniture Fixing
  const r = await readTogether(docs, replay({ trades: [
    { code: 'joinery', quotes: ['Custom joinery: kitchen cabinets, wardrobes and vanity units'], reason: 'r', services: [
      { key: 'joinery.kitchens', quote: 'Custom joinery: kitchen cabinets, wardrobes and vanity units', licence: 'covered' },
      { key: 'joinery.custom_furniture', quote: 'Wooden Furniture Fixing', licence: 'covered' },              // the licence's line only
    ] },
    { code: 'doors', quotes: ['Wooden Doors and Windows Manufacturing'], reason: 'licence activity', services: [] },   // the licence's line only
  ] }), P.company);
  assert(r.ok);
  assertEquals(r.trades.map((t) => t.code), ['joinery']);
  assertEquals(r.services.map((s) => s.key), ['joinery.kitchens']);
  assertEquals(r.rejected.filter((x) => /licence/.test(x.why)).map((x) => x.code).sort(), ['doors', 'joinery.custom_furniture']);
});

Deno.test('no model: nothing is guessed, every document says it is still being read, and a licence alone is never sent to the model', async () => {
  const { docs, P } = await docsOf('P4');
  const seen: string[] = [];
  const down: TradeResolveDeps = { readProfile: fakeReader(() => ({ ok: false, error: 'model unavailable (503): no route' }), { seen }) };
  const r = await readTogether(docs, down, P.company);
  assert(!r.ok && r.why === 'unavailable');
  const laid = withReading(docs, r);
  assertEquals(laid.map((d) => [d.kind, d.trades.length, d.choice ?? null]), [['licence', 0, null], ['profile', 0, 'unavailable']]);
  assert(/^still being read: /.test(laid[1].reason ?? ''));
  assertEquals(servicesAndLicence(r, laid).proposed, []);
  // the licence on its own: the model is not asked at all
  const only = await readTogether([docs[0]], down, P.company);
  assert(!only.ok && only.why === 'no_documents');
  assertEquals(seen.length, 1);
});
