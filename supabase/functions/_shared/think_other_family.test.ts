// A re-asked question is written by another model family (ceo, 10 Nov 2026, rulings 1059 / 1574). fn_ceo_revision_refile
// re-asks a revision the usual route failed to write, once, with request.otherFamilyThan = the model that failed. The
// synthesis (both the first pass and the corrective pass after a disagreeing reviewer) must name it as counterpartModel,
// so the gateway routes it through fn_ai_route_review_for to another family. Without it, the route is the class's own.
// No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { think, type LlmReply, type Phase, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);
function mock(verdict: 'agree' | 'disagree' = 'agree') {
  const calls: { phase: Phase; o: Record<string, unknown> }[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (phase, _s, _i, o) => {
      calls.push({ phase, o: o as Record<string, unknown> });
      const content = phase === 'synthesise' ? J({ answer: 'The revision answers each reason.', reasoning: ['s1: the case'], cited: [], confidence: 0.9 })
        : phase === 'verify' ? J({ verdict, problems: verdict === 'agree' ? [] : ['a reason is not answered'] })
        : J({ steps: [{ id: 's1', goal: 'x', query: 'x', needs_knowledge: false }], facts: [], high_stakes: false });
      return Promise.resolve({ content, model: 'anthropic/claude-sonnet-5.5' } as LlmReply);
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn) => Promise.resolve({ data: fn === 'fn_case_recall' ? { cases: [] } : [], error: null }),
  };
  return { deps, calls };
}

Deno.test('a re-asked question names the failed model as counterpart on every synthesis pass', async () => {
  const m = mock('disagree');
  await think(m.deps, { context: { audience: 'internal' }, seat: 'marketing', surface: 'marketing.ceo_revision', question: 'Revise the plan.',
    stakes: 'high', otherFamilyThan: 'openai/gpt-6-luna-pro' });
  const synth = m.calls.filter((c) => c.phase === 'synthesise');
  assertEquals(synth.length, 2);                                   // the first pass and the corrective pass
  for (const s of synth) assertEquals(s.o.counterpartModel, 'openai/gpt-6-luna-pro');
  // the independent check still reads against the model that WROTE the answer, not the one that failed
  assertEquals(m.calls.find((c) => c.phase === 'verify')?.o.counterpartModel, 'anthropic/claude-sonnet-5.5');
});

Deno.test('a question that does not ask for another family keeps the class route', async () => {
  const m = mock();
  await think(m.deps, { context: { audience: 'internal' }, seat: 'marketing', surface: 'marketing.ceo_revision', question: 'Revise the plan.' });
  const synth = m.calls.filter((c) => c.phase === 'synthesise');
  assert(synth.length >= 1);
  for (const s of synth) assert(!('counterpartModel' in s.o), 'no counterpart on an ordinary synthesis');
});
