// distilLessons with a mocked model and database: a group is reasoned at high stakes, verified by another
// family, and handed to the apply routine with its subject; under the hold it is queued, never worded.
import { assert, assertEquals } from 'jsr:@std/assert';
import { distilLessons } from './learning_loop.ts';
import type { ThinkDeps } from './think.ts';

const CLUSTER = [{ seat: 'sales_engineer', cluster_key: 'sales_engineer:abc', cases: [1, 2, 3].map((i) => ({ case_id: i, case_kind: 'quote', situation: 'ZZ DEMO HVAC quote ' + i, decision: null, outcome: 'lost at reveal', finalised: true, correction: null })) }];
function deps(gateOpen: boolean) {
  const rpcs: [string, Record<string, unknown>][] = []; const phases: string[] = [];
  const d: ThinkDeps = {
    gate: () => Promise.resolve(gateOpen ? { allowed: true } : { allowed: false, rule: 'founder_hold' }),
    llm: (phase, _s, _i, o) => {
      phases.push(phase + (o.counterpartModel ? ':counterpart' : ''));
      const c = phase === 'decompose' ? '{"steps":[{"id":"s1","goal":"what the losses share","query":"why HVAC quotes lose at reveal"}],"facts":[]}'
        : phase === 'verify' ? '{"verdict":"agree","problems":[]}'
        : '{"answer":"HVAC quotes lost at reveal when priced above the band; match on the band first (#1, #2, #3).","reasoning":["s1: all three were above band"],"cited":[],"confidence":0.7}';
      return Promise.resolve({ content: c, model: phase === 'verify' ? 'openai/gpt-sol-5.6' : 'qwen/qwen3.8-max-0902' });
    },
    embed: () => Promise.resolve([0.1, 0.2]),
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_lesson_clusters') return Promise.resolve({ data: CLUSTER, error: null });
      if (fn === 'fn_lesson_unembedded') return Promise.resolve({ data: [{ id: 5, finding: 'x' }], error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: 1, error: null });
    },
  };
  return { d, rpcs, phases };
}

Deno.test('a group of outcomes becomes a lesson verified by another family, applied with its subject', async () => {
  const m = deps(true);
  const r = await distilLessons({}, m.d) as { rows: { status: string }[]; embedded: number };
  assertEquals(r.rows[0].status, 'answered');
  assertEquals(r.embedded, 1);
  assert(m.phases.includes('verify:counterpart'), 'the lesson was not verified by another family');
  const apply = m.rpcs.find(([f]) => f === 'fn_reason_apply_learning__distil')!;
  const res = apply[1].p_result as { subject: { cluster_key: string }; verified: { status: string } };
  assertEquals(res.subject.cluster_key, 'sales_engineer:abc');
  assertEquals(res.verified.status, 'agreed');
});

Deno.test('under the hold the group is queued for reasoning, and nothing is applied', async () => {
  const m = deps(false);
  const r = await distilLessons({}, m.d) as { rows: { status: string }[] };
  assertEquals(r.rows[0].status, 'held');
  assert(m.rpcs.some(([f, a]) => f === 'fn_reason_hold' && a.p_surface === 'learning.distil'));
  assertEquals(m.rpcs.filter(([f]) => f === 'fn_reason_apply_learning__distil').length, 0);
});
