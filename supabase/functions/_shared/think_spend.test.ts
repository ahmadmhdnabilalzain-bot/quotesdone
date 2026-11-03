// What think() spends on (it_engineer, 3 Nov 2026): a routine duty on the seat's easy route, and the independent check
// decided by code when every figure is printed in the sources. No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { EASY_DUTY_SURFACE, easyClass, figuresGrounded, figuresOf, think, type LlmReply, type Phase, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);
function mock(answer: string) {
  const calls: { phase: Phase; o: Record<string, unknown> }[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (phase, _s, _i, o) => {
      calls.push({ phase, o: o as Record<string, unknown> });
      const content = phase === 'synthesise' ? J({ answer, reasoning: ['s1: the settled facts'], cited: [], confidence: 0.9 })
        : phase === 'verify' ? J({ verdict: 'agree', problems: [] })
        : J({ steps: [{ id: 's1', goal: 'x', query: 'x', needs_knowledge: false }], facts: [], high_stakes: true });
      return Promise.resolve({ content, model: 'm' } as LlmReply);
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn) => Promise.resolve({ data: fn === 'fn_case_recall' ? { cases: [] } : [], error: null }),
  };
  return { deps, calls };
}

Deno.test("a seat's own high-stakes answer whose every figure is in the settled facts is checked by code; any other goes to the model", async () => {
  const grounded = 'The bank fee is AED 199 plus AED 9.95 VAT a month.';
  { const m = mock(grounded); const r = await think(m.deps, { context: { audience: 'internal' }, seat: 'ceo', surface: 'test', question: 'What is the bank fee?' });
    assertEquals(m.calls.map((c) => c.phase), ['decompose', 'synthesise']); assertEquals(r.verified?.by, 'code'); }
  // a figure the facts do not print -> the model checks it
  { const m = mock('The bank fee is AED 250 a month.'); await think(m.deps, { context: { audience: 'internal' }, seat: 'ceo', surface: 'test', question: 'q' });
    assertEquals(m.calls.map((c) => c.phase), ['decompose', 'synthesise', 'verify']); }
  // the caller demanded the check -> the model checks it
  { const m = mock(grounded); await think(m.deps, { context: { audience: 'internal' }, seat: 'ceo', surface: 'test', question: 'q', stakes: 'high' });
    assert(m.calls.some((c) => c.phase === 'verify')); }
  // a customer reads it -> the model checks it, figures or not
  { const m = mock('Suppliers pay AED 199 a month.'); await think(m.deps, { context: { audience: 'customer' }, seat: 'customer_support', surface: 'test', question: 'q' });
    assert(m.calls.some((c) => c.phase === 'verify')); }
});

Deno.test("an easy run asks its judgement on the routine route, and an internal question is marked internal for the duty ceiling", async () => {
  const m = mock('Done.');
  await think(m.deps, { context: { audience: 'internal' }, seat: 'ceo', surface: 'ceo.knowledge_refresh', question: 'q', easy: true });
  const synth = m.calls.find((c) => c.phase === 'synthesise')!;
  assertEquals(synth.o.taskClass, 'routine_employee_reasoning');
  assertEquals(synth.o.internal, true);
  const c = mock('Done.');
  await think(c.deps, { context: { audience: 'customer' }, seat: 'customer_support', surface: 'x', question: 'q' });
  assert(c.calls.every((x) => x.o.internal === false));
});

Deno.test("the CEO's quarterly knowledge re-check is an easy duty: its judgement goes on the routine route, nothing else moves", () => {
  assert(EASY_DUTY_SURFACE.test('ceo.knowledge_refresh'));
  assert(!EASY_DUTY_SURFACE.test('ceo.experiment_approval'));
  assert(!EASY_DUTY_SURFACE.test('wa_inbound.unwritten_reply'));
  assertEquals(easyClass('internal_judgement', true), 'routine_employee_reasoning');
  assertEquals(easyClass('internal_judgement', false), 'internal_judgement');
  assertEquals(easyClass('internal_judgement', undefined), 'internal_judgement');
  assertEquals(easyClass('knowledge_validation', true), 'knowledge_validation');      // the check keeps its class
  assertEquals(easyClass('customer_communication', true), 'customer_communication');  // an audience class never moves
});

Deno.test('code agrees only when EVERY figure, with the word after it, is printed in the sources', () => {
  const src = 'Suppliers pay AED 1,500 a year. A reveal costs 3% of the quote. Refunds are paid within 14 working days.';
  assert(figuresGrounded('The fee is AED 1500 a year and a reveal costs 3%.', src));
  assert(figuresGrounded('Refunds take 14 working days.', src));
  assert(figuresGrounded('الاشتراك ١٥٠٠ a year', src));                              // Arabic-Indic digits are the same figure
  assert(!figuresGrounded('Refunds take 14 days.', src.replace('14 working', '10 working') + ' 14 suppliers'));  // "14 days" is not printed
  assert(!figuresGrounded('Refunds take 7 working days.', src));
  assert(!figuresGrounded('The fee is AED 1500 a year and a reveal costs 5%.', src));  // one ungrounded figure sends it to the model
  assert(!figuresGrounded('You need a permit from the municipality.', src));          // no figure: code cannot judge it
  assertEquals(figuresOf('AED 1,500 a year, 3 %'), ['1500 a', '3 %']);
});
