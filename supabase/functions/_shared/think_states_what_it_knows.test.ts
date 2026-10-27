// The seat states what it knows (ceo, ledger 1003 stage 2, 19 Oct 2026). Each case replays a failure measured on the
// real-model seat exam of 19 Oct (main d1ef06e): an answer held for citing its own brief, held for a question that
// changed nothing, held for one provider 5xx, and a pack entry the planner's paraphrase never fetched. No network.
import { assert, assertEquals } from 'jsr:@std/assert';
import { citable, groundDraft, refuse, think, type Fact, type LlmReply, type ThinkDeps } from './think.ts';

const J = JSON.stringify;
const ANSWER = 'The launch-path probe runs every hour on the hour; a failure opens a finding for the it_engineer seat, which owns the fix and closes it once the next probe passes, with no one else asked to act on it.';

Deno.test('a citation of the settled facts is valid: "brief", or an id the brief carries; an invented id is still refused', () => {
  const settled = '... CT§8 Refunds ... (accountant:non-response-charge-accounting) ...';
  const d = { answer: ANSWER, reasoning: ['s1: x'], cited: ['brief', 'CT§8(f)', 'accountant:non-response-charge-accounting'] };
  const o = { missing: [] as Fact[], conversationText: '', requireTrail: true };
  assertEquals(refuse(d, { ...o, sourceIds: citable(new Set(), settled, d) }), null);
  assertEquals(refuse(d, { ...o, sourceIds: new Set() }) !== null, true, 'without the brief the same draft was held');
  const bad = { ...d, cited: ['kb_chunks:999'] };
  assert(refuse(bad, { ...o, sourceIds: citable(new Set(), settled, bad) })?.includes('kb_chunks:999'));
});

Deno.test('a question that changes nothing is dropped when the answer stands; a thin answer that only asks is still refused', () => {
  const d = { answer: ANSWER, reasoning: ['s1'], cited: [], asked_back: 'Which probe do you mean?' };
  groundDraft(d, []);
  assertEquals(d.asked_back, null);
  const thin = { answer: 'Which probe?', reasoning: ['s1'], cited: [], asked_back: 'Which probe?' };
  groundDraft(thin, []);
  assert(refuse(thin, { missing: [], sourceIds: new Set(), conversationText: '' })?.includes('asked back'));
  const changes = { answer: ANSWER, reasoning: ['s1'], cited: [], asked_back: 'Which emirate?' };
  groundDraft(changes, [{ name: 'emirate', why: 'x', changes_answer: true, value: null, from: null }]);
  assertEquals(changes.asked_back, 'Which emirate?', 'a decision-changing question stays');
});

function deps(llm: ThinkDeps['llm']) {
  const retrieved: string[] = [];
  const d: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never), llm,
    embed: (t) => Promise.resolve(t ? [0.1, 0.2] : null),
    rpc: (fn, args) => { if (fn === 'fn_reason_retrieve') retrieved.push(String(args.p_embedding)); return Promise.resolve({ data: fn.startsWith('fn_case_recall') ? { cases: [] } : fn === 'fn_reason_hold' ? 7 : [], error: null }); },
  };
  return { d, retrieved };
}
const PLAN = J({ steps: [{ id: 's1', goal: 'g', query: 'launch path probe cadence' }], facts: [], high_stakes: false });
const DRAFT = J({ answer: ANSWER, reasoning: ['s1: hourly'], cited: [], confidence: 0.9 });

Deno.test('one provider 5xx on the plan or the answer is retried once and answered', async () => {
  const seen: string[] = [];
  const fails = new Set(['decompose', 'synthesise']);
  const m = deps((phase) => { seen.push(phase); if (fails.delete(phase)) return Promise.resolve({ content: null, error: 'gateway_http_503' } as LlmReply); return Promise.resolve({ content: phase === 'decompose' ? PLAN : DRAFT, model: 'm' }); });
  const r = await think(m.d, { seat: 'it_engineer', surface: 'test', question: 'How often does the launch-path probe run?', context: { audience: 'internal' } });
  assertEquals(r.status, 'answered');
  assertEquals(seen, ['decompose', 'decompose', 'synthesise', 'synthesise']);
});

Deno.test('a hold or an open circuit is not retried', async () => {
  const seen: string[] = [];
  const m = deps((phase) => { seen.push(phase); return Promise.resolve({ content: null, error: 'gateway_http_503: circuit_open' } as LlmReply); });
  const r = await think(m.d, { seat: 'it_engineer', surface: 'test', question: 'q?', context: { audience: 'internal' } });
  assertEquals(r.status, 'held');
  assertEquals(seen, ['decompose']);
});

Deno.test('the question as asked is retrieved beside the plan; a caller\'s own plan is kept exactly', async () => {
  const m = deps((phase) => Promise.resolve({ content: phase === 'decompose' ? PLAN : DRAFT, model: 'm' }));
  const r = await think(m.d, { seat: 'it_engineer', surface: 'test', question: 'How often does the launch-path probe run?', context: { audience: 'internal' } });
  assertEquals(r.steps.filter((s) => s.kind === 'retrieve').map((s) => s.id), ['s1', 'q']);
  const n = deps((phase) => Promise.resolve({ content: phase === 'decompose' ? PLAN : DRAFT, model: 'm' }));
  const r2 = await think(n.d, { seat: 'it_engineer', surface: 'test', question: 'x?', context: { audience: 'internal' }, plan: { steps: [{ id: 'p', goal: 'g', query: 'y' }] } });
  assertEquals(r2.steps.filter((s) => s.kind === 'retrieve').map((s) => s.id), ['p']);
});

Deno.test('a common word the brief happens to contain is not a citation (release review of #1584)', () => {
  const settled = 'The fee is 3% plus VAT in AED. CT§8 Refunds. CT§80 Other. (accountant:non-response-charge-accounting)';
  for (const word of ['fee', 'VAT', 'AED', 'Refunds', 'CT§8 Refunds', 'accountant', 'CT§9', 'accountant:non-response']) {
    const d = { answer: ANSWER, reasoning: ['s1'], cited: [word] };
    assert(refuse(d, { missing: [], conversationText: '', requireTrail: true, sourceIds: citable(new Set(), settled, d) })?.includes(word), word + ' passed');
  }
});

Deno.test('a deadline or timeout is never retried, on the plan or the answer (the 150 s edge wall)', async () => {
  for (const error of ['gateway_http_502:gateway_deadline', 'timed out']) {
    const seen: string[] = [];
    const m = deps((phase) => { seen.push(phase); return Promise.resolve(phase === 'decompose' && seen.length === 1 ? { content: null, error } as LlmReply : phase === 'decompose' ? { content: PLAN, model: 'm' } : { content: null, error } as LlmReply); });
    await think(m.d, { seat: 'it_engineer', surface: 'test', question: 'q?', context: { audience: 'internal' } });
    assertEquals(seen.filter((p) => p === 'decompose').length, 1, error);
  }
  const seen: string[] = [];
  const m = deps((phase) => { seen.push(phase); return Promise.resolve(phase === 'decompose' ? { content: PLAN, model: 'm' } : { content: null, error: 'gateway_http_502:gateway_deadline' } as LlmReply); });
  await think(m.d, { seat: 'it_engineer', surface: 'test', question: 'q?', context: { audience: 'internal' } });
  assertEquals(seen, ['decompose', 'synthesise']);
});
