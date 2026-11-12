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
import { answerQuestion, checkAnswer, listQuestions, NEW_SITTING_MS, storeQuestions, toStore, twinsOf, type QuestionRow } from './supplier_service_questions.ts';
import { aboutHash, type SupplierServiceQuestionDraft } from './supplier_profile_reading.ts';
import { capabilityConfirm } from './supplier_capability.ts';
import { proposeFromRead, type DocEvidence } from './supplier_doc_trades.ts';
import { sourceDocsStoreRpc } from './source_docs_store_stub.ts';
import { fakeReader, fakeTaxonomy } from './supplier_profile_reading.test_reader.ts';

type Row = Record<string, unknown>;
/** A PostgREST-shaped in-memory database: eq / in filters, select, maybeSingle, insert, update, upsert on a unique key. */
function memDb(seed: Record<string, Row[]> = {}, opts: { noSame?: boolean; failUpdate?: boolean } = {}) {
  const t: Record<string, Row[]> = { supplier_service_question: [], supplier_capabilities: [], supplier_capability_confirmation: [], service_implication: [],
    taxonomy_trade: [{ code: 'swimming_pools', label: 'Swimming pools', active: true }, { code: 'landscaping', label: 'Landscaping', active: true }, { code: 'labour_supply', label: 'Labour supply', active: true }],
    taxonomy_role: [{ code: 'contractor', label: 'Contractor', active: true }], taxonomy_trade_service: [{ trade_code: 'swimming_pools', active: true }], leads: [], taxonomy_trade_proposal: [], agent_actions: [], ...seed };
  let nextId = 1;
  const from = (table: string) => {
    const f: [string, string, unknown][] = []; let op: 'select' | 'update' | 'insert' | 'upsert' = 'select'; let payload: Row | Row[] | null = null; let conflict: string[] = []; let ignore = false; let cols = '';
    const match = (r: Row) => f.every(([k, kind, v]) => kind === 'eq' ? r[k] === v : (v as unknown[]).includes(r[k]));
    const run = () => {
      const rows = t[table] ??= [];
      if (table === 'service_implication' && opts.noSame && f.some(([k]) => k === 'same')) return { data: null, error: { message: 'column service_implication.same does not exist' } };
      if (op === 'select') {
        if (cols.includes('services_partner') && t.__noPartnerColumn) return { data: null, error: { message: 'column supplier_capabilities.services_partner does not exist' } };
        return { data: rows.filter(match), error: null };
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
      select: (c?: string) => { cols = c ?? ''; return b; }, order: () => b, limit: () => b,
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
  // a trade evidenced with no service under it: code asks its services (report 3.3)
  const deps = { readProfile: fakeReader(() => ({ trades: [{ code: 'labour_supply', quote }] }), { taxonomy: tax }) };
  const doc = (): DocEvidence => ({ path: 'profiles/7/p.pdf', name: 'ZZ DEMO profile.pdf', kind: 'profile', status: 'read', read_at: '2026-11-12T09:00:00Z', text: quote, trades: [] } as DocEvidence);
  assert((await proposeFromRead(a, 7, [doc()], deps, ['ZZ DEMO Staffing', null])).ok);
  const first = t.supplier_service_question.map((r) => `${r.kind}:${r.status}`);
  assertEquals(first, ['trade_services:open']);
  assertEquals((t.supplier_service_question[0].about as Row).quote, quote, 'the card quotes his sentence');
  assert((await proposeFromRead(a, 7, [doc()], deps, ['ZZ DEMO Staffing', null])).ok);
  assertEquals(t.supplier_service_question.length, 1, 'the same documents read again: no second question');
  await answerQuestion(a, 7, { id: t.supplier_service_question[0].id, answer: { none: true } });
  assert((await proposeFromRead(a, 7, [doc()], deps, ['ZZ DEMO Staffing', null])).ok);
  assertEquals(t.supplier_service_question.map((r) => `${r.kind}:${r.status}`), ['trade_services:answered'], 'answered: never asked again');
  assertEquals(t.supplier_capabilities[0].services, [], 'a reading writes no service');
});
