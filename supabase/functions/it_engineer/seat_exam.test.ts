// The weekly seat exam the company runs itself (ledger 1084/1443): runExamBatch with stub deps, no model and no database.
// Before seat_exam.ts existed this file could not import, so every case here failed; each case names the founder's rule it holds.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { type AskRow, type ExamDeps, type ExamItem, isFreshWording, missingFacts, parseJudge, parseWording, runExamBatch } from './seat_exam.ts';

const ITEM: ExamItem = {
  item_id: 'accountant-exam-03', seat: 'accountant',
  q_en: "Is anything added to the reveal fee for paying by card, and who bears Stripe's fee?",
  expected_facts: ['nothing is added for paying by card', '2.9% plus AED 1'],
  used_wordings: ['When a customer pays the reveal fee by card, is there a surcharge, and who absorbs the Stripe charge?'],
  fix_id: null, fix_ref: null,
};

function deps(o: Partial<ExamDeps> & { queue?: ExamItem[] } = {}) {
  const queue = [...(o.queue ?? [ITEM])];
  const rows: AskRow[] = [];
  const lessons: number[] = [];
  let clock = 0;
  const d: ExamDeps = {
    next: async () => ({ items: queue.length ? [queue.shift()!] : [], stop: null }),
    reword: async () => ({ content: JSON.stringify({ wording: 'Does paying the reveal fee with a card cost the customer extra, and who carries the Stripe processing fee?' }), error: null }),
    answer: async () => ({ status: 'answered', answer: 'Nothing is added for paying by card; QuotesDone bears Stripe\'s 2.9% plus AED 1.', model: 'stub', reason: null }),
    judge: async () => ({ content: null, error: 'not called' }),
    record: async (r) => { rows.push(r); return { asked_id: rows.length, fix_id: r.pass ? null : 41, lesson_needed: !r.pass && r.status !== 'no_wording' }; },
    lesson: async (id) => { lessons.push(id); return { knowledge_id: 900 + id, error: null }; },
    now: () => (clock += 1000),
    ...o,
  };
  return { d, rows, lessons };
}

Deno.test('1084: a wording that repeats the question or an earlier wording is never asked', () => {
  assert(!isFreshWording(ITEM.q_en, ITEM));
  assert(!isFreshWording(ITEM.used_wordings[0].toUpperCase() + '  ', ITEM));
  assert(isFreshWording('Who pays the card processing fee on a reveal, and does the customer pay any card surcharge?', ITEM));
  assertEquals(parseWording(JSON.stringify({ wording: ITEM.q_en }), ITEM), null);
  assertEquals(parseWording('not json', ITEM), null);
});

Deno.test('1084: the real answer is graded by code first; a pass records and makes no fix', async () => {
  const { d, rows, lessons } = deps();
  const r = await runExamBatch(d, 7);
  assertEquals(r.asked, 1); assertEquals(r.passed, 1); assertEquals(r.stop, 'all_asked');
  assertEquals(rows[0].graded_by, 'code'); assertEquals(rows[0].pass, true); assertEquals(rows[0].run_id, 7);
  assert(rows[0].wording !== ITEM.q_en && !ITEM.used_wordings.includes(rows[0].wording));
  assertEquals(lessons, []);
});

Deno.test('1084: a mistake leads to an actual fix: the miss is recorded and the lesson is written', async () => {
  const { d, rows, lessons } = deps({ answer: async () => ({ status: 'answered', answer: 'A small card fee is added.', model: 'stub', reason: null }),
    judge: async () => ({ content: JSON.stringify({ facts: [{ fact: 'nothing is added for paying by card', present: false }, { fact: '2.9% plus AED 1', present: false }] }), error: null }) });
  const r = await runExamBatch(d, 7);
  assertEquals(r.missed, 1); assertEquals(r.lessons, 1);
  assertEquals(rows[0].pass, false); assertEquals(rows[0].graded_by, 'model'); assertEquals(rows[0].missing.length, 2);
  assertEquals(lessons, [41]);
});

Deno.test('a fact said in other words passes on the model judge, never on a guess', async () => {
  const { d, rows } = deps({ answer: async () => ({ status: 'answered', answer: 'No surcharge for cards. We absorb Stripe (2.9% + AED 1).', model: 'stub', reason: null }),
    judge: async () => ({ content: '```json\n{"facts":[{"fact":"nothing is added for paying by card","present":true},{"fact":"2.9% plus AED 1","present":true}]}\n```', error: null }) });
  await runExamBatch(d, 7);
  assertEquals(rows[0].pass, true); assertEquals(rows[0].graded_by, 'model');
  // a judge that leaves a fact ungraded is not read: the code's verdict stands
  assertEquals(parseJudge(JSON.stringify({ facts: [{ fact: '2.9% plus AED 1', present: true }] }), ITEM.expected_facts), null);
});

Deno.test('a wording outage is recorded as no_wording and opens no fix', async () => {
  const { d, rows, lessons } = deps({ reword: async () => ({ content: null, error: 'gateway 503' }) });
  const r = await runExamBatch(d, 7);
  assertEquals(r.no_wording, 1); assertEquals(rows[0].status, 'no_wording'); assertEquals(lessons, []);
});

Deno.test('the batch stops on the run\'s stop (the week\'s AED cap) and on its own clock', async () => {
  const capped = deps({ next: async () => ({ items: [ITEM], stop: 'week_cap' }) });
  assertEquals((await runExamBatch(capped.d, 7)).stop, 'week_cap'); assertEquals(capped.rows.length, 0);
  let t = 0;
  const slow = deps({ queue: [ITEM, { ...ITEM, item_id: 'b' }, { ...ITEM, item_id: 'c' }], now: () => (t += 30_000) });
  const r = await runExamBatch(slow.d, 7, { budgetMs: 100_000, max: 9 });
  assertEquals(r.stop, 'clock'); assert(r.asked < 3);
});

Deno.test('a record that fails stops the batch rather than asking on unrecorded', async () => {
  const { d } = deps({ record: async () => ({ asked_id: 0, fix_id: null, lesson_needed: false, error: 'permission denied' }) });
  const r = await runExamBatch(d, 7);
  assertEquals(r.asked, 0); assert(r.stop?.startsWith('record_failed'));
});

Deno.test('missingFacts ignores case, punctuation and hyphenation', () => {
  assertEquals(missingFacts('The Title-Block names it', ['title block']), []);
});
