// THE QUESTIONS ARE A RECORD (12 Nov 2026, slice 4; ruling 1647). Seat: sales_engineer; built by it_engineer.
// Replayed against an in-memory table with the real storeQuestions / listQuestions / answerQuestion / capabilityConfirm, no network:
//   * a re-read of the same documents stores nothing twice, and never re-asks a question or a key he answered;
//   * a key that is only the `same` twin of one he has is not asked (read only when the column exists);
//   * another supplier's question is refused as not found; an expired one is refused; every answer is checked against its card;
//   * an answer writes nothing into his services, and after a confirm it changes nothing until he confirms again;
//   * "Something else" is stored at once, and mapped after the answer, coming back as a card, never as a tick;
//   * Confirm writes services_partner as a subset of services and records every answered question in the ledger.
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/_shared/supplier_service_questions.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { answerQuestion, catalogueOptions, checkAnswer, listQuestions, NEW_SITTING_MS, NOTHING_MAX, storeQuestions, toStore, twinsOf, type CatalogueRow, type QuestionRow } from './supplier_service_questions.ts';
import { servicesSaveRewrite } from './supplier_services.ts';
import { aboutHash, type SupplierServiceQuestionDraft } from './supplier_profile_reading.ts';
import { capabilityConfirm } from './supplier_capability.ts';
import { proposeFromRead, type DocEvidence } from './supplier_doc_trades.ts';
import { sourceDocsStoreRpc } from './source_docs_store_stub.ts';
import { fakeTaxonomy } from './supplier_profile_reading.test_reader.ts';
import { readInTwoSteps, type ProfileReader } from './supplier_profile_reading.ts';

type Row = Record<string, unknown>;
/** A PostgREST-shaped in-memory database: eq / in filters, select, maybeSingle, insert, update, upsert on a unique key. */
function memDb(seed: Record<string, Row[]> = {}, opts: { noSame?: boolean; failUpdate?: boolean } = {}) {
  const t: Record<string, Row[]> = { supplier_service_question: [], supplier_capabilities: [], supplier_capability_confirmation: [], service_implication: [],
    taxonomy_trade: [{ code: 'swimming_pools', label: 'Swimming pools', active: true }, { code: 'landscaping', label: 'Landscaping', active: true }, { code: 'labour_supply', label: 'Labour supply', active: true }],
    taxonomy_role: [{ code: 'contractor', label: 'Contractor', active: true }], taxonomy_trade_service: [{ trade_code: 'swimming_pools', active: true }], leads: [], taxonomy_trade_proposal: [], agent_actions: [], ...seed };
  let nextId = 1;
  const from = (table: string) => {
    const f: [string, string, unknown][] = []; let lo = 0, hi = Infinity; let op: 'select' | 'update' | 'insert' | 'upsert' = 'select'; let payload: Row | Row[] | null = null; let conflict: string[] = []; let ignore = false; let cols = '';
    const match = (r: Row) => f.every(([k, kind, v]) => kind === 'eq' ? r[k] === v : (v as unknown[]).includes(r[k]));
    const run = () => {
      const rows = t[table] ??= [];
      if (table === 'service_implication' && opts.noSame && f.some(([k]) => k === 'same')) return { data: null, error: { message: 'column service_implication.same does not exist' } };
      if (op === 'select') {
        if (cols.includes('services_partner') && t.__noPartnerColumn) return { data: null, error: { message: 'column supplier_capabilities.services_partner does not exist' } };
        return { data: rows.filter(match).slice(lo, hi + 1), error: null };
      }
      if (op === 'update') { if (opts.failUpdate && table === 'supplier_service_question') return { data: null, error: { message: 'refused' } }; const hit = rows.filter(match); hit.forEach((r) => Object.assign(r, payload)); return { data: hit, error: null }; }
      const list = (Array.isArray(payload) ? payload : [payload!]) as Row[];
      for (const r of list) {
        const dup = conflict.length ? rows.find((x) => conflict.every((c) => x[c] === r[c])) : undefined;
        if (dup) { if (!ignore) Object.assign(dup, r); continue; }
        rows.push({ id: nextId++, ...r });
      }
      return { data: list, error: null };
    };
    const b: Record<string, unknown> = {};
    Object.assign(b, {
      select: (c?: string) => { cols = c ?? ''; return b; }, order: () => b, limit: () => b, range: (a: number, z: number) => { lo = a; hi = z; return b; },
      eq: (k: string, v: unknown) => { f.push([k, 'eq', v]); return b; }, in: (k: string, v: unknown[]) => { f.push([k, 'in', v]); return b; },
      update: (r: Row) => { op = 'update'; payload = r; return b; }, insert: (r: Row | Row[]) => { op = 'insert'; payload = r; return b; },
      upsert: (r: Row | Row[], o: { onConflict?: string; ignoreDuplicates?: boolean } = {}) => { op = 'upsert'; payload = r; conflict = (o.onConflict ?? '').split(',').filter(Boolean); ignore = !!o.ignoreDuplicates; return b; },
      maybeSingle: async () => { const r = run(); return { data: Array.isArray(r.data) ? r.data[0] ?? null : r.data, error: r.error }; },
      single: async () => { const r = run(); return { data: Array.isArray(r.data) ? r.data[0] ?? null : r.data, error: r.error }; },
      then: (res: (v: unknown) => void, rej?: (e: unknown) => void) => { try { res(run()); } catch (e) { rej?.(e); } },
    });
    return b;
  };
  return { admin: { from, rpc: async () => ({ data: { ok: true, decision: 'unchanged' }, error: null }) }, t };
}

