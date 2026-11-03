// aiReply() with a stubbed model. No network, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert';
import { aiReply, aiSystem, proseOf } from './ai_reply.ts';
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
  const s = stub([A('The supplier is Al Noor Contracting, call 050 123 4567.'), A('Your supplier stays anonymous until you reveal them. Call us on +1 218 316 6814.')]);
  const r = await aiReply(s.deps, { ...req, forbidden: ['Al Noor Contracting'] });
  assertEquals(r.reply, 'Your supplier stays anonymous until you reveal them. Call us on +1 218 316 6814.');
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

// prevented by: this test. Run c89dc272 (WhatsApp, 18 Oct 2026): conversation_reply came back ok and the customer got
// the held notice, because an answer wrapped in a fence with surrounding newlines, or after a lead-in sentence, did
// not JSON.parse and read as "no model answered". Each shape below must yield the answer on the FIRST call.
Deno.test('an ok answer in a fence, with newlines or a lead-in sentence, is used, not discarded', async () => {
  const body = 'Installation of aluminium windows on a villa usually takes a few days, depending on the area.';
  for (const content of [
    '\n```json\n' + A(body) + '\n```\n',
    'Here is my reply:\n' + A(body),
    '  ' + A(body) + '\n',
  ]) {
    const s = stub([content]);
    const r = await aiReply(s.deps, req);
    assertEquals(r.reply, body, 'discarded: ' + JSON.stringify(content));
    assertEquals(s.calls.length, 1, 'no second model was asked for an answer we already had');
  }
});
Deno.test('an answer cut at the output cap is still refused, never sent half-written', async () => {
  const s = stub(['{"answer":"Installation usually takes a few days, depending on', null, null, null]);
  assertEquals((await aiReply(s.deps, req)).reply, '');
  assertEquals(s.calls[0].o.max, 900);
});

// founder_instruction 1339 (27 Oct 2026): "the engineer and customer support never replies without llm unless the server of
// open router is down". `outage` is the only licence a caller has to send code-written text; it must be true only when no
// call reached a model. A model that answered keeps its own safe sentences (salvage); `must` text is required exactly.
Deno.test('1339: outage only when every call failed at the provider; a refused answer is not an outage', async () => {
  const down = await aiReply(stub([]).deps, req);   // every call: { content: null, error: 'down' } — not an outage word
  assertEquals(down.outage, false, "'down' is not an outage signal; only the provider's own failure is");
  const s = stub([]);
  (s.deps as { llm: unknown }).llm = () => Promise.resolve({ content: null, error: 'gateway_http_502' } as LlmReply);
  const r502 = await aiReply(s.deps, req);
  assertEquals([r502.reply, r502.outage], ['', true]);
  (s.deps as { llm: unknown }).llm = () => Promise.resolve({ content: null, error: 'client_timeout_30000ms' } as LlmReply);
  assertEquals((await aiReply(s.deps, req)).outage, true);
  const refused = await aiReply(stub([A('5% fee.'), A('5% fee.'), A('5% fee.'), A('5% fee.')]).deps, req);
  assertEquals([refused.reply, refused.outage], ['', false], 'the model answered: no code-written fallback is licensed');
});
Deno.test("1339: the model's own safe sentences are kept when no whole draft passes; code adds no word", async () => {
  const bad = A('The reveal fee is 3% of the quote you choose, with no card fee and no VAT. Our system runs on openrouter.');
  const r = await aiReply(stub([bad, bad, bad, bad]).deps, req);
  assertEquals(r.reply, 'The reveal fee is 3% of the quote you choose, with no card fee and no VAT.');
  assert(r.attempts.some((a) => a.startsWith('salvaged')));
});
Deno.test('1339: must-carry text (a case reference) is rewritten in when the draft leaves it out', async () => {
  const s = stub([A('Thank you, your problem is logged and our team will look at it.'), A('Thank you, your problem is logged under reference QD-C-0042; our team will look at it.')]);
  const r = await aiReply(s.deps, { ...req, must: ['QD-C-0042'] });
  assertEquals(r.reply, 'Thank you, your problem is logged under reference QD-C-0042; our team will look at it.');
  assert(s.calls[1].input.includes('QD-C-0042'));
});

// customer_support, 2 Nov 2026: a speculative WhatsApp draft that was discarded is aborted: the signal reaches the model call, and once
// aborted no call starts (no rewrite, no counterpart rung), so a discarded draft costs nothing more.
Deno.test('a signal reaches the model call; an aborted request starts no call', async () => {
  const ac = new AbortController();
  const s = stub([A('The reveal fee is 3% of the quote you choose; no card fee is added and no VAT is charged on it.')]);
  await aiReply(s.deps, { ...req, signal: ac.signal });
  assertEquals(s.calls[0].o.signal, ac.signal);
  ac.abort();
  const t = stub([A('x')]);
  const r = await aiReply(t.deps, { ...req, signal: ac.signal });
  assertEquals(t.calls.length, 0); assertEquals(r.reply, '');
});

