// needsAPerson with a MOCKED model and database (customer_support, 13 Oct 2026). The widget runs it after every reply;
// on production it planned (decompose) and retrieved knowledge into a ~15k-token synthesis that was cut off at its cap.
// Proves: no decompose call, no retrieval, ONE synthesis whose prompt stays small, inside its 900-token cap.
//   deno test --no-lock supabase/functions/_shared/reasoned_decisions.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { needsAPerson } from './reasoned_decisions.ts';

function mock(choice: string, o: { content?: string | null; hold?: boolean } = {}) {
  const calls: { phase: Phase; chars: number; max?: number; taskClass: string }[] = [];
  const rpcs: string[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.hold ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : { allowed: false, rule: 'route_not_registered' }) as GateAnswer),
    llm: (phase, system, input, x) => {
      calls.push({ phase, chars: system.length + input.length, max: x.max, taskClass: x.taskClass });
      const content = 'content' in o ? o.content : phase === 'synthesise' ? JSON.stringify({ answer: 'They ask to speak to a human.', decision: { choice } }) : JSON.stringify({ verdict: 'agree', problems: [] });
      return Promise.resolve({ content, model: 'm' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn) => {
      rpcs.push(fn);
      if (fn === 'fn_reason_hold') return Promise.resolve({ data: 77, error: null });
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

// THE FAILURE PATH: no guess. A failed, held or unparseable call is value null and the question is filed in the
// hold queue (fn_reason_hold), whose replay (reasoned_delivery.ts, site_assistant.person) files the CEO report.
for (const [name, o] of [
  ['failed (no content)', { content: null }],
  ['unparseable', { content: 'not json {' }],
  ['held by the gate', { hold: true }],
] as const) {
  Deno.test(`needsAPerson ${name}: value null, question queued`, async () => {
    const m = mock('needs_a_person', o);
    const r = await needsAPerson(m.deps, ASK);
    assertEquals(r.value, null);
    assertEquals(r.result.status, 'held');
    assertEquals(m.rpcs.filter((f) => f === 'fn_reason_hold').length, 1);
  });
}