const draft = (kind: SupplierServiceQuestionDraft['kind'], about: SupplierServiceQuestionDraft['about'], options: { key: string | null; label_en: string }[], status: 'open' | 'later' = 'open'): SupplierServiceQuestionDraft =>
  ({ kind, about, about_hash: aboutHash(kind, about), prompt_en: `${kind}?`, options: options.map((o) => ({ ...o, own_words: !o.key })), multi: kind !== 'licence', status, source: 'supplier_doc_trades@5' });
const STAFF = draft('vague', { quote: 'We supply staff and similar services.', doc: 'p.pdf', trade: 'labour_supply' },
  [{ key: 'labour_supply.general', label_en: 'General labour' }, { key: 'labour_supply.skilled', label_en: 'Skilled labour' }, { key: null, label_en: 'Freelancers' }]);
const POOLS = draft('partner', { quote: 'through our specialist partner', doc: 'p.pdf', trade: 'swimming_pools', words: ['Pool construction', 'Pool maintenance'] },
  [{ key: 'swimming_pools.pool_construction', label_en: 'Pool construction' }, { key: 'swimming_pools.pool_maintenance', label_en: 'Pool maintenance' }]);
const UMB = draft('umbrella', { quote: null, doc: null, trade: 'landscaping' },
  [{ key: 'landscaping.pools', label_en: 'Swimming pools' }, { key: 'landscaping.hardscape', label_en: 'Hardscape' }]);

Deno.test('a re-read of the same documents stores nothing twice; an open question is not duplicated', async () => {
  const { admin, t } = memDb();
  assertEquals((await storeQuestions(admin, 7, [STAFF, POOLS])).stored, 2);
  const again = await storeQuestions(admin, 7, [STAFF, POOLS]);
  assertEquals([again.stored, again.expired], [0, 0]);
  assertEquals(t.supplier_service_question.length, 2);
  assertEquals((await listQuestions(admin, 7)).map((q) => q.kind), ['vague', 'partner'], 'in the order they are asked');
});

Deno.test('an answered question, and every key it decided, is never asked again, even worded differently by a new reading', async () => {
  const { admin, t } = memDb();
  await storeQuestions(admin, 7, [STAFF]);
  const [id] = t.supplier_service_question.map((r) => r.id as number);
  const [s] = await answerQuestion(admin, 7, { id, answer: { picked: [0] } });
  assertEquals(s, 200);
  const reworded = draft('vague', { quote: 'We supply manpower.', doc: 'p.pdf', trade: 'labour_supply' }, [{ key: 'labour_supply.general', label_en: 'General labour' }, { key: 'labour_supply.skilled', label_en: 'Skilled labour' }]);
  assertEquals((await storeQuestions(admin, 7, [STAFF, reworded])).stored, 0, 'both keys were decided (one chosen, one not)');
  const more = draft('vague', { quote: 'We supply manpower.', doc: 'p.pdf', trade: 'labour_supply' }, [{ key: 'labour_supply.general', label_en: 'General labour' }, { key: 'labour_supply.drivers_operators', label_en: 'Drivers' }]);
  await storeQuestions(admin, 7, [STAFF, more]);
  const added = t.supplier_service_question.find((r) => r.about_hash === more.about_hash)!;
  assertEquals((added.options as { key: string }[]).map((o) => o.key), ['labour_supply.drivers_operators'], 'only the key he never decided');
  assertEquals(t.supplier_service_question.find((r) => r.id === id)!.status, 'answered', 'his answer stands');
});

Deno.test('a question his new documents no longer raise is expired; an answered one is kept', async () => {
  const { admin, t } = memDb();
  await storeQuestions(admin, 7, [STAFF, POOLS]);
  const pools = t.supplier_service_question.find((r) => r.kind === 'partner')!;
  await answerQuestion(admin, 7, { id: pools.id, answer: { per: { 0: 'partner', 1: 'no' } } });
  const r = await storeQuestions(admin, 7, []);
  assertEquals(r.expired, 1);
  assertEquals(t.supplier_service_question.map((x) => x.status).sort(), ['answered', 'expired']);
  const [s, o] = await answerQuestion(admin, 7, { id: t.supplier_service_question.find((x) => x.status === 'expired')!.id, answer: { picked: [0] } });
  assertEquals([s, o.code], [409, 'question_expired']);
});

