// modelSays with a stubbed model. No network, no paid call. Rulings 1195-1197: the words are the model's; code hands
// over what happened as facts, and when no model answers the result is '' (the caller sends nothing).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { modelSays } from './model_says.ts';
import type { LlmReply, ThinkDeps } from '../_shared/think.ts';

function stub(answers: (string | null)[]) {
  const calls: { system: string; input: string; o: Record<string, unknown> }[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    llm: (_p: string, system: string, input: string, o: Record<string, unknown>) => {
      calls.push({ system, input, o });
      const a = answers.shift();
      return Promise.resolve((a == null ? { content: null, error: 'down' } : { content: a, model: 'stub' }) as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }),
  } as unknown as ThinkDeps;
  return { deps, calls };
}
const A = (answer: string) => JSON.stringify({ answer });

Deno.test('the routine result reaches the model as facts and the model writes the reply', async () => {
  const s = stub([A('Done: your quotation for the ZZ DEMO job is now AED 9,000.')]);
  const r = await modelSays(s.deps, { audience: 'supplier', lang: 'ar', message: 'make it 9000', situation: 'pricing routine: {"ok":true,"old":10000,"new":9000}',
    subject: { fixture: true, phone: '+971500000021' } });
  assertEquals(r.text, 'Done: your quotation for the ZZ DEMO job is now AED 9,000.');
  assert(s.calls[0].system.includes('"new":9000'), 'the routine result is in the facts');
  assert(s.calls[0].system.includes('suppliers are always answered in English'), 'a supplier is answered in English even when they wrote Arabic');
  assertEquals((s.calls[0].o.subject as Record<string, unknown>).fixture, true, 'a ZZ DEMO turn is tagged for the rehearsal window');
});

Deno.test('no model answers: the text is empty — never a canned sentence', async () => {
  const s = stub([null, null, null, null]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'hi', situation: 'greet them' });
  assertEquals(r.text, '');
  assert(s.calls.length >= 2, 'the backup model was asked too: ' + r.attempts.join(','));
});

Deno.test('a thrown model is the same as no model: empty, nothing invented', async () => {
  const deps = { gate: () => Promise.resolve(null), llm: () => { throw new Error('boom'); }, embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }) } as unknown as ThinkDeps;
  assertEquals((await modelSays(deps, { audience: 'visitor', lang: 'en', message: 'x', situation: 'y' })).text, '');
});
