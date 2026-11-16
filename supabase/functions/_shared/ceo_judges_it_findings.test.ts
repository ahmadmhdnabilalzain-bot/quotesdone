// The CEO judges an IT finding with the model (ceo, 13 Nov 2026, founder ledger 1688). The held question the ceo.company_pool duty
// files (fn_ceo_ask, scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql) is reasoned by think() as replayHeld
// runs it: a routine duty of the seat (EASY_DUTY_SURFACE, INTERNAL_DUTY_SURFACE), so on the CEO's routine route, never the Opus
// route, and never gated on ceo_model_slot. The model is stubbed: a faithful answer, an invalid answer, no answer. No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { EASY_DUTY_SURFACE, INTERNAL_DUTY_SURFACE, think, type LlmReply, type ThinkDeps, type ThinkRequest } from './think.ts';

const OPTIONS = ['fix_now:sales_engineer', 'fix_now:customer_support', 'fix_now:accountant', 'fix_now:marketing', 'fix_now:it_engineer',
  'accept_risk', 'duplicate_of:401', 'needs_founder:money', 'needs_founder:destructive_production_change', 'needs_founder:fact_only_he_holds']
  .map((id) => ({ id, meaning: id }));
// the request exactly as fn_ceo_ask stores it, with what replayHeld adds for this surface
const request = (): ThinkRequest => ({
  seat: 'ceo', surface: 'ceo.it_finding', question: 'IT finding #403375: "a probe fault" (critical, open since 10 Nov, seen 4 times). As CEO, decide what happens next and give the reason in one or two sentences.',
  context: { audience: 'internal', case: { handoff_id: 403375, issue_key: 'duty:probe:x', severity: 'critical', still_open: true } },
  decision: { name: 'ceo.it_finding', options: OPTIONS }, plan: { steps: [] }, research: false, stakes: 'normal',
  subject: { handoff_id: 403375, round: 1 }, easy: EASY_DUTY_SURFACE.test('ceo.it_finding'), internalDuty: INTERNAL_DUTY_SURFACE.test('ceo.it_finding'),
});
function deps(reply: () => LlmReply) {
  const classes: string[] = []; const rpcs: string[] = [];
  const d = {
    gate: () => Promise.resolve(null),
    llm: (_p: string, _s: string, _i: string, o: { taskClass: string }) => { classes.push(o.taskClass); return Promise.resolve(reply()); },
    embed: () => Promise.resolve([0.1, 0.2]),
    rpc: (fn: string) => { rpcs.push(fn); return Promise.resolve({ data: fn === 'fn_judgement_record' ? 41 : fn.startsWith('fn_case_recall') ? { cases: [] } : fn === 'fn_seat_pool_context' ? { block: 'YOUR HAND-OVERS: Waiting on you: 105 hand-over(s) to answer.' } : [], error: null }); },
  } as unknown as ThinkDeps;
  return { d, classes, rpcs };
}

Deno.test('the CEO triage surfaces are the seat\'s routine duty, on its routine route', () => {
  // ceo.authority too (third review, item 4: it ran on the Opus route at ~AED 0.42 a call against a cap priced at AED 0.0106)
  for (const s of ['ceo.it_finding', 'ceo.overdue_handoff', 'ceo.authority']) { assert(EASY_DUTY_SURFACE.test(s), s); assert(INTERNAL_DUTY_SURFACE.test(s), s); }
  assert(!EASY_DUTY_SURFACE.test('ceo.management_review'), 'the hard reviews keep the CEO\'s own route');
});

Deno.test('a faithful answer is a decision among the four, on the routine route, with the pool in front of it', async () => {
  const m = deps(() => ({ content: JSON.stringify({ answer: 'The fault touches only a probe surface; accept it for two weeks.', reasoning: ['low blast'], cited: [], asked_back: null, confidence: 0.8, decision: { choice: 'accept_risk' } }), model: 'stub/routine' }));
  const r = await think(m.d, request());
  assertEquals(r.status, 'answered');
  assertEquals(r.decision?.choice, 'accept_risk');
  assert(m.classes.length > 0 && m.classes.every((c) => c !== 'internal_judgement'), 'routine route only: ' + m.classes.join(','));
  assert(m.rpcs.includes('fn_seat_pool_context'), 'the CEO reads the pool before deciding');
});

Deno.test('an invalid answer and no answer decide nothing: the question is held, never applied by code', async () => {
  for (const reply of [
    () => ({ content: JSON.stringify({ answer: 'Fix it.', reasoning: [], cited: [], asked_back: null, decision: { choice: 'reassign_to_founder' } }), model: 'stub' }),
    () => ({ content: null, model: 'stub', error: 'no reply' }),
  ]) {
    const r = await think(deps(reply as () => LlmReply).d, request());
    assertEquals(r.status, 'held', JSON.stringify(r.decision));
    assert(!r.decision?.choice, 'no choice may come back');
  }
});

Deno.test('a question of authority is two choices on the routine route; no founder option exists to choose', async () => {
  const m = deps(() => ({ content: JSON.stringify({ answer: 'One request, a customer on site: let it through once.', reasoning: [], cited: [], asked_back: null, confidence: 0.8, decision: { choice: 'allow_once' } }), model: 'stub/routine' }));
  const req: ThinkRequest = { ...request(), surface: 'ceo.authority', question: 'The sales_engineer asks: match request 41 (matching on inquiry:41). As CEO you decide alone.',
    decision: { name: 'ceo.authority', options: [{ id: 'allow_once', meaning: 'once' }, { id: 'refuse', meaning: 'no' }] },
    easy: EASY_DUTY_SURFACE.test('ceo.authority'), internalDuty: INTERNAL_DUTY_SURFACE.test('ceo.authority') };
  const r = await think(m.d, req);
  assertEquals(r.decision?.choice, 'allow_once');
  assert(m.classes.length > 0 && m.classes.every((c) => c !== 'internal_judgement'), 'routine route only: ' + m.classes.join(','));
  const asked = await think(deps(() => ({ content: JSON.stringify({ answer: 'Ask the founder about it.', reasoning: [], cited: [], asked_back: null, decision: { choice: 'ask_founder' } }), model: 'stub' })).d, req);
  assertEquals(asked.status, 'held', 'ask_founder is not a choice: nothing is decided');
});
