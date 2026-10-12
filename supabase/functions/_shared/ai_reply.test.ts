// aiReply() with a stubbed model. No network, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert';
import { aiReply } from './ai_reply.ts';
import type { LlmReply, ThinkDeps } from './think.ts';

const COMPANY = 'REVEAL FEE: the customer pays 3.00% of the selected quotation value. No card fee is added.';
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
    rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: COMPANY } : null, error: null }),
  } as unknown as ThinkDeps;
  return { deps, calls };
}
const A = (answer: string, action?: string) => JSON.stringify({ answer, ...(action ? { action } : {}) });
const req = { seat: 'customer_support' as const, channel: 'email', audience: 'customer' as const, lang: 'en' as const, message: 'What is the reveal fee?' };

// prevented by: this test. The brief is given, the model writes the reply, a wrong figure is rewritten BY THE MODEL,
// and when no model answers the reply is '' — code never supplies text.
Deno.test('the model writes the reply from the brief', async () => {
  const s = stub([A('The reveal fee is 3% of the quote you choose, and no card fee is added.')]);
  const r = await aiReply(s.deps, req);
  assertEquals(r.reply, 'The reveal fee is 3% of the quote you choose, and no card fee is added.');
  assert(s.calls[0].system.includes(COMPANY), 'the company brief is in the system prompt');
});
Deno.test('a figure the brief does not state is rewritten by the model', async () => {
  const s = stub([A('The reveal fee is 5%.'), A('The reveal fee is 3%.')]);
  const r = await aiReply(s.deps, req);
  assertEquals(r.reply, 'The reveal fee is 3%.');
  assert(s.calls[1].input.includes('the figure 5'));
});
Deno.test('a reply that names our machinery is rewritten, never replaced with a canned line', async () => {
  const s = stub([A('Sorry, circuit_open from openrouter.'), A('The reveal fee is 3%.')]);
  assertEquals((await aiReply(s.deps, req)).reply, 'The reveal fee is 3%.');
});
Deno.test('the model ladder: route, then another family; nothing answers -> no text', async () => {
  const s1 = stub([null, A('The reveal fee is 3%.')]);
  const r1 = await aiReply(s1.deps, req);
  assertEquals(r1.reply, 'The reveal fee is 3%.');
  assert('counterpartModel' in s1.calls[1].o);
  const r2 = await aiReply(stub([null, null]).deps, req);
  assertEquals(r2.reply, '');
});
Deno.test('suppliers are answered in English; an action is picked from the list only', async () => {
  const s = stub([A('Registration is free for the first 1000 suppliers.', 'escalate'), A('ok', 'bogus')]);
  const r = await aiReply(s.deps, { ...req, audience: 'supplier', lang: 'ar', actions: [{ id: 'escalate', meaning: 'pass to the CEO' }] });
  assertEquals(r.action, 'escalate');
  assert(s.calls[0].system.includes('UAE English'));
  const r2 = await aiReply(stub([A('Done.', 'bogus')]).deps, { ...req, actions: [{ id: 'escalate', meaning: 'x' }] });
  assertEquals(r2.action, null);
});
