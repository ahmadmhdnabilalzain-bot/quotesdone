// The weekly seat exam the company runs itself (ledger 1084/1443): runExamBatch with stub deps, no model and no database.
// Before seat_exam.ts existed this file could not import, so every case here failed; each case names the founder's rule it holds.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { type AskRow, type ExamDeps, type ExamItem, REWORD_SYSTEM, isFreshWording, missingFacts, parseJudge, parseWording, rewordInput, runExamBatch, termsOfArt } from './seat_exam.ts';

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
  const r = await runExamBatch(slow.d, 7, { budgetMs: 140_000, itemMs: 125_000, max: 9 });
  // the first item always starts; a second never starts when it could not finish inside the edge's wall
  assertEquals(r.stop, 'clock'); assertEquals(r.asked, 1);
});

Deno.test('a record that fails stops the batch rather than asking on unrecorded', async () => {
  const { d } = deps({ record: async () => ({ asked_id: 0, fix_id: null, lesson_needed: false, error: 'permission denied' }) });
  const r = await runExamBatch(d, 7);
  assertEquals(r.asked, 0); assert(r.stop?.startsWith('record_failed'));
});

Deno.test('missingFacts ignores case, punctuation and hyphenation', () => {
  assertEquals(missingFacts('The Title-Block names it', ['title block']), []);
});

// ── 19 Nov 2026 (it_engineer): run 1 of 15 Nov asked 18 and passed 1, and the judge never ran ──────────────────────────
// it_engineer/index.ts called the judge as task knowledge_validation with no counterpart_model, and ai_gateway refuses a review
// class without the author's model (400 review_needs_counterpart): 18 wording calls, 0 judge calls in the run window. 13 of
// the 17 misses were the right answer in other words. The judge now names the model that wrote the answer; the gateway picks
// a reviewer of another family (fn_ai_route_review_for). the_judge_names_the_answering_model.test.ts runs the real gateway.
Deno.test('the judge is told which model wrote the answer, so the gateway can route it to another family', async () => {
  const seen: { system: string; author: string }[] = [];
  const { d, rows } = deps({
    answer: async () => ({ status: 'answered', answer: 'Paying by card adds nothing; QuotesDone bears the Stripe charge of 2.9% + AED 1.', model: 'openai/gpt-6-luna-pro', reason: null }),
    judge: async (system, _input, author) => { seen.push({ system, author }); return { content: JSON.stringify({ facts: ITEM.expected_facts.map((fact) => ({ fact, present: true })) }), error: null }; },
  });
  await runExamBatch(d, 7);
  assertEquals(seen.map((s) => s.author), ['openai/gpt-6-luna-pro']);
  assertEquals([rows[0].graded_by, rows[0].pass], ['model', true]);
});

Deno.test('an answer whose model is not known is not put to a judge that could not prove its independence', async () => {
  let judged = 0;
  const { d, rows } = deps({
    answer: async () => ({ status: 'answered', answer: 'Paying by card adds nothing.', model: null, reason: null }),
    judge: async () => { judged++; return { content: null, error: 'must not be called' }; },
  });
  await runExamBatch(d, 7);
  // graded by code and failed: fn_seat_exam_record (every_seat_knows_the_facts_its_exam_asks.sql) counts it unjudged, opens no fix
  assertEquals([judged, rows[0].graded_by, rows[0].pass], [0, 'code', false]);
});

// ceo-exam-09 of run 1: "Which strategic powers can QuotesDone realistically build first?" was reworded "Which strategic
// capabilities is QuotesDone realistically able to develop earliest?". "Strategic powers" names the framework the expected fact
// ("counter-positioning") belongs to; without it the seat answered a different question. ceo-exam-10 lost "hiring".
const CEO09: ExamItem = { item_id: 'ceo-exam-09', seat: 'ceo', q_en: 'Which strategic powers can QuotesDone realistically build first?',
  expected_facts: ['counter-positioning'], used_wordings: [], fix_id: null, fix_ref: null };
const CEO10: ExamItem = { ...CEO09, item_id: 'ceo-exam-10', q_en: 'What is the buyer really hiring QuotesDone to do?', expected_facts: ['comparable, compliant quotations'] };

Deno.test('a rewording keeps the terms of art: ceo-09 loses "strategic powers" and is refused', () => {
  assertEquals(termsOfArt(CEO09.q_en), ['strategic powers', 'QuotesDone']);
  assertEquals(parseWording(JSON.stringify({ wording: 'Which strategic capabilities is QuotesDone realistically able to develop earliest?' }), CEO09), null);
  assertEquals(parseWording(JSON.stringify({ wording: 'Of the strategic powers, which could QuotesDone realistically establish earliest?' }), CEO09),
    'Of the strategic powers, which could QuotesDone realistically establish earliest?');
  assertEquals(parseWording(JSON.stringify({ wording: 'What service is the buyer bringing QuotesDone in to provide?' }), CEO10), null);
  assert(parseWording(JSON.stringify({ wording: 'When a buyer hires QuotesDone, what job is he really hiring it to do?' }), CEO10));
  // the prompt names the terms to keep, and says which kinds of term are never paraphrased
  assertEquals(JSON.parse(rewordInput(CEO09)).keep_verbatim, ['strategic powers', 'QuotesDone']);
  for (const kind of ['named laws', 'decrees', 'product', 'role', 'numbers', 'rulings', 'KEEP_VERBATIM']) assert(REWORD_SYSTEM.includes(kind), kind);
});

