// TWO READS OF ONE SUPPLIER NEVER OVERWRITE EACH OTHER (12 Nov 2026, customer_support; final audit R1 = regcert_diagnosis F1,
// BLOCKER; founder "Proceed with fixes", ledger 1642).
//
// Paid registration certification run 2 (tag 2777f7ae), J1 desktop, lead 157558, edge_logs by trace id:
//   22:53:07.260  licence request   markReading(licence)                      licence 'reading'
//   22:53:17.975  profile job       proposeFromRead reads source_docs          its copy: licence still 'reading'
//   22:53:21.408  licence job       proposeFromRead writes                     licence 'read', 3 activities
//   22:54:03.301  profile job       proposeFromRead writes ITS COPY            licence 'reading' again, licence_check.activities []
// and the gate held the supplier pending / documents_being_read until the sweep. This replays that order, the reverse order,
// and a profile with a catalogue both ways, against the real markReading / readTexts / proposeFromRead with the real fixtures,
// an in-memory supplier_capabilities row written through the same compare-and-set fn_supplier_source_docs_store does
// (source_docs_store_stub.ts), and a reader model the test releases by hand. On main 2cc9d1017 (whole-value upserts) the
// four replays FAIL; the reproduction is the audit's repro/source_docs_lost_update.test.ts, extended.
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/_shared/two_reads_of_one_supplier_never_overwrite_each_other.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { markReading, proposeFromRead, readTexts, sourceDocsFingerprint, type DocEvidence } from './supplier_doc_trades.ts';
import { sourceDocsStoreRpc } from './source_docs_store_stub.ts';

// supplier_docs_later's imports build a client at load (stubbed: nothing here reaches it)
if (!Deno.env.get('SUPABASE_URL')) { Deno.env.set('SUPABASE_URL', 'http://stub.invalid'); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key'); }
const { readStoredDocsLater } = await import('./supplier_docs_later.ts');
const FIX = new URL('../../../scripts/e2e/fixtures/registration/', import.meta.url);
const S = 157558;
const known = ['ZZ DEMO Saker Electromechanical Contracting LLC', null];

type Row = { supplier_id: number; source_docs?: Record<string, unknown>; proposed_trades?: string[] };
/** An in-memory row. `hold` pauses a store whose documents match it until the test lets it go (to interleave two writers). */
function fakeAdmin(files: Record<string, Uint8Array>, opts: { failMarkOf?: string } = {}) {
  let row: Row | null = null;
  // the supplier's leads row: the files it names (license_doc_path, company_profile_doc_path) decide what a replaced file is
  const lead: Record<string, unknown> = { company_name: known[0], licence_legal_name: null, license_doc_path: null, company_profile_doc_path: null };
  const log: string[] = [];
  const holds: { when: (docs: DocEvidence[]) => boolean; reached: () => void; go: Promise<void> }[] = [];
  const store = sourceDocsStoreRpc(() => row, (n) => { row = { ...(row ?? { supplier_id: S }), ...(n as Row) }; });
  const admin = {
    row: () => row, log, lead,
    /** The next store whose documents satisfy `when` waits for the returned go(); `reached` resolves when it is waiting. */
    hold(when: (docs: DocEvidence[]) => boolean) {
      let go!: () => void, reached!: () => void;
      const h = { when, reached: () => reached(), go: new Promise<void>((r) => { go = r; }) };
      holds.push(h);
      return { reached: new Promise<void>((r) => { reached = r; }), go: () => go() };
    },
    rpc: async (fn: string, a: Record<string, unknown>) => {
      const docs = ((a.p_source_docs as { docs?: DocEvidence[] })?.docs ?? []);
      const i = holds.findIndex((h) => h.when(docs));
      if (i >= 0) { const [h] = holds.splice(i, 1); h.reached(); await h.go; }
      if (opts.failMarkOf && docs.some((d) => d.path === opts.failMarkOf && d.status === 'reading')) { log.push('mark failed'); return { data: null, error: { message: 'upstream connect error' } }; }
      const r = await store(fn, a);
      log.push(`${r.data ? 'write' : 'refused'} ${docs.map((d) => `${d.kind}:${d.status}`).join(',')}`);
      return r;
    },
    from: (table: string) => table === 'supplier_capabilities' ? {
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row ? structuredClone(row) : null, error: null }) }) }),
    } : {   // leads (knownNames), agent_actions (licenceScopeCheck, docTradesHeld): nothing asserted here
      select: () => ({ eq: function eq() { return { eq, limit: async () => ({ data: [] }), maybeSingle: async () => ({ data: table === 'leads' ? { ...lead } : null }) }; } }),
      insert: async () => ({ error: null }), update: () => ({ eq: async () => ({ error: null }) }),
    },
    storage: { from: () => ({
      // production refused the text sidecar until R4 ("mime type text/plain is not supported"): mirrored, so the read-again path is the harder one
      upload: async (p: string) => p.endsWith('.read.txt') ? { error: { message: 'mime type text/plain is not supported' } } : { error: null },
      download: async (p: string) => ({ data: files[p] ? new Blob([files[p] as BlobPart]) : null }),
    }) },
  };
  return admin;
}
// A reader model the test releases by hand; it proposes one trade and one service quoted from the first non-licence document.
function heldModel() {
  let called!: () => void, release!: () => void;
  const wasCalled = new Promise<void>((r) => { called = r; }), released = new Promise<void>((r) => { release = r; });
  const seen: string[] = [];
  const chooseTrades = async (text: string) => {
    seen.push(text); called(); await released;
    const body = text.split(/^=== (?:profile|catalogue): .* ===$/m)[1] ?? '';
    const quote = (body.split('\n').map((l) => l.trim()).find((l) => l.length > 25 && !l.startsWith('===')) ?? '').slice(0, 120);
    return { ok: true as const, rejected: [], trades: [{ code: 'mep_general', quote, reason: 'stated', quotes: [quote], services: [{ key: 'mep_general.mep_install', quote, licence: 'covered' as const, label: 'Full MEP installation' }] }] };
  };
  return { deps: { chooseTrades }, wasCalled, release, seen };
}
type Doc = { kind: string; status: string; path: string; activities?: string[]; trades?: unknown[] };
const docsOf = (a: ReturnType<typeof fakeAdmin>) => (a.row()?.source_docs?.docs ?? []) as Doc[];
const licenceCheck = (a: ReturnType<typeof fakeAdmin>) => a.row()!.source_docs!.licence_check as { activities: string[] };
const files = async (...ds: { path: string; file: string }[]) => Object.fromEntries(await Promise.all(ds.map(async (d) => [d.path, await Deno.readFile(new URL(d.file, FIX))])));
const pdf = (d: { path: string; name: string; kind: 'licence' | 'profile' | 'catalogue' }, bytes: Record<string, Uint8Array>) => ({ ...d, bytes: bytes[d.path], mime: 'application/pdf' });

