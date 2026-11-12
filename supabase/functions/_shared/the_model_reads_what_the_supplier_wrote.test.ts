// THE MODEL READS WHAT THE SUPPLIER WROTE: HIS LICENCE, HIS TYPED SERVICES, WHETHER HE ONLY SUPPLIES (12 Nov 2026, it_engineer for
// sales_engineer; founder rulings 1663/1664/1666: "Trade license reading, company profile reading, there's no code first, 100%"; the
// LLM-first audit of 12 Nov 2026, findings A3, A4 and A5). Every model answer below is a STAND-IN written for this test (no paid call):
// what is proved is the plumbing around the model, through the REAL two steps (readInTwoSteps: checkReading's quote checks, the mapping's
// key checks) and proposalOf; what the model itself answers on a real input is the paid check's.
//   A5  the reading is given the licence itself, not code's cut of it; the activities on the card and in the licence check are the
//       ones a model read (the reading's own, the licence reader's, a scan's), never re-split at commas;
//   A3  the Services tab's own-words box is read by the model unless every part of it IS one of our service names; what the model
//       offers comes back OFF until he adds it, a partner service marked, his unmapped words kept;
//   A4  "supply only" is his own answer, else what the model read, else what the reading of his documents said; never a word list.
//   deno test --no-lock --node-modules-dir=none supabase/functions/_shared/the_model_reads_what_the_supplier_wrote.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { checkReading, mergeReadings, readInTwoSteps, type Ask, type ProfileReader, type Taxonomy } from './supplier_profile_reading.ts';
import { LICENCE_TEXT_MAX, modelReadText, preparedText, readDocForTrades, readTogether, servicesAndLicence, type TradeResolveDeps } from './supplier_doc_trades.ts';
import { exactLabelsOf, REWRITE_PART_CHARS, REWRITE_UNAVAILABLE_EN, servicesRewrite } from './supplier_services.ts';

// ── A5: THE LICENCE ──────────────────────────────────────────────────────────────────────────────────────────────────────
// A DED-style licence as a text layer reads: the activity on the label's own line holds a comma, and a second one sits in a table at the
// foot of the page under "Activity Code | Activity Name" (the layouts the audit names, document_expiry/licence_fields.ts 142-181).
const LICENCE = [
  'ZZ DEMO FALCON COOLING LLC', 'Licence No 000000', 'Legal Type Limited Liability Company',
  'Activities: Air-Conditioning, Ventilation & Air Filtration Systems Installation',
  'Issue Date 01/01/2026 Expiry Date 31/12/2026',
  'Activity Code | Activity Name', '4322004 | Plumbing & Sanitary Installation',
].join('\n');
const ACTS = ['Air-Conditioning, Ventilation & Air Filtration Systems Installation', 'Plumbing & Sanitary Installation'];

Deno.test('A5: the reading is given the licence itself, the activity with a comma and the one in a table at the foot of the page', () => {
  const t = preparedText('licence', LICENCE).text;
  assert(t.includes(ACTS[0]), 'the activity was cut at its comma: ' + JSON.stringify(t));
  assert(t.includes('4322004 | Plumbing & Sanitary Installation'), 'the table at the foot of the page was not given: ' + JSON.stringify(t));
});

// review of PR #1980: the licence goes with every part of step A; a mis-filed long document must not swell a part past its clock
Deno.test('A5: the licence given to the reading is capped at about 2,000 characters (the longest measured licence is 810)', () => {
  assert(LICENCE_TEXT_MAX <= 2_000, String(LICENCE_TEXT_MAX));
  assertEquals(preparedText('licence', LICENCE + '\n' + 'x'.repeat(5_000)).text.length, LICENCE_TEXT_MAX);
});

Deno.test('A5: a licence\'s activities as a model read them are stored whole, never split again at a comma', async () => {
  // a scan: the licence reader's list arrives as photo_text
  const scan = await readDocForTrades({ path: 'licenses/1/l.pdf', name: 'l.pdf', kind: 'licence', photo_text: modelReadText('licence', ACTS) }, {}, { textOnly: true });
  assertEquals(scan.activities, ACTS);
  // a text layer whose model read the caller holds (license_extract): the model's list, not the label parser's
  const text = await readDocForTrades({ path: 'licenses/1/l.txt', name: 'l.txt', kind: 'licence', photo_text: LICENCE, model_activities: ACTS }, {}, { textOnly: true });
  assertEquals(text.activities, ACTS);
});