Deno.test('a key that is only the same twin of one he has is not asked; with no same column every key is asked', async () => {
  const twins = twinsOf([{ from: 'swimming_pools.pool_construction', to: 'landscaping.pools' }]);
  const kept = toStore([UMB], [], new Set(['swimming_pools.pool_construction']), twins);
  assertEquals(kept[0].options.map((o) => o.key), ['landscaping.hardscape']);
  const seed = { service_implication: [{ from_code: 'swimming_pools.pool_construction', implies_trade: 'landscaping', implies_code: 'pools', active: true, same: true }] };
  const withCol = memDb(seed);
  await storeQuestions(withCol.admin, 7, [UMB], ['swimming_pools.pool_construction']);
  assertEquals((withCol.t.supplier_service_question[0].options as { key: string }[]).map((o) => o.key), ['landscaping.hardscape']);
  const noCol = memDb(seed, { noSame: true });
  await storeQuestions(noCol.admin, 7, [UMB], ['swimming_pools.pool_construction']);
  assertEquals((noCol.t.supplier_service_question[0].options as { key: string }[]).map((o) => o.key), ['landscaping.pools', 'landscaping.hardscape'], 'the column is absent: no twins');
});

Deno.test('at most five cards are open at once across old and new; the rest wait and are offered on his next visit', async () => {
  const { admin, t } = memDb();
  const many = Array.from({ length: 7 }, (_, i) => draft('trade_services', { quote: `line ${i}`, doc: 'p.pdf', trade: `t${i}` }, [{ key: `t${i}.a`, label_en: 'A' }]));
  await storeQuestions(admin, 7, many);
  assertEquals(t.supplier_service_question.filter((r) => r.status === 'open').length, 5);
  for (const r of t.supplier_service_question.filter((x) => x.status === 'open')) await answerQuestion(admin, 7, { id: r.id, answer: { none: true } });
  assertEquals((await listQuestions(admin, 7)).filter((q) => q.status === 'open').length, 0, 'the same sitting: no more cards');
  const later = await listQuestions(admin, 7, Date.now() + NEW_SITTING_MS + 1000);
  assertEquals(later.filter((q) => q.status === 'open').length, 2, 'the next visit: the two kept as later');
});

Deno.test('another supplier\'s question is refused exactly as one that does not exist', async () => {
  const { admin, t } = memDb();
  await storeQuestions(admin, 8, [STAFF]);
  const id = t.supplier_service_question[0].id;
  const [s, o] = await answerQuestion(admin, 7, { id, answer: { picked: [0] } });
  assertEquals([s, o.code], [404, 'question_not_found']);
  assertEquals(t.supplier_service_question[0].status, 'open', 'nothing was written');
  assertEquals((await answerQuestion(admin, 7, { id: 999, answer: { picked: [0] } }))[1].code, 'question_not_found');
  assertEquals((await answerQuestion(admin, 7, { id: 'x' }))[1].code, 'question_bad_id');
});

Deno.test('every answer is checked against its card', () => {
  const q = { kind: 'vague', options: STAFF.options, multi: true } as Pick<QuestionRow, 'kind' | 'options' | 'multi'>;
  assertEquals(checkAnswer(q, { picked: [2, 0, 0] }), { ok: true, answer: { picked: [0, 2] } });
  assertEquals(checkAnswer(q, { picked: [3] }), { ok: false, code: 'answer_bad_pick' });
  assertEquals(checkAnswer(q, {}), { ok: false, code: 'answer_empty' });
  assertEquals(checkAnswer(q, { none: true, picked: [1] }), { ok: false, code: 'answer_conflict' });
  assertEquals(checkAnswer(q, { other: '  dispatch riders  ' }), { ok: true, answer: { other: 'dispatch riders' } });
  assertEquals(checkAnswer({ ...q, multi: false }, { picked: [0, 1] }), { ok: false, code: 'answer_one_only' });
  const p = { kind: 'partner', options: POOLS.options, multi: true } as Pick<QuestionRow, 'kind' | 'options' | 'multi'>;
  assertEquals(checkAnswer(p, { per: { 0: 'partner' } }), { ok: false, code: 'answer_incomplete' }, 'every service of a partner card is answered');
  assertEquals(checkAnswer(p, { per: { 0: 'partner', 1: 'own' } }), { ok: true, answer: { per: { 0: 'partner', 1: 'own' } } });
  assertEquals(checkAnswer(p, { per: { 0: 'maybe', 1: 'own' } }), { ok: false, code: 'answer_bad_pick' });
  assertEquals(checkAnswer({ kind: 'nothing', options: [], multi: false }, { none: true }), { ok: false, code: 'answer_empty' }, 'the nothing card needs his words');
  assertEquals(checkAnswer({ kind: 'shown', options: STAFF.options, multi: true }, { only_inside: true }), { ok: true, answer: { only_inside: true } });
});

