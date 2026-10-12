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
  const s = stub([A('The reveal fee is 3% of the quote you choose; no card fee is added and no VAT is charged on it.')]);
  const r = await aiReply(s.deps, req);
  assertEquals(r.reply, 'The reveal fee is 3% of the quote you choose; no card fee is added and no VAT is charged on it.');
  assert(s.calls[0].system.includes(COMPANY), 'the company brief is in the system prompt');
});
Deno.test('a figure the brief does not state is rewritten by the model', async () => {
  const s = stub([A('The reveal fee is 5%.'), A('The reveal fee is 3%, with no card fee and no VAT.')]);
  const r = await aiReply(s.deps, req);
  assertEquals(r.reply, 'The reveal fee is 3%, with no card fee and no VAT.');
  assert(s.calls[1].input.includes('the figure 5'));
});
Deno.test('a reply that names our machinery is rewritten, never replaced with a canned line', async () => {
  const s = stub([A('Sorry, circuit_open from openrouter.'), A('The reveal fee is 3%, with no card fee and no VAT.')]);
  assertEquals((await aiReply(s.deps, req)).reply, 'The reveal fee is 3%, with no card fee and no VAT.');
});
Deno.test('the model ladder: route, then another family; nothing answers -> no text', async () => {
  const s1 = stub([null, A('The reveal fee is 3%, with no card fee and no VAT.')]);
  const r1 = await aiReply(s1.deps, req);
  assertEquals(r1.reply, 'The reveal fee is 3%, with no card fee and no VAT.');
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

// prevented by: these tests (#1335's needs, 12 Oct 2026). Identity before a reveal, deferrals, the call cap, the
// escalation flag and the sender's rate bucket.
Deno.test('another party identity or an unpublished contact is rewritten; the published contact passes', async () => {
  const s = stub([A('The supplier is Al Noor Contracting, call 050 123 4567.'), A('Your supplier stays anonymous until you reveal them. Call us on +971 50 931 9355.')]);
  const r = await aiReply(s.deps, { ...req, forbidden: ['Al Noor Contracting'] });
  assertEquals(r.reply, 'Your supplier stays anonymous until you reveal them. Call us on +971 50 931 9355.');
  assert(s.calls[1].input.includes("reveals another party's identity") && s.calls[1].input.includes('contact or licence details'));
});
Deno.test('a deferral is rewritten (903)', async () => {
  const s = stub([A("I'll check and get back to you."), A('The reveal fee is 3%, with no card fee and no VAT.')]);
  assertEquals((await aiReply(s.deps, req)).reply, 'The reveal fee is 3%, with no card fee and no VAT.');
});
Deno.test('at most 4 model calls per reply, then no text', async () => {
  const s = stub([A('5% fee.'), A('5% fee.'), A('5% fee.'), A('5% fee.'), A('5% fee.'), A('5% fee.')]);
  const r = await aiReply(s.deps, req);
  assertEquals(r.reply, '');
  assertEquals(s.calls.length, 4);
});
Deno.test('escalate and the rate bucket ride on the same call', async () => {
  const s = stub([JSON.stringify({ answer: 'Your refund request is now with our management team.', escalate: true })]);
  const r = await aiReply(s.deps, { ...req, askEscalate: true, rateKey: 'wa:+971500000001' });
  assertEquals(r.escalate, true);
  assertEquals(s.calls[0].o.rateKey, 'wa:+971500000001');
});