const lic = { path: `licenses/${S}/1794437576833_L1_dubai_det_bilingual.pdf`, name: 'L1_dubai_det_bilingual.pdf', kind: 'licence' as const };
const prof = { path: `profiles/${S}/1794437594079_P1_mep_contractor.pdf`, name: 'P1_mep_contractor.pdf', kind: 'profile' as const };
const cat = { path: `catalogs/${S}/2_P4_hvac.pdf`, name: 'P4_hvac.pdf', kind: 'catalogue' as const };

Deno.test('run 2 J1 replayed: a licence read that lands while the profile is with the model stays read, with its activities', async () => {
  const bytes = await files({ path: lic.path, file: 'L1_dubai_det_bilingual.pdf' }, { path: prof.path, file: 'P1_mep_contractor.pdf' });
  const admin = fakeAdmin(bytes);
  const model = heldModel();
  await markReading(admin, S, [lic]);                                        // 22:53:07.260 licence request answers; its model read is still running
  await markReading(admin, S, [prof]);                                       // 22:53:17.044 profile request
  await markReading(admin, S, [prof]);                                       // 22:53:17.926 profile job
  const profileJob = proposeFromRead(admin, S, await readTexts(admin, [pdf(prof, bytes)], known), model.deps, known);   // 22:53:17.975 its copy
  await model.wasCalled;
  assert(!/=== licence:/.test(model.seen[0]), 'the profile job read the documents while the licence was still marked reading');
  await markReading(admin, S, [lic]);                                        // 22:53:21.326 licence job, after its own model read landed
  assert((await proposeFromRead(admin, S, await readTexts(admin, [pdf(lic, bytes)], known), model.deps, known)).ok);   // 22:53:21.408
  assertEquals(docsOf(admin).find((d) => d.kind === 'licence')!.activities?.length, 3, 'the licence job recorded the licence read, with its three activities');
  model.release();                                                           // 22:54:03.301 the profile job writes
  assert((await profileJob).ok);
  console.log('writes, in order:\n  ' + admin.log.join('\n  '));
  const docs = docsOf(admin);
  assertEquals(docs.filter((d) => d.status === 'reading').map((d) => d.kind), [], 'no document is left "reading" once both reads finished (else: pending, documents_being_read)');
  assertEquals(docs.find((d) => d.kind === 'licence')!.status, 'read', 'the licence the licence job read is still read after the profile job writes');
  assertEquals(docs.find((d) => d.kind === 'profile')!.status, 'read');
  assertEquals(licenceCheck(admin).activities.length, 3, 'the Services tab still holds the licence activities');
  assert(/=== licence:/.test(model.seen.at(-1)!), 'the profile was read together again, now with the licence that was read meanwhile');
});