Deno.test('an answer writes nothing into his services; after a confirm it is stored and changes nothing until he confirms again', async () => {
  const { admin, t } = memDb({ supplier_capabilities: [{ supplier_id: 7, trades: ['labour_supply'], roles: ['contractor'], services: ['labour_supply.general'], confirmed_at: '2026-11-12T08:00:00Z' }] });
  await storeQuestions(admin, 7, [POOLS]);
  const [s, o] = await answerQuestion(admin, 7, { id: t.supplier_service_question[0].id, answer: { per: { 0: 'own', 1: 'own' } } });
  assertEquals([s, o.confirmed], [200, true], 'the client is told he is confirmed: Update applies it');
  assertEquals(t.supplier_capabilities[0].services, ['labour_supply.general']);
  assertEquals(t.supplier_service_question[0].status, 'answered');
});

Deno.test('"Something else" is stored at once and mapped after the answer: a fitting key comes back as a card, never as a tick', async () => {
  const { admin, t } = memDb({ supplier_capabilities: [{ supplier_id: 7, services: [] }] });
  await storeQuestions(admin, 7, [STAFF]);
  const jobs: Promise<unknown>[] = [];
  let mapped = '';
  const [s, o] = await answerQuestion(admin, 7, { id: t.supplier_service_question[0].id, answer: { other: 'dispatch riders on contract' } },
    { waitUntil: (p) => jobs.push(p), mapWords: async (w) => { mapped = w; return [{ key: 'labour_supply.drivers_operators', label_en: 'Drivers & equipment operators' }]; } });
  assertEquals(s, 200);
  assertEquals((o.question as Row).answer, { other: 'dispatch riders on contract' }, 'his words are in the answer before any mapping');
  assertEquals(t.supplier_service_question.length, 1, 'the mapping has not run inside the answer');
  await Promise.all(jobs);
  assertEquals(mapped, 'dispatch riders on contract');
  const card = t.supplier_service_question.find((r) => r.kind === 'new_key')!;
  assertEquals([card.status, (card.options as { key: string }[])[0].key], ['open', 'labour_supply.drivers_operators']);
  assertEquals(t.supplier_capabilities[0].services, [], 'nothing was ticked for him');
});

Deno.test('a failed answer write says so; nothing is half-written', async () => {
  const { admin, t } = memDb({}, { failUpdate: true });
  await storeQuestions(admin, 7, [STAFF]);
  const [s, o] = await answerQuestion(admin, 7, { id: t.supplier_service_question[0].id, answer: { picked: [0] } });
  assertEquals([s, o.code], [500, 'answer_write_failed']);
  assertEquals(t.supplier_service_question[0].status, 'open');
});

Deno.test('Confirm writes services_partner as a subset of services and records the answered questions in the ledger', async () => {
  const { admin, t } = memDb({ supplier_capabilities: [{ supplier_id: 7, trades: [], services: [], services_partner: [] }] });
  await storeQuestions(admin, 7, [POOLS]);
  await answerQuestion(admin, 7, { id: t.supplier_service_question[0].id, answer: { per: { 0: 'partner', 1: 'no' } } });
  const [s, o] = await capabilityConfirm(admin, 7, { trades: ['swimming_pools'], roles: ['contractor'], services: ['swimming_pools.pool_construction'],
    services_partner: ['swimming_pools.pool_construction', 'swimming_pools.pool_maintenance'] });
  assertEquals(s, 200, JSON.stringify(o));
  // the upsert of the in-memory capabilities row has no conflict key, so the confirmed row is the last one written
  const row = t.supplier_capabilities.at(-1)!;
  assertEquals(row.services_partner, ['swimming_pools.pool_construction'], 'a partner key he did not confirm is dropped');
  const ledger = t.supplier_capability_confirmation.at(-1)!.confirmed as Row;
  assertEquals(ledger.services_partner, ['swimming_pools.pool_construction']);
  assertEquals((ledger.answers as Row[]).map((a) => a.answer), [{ per: { 0: 'partner', 1: 'no' } }]);
});

Deno.test('Confirm before the column exists writes as before (no services_partner), and keeps the stored partner keys when none are sent', async () => {
  const pre = memDb({ supplier_capabilities: [{ supplier_id: 7, trades: [], services: [] }], __noPartnerColumn: [] });
  const [s] = await capabilityConfirm(pre.admin, 7, { trades: ['swimming_pools'], roles: ['contractor'], services: ['swimming_pools.pool_construction'], services_partner: ['swimming_pools.pool_construction'] });
  assertEquals(s, 200);
  assert(!('services_partner' in pre.t.supplier_capabilities.at(-1)!), 'nothing is written to a column that does not exist');
  const kept = memDb({ supplier_capabilities: [{ supplier_id: 7, trades: ['swimming_pools'], services: ['swimming_pools.pool_construction', 'swimming_pools.pool_maintenance'], services_partner: ['swimming_pools.pool_construction', 'swimming_pools.pool_maintenance'] }] });
  await capabilityConfirm(kept.admin, 7, { trades: ['swimming_pools'], roles: ['contractor'], services: ['swimming_pools.pool_maintenance'] });
  assertEquals(kept.t.supplier_capabilities.at(-1)!.services_partner, ['swimming_pools.pool_maintenance'], 'the older route keeps what is stored, cut to what he confirms');
});