Deno.test('the terms of art of the other run-1 questions are found, and their run-1 wordings still pass', () => {
  const law: ExamItem = { ...CEO09, q_en: 'Under Federal Decree-Law No. 32 of 2021, may a seat sign a guarantee (ruling 721)?' };
  assertEquals(termsOfArt(law.q_en), ['Federal Decree-Law No', '32', '2021', 'ruling 721']);
  assertEquals(parseWording(JSON.stringify({ wording: 'May a seat sign a guarantee, per Federal Decree-Law No. 32 of 2021 and ruling 721?' }), law),
    'May a seat sign a guarantee, per Federal Decree-Law No. 32 of 2021 and ruling 721?');
  assertEquals(parseWording(JSON.stringify({ wording: 'May a seat sign a guarantee under the 2021 companies law?' }), law), null);
  const kept: [string, string][] = [
    ["Is anything added to the reveal fee for paying by card, and who bears Stripe's fee?", 'Who is responsible for Stripe\u2019s fee when a reveal fee is paid by card, and does card payment add anything to the reveal fee?'],
    ['How should third-party GitHub Actions be referenced in workflows?', 'Within workflows, what is the proper way to refer to GitHub Actions created by third parties?'],
    ['When did the second edition of NRM2 take effect?', 'On what date did NRM2\u2019s second edition come into force?'],
    ['The customer wrote "I don\'t need a human". Is that a handoff request?', 'Does the customer\'s statement, \u201cI don\'t need a human,\u201d qualify as a handoff request?'],
    ['How many OTP requests per number prefix in an hour counts as a burst?', 'For a given number prefix, what number of OTP requests within one hour constitutes a burst?'],
    ['How do we measure share of voice against competitors?', 'What method can we use to assess our share of voice compared with competitors?'],
    ['Can a seat sign a guarantee on behalf of the company?', 'May one of the company\u2019s seats execute a guarantee for it?'],
  ];
  for (const [q, w] of kept) assertEquals(parseWording(JSON.stringify({ wording: w }), { q_en: q, used_wordings: [] }), w, q);
});

// ── review of #2077 (19 Nov 2026) ───────────────────────────────────────────────────────────────────────────────────────
const DROPS = JSON.stringify({ wording: 'Which strategic capabilities is QuotesDone realistically able to develop earliest?' });
const KEEPS = JSON.stringify({ wording: 'Of the strategic powers, which could QuotesDone realistically establish earliest?' });

Deno.test('a wording that drops a term of art is asked for again once, naming the dropped terms', async () => {
  const inputs: string[] = [];
  const replies = [DROPS, KEEPS];
  const { d, rows } = deps({ queue: [CEO09], reword: async (_s, input) => { inputs.push(input); return { content: replies.shift()!, error: null }; },
    answer: async () => ({ status: 'answered', answer: 'Counter-positioning first.', model: 'openai/gpt-6-luna-pro', reason: null }) });
  const r = await runExamBatch(d, 7);
  assertEquals(inputs.length, 2);
  assertEquals(JSON.parse(inputs[0]).dropped_last_time, undefined);
  assertEquals(JSON.parse(inputs[1]).dropped_last_time, ['strategic powers']);
  assert(REWORD_SYSTEM.includes('DROPPED_LAST_TIME'));
  assertEquals([r.asked, r.passed, r.no_wording, rows[0].wording], [1, 1, 0, JSON.parse(KEEPS).wording]);
});

Deno.test('the batch records a twice-refused wording as no_wording: nothing is asked, no fix, no lesson', async () => {
  let rewords = 0, answered = 0;
  const { d, rows, lessons } = deps({ queue: [CEO09], reword: async () => { rewords++; return { content: DROPS, error: null }; },
    answer: async () => { answered++; return { status: 'answered', answer: 'x', model: 'stub', reason: null }; } });
  const r = await runExamBatch(d, 7);
  assertEquals([rewords, answered, r.asked, r.no_wording, r.missed, r.unjudged], [2, 0, 1, 1, 0, 0]);
  assertEquals([rows[0].status, rows[0].wording, rows[0].pass], ['no_wording', '', false]);
  assertEquals(lessons, []);
  // an outage (no reply) is not asked again: only a wording that dropped a term is
  let outage = 0;
  const o = deps({ reword: async () => { outage++; return { content: null, error: 'gateway 503' }; } });
  await runExamBatch(o.d, 7);
  assertEquals(outage, 1);
});

Deno.test('the batch counts an unjudged answer apart from a judged miss', async () => {
  const unj = deps({ answer: async () => ({ status: 'answered', answer: 'Paying by card adds nothing.', model: null, reason: null }) });
  const a = await runExamBatch(unj.d, 7);
  assertEquals([a.unjudged, a.missed, a.passed], [1, 0, 0]);
  const judged = deps({ answer: async () => ({ status: 'answered', answer: 'A small card fee is added.', model: 'stub', reason: null }),
    judge: async () => ({ content: JSON.stringify({ facts: ITEM.expected_facts.map((fact) => ({ fact, present: false })) }), error: null }) });
  const b = await runExamBatch(judged.d, 7);
  assertEquals([b.unjudged, b.missed], [0, 1]);
});