Deno.test('the reverse order: the profile read lands first and the licence read, which took its copy before that, writes second', async () => {
  const bytes = await files({ path: lic.path, file: 'L1_dubai_det_bilingual.pdf' }, { path: prof.path, file: 'P1_mep_contractor.pdf' });
  const admin = fakeAdmin(bytes);
  const model = heldModel();
  await markReading(admin, S, [lic]);
  await markReading(admin, S, [prof]);
  const profileJob = proposeFromRead(admin, S, await readTexts(admin, [pdf(prof, bytes)], known), model.deps, known);
  await model.wasCalled;
  await markReading(admin, S, [lic]);
  // the licence job takes its copy (profile 'reading') and is held at its write until the profile has written
  const held = admin.hold((docs) => docs.some((d) => d.kind === 'licence' && d.status === 'read'));
  const licenceJob = proposeFromRead(admin, S, await readTexts(admin, [pdf(lic, bytes)], known), model.deps, known);
  await held.reached;
  model.release();
  assert((await profileJob).ok);
  assertEquals(docsOf(admin).find((d) => d.kind === 'profile')!.status, 'read', 'the profile read landed first');
  held.go();
  assert((await licenceJob).ok);
  console.log('writes, in order:\n  ' + admin.log.join('\n  '));
  const docs = docsOf(admin), profile = docs.find((d) => d.kind === 'profile')!;
  assertEquals(docs.filter((d) => d.status === 'reading').map((d) => d.kind), [], 'no document is left "reading"');
  assertEquals(profile.status, 'read', 'the profile the profile job read is still read after the licence job writes');
  assert((profile.trades ?? []).length > 0, 'with the trades read from it');
  assertEquals(licenceCheck(admin).activities.length, 3, 'and the licence check holds the activities');
  assertEquals(admin.row()!.proposed_trades, ['mep_general']);
});

for (const order of ['profile first', 'catalogue first'] as const) {
  Deno.test(`no licence: a catalogue attached while the profile is with the model, ${order} to land, keeps both read with their trades`, async () => {
    const bytes = await files({ path: prof.path, file: 'P1_mep_contractor.pdf' }, { path: cat.path, file: 'P4_hvac.pdf' });
    const admin = fakeAdmin(bytes);
    const mP = heldModel(), mC = heldModel();
    await markReading(admin, S, [prof]);
    const profileJob = proposeFromRead(admin, S, await readTexts(admin, [pdf(prof, bytes)], known), mP.deps, known);
    await mP.wasCalled;
    await markReading(admin, S, [cat]);                                      // the supplier attaches a catalogue meanwhile
    const catalogueJob = proposeFromRead(admin, S, await readTexts(admin, [pdf(cat, bytes)], known), mC.deps, known);
    await mC.wasCalled;
    const [first, second, firstJob, secondJob] = order === 'profile first' ? [mP, mC, profileJob, catalogueJob] : [mC, mP, catalogueJob, profileJob];
    first.release(); assert((await firstJob).ok);
    second.release(); assert((await secondJob).ok);
    console.log('writes, in order:\n  ' + admin.log.join('\n  '));
    const docs = docsOf(admin);
    assertEquals(docs.map((d) => `${d.kind}:${d.status}`).sort(), ['catalogue:read', 'profile:read'], 'both documents are read');
    assert((docs.find((d) => d.kind === 'profile')!.trades ?? []).length > 0, 'and the trades read from the profile are still proposed');
  });
}