// THE WRITER: proposeFromRead stores the reading's questions when a reading lands, through the real two steps (fakeReader) and
// proposalOf. A second reading of the same documents adds nothing.

Deno.test('a reading that lands stores its questions once: a re-read neither duplicates an open question nor re-asks an answered one', async () => {
  const { admin, t } = memDb({ supplier_capabilities: [{ supplier_id: 7, services: [], source_docs: {} }] });
  const store = sourceDocsStoreRpc(() => t.supplier_capabilities[0], (n) => Object.assign(t.supplier_capabilities[0], n));
  const a = { ...admin, rpc: store, storage: { from: () => ({ download: async () => ({ data: null }), upload: async () => ({ error: null }) }) } };
  const quote = 'We supply staff and similar services to companies across the Emirates.';
  const tax = fakeTaxonomy(['labour_supply'], ['labour_supply.general', 'labour_supply.skilled']);
  // the recruitment company (H02): one vague statement and its question, through the real two steps and code's checks
  const readProfile: ProfileReader = async (docs, company) => {
    const r = await readInTwoSteps(docs, company, tax, (step) => Promise.resolve({ ok: true as const, content: step === 'read'
      ? JSON.stringify({ summary: 'A staffing company.', evidence: [], vague: [{ quote, why: 'no kind of staff', ask: 'What sort of staff do you supply?',
          options: [{ label: 'General labour', trade: 'labour_supply' }, { label: 'Skilled labour', trade: 'labour_supply' }] }], also_ask: [], licence: { covers_profile: 'no_licence', note: '' } })
      : JSON.stringify({ map: [{ i: 1, keys: ['labour_supply.general'] }, { i: 2, keys: ['labour_supply.skilled'] }] }) }));
    return r.ok ? { ...r, taxonomy: tax, implications: [] } : r;
  };
  const deps = { readProfile };
  const doc = (): DocEvidence => ({ path: 'profiles/7/p.pdf', name: 'ZZ DEMO profile.pdf', kind: 'profile', status: 'read', read_at: '2026-11-12T09:00:00Z', text: quote, trades: [] } as DocEvidence);
  assert((await proposeFromRead(a, 7, [doc()], deps, ['ZZ DEMO Staffing', null])).ok);
  const first = t.supplier_service_question.map((r) => `${r.kind}:${r.status}`);
  assertEquals(first, ['vague:open']);
  assertEquals((t.supplier_service_question[0].about as Row).quote, quote, 'the card quotes his sentence');
  assert((await proposeFromRead(a, 7, [doc()], deps, ['ZZ DEMO Staffing', null])).ok);
  assertEquals(t.supplier_service_question.length, 1, 'the same documents read again: no second question');
  await answerQuestion(a, 7, { id: t.supplier_service_question[0].id, answer: { none: true } });
  assert((await proposeFromRead(a, 7, [doc()], deps, ['ZZ DEMO Staffing', null])).ok);
  assertEquals(t.supplier_service_question.map((r) => `${r.kind}:${r.status}`), ['vague:answered'], 'answered: never asked again');
  assertEquals(t.supplier_capabilities[0].services, [], 'a reading writes no service');
});

Deno.test('a trade-wide shown card is stored only from two captions of that trade, never from a brand line (measured on H09 and H10)', () => {
  const pro = draft('shown', { quote: 'DHA fit-out approvals', doc: 'p.pdf', trade: 'pro_government_services', words: ['DHA fit-out approvals'] },
    [{ key: 'pro_government_services.employment_visas_work_permits', label_en: 'Employment visas' }]);
  const clean = draft('shown', { quote: 'Karcher', doc: 'p.pdf', trade: 'cleaning', words: ['Karcher cleaning equipment'] }, [{ key: 'cleaning.deep_cleaning', label_en: 'Deep cleaning' }]);
  const joinery = draft('shown', { quote: 'Kitchens', doc: 'p.pdf', trade: 'joinery' }, [{ key: 'joinery.kitchens', label_en: 'Kitchens' }]);
  const ev = [{ basis: 'shown', trade: 'pro_government_services', keys: [] }, { basis: 'brand', trade: 'cleaning', keys: [] }, { basis: 'shown', trade: 'joinery', keys: ['joinery.kitchens'] }];
  assertEquals(toStore([pro, clean, joinery], [], new Set(), new Map(), ev).map((q) => q.about.trade), ['joinery']);
  const twice = [...ev, { basis: 'shown', trade: 'pro_government_services', keys: [] }];
  assertEquals(toStore([pro], [], new Set(), new Map(), twice).length, 1, 'two captions of the trade: asked');
});