// Run 41540859092: Sonnet answered "Sorry to hear that. AC repair is covered, ..." as plain text, no JSON; the parser read ''
// and the turn paid a 278k-token other-family call. Plain prose is the answer now; an object cut off mid-answer still is not.
Deno.test('a reply written as plain prose is the reply; a cut-off object is still refused', async () => {
  const mk = (answers: string[]) => {
    const calls: string[] = [];
    const deps = { gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
      llm: () => { const a = answers.shift() ?? null; calls.push(String(a)); return Promise.resolve({ content: a, model: 'stub' } as LlmReply); } } as unknown as ThinkDeps;
    return { deps, calls };
  };
  const prose = mk(['Sorry to hear that. AC repair is a trade our suppliers cover; describe the job and the unit and we will send it to them.']);
  const r = await aiReply(prose.deps, { seat: 'customer_support', channel: 'whatsapp', audience: 'customer', lang: 'en', message: 'ZZ DEMO my AC is broken' });
  assert(r.reply.startsWith('Sorry to hear that.'), 'prose read as the reply: ' + r.attempts.join(' | '));
  assertEquals(prose.calls.length, 1, 'no second rung');
  const cut = mk(['{"answer":"Sorry to hear that. AC repair is', '{"answer":"Sorry to hear that. AC repair is', '{"answer":"Sorry', '{"answer":"Sorry']);
  const r2 = await aiReply(cut.deps, { seat: 'customer_support', channel: 'whatsapp', audience: 'customer', lang: 'en', message: 'ZZ DEMO my AC is broken' });
  assertEquals(r2.reply, '', 'control: a cut-off object is never sent');
});

// Review of #1816. Prose carries no action and no escalate flag, so it is the reply only when neither is asked for; otherwise
// the same rung is asked again for the object. Each assertion fails on 3e756c6c (prose taken as the reply in every case).
const mkRec = (answers: string[]) => {
  const systems: string[] = []; const opts: Record<string, unknown>[] = [];
  const deps = { gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
    llm: (_p: string, sys: string, _i: string, o: Record<string, unknown>) => { systems.push(sys); opts.push(o); return Promise.resolve({ content: answers.shift() ?? null, model: 'stub' } as LlmReply); } } as unknown as ThinkDeps;
  return { deps, systems, opts };
};
Deno.test('the supplier quotation chat (actions): a prose "Done, submitted" is not the reply; the object is asked for on the same rung', async () => {
  const s = mkRec(['Done, your quotation has been submitted to the customer.',
    JSON.stringify({ answer: 'Your quotation is complete. Shall I submit it to the customer now?', action: 'none' })]);
  const r = await aiReply(s.deps, { seat: 'sales_engineer', channel: 'portal', audience: 'supplier', lang: 'en', message: 'ZZ DEMO submit it',
    actions: [{ id: 'submit', meaning: 'submit the quotation' }, { id: 'none', meaning: 'nothing to do yet' }] });
  assert(!r.reply.startsWith('Done'), 'the prose was not taken: ' + r.attempts.join(' | '));
  assertEquals(r.action, 'none');
  assertEquals(s.opts.length, 2);
  assertEquals(s.opts[1].counterpartModel, undefined, 'asked again on the same rung, not the other family');
});
Deno.test('WhatsApp (askEscalate): a prose answer is not the reply; the rewrite brings the escalate flag', async () => {
  const s = mkRec(['I am sorry this happened. Please reach our team on +1 218 316 6814 and we will look into it.',
    JSON.stringify({ answer: 'I am sorry this happened. Please reach our team on +1 218 316 6814 and we will look into it.', escalate: true })]);
  const r = await aiReply(s.deps, { seat: 'customer_support', channel: 'whatsapp', audience: 'customer', lang: 'en', message: 'ZZ DEMO you took my money', askEscalate: true });
  assert(r.reply.includes('+1 218 316 6814'), r.attempts.join(' | '));
  assertEquals(r.escalate, true, 'the model flag survives (it is OR-ed with the router)');
  assert(r.attempts[0].startsWith('route:prose'), r.attempts.join(' | '));
});
Deno.test('prose that is a preamble, meta-text, a trailing key or cut off is never a reply; a finished one is', () => {
  assertEquals(proseOf("Here's my reply: Thank you for your message."), '');
  assertEquals(proseOf('Answer: Thank you for your message.'), '');
  assertEquals(proseOf('The user is asking about fees, so I should explain them.'), '');
  assertEquals(proseOf('The customer is asking about a refund.'), '');
  assertEquals(proseOf('Thank you for your message. escalate: true'), '');
  assertEquals(proseOf('Thank you for your message. Our suppliers cover AC repair and you can'), '', 'cut at the token cap');
  assertEquals(proseOf('Thank you. Reach a person on:'), '');
  assertEquals(proseOf('Thank you for your message. Reach our team any time.'), 'Thank you for your message. Reach our team any time.');
  assert(proseOf('Our team will help you.\nmanagement@quotesdone.com') !== '', 'a reply ending on its own contact line is finished');
});
Deno.test('the brief-less ask is told to state no company fact beyond its facts, and is not pushed to answer everything', () => {
  const r = { seat: 'customer_support' as const, channel: 'whatsapp', audience: 'customer' as const, lang: 'en' as const, message: 'x' };
  const lean = aiSystem({ ...r, briefInPrompt: false }, 'en'); const full = aiSystem(r, 'en');
  assert(lean.includes('You do NOT have the company brief'), lean);
  assert(!lean.includes('never say you do not know'), 'no pressure to answer what the facts do not cover');
  assert(full.includes('never say you do not know') && full.includes('COMPANY BRIEF'), 'control: the full prompt is unchanged');
});
