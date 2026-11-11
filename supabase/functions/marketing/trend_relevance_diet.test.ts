// A trend-relevance choice with the prompt diet's content switch 'a_trend_relevance_choice_plans_and_retrieves_nothing'
// (OFF by default; marketing/duties/trends_geo.ts judgeTrend). ON: no planner call and no knowledge retrieval; the headline,
// the settled facts and the founder's rulings still reach the one call that decides. No network.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import type { GateAnswer } from '../_shared/llm_hold.ts';
import { settledFacts, type LlmReply, type Phase, type ThinkDeps } from '../_shared/think.ts';
import { judgeTrend } from './duties/trends_geo.ts';

const J = (x: unknown) => JSON.stringify(x);
const T = { id: 7, title: 'Dubai Municipality updates its fit-out permit fees', url: 'https://example.invalid/news/7', source: 'ZZ DEMO feed' };
function mock() {
  const phases: Phase[] = []; const rpcs: string[] = []; const sys: Record<string, unknown>[] = []; const inputs: string[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (phase, system, input, o) => {
      phases.push(phase); sys.push({ system, ...(o as Record<string, unknown>) }); inputs.push(input);
      const content = phase === 'decompose' ? J({ steps: [{ id: 's1', goal: 'fit-out permits', query: 'Dubai fit-out permit fees' }], facts: [], high_stakes: false })
        : J({ answer: 'Fit-out buyers will ask about permit costs.', reasoning: [], cited: ['brief'], confidence: 0.8, decision: { choice: 'relevant' } });
      return Promise.resolve({ content, model: 'openai/gpt-6-luna-pro' } as LlmReply);
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn) => { rpcs.push(fn); return Promise.resolve({ data: fn === 'fn_reason_retrieve' ? [{ source: 'marketing_knowledge', id: 1, title: 't', excerpt: 'x'.repeat(2000), similarity: 0.9 }] : fn === 'fn_case_recall' ? { cases: [] } : 1, error: null }); },
  };
  return { deps, phases, rpcs, sys, inputs };
}

Deno.test('OFF (the default call): the plan and the retrieval run as before', async () => {
  const m = mock();
  const j = await judgeTrend(m.deps, T);
  assertEquals(j?.relevant, true);
  assertEquals(m.phases, ['decompose', 'synthesise']);
  assert(m.rpcs.includes('fn_reason_retrieve'));
});

Deno.test('ON: one call decides, with no plan and no retrieved rows; the headline, the settled facts and the rulings stay', async () => {
  const before = mock(); await judgeTrend(before.deps, T);
  const m = mock();
  const j = await judgeTrend(m.deps, T, { plansNothing: true });
  assertEquals(j?.relevant, true);
  assertEquals(m.phases, ['synthesise']);
  assert(!m.rpcs.includes('fn_reason_retrieve'), 'no knowledge retrieval');
  assertStringIncludes(m.inputs[0], T.title);
  assertEquals(m.sys[0].sysStable, settledFacts('internal', 'marketing'));
  assertStringIncludes(String(m.sys[0].system), 'Standing rulings of the founder');
  assertStringIncludes(String(m.sys[0].system), 'relevant (it changes what UAE buyers');
  const sent = (x: ReturnType<typeof mock>) => x.inputs.reduce((n, s) => n + s.length, 0) + x.sys.reduce((n, s) => n + String(s.system).length + String(s.sysStable ?? '').length, 0);
  assert(sent(m) < sent(before) * 0.6, `${sent(m)} vs ${sent(before)} characters across the run`);
});