Deno.test('a trade card is not stored for a trade whose only evidence is his own words no key covers (H01: garden lighting)', () => {
  const elec = draft('trade_services', { quote: 'Garden lighting', doc: 'p.pdf', trade: 'electrical' }, [{ key: 'electrical.lighting', label_en: 'Lighting' }]);
  const build = draft('trade_services', { quote: 'all kinds of building materials', doc: 'p.pdf', trade: 'building_materials' }, [{ key: 'building_materials.tiles', label_en: 'Tiles' }]);
  // H01 states keyed services of its own (gypsum ceilings, painting ...): the electrical card for "Garden lighting" alone is noise there
  const ev = [{ basis: 'stated', trade: 'electrical', keys: [] }, { basis: 'stated', trade: 'gypsum', keys: ['gypsum.false_ceiling'] }];
  assertEquals(toStore([elec, build], [], new Set(), new Map(), ev).map((q) => q.about.trade), ['building_materials'], 'a trade with no evidence at all is still asked');
  // H02 states nothing with a key of its own: its trade card is the only way its trade is not left as free text (review of slice 4, finding 3)
  const rec = draft('trade_services', { quote: 'Recruitment services', doc: 'p.pdf', trade: 'recruitment_executive_search' }, [{ key: 'recruitment_executive_search.permanent_recruitment', label_en: 'Permanent recruitment' }]);
  assertEquals(toStore([rec], [], new Set(), new Map(), [{ basis: 'stated', trade: 'recruitment_executive_search', keys: [] }]).length, 1);
});

Deno.test('the partner question comes before a trade card, and the open cards are counted by that order', () => {
  const trades = Array.from({ length: 5 }, (_, i) => draft('trade_services', { quote: `t${i}`, doc: 'p.pdf', trade: `t${i}` }, [{ key: `t${i}.a`, label_en: 'A' }]));
  const out = toStore([...trades, POOLS], [], new Set());
  assertEquals(out[0].kind, 'partner');
  assertEquals(out.filter((q) => q.status === 'open').length, 5);
  assertEquals(out.find((q) => q.kind === 'partner')!.status, 'open', 'the partner card is never the one kept for later');
});

