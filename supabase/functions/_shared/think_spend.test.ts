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

Deno.test("an easy run asks its judgement on the routine route; only a DECLARED duty for an internal audience counts as internal", async () => {
  const m = mock('Done.');
  await think(m.deps, { context: { audience: 'internal' }, seat: 'ceo', surface: 'ceo.knowledge_refresh', question: 'q', easy: true, internalDuty: true });
  const synth = m.calls.find((c) => c.phase === 'synthesise')!;
  assertEquals(synth.o.taskClass, 'routine_employee_reasoning');
  assertEquals(synth.o.internal, true);
  // an internal judgement about a real supplier (no declaration) is never counted (review of this PR, finding 1)
  const s = mock('Done.');
  await think(s.deps, { context: { audience: 'internal' }, seat: 'sales_engineer', surface: 'sql.fn_supplier_twin', question: 'q' });
  assert(s.calls.every((x) => x.o.internal === false));
  // a declaration for an outside audience is never counted either
  const c = mock('Done.');
  await think(c.deps, { context: { audience: 'customer' }, seat: 'customer_support', surface: 'x', question: 'q', internalDuty: true });
  assert(c.calls.every((x) => x.o.internal === false));
});

Deno.test('a daily-ceiling skip holds the question as the hold does, so it keeps its tries', async () => {
  const deps = mock('x').deps;
  const held: string[] = [];
  const d: ThinkDeps = { ...deps,
    llm: () => Promise.resolve({ content: null, error: 'gateway_http_503:daily_ceiling:the internal model spend today is USD 2.01' } as LlmReply),
    rpc: (fn, a) => { if (fn === 'fn_reason_hold') held.push(String(a.p_reason)); return Promise.resolve({ data: fn === 'fn_case_recall' ? { cases: [] } : 1, error: null }); } };
  const r = await think(d, { context: { audience: 'internal' }, seat: 'ceo', surface: 'ceo.knowledge_refresh', question: 'q', internalDuty: true });
  assertEquals(r.status, 'held');
  assertEquals(held, ['model_hold']);
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
  const src = ['Suppliers pay AED 1,500 a year. A reveal costs 3% of the quote.', 'Refunds are paid within 14 working days.'];
  assert(figuresGrounded('The fee is AED 1500 a year and a reveal costs 3%.', src));
  assert(figuresGrounded('Refunds are paid in 14 working days.', src));
  assert(figuresGrounded('suppliers pay aed ١٥٠٠ a year', src));                     // Arabic-Indic digits are the same figure
  // the reviewer's cases (review of this PR): a different period, currency, or unit after the figure is not the same figure
  assert(!figuresGrounded('Suppliers pay AED 1,500 a month.', src));
  assert(!figuresGrounded('Suppliers pay USD 1,500 a year.', src));
  assert(!figuresGrounded('Refunds take 14 days.', src));
  assert(!figuresGrounded('Refunds are paid within 7 working days.', src));
  assert(!figuresGrounded('The fee is AED 1500 a year and a reveal costs 5%.', src));  // one ungrounded figure sends it to the model
  assert(!figuresGrounded('You need a permit from the municipality.', src));          // no figure: code cannot judge it
  // a figure must be printed in ONE source with its words, never stitched across two
  assert(!figuresGrounded('pay AED 14 working', ['pay AED 99', '14 working']));
  assertEquals(figuresOf('AED 1,500 a year, 3 % of fees').map((f) => [f.before, f.num, f.after]), [['aed', '1500', 'year'], ['year', '3%', 'fees']]);
  // the re-review's cases: the word after a '%' and a comparator both count
  assert(!figuresGrounded('A reveal costs 3% of the subscription.', src));
  assert(!figuresGrounded('It is more than 3% of the quote.', ['It is less than 3% of the quote.']));
  assert(figuresGrounded('It is less than 3% of the quote.', ['It is less than 3% of the quote.']));
});
