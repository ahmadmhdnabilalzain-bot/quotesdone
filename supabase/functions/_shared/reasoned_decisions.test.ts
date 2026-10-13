// needsAPerson with a MOCKED model and database (customer_support, 13 Oct 2026). The widget runs it after every reply;
// on production it planned (decompose) and retrieved knowledge into a ~15k-token synthesis that was cut off at its cap.
// Proves: no decompose call, no retrieval, ONE synthesis whose prompt stays small, inside its 900-token cap.
//   deno test --no-lock supabase/functions/_shared/reasoned_decisions.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { needsAPerson } from './reasoned_decisions.ts';

function mock(choice: string) {
  const calls: { phase: Phase; chars: number; max?: number; taskClass: string }[] = [];
  const rpcs: string[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: false, rule: 'route_not_registered' } as GateAnswer),
    llm: (phase, system, input, o) => {
      calls.push({ phase, chars: system.length + input.length, max: o.max, taskClass: o.taskClass });
      const content = phase === 'synthesise' ? JSON.stringify({ answer: 'They ask to speak to a human.', decision: { choice } }) : JSON.stringify({ verdict: 'agree', problems: [] });
      return Promise.resolve({ content, model: 'm' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn) => {
      rpcs.push(fn);
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      // A knowledge read returns big rows; if one fired, the prompt would balloon and the assertions below fail.
      if (fn.startsWith('fn_reason_retrieve')) return Promise.resolve({ data: Array.from({ length: 6 }, (_, i) => ({ source: 'k', id: i, title: 't', excerpt: 'x'.repeat(1200), similarity: 0.9 })), error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { deps, calls, rpcs };
}

const ASK = { seat: 'customer_support' as const, surface: 'site_assistant.person', message: 'Can I speak to a real person please?', audience: 'visitor' as const, dedupeKey: 'widget:person:t' };

Deno.test('needsAPerson: no decompose, no retrieval, one small synthesis within its cap', async () => {
  const m = mock('needs_a_person');
  const r = await needsAPerson(m.deps, ASK);
  assertEquals(r.value, true);
  assertEquals(m.calls.map((c) => c.phase), ['synthesise']);   // removed: the decompose call (routine_employee_reasoning)
  assertEquals(m.rpcs.filter((f) => f.startsWith('fn_reason_retrieve')).length, 0);
  const s = m.calls[0];
  assertEquals(s.max, 900);
  assertEquals(s.taskClass, 'customer_communication');
  // ~4 chars a token: the whole prompt stays well under 2k tokens (it was 14.6-15.7k on production).
  assert(s.chars < 8000, `synthesis prompt is ${s.chars} chars`);
});

Deno.test('needsAPerson: a plain question decides no_person on the same single call', async () => {
  const m = mock('no_person');
  const r = await needsAPerson(m.deps, { ...ASK, message: 'What is the difference between MDF and plywood?' });
  assertEquals(r.value, false);
  assertEquals(m.calls.length, 1);
});