Deno.test('a licence replaced while it was read is not marked or written again over the newer licence (final audit R3, the real order)', async () => {
  // Production's order (review of the fix, replay r3_remark): A's model read is slow; B is uploaded, recorded and read; then A's job
  // runs readStoredDocsLater, which marks A again before it reads. On the first fix that re-mark replaced B and A's read was stored.
  const A = { path: `licenses/${S}/1_A.pdf`, name: 'A.pdf', kind: 'licence' as const };
  const B = { path: `licenses/${S}/2_B.pdf`, name: 'B.pdf', kind: 'licence' as const };
  const bytes = await files({ path: A.path, file: 'L1_dubai_det_bilingual.pdf' }, { path: B.path, file: 'L1_dubai_det_bilingual.pdf' });
  const admin = fakeAdmin(bytes);
  const deps = { chooseTrades: async () => ({ ok: true as const, rejected: [], trades: [] }) };
  admin.lead.license_doc_path = A.path; await markReading(admin, S, [A]);           // process_docs A: row names A, A marked
  admin.lead.license_doc_path = B.path; await markReading(admin, S, [B]);           // process_docs B: row names B, B marked
  await readStoredDocsLater(admin as never, S, [{ ...pdf(B, bytes), gate: false }], { deps });   // B's job
  await readStoredDocsLater(admin as never, S, [{ ...pdf(A, bytes), gate: false }], { deps });   // A's job, after its late model read
  console.log('writes, in order:\n  ' + admin.log.join('\n  '));
  assertEquals(docsOf(admin).map((d) => `${d.path}:${d.status}`), [`${B.path}:read`], 'the row still holds licence B, the file leads names');
  // and a read of A that reaches proposeFromRead by another road is dropped the same way
  const late = await proposeFromRead(admin, S, await readTexts(admin, [pdf(A, bytes)], known), deps, known);
  assert(late.ok); assertEquals(late.docs, [], "A's read wrote nothing");
  assertEquals(docsOf(admin).map((d) => d.path), [B.path]);
});

Deno.test('a new licence whose mark failed is still read and recorded: "replaced" is decided by the row, not by the mark', async () => {
  const A = { path: `licenses/${S}/1_A.pdf`, name: 'A.pdf', kind: 'licence' as const };
  const B = { path: `licenses/${S}/2_B.pdf`, name: 'B.pdf', kind: 'licence' as const };
  const bytes = await files({ path: A.path, file: 'L1_dubai_det_bilingual.pdf' }, { path: B.path, file: 'L1_dubai_det_bilingual.pdf' });
  const admin = fakeAdmin(bytes, { failMarkOf: B.path });
  const deps = { chooseTrades: async () => ({ ok: true as const, rejected: [], trades: [] }) };
  admin.lead.license_doc_path = A.path; await markReading(admin, S, [A]);
  await proposeFromRead(admin, S, await readTexts(admin, [pdf(A, bytes)], known), deps, known);   // licence A on file, read
  admin.lead.license_doc_path = B.path;
  assert(await markReading(admin, S, [B]), 'the mark of B failed (logged only)');
  const r = await proposeFromRead(admin, S, await readTexts(admin, [pdf(B, bytes)], known), deps, known);
  assert(r.ok);
  assertEquals(docsOf(admin).map((d) => `${d.path}:${d.status}`), [`${B.path}:read`], 'the new licence, which leads names, is the one recorded');
});

Deno.test('the fingerprint is the one fn_supplier_source_docs_store computes (the literal its probe holds)', () => {
  const docs = [{ path: 'licenses/1/a.pdf', name: 'a.pdf', kind: 'licence', status: 'reading', read_at: '2026-11-11T22:53:07.260Z', trades: [] },
                { path: 'profiles/1/p.pdf', name: 'p.pdf', kind: 'profile', status: 'reading', read_at: '2026-11-11T22:53:17.044Z', trades: [] }];
  const probe = Deno.readTextFileSync(new URL('../../../scripts/sql/two_reads_of_one_suppliers_documents_never_overwrite_each_other_probe.sql', import.meta.url));
  const literal = /v_fp0 jsonb := '([^']+)'/.exec(probe)![1];
  assertEquals(sourceDocsFingerprint({ reader: 'supplier_doc_trades@4', docs }), JSON.parse(literal));
  assertEquals(sourceDocsFingerprint({}), { v: 0, docs: [] });
  assertEquals(sourceDocsFingerprint({ v: 4, docs: [{ path: 'x' }] }), { v: 4, docs: [['x', null, null]] });
});