// THE FOUNDER'S EXAMPLE (ruling 1647; review of slice 4, finding 14): the recruitment company's staff card draws its chips from the catalogue.
// The 18 labour_supply services as live on 12 Nov 2026 (taxonomy_trade_service, active; first six aliases each), and the recorded card's
// eight suggestions (run c0afdde7): three keyed by its mapping, five in the model's words.
const LABOUR: CatalogueRow[] = [
  { key: "labour_supply.skilled", trade: 'labour_supply', label: "Skilled trades labour", aliases: ["skilled labour", "skilled labor", "skilled worker", "skilled manpower", "tradesmen", "\u0639\u0645\u0627\u0644\u0629 \u0641\u0646\u064a\u0629"] },
  { key: "labour_supply.general", trade: 'labour_supply', label: "General labour", aliases: ["general labour", "general labor", "helpers", "unskilled labour", "labourers", "\u0639\u0645\u0627\u0644\u0629 \u0639\u0627\u0645\u0629"] },
  { key: "labour_supply.hourly", trade: 'labour_supply', label: "Hourly labour hire", aliases: ["hourly labour", "hourly labor", "hourly workers", "hourly manpower", "labour on hourly", "\u0639\u0645\u0627\u0644\u0629 \u0628\u0627\u0644\u0633\u0627\u0639\u0629"] },
  { key: "labour_supply.project_manpower", trade: 'labour_supply', label: "Project manpower contracts", aliases: ["manpower supply", "manpower contract", "project manpower", "\u0639\u0642\u0648\u062f \u0639\u0645\u0627\u0644\u0629", "\u062a\u0648\u0631\u064a\u062f \u0642\u0648\u0649 \u0639\u0627\u0645\u0644\u0629", "\u0642\u0648\u0649 \u0639\u0627\u0645\u0644\u0629 \u0644\u0644\u0645\u0634\u0627\u0631\u064a\u0639"] },
  { key: "labour_supply.supervisors", trade: 'labour_supply', label: "Foremen & supervisors", aliases: ["foreman", "foremen", "site supervisor", "labour supervisor", "\u0641\u0648\u0631\u0645\u0646", "\u0645\u0631\u0627\u0642\u0628 \u0639\u0645\u0627\u0644"] },
  { key: "labour_supply.drivers_operators", trade: 'labour_supply', label: "Drivers & equipment operators", aliases: ["bus drivers supply", "driver supply", "drivers supply", "equipment operators", "forklift operators", "heavy duty drivers"] },
  { key: "labour_supply.cleaners_housekeeping", trade: 'labour_supply', label: "Cleaners & housekeeping staff", aliases: ["cleaners supply", "cleaning labour", "cleaning manpower", "cleaning staff", "housekeepers", "housekeeping staff"] },
  { key: "labour_supply.hospitality_staff", trade: 'labour_supply', label: "Hospitality staff (waiters, stewards, kitchen helpers)", aliases: ["banquet staff", "baristas", "catering staff", "f&b staff", "hospitality manpower", "kitchen helpers"] },
  { key: "labour_supply.engineers_technicians", trade: 'labour_supply', label: "Engineers & technicians on secondment", aliases: ["engineer supply", "engineers on contract", "engineers on secondment", "engineers supply", "mep technicians supply", "technical staff supply"] },
  { key: "labour_supply.professional_staff", trade: 'labour_supply', label: "Professional staff on contract (finance, IT, HR, sales)", aliases: ["accountants on contract", "contract professionals", "it contractors", "professional staffing", "specialist staff supply", "\u062a\u0648\u0631\u064a\u062f \u0643\u0641\u0627\u0621\u0627\u062a"] },
  { key: "labour_supply.warehouse_factory", trade: 'labour_supply', label: "Warehouse & factory workers", aliases: ["factory workers", "loading and unloading workers", "pickers and packers", "production workers", "warehouse staff", "warehouse workers"] },
  { key: "labour_supply.promoters_merchandisers", trade: 'labour_supply', label: "Promoters & merchandisers", aliases: ["brand ambassadors", "brand promoters", "in-store promoters", "merchandisers", "promoters", "sales promoters"] },
  { key: "labour_supply.freelancers", trade: 'labour_supply', label: "Freelancers & independent contractors", aliases: ["freelance professionals", "freelance staff", "freelancer supply", "freelancers", "independent contractors", "\u0639\u0645\u0644 \u062d\u0631"] },
  { key: "labour_supply.office_admin_staff", trade: 'labour_supply', label: "Office & admin staff", aliases: ["admin assistants supply", "clerical staff supply", "office administrators supply", "office assistants supply", "\u0645\u0633\u0627\u0639\u062f\u064a\u0646 \u0625\u062f\u0627\u0631\u064a\u064a\u0646", "\u0645\u0648\u0638\u0641\u064a \u0633\u0643\u0631\u062a\u0627\u0631\u064a\u0629"] },
  { key: "labour_supply.office_boys", trade: 'labour_supply', label: "Office boys, tea boys & messengers", aliases: ["messenger", "messengers", "office boy", "office boys", "pantry boy", "tea boy"] },
  { key: "labour_supply.delivery_riders", trade: 'labour_supply', label: "Delivery riders (motorbike)", aliases: ["bike riders", "delivery rider", "delivery riders", "motorbike riders", "rider supply", "\u0631\u0627\u064a\u062f\u0631"] },
  { key: "labour_supply.receptionists", trade: 'labour_supply', label: "Receptionists & front-desk staff", aliases: ["front desk staff supply", "front office staff", "reception staff supply", "receptionist supply", "\u062a\u0648\u0631\u064a\u062f \u0645\u0648\u0638\u0641\u064a \u0627\u0633\u062a\u0642\u0628\u0627\u0644", "\u0645\u0648\u0638\u0641\u0627\u062a \u0627\u0633\u062a\u0642\u0628\u0627\u0644 \u0628\u0639\u0642\u0648\u062f"] }
];
const H02_CARD = { about: { quote: 'We supply staff and similar services to companies across the Emirates.', doc: 'p.pdf', trade: 'labour_supply' },
  options: [{ key: 'labour_supply.general', label_en: 'General labour', own_words: false }, { key: 'labour_supply.skilled', label_en: 'Skilled trades labour', own_words: false },
    { key: null, label_en: 'Drivers', own_words: true }, { key: null, label_en: 'Cleaners', own_words: true }, { key: null, label_en: 'Security guards', own_words: true },
    { key: null, label_en: 'Hospitality staff', own_words: true }, { key: 'hr_outsourcing.office_staff_outsourcing', label_en: 'Office staff outsourcing', own_words: false },
    { key: null, label_en: 'Engineers and technicians', own_words: true }] };
const CAT = [...LABOUR, { key: 'hr_outsourcing.office_staff_outsourcing', trade: 'hr_outsourcing', label: 'Office staff outsourcing', aliases: [] }];

Deno.test('the founder\'s example: the staff card offers the catalogue\'s kinds of staff, every chip a key but one the catalogue lacks', () => {
  const twins = twinsOf([{ from: 'labour_supply.office_admin_staff', to: 'hr_outsourcing.office_staff_outsourcing' }]);
  const o = catalogueOptions(H02_CARD, CAT, twins, new Set());
  const keys = o.filter((x) => x.key).map((x) => x.key);
  // the model's suggestions first, each as the key that covers it, then the rest of the trade in catalogue order
  assertEquals(keys.slice(0, 7), ['labour_supply.general', 'labour_supply.skilled', 'labour_supply.drivers_operators', 'labour_supply.cleaners_housekeeping',
    'labour_supply.hospitality_staff', 'hr_outsourcing.office_staff_outsourcing', 'labour_supply.engineers_technicians']);
  for (const k of ['labour_supply.professional_staff', 'labour_supply.freelancers']) assert(keys.includes(k), `${k}: the founder named it`);
  assertEquals(o.filter((x) => !x.key).map((x) => x.label_en), ['Security guards'], 'kept in his words only what no labour_supply service covers');
  assert(!keys.includes('labour_supply.office_admin_staff'), 'not both twins of one piece of work');
  assertEquals(o.length, 18, '17 keys and one in his words');
  // through the storage path: a vague card is redrawn from the catalogue, minus what he already has
  const d = { ...draft('vague', H02_CARD.about, H02_CARD.options.map((x) => ({ key: x.key, label_en: x.label_en }))) };
  const st = toStore([d], [], new Set(['labour_supply.general']), twins, undefined, CAT)[0];
  assert(!st.options.some((x) => x.key === 'labour_supply.general') && st.options.some((x) => x.key === 'labour_supply.freelancers'));
});