// a profile of an HVAC contractor whose licence the reading judges as not covering it (stand-in answer)
const TAX: Taxonomy = { trades: [
  { code: 'hvac', label: 'HVAC', services: [{ key: 'hvac.duct_cleaning', label: 'Duct cleaning' }, { key: 'hvac.ac_installation', label: 'AC installation' }] },
  { code: 'gypsum', label: 'Gypsum', services: [{ key: 'gypsum.partitions', label: 'Gypsum partitions', aliases: ['gypsum partition'] }] },
  { code: 'painting', label: 'Painting & finishes', services: [{ key: 'painting.interior', label: 'Interior painting', aliases: ['painting'] }] },
  { code: 'swimming_pools', label: 'Swimming pools', services: [{ key: 'swimming_pools.construction', label: 'Swimming pool construction' }] },
  { code: 'cleaning', label: 'Cleaning', services: [{ key: 'cleaning.water_tank', label: 'Water tank cleaning' }] },
], adjacent: [] };
/** A stand-in model: step A answers `read`, step B maps phrase n to `maps[words]`. `seen` keeps every step-A text. */
const standIn = (read: Record<string, unknown>, maps: Record<string, string[]>, seen: string[] = []): Ask => (step, _sys, text) => {
  if (step === 'read') { seen.push(text); return Promise.resolve({ ok: true, content: JSON.stringify({ summary: '', vague: [], also_ask: [], brands: [], areas: [], roles: [], ...read }) }); }
  const map = [...text.matchAll(/^(\d+)\. (.+?) {2}\[/gm)].map((m) => ({ i: Number(m[1]), keys: maps[m[2]] ?? [] }));
  return Promise.resolve({ ok: true, content: JSON.stringify({ map }) });
};
const reader = (ask: Ask, saidSeen: (string | undefined)[] = []): ProfileReader => async (docs, company, o = {}) => {
  saidSeen.push(o.said);
  const r = await readInTwoSteps(docs, company, TAX, ask, o);
  return r.ok ? { ...r, taxonomy: TAX, implications: [] } : r;
};

Deno.test('A5: the activities in the licence check and on the "which is your business" card are the ones the reading read off the licence', async () => {
  const PROFILE = 'ZZ DEMO Falcon Cooling LLC\nOur services\nDuct cleaning for villas and offices';
  const lic = await readDocForTrades({ path: 'licenses/1/l.txt', name: 'l.txt', kind: 'licence', photo_text: LICENCE }, {}, { textOnly: true });
  const prof = await readDocForTrades({ path: 'profiles/1/p.txt', name: 'p.txt', kind: 'profile', photo_text: PROFILE }, {}, { textOnly: true });
  const seen: string[] = [];
  const ask = standIn({ evidence: [{ words: 'duct cleaning', quote: 'Duct cleaning for villas and offices', basis: 'stated', trade: 'hvac', licence: 'not_covered' }],
    licence: { covers_profile: 'no', note: 'the licence names installation, the profile cleaning', activities: ACTS } }, { 'duct cleaning': ['hvac.duct_cleaning'] }, seen);
  const deps: TradeResolveDeps = { readProfile: reader(ask) };
  const r = await readTogether([lic, prof], deps, 'ZZ DEMO Falcon Cooling LLC');
  assert(r.ok, JSON.stringify(r));
  assert(seen[0].includes('4322004 | Plumbing & Sanitary Installation') && seen[0].includes(ACTS[0]), 'the reading was not given the licence itself');
  assertEquals(servicesAndLicence(r, [lic, prof]).licence_check.activities, ACTS);
  const card = r.profile!.questions.find((q) => q.kind === 'licence');
  assert(card && card.prompt_en.includes(`Your trade licence lists ${ACTS.join('; ')}.`), card?.prompt_en);
});

// ── A4: SUPPLY ONLY IS THE READING'S ANSWER ──────────────────────────────────────────────────────────────────────────────
Deno.test('A4: the reading says whether the company only supplies; over parts, a part that shows work on site decides it', () => {
  const docs = [{ path: 'p', name: 'p', kind: 'profile' as const, text: 'we clean water tanks' }];
  const codes = new Set(TAX.trades.map((t) => t.code));
  const one = (so: unknown) => { const c = checkReading(JSON.stringify({ summary: '', evidence: [], supply_only: so, licence: {} }), docs, codes); assert(c.ok); return c.reading; };
  assertEquals([one(true).supply_only, one(false).supply_only, one(null).supply_only, one(undefined).supply_only], [true, false, null, null]);
  assertEquals(mergeReadings([one(true), one(false)]).supply_only, false);
  assertEquals(mergeReadings([one(null), one(true)]).supply_only, true);
  assertEquals(mergeReadings([one(null)]).supply_only, null);
});

// ── A3 AND A4 ON THE SERVICES TAB: an in-memory database (supplier_services_save.test.ts's shape) ───────────────────────────
function fakeDb(cap: Record<string, unknown> = {}) {
  const selected: string[] = [];
  const rows: Record<string, Record<string, unknown>[]> = {
    taxonomy_trade_service: TAX.trades.flatMap((t) => t.services.map((s, i) => ({ trade_code: t.code, code: s.key.split('.')[1], label_en: s.label, label_ar: 'خدمة ' + s.key, aliases: s.aliases ?? [], sort: i, embedding_gte: null, embedding_ml: null }))),
    service_implication: [{ from_code: 'gypsum.partitions', implies_trade: 'painting', implies_code: 'interior', reason_en: 'partitions are painted', reason_ar: 'تُدهن القواطع' }],
    supplier_capabilities: [{ supplier_id: 7, services_removed: [], ...cap }],
  };
  const q = (table: string) => {
    let lo = 0, hi = Infinity;
    const b: Record<string, unknown> = {};
    const chain = () => b;
    Object.assign(b, { select: (cols: string) => { selected.push(`${table}:${cols}`); return b; }, eq: chain, in: chain, order: chain, limit: chain, range: (a: number, z: number) => { lo = a; hi = z; return b; },
      maybeSingle: () => Promise.resolve({ data: (rows[table] ?? [])[0] ?? null, error: null }),
      then: (res: (v: unknown) => void) => res({ data: (rows[table] ?? []).slice(lo, hi + 1), error: null }) });
    return b;
  };
  return { from: q, rpc: () => Promise.resolve({ data: null, error: { message: 'no rpc in this test' } }), selected };
}
const WORDS = 'Supply & fix of gypsum partitions and some painting touch-ups';
const READ_WORDS = { evidence: [
  { words: 'gypsum partitions supply and fixing', quote: WORDS, basis: 'stated', trade: 'gypsum' },
  { words: 'painting touch-ups', quote: WORDS, basis: 'stated', trade: 'painting' }] };

Deno.test('A3: his own words are read by the model, and what it offers comes back off until he adds it', async () => {
  const seen: string[] = [];
  const ask = standIn({ ...READ_WORDS, supply_only: false }, { 'gypsum partitions supply and fixing': ['gypsum.partitions'], 'painting touch-ups': ['painting.interior'] }, seen);
  const [st, out] = await servicesRewrite(fakeDb(), 7, { text: WORDS }, { reader: reader(ask) });
  assertEquals(st, 200);
  assert(seen.length === 1 && seen[0].includes(WORDS), 'the model was not given his sentence');
  // nothing is his until he adds it: no service listed as stated, every key offered (meaning.proposals, which the tab shows unticked)
  assertEquals(out.service_keys, []);
  const proposals = (out.meaning as { proposals: { key: string; lines: string[]; delivery: string }[] }).proposals;
  assertEquals(proposals.map((p) => p.key).sort(), ['gypsum.partitions', 'painting.interior']);
  assert(proposals.every((p) => p.lines[0] === WORDS && p.delivery === 'own'));
  // what the offered keys imply is struck out too (asked, never assumed)
  assert((out.implied as { removed: boolean }[]).every((i) => i.removed));
});

// CORRECTED after the review of PR #1980 (defect 5): a typed "Plastic" was listed as recycling_scrap.plastic, code deciding what his word
// means. Our own unique names are now OFFERED (because 'exact_label'), never listed; still no model is asked for them.
Deno.test('A3: a text made only of our own unique service names is offered as those services, never listed, and no model is asked; an alias alone is the model\'s', async () => {
  const vocab = TAX.trades.flatMap((t) => t.services.map((s) => ({ trade_code: t.code, code: s.key.split('.')[1], label_en: s.label, label_ar: '', aliases: s.aliases ?? [] })));
  assertEquals(exactLabelsOf(' gypsum PARTITIONS ,Interior painting\n', vocab)?.map((s) => s.code), ['partitions', 'interior']);
  assertEquals(exactLabelsOf('painting', vocab), null, 'an alias is not the service\'s own name');
  assertEquals(exactLabelsOf(WORDS, vocab), null);
  let asked = 0;
  const [st, out] = await servicesRewrite(fakeDb(), 7, { text: 'Gypsum partitions, Interior painting' }, { reader: () => { asked++; return Promise.resolve({ ok: false, error: 'never asked' }); } });
  assertEquals([st, asked, out.service_keys], [200, 0, []]);
  assertEquals((out.meaning as { proposals: { key: string; because: string }[] }).proposals.map((p) => [p.key, p.because]),
    [['gypsum.partitions', 'exact_label'], ['painting.interior', 'exact_label']]);
});

// CORRECTED after the review of PR #1980 (defect 1, probe P4): an offered partner service was kept by the tab as his OWN with one tap. It
// is never offered now: his line stays his own words. And no answer keeps every part of his text (defect 7), never a 503.
Deno.test('A3: a service he says goes through a partner is never offered, its line stays his own words; no answer keeps all his words', async () => {
  const text = 'We do gypsum partitions. Swimming pools through our subcontractor ZZ DEMO Pools. Majlis decoration';
  const ask = standIn({ evidence: [
    { words: 'gypsum partitions', quote: 'We do gypsum partitions.', basis: 'stated', trade: 'gypsum' },
    { words: 'swimming pool construction', quote: 'Swimming pools through our subcontractor ZZ DEMO Pools.', basis: 'partner', partner_name: 'ZZ DEMO Pools', trade: 'swimming_pools' },
    { words: 'majlis decoration', quote: 'Majlis decoration', basis: 'stated', trade: 'gypsum' }] },
    { 'gypsum partitions': ['gypsum.partitions'], 'swimming pool construction': ['swimming_pools.construction'] });
  const [, out] = await servicesRewrite(fakeDb(), 7, { text }, { reader: reader(ask) });
  const proposals = (out.meaning as { proposals: { key: string; delivery: string }[] }).proposals;
  assertEquals(proposals.map((p) => [p.key, p.delivery]), [['gypsum.partitions', 'own']], 'a partner service was offered, and one tap makes it his own');
  assertEquals(out.service_keys, []);
  assertEquals(out.own_words, ['Majlis decoration', 'Swimming pools through our subcontractor ZZ DEMO Pools.']);
  const [st, fail] = await servicesRewrite(fakeDb(), 7, { text }, { reader: () => Promise.resolve({ ok: false, error: 'gateway 502' }) });
  assertEquals([st, (fail.meaning as { state: string }).state, fail.own_words], [200, 'unavailable', ['We do gypsum partitions', 'Swimming pools through our subcontractor ZZ DEMO Pools', 'Majlis decoration']]);
  assertEquals((fail.model as { message_en: string }).message_en, REWRITE_UNAVAILABLE_EN);
});

Deno.test('A4: on the Services tab supply only is his answer, else what the model read in his words, else what his documents said; never the words "General Trading"', async () => {
  const TANKS = 'Al Noor General Trading LLC – we clean water tanks';
  const read = (so: boolean | null) => standIn({ evidence: [{ words: 'water tank cleaning', quote: TANKS, basis: 'stated', trade: 'cleaning' }], supply_only: so }, { 'water tank cleaning': ['cleaning.water_tank'] });
  const so = async (o: { cap?: Record<string, unknown>; body?: Record<string, unknown>; model: boolean | null; said?: (string | undefined)[] }) =>
    (await servicesRewrite(fakeDb(o.cap), 7, { text: TANKS, ...o.body }, { reader: reader(read(o.model), o.said) }))[1].supply_only as { proposed: boolean; applied: boolean; by: string };
  // the audit's input: the word list said supply only ("trading" and no installation word); the model reads the work
  assertEquals(await so({ model: false }), { proposed: false, applied: false, by: 'his_words' });
  // his words say nothing either way: the reading of his documents decides
  assertEquals(await so({ model: null, cap: { profile_supply_only: true } }), { proposed: true, applied: true, by: 'his_documents' });
  assertEquals(await so({ model: null }), { proposed: false, applied: false, by: 'unsaid' });
  // his own answer wins over both, and the model is told it
  const said: (string | undefined)[] = [];
  assertEquals(await so({ model: false, body: { supply_only: true }, said }), { proposed: false, applied: true, by: 'his_answer' });
  assert(/only supplies goods/.test(said[0] ?? ''), JSON.stringify(said));
});

// ── THE REVIEW OF PR #1980: his typed line maps only his claims, waits a bounded time, and the toggle never reads again ─────────────
Deno.test('A3 (review 2): a typed line maps only his claims: step A is told to return no chips, and a failing chip mapping loses nothing', async () => {
  const seen: string[] = []; let maps = 0;
  // a stand-in model that, told nothing, also returns "also ask" chips; and whose every mapping call FAILS
  const ask: Ask = (step, _sys, text) => {
    if (step === 'map') { maps++; return Promise.resolve({ ok: false, error: 'gateway 502' }); }
    seen.push(text);
    return Promise.resolve({ ok: true, content: JSON.stringify({ summary: '', vague: [], brands: [], areas: [], roles: [],
      evidence: [{ words: 'Gypsum partitions', quote: 'We do gypsum partitions', basis: 'stated', trade: 'gypsum' }],
      also_ask: [{ because: 'gypsum', options: [{ label: 'False ceilings', trade: 'gypsum' }, { label: 'Bulkheads', trade: 'gypsum' }] }] }) });
  };
  const [st, out] = await servicesRewrite(fakeDb(), 7, { text: 'We do gypsum partitions' }, { reader: reader(ask) });
  assert(/Return "also_ask":\[\]/.test(seen[0]), 'step A was not told to return no chips');
  // his one claim IS a catalogue name, so code names it and step B is never asked: the wait is step A alone
  assertEquals([st, maps, (out.meaning as { proposals: { key: string }[] }).proposals.map((p) => p.key)], [200, 0, ['gypsum.partitions']]);
});

Deno.test('A3 (review 3): his text is read in small parts at once, within a deadline under the tab\'s 90 s, and never past it', async () => {
  // (a) the names only: the vector columns are not loaded for a reading the model does
  const db = fakeDb();
  let opts: Record<string, unknown> = {};
  await servicesRewrite(db, 7, { text: 'We do gypsum partitions' }, { reader: (_d, _c, o = {}) => { opts = o; return Promise.resolve({ ok: false, error: 'x' }); } });
  assert(!db.selected.some((x) => /embedding/.test(x)), db.selected.join(' | '));
  assertEquals([opts.claimsOnly, opts.partChars], [true, REWRITE_PART_CHARS]);
  // a 2,000-character text: four parts read at once, not one long read
  const reads: string[] = [];
  const long = Array.from({ length: 40 }, (_, i) => `Line ${i} we do gypsum partitions for villas.`).join('\n').slice(0, 2_000);
  await readInTwoSteps([{ path: 't', name: 't', kind: 'profile', text: long }], null, TAX, (step, _s, t) => { if (step === 'read') reads.push(t); return Promise.resolve({ ok: false, error: 'x' }); }, { claimsOnly: true, partChars: REWRITE_PART_CHARS });
  assert(reads.length >= 3, `${reads.length} read call(s) for ${long.length} characters`);
  // (c) no answer in time: his words kept, he is told, and the answer comes at the deadline, not after the tab gave up
  const t0 = Date.now();
  const [st, out] = await servicesRewrite(fakeDb(), 7, { text: 'Majlis decoration, Swimming pools' }, { deadlineMs: 50, reader: () => new Promise(() => {}) });
  assert(Date.now() - t0 < 2_000);
  assertEquals([st, (out.meaning as { state: string }).state, out.own_words], [200, 'unavailable', ['Majlis decoration', 'Swimming pools']]);
});

Deno.test('A3 (review 3b): the tab\'s "We only supply" / "We also install" changes the answer on screen and never reads his words again', async () => {
  const tab = await Deno.readTextFile(new URL('../../../src/components/portal/supplier/ServicesTab.tsx', import.meta.url));
  assert(!/rewrite\(\{ supplyOnly:/.test(tab), 'the toggle runs the whole read again');
  assert(/onClick=\{toggleSupplyOnly\}/.test(tab));
  assert(/next\.meaning\?\.state === 'unavailable' && next\.model\?\.message_en\) setRwMsg\(next\.model\.message_en\)/.test(tab), 'he is not told his words were kept');
});
