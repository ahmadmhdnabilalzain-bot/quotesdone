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
  // founder ruling 1219: the reply class (Sonnet 5.5 > Gemini) and the brief as the cached sys_stable prefix
  assert(String(s.calls[0].o.sysStable).includes(COMPANY), 'the company brief rides as the cacheable sys_stable block');
  assert(!s.calls[0].system.includes(COMPANY), 'the varying half does not repeat the brief');
  assertEquals(s.calls[0].o.taskClass, 'conversation_reply');
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

// prevented by: this test (sales_engineer, 13 Oct 2026). The knowledge block (BRIEF_TEXT) is in every brief, and its
// regulation digests state a 5% VAT; a wrong 5% reveal fee must still be refused.
Deno.test('the knowledge block never licenses a fee figure', async () => {
  const { BRIEF_TEXT } = await import('./brief.generated.ts');
  assert(BRIEF_TEXT.includes('5%'), 'precondition: the knowledge block states a 5% figure');
  const s = stub([A('The reveal fee is 5%.'), A('The reveal fee is 3%, with no card fee and no VAT.')]);
  assertEquals((await aiReply(s.deps, req)).reply, 'The reveal fee is 3%, with no card fee and no VAT.');
  const stable = String(s.calls[0].o.sysShared ?? '') + String(s.calls[0].o.sysStable ?? '');
  assert(stable.includes('# Conversation playbook:') && stable.includes('How you hold a conversation'), 'the playbooks ride in the cached blocks (sys_shared)');
  assert(!s.calls[0].system.includes('# Conversation playbook:'), 'and not again in the varying sys');
});

// prevented by: these tests (review of #1382). The style is sent once (inside BRIEF_TEXT), and nothing written only in
// the knowledge block -- a figure, a licence-like number -- is licensed by it.
Deno.test('the conversation style reaches the model exactly once (sys_shared + sys_stable + sys)', async () => {
  const { CONVERSATION_STYLE } = await import('./brief.generated.ts');
  const s = stub([A('The reveal fee is 3%, with no card fee and no VAT.')]);
  await aiReply(s.deps, req);
  const whole = String(s.calls[0].o.sysShared ?? '') + String(s.calls[0].o.sysStable ?? '') + s.calls[0].system;
  assertEquals(whole.split(CONVERSATION_STYLE.slice(0, 60)).length - 1, 1);
});
Deno.test('a licence number that only the knowledge block states is still refused', async () => {
  const s = stub([A('Our trade licence is 1633275.'), A('The reveal fee is 3%, with no card fee and no VAT.')]);
  assertEquals((await aiReply(s.deps, req)).reply, 'The reveal fee is 3%, with no card fee and no VAT.');
});

// prevented by: this test (13 Oct 2026). Every reply sends the knowledge block as the shared cached block, the rest of
// the brief as the stable one, on the 1-hour tier; the reply language is in the uncached system text.
Deno.test('the knowledge block rides as the shared cached block on the 1-hour tier, the language after it', async () => {
  const { BRIEF_TEXT } = await import('./brief.generated.ts');
  const s = stub([A('هذا رد.')]);
  await aiReply(s.deps, { ...req, lang: 'ar' });
  assertEquals(s.calls[0].o.sysShared, BRIEF_TEXT);
  assertEquals(s.calls[0].o.cacheTtl, '1h');
  assert(!String(s.calls[0].o.sysStable).includes(BRIEF_TEXT));
  assert(s.calls[0].system.includes('Arabic') && !String(s.calls[0].o.sysStable).includes('Gulf Arabic'));
});