Deno.test('a question that expired and is drafted again by a later reading is asked again, on the same row', async () => {
  const { admin, t } = memDb();
  await storeQuestions(admin, 7, [STAFF]);
  await storeQuestions(admin, 7, []);
  assertEquals(t.supplier_service_question.map((r) => r.status), ['expired']);
  const again = await storeQuestions(admin, 7, [STAFF]);
  assertEquals([again.stored, t.supplier_service_question.length, t.supplier_service_question[0].status], [1, 1, 'open']);
});

Deno.test('the "nothing" card keeps a line or two of his words (its box takes 500), other cards one line', () => {
  const long = 'We supply sand, cement blocks, aggregates and steel to contractors in Sharjah and Ajman, with our own trucks and a yard in Sajja. '.repeat(3);
  const n = checkAnswer({ kind: 'nothing', options: [], multi: false }, { other: long });
  assert(n.ok && n.answer.other!.length > 120 && n.answer.other!.length <= NOTHING_MAX);
  const v = checkAnswer({ kind: 'vague', options: STAFF.options, multi: true }, { other: long });
  assert(v.ok && v.answer.other!.length === 120);
});

// A SUPPLIER CONFIRMED BEFORE THIS BUILD keeps the implied services ruling 439 gave him: a new document read by @5 must not strip them on
// his next Update (review of slice 4, finding 10; lead 19398). A supplier confirming for the first time through the questions loses them.
function saveDb(confirmed: boolean) {
  const db = memDb({
    supplier_capabilities: [{ supplier_id: 7, trades: ['gypsum'], roles: ['contractor'], services: confirmed ? ['gypsum.false_ceiling'] : [], services_removed: [], confirmed_at: confirmed ? '2026-11-11T09:00:00Z' : null }],
    taxonomy_trade: [{ code: 'gypsum', label: 'Gypsum', active: true }, { code: 'painting', label: 'Painting', active: true }],
    taxonomy_trade_service: [{ trade_code: 'gypsum', code: 'false_ceiling', label_en: 'False ceilings', label_ar: 'x', active: true }, { trade_code: 'painting', code: 'interior', label_en: 'Interior painting', label_ar: 'x', active: true }],
    service_implication: [{ from_code: 'gypsum.false_ceiling', implies_trade: 'painting', implies_code: 'interior', reason_en: 'r', reason_ar: 'r', active: true }],
  });
  return db;
}
Deno.test('"asked" never strips a supplier confirmed before; it removes the untapped implications of a first confirm', async () => {
  for (const confirmed of [true, false]) {
    const { admin, t } = saveDb(confirmed);
    const [s, o] = await servicesSaveRewrite(admin, 7, { trades: ['gypsum'], roles: ['contractor'], services: ['gypsum.false_ceiling'], asked: true }, [], { waitUntil: null });
    assertEquals(s, 200, JSON.stringify(o));
    const removed = t.supplier_capabilities[0].services_removed as string[];
    assertEquals(removed.includes('painting.interior'), !confirmed, confirmed ? 'a confirmed supplier lost an implied service he was never asked about' : 'the first confirm kept an implication he did not tick');
  }
});

Deno.test('his own words for work through a partner ("Jacuzzi", no key) are confirmed with their partner basis', async () => {
  const { admin, t } = saveDb(false);
  const [s, o] = await servicesSaveRewrite(admin, 7, { trades: ['gypsum'], roles: ['contractor'], services: ['gypsum.false_ceiling'], own_words: ['Jacuzzi'], partner: ['Jacuzzi', 'Pool lighting'] }, [], { waitUntil: null });
  assertEquals(s, 200, JSON.stringify(o));
  assertEquals(t.supplier_capabilities[0].services_partner, ['Jacuzzi'], 'his partner words, and only words he confirmed');
  assert((t.supplier_capabilities[0].services as string[]).includes('Jacuzzi'));
});

Deno.test('a "companies like yours" card never asks again what an earlier card asks, nor its same twin (H01: pools on the partner card)', () => {
  const umb = draft('umbrella', { quote: null, doc: null, trade: 'landscaping' }, [{ key: 'landscaping.pools', label_en: 'Swimming pools' }, { key: 'landscaping.hardscape', label_en: 'Hardscape' }, { key: 'swimming_pools.pool_maintenance', label_en: 'Pool maintenance' }]);
  const out = toStore([POOLS, umb], [], new Set(), twinsOf([{ from: 'swimming_pools.pool_construction', to: 'landscaping.pools' }]));
  assertEquals(out.find((q) => q.kind === 'umbrella')!.options.map((o) => o.key), ['landscaping.hardscape']);
});
