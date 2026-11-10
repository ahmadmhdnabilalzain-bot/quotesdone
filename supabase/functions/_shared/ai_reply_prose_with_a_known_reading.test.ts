// aiReply: a finished prose first draft is the reply when the CALLER already read whether a person is needed (it_engineer,
// 10 Nov 2026, WhatsApp latency R4/R5; the reasoning is in ai_reply.ts's header). Stubbed model, no network, no paid call.
// Red before escalateReading existed: the prose draft was asked again for the object (a second ~80k-token call).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { aiReply } from './ai_reply.ts';
import type { LlmReply, ThinkDeps } from './think.ts';

function stub(answers: string[]) {
  const calls: string[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    llm: (_p: string, _s: string, input: string) => { calls.push(input); return Promise.resolve({ content: answers.shift() ?? null, model: 'stub' } as LlmReply); },
    embed: () => Promise.resolve(null),
    rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_ai_route' ? { model: 'openai/gpt-6-luna-pro' } : null, error: null }),
  } as unknown as ThinkDeps;
  return { deps, calls };
}
const PROSE = 'Yes, we cover glass balustrades across the UAE, so you can send your request here at any time.';
const req = { seat: 'customer_support' as const, channel: 'whatsapp', audience: 'customer' as const, lang: 'en' as const, message: 'Do you cover glass balustrades?', askEscalate: true };

Deno.test('a known reading: the prose first draft is the reply, in one call, carrying the reading as its escalate answer', async () => {
  for (const reading of [false, true]) {
    const s = stub([PROSE, JSON.stringify({ answer: 'object form', escalate: false })]);
    const r = await aiReply(s.deps, { ...req, escalateReading: () => Promise.resolve(reading) });
    assertEquals(r.reply, PROSE);
    assertEquals(s.calls.length, 1, 'no second call to wrap the prose in JSON');
    assertEquals(r.escalate, reading, 'the escalate answer is the caller\'s reading');
  }
});

Deno.test('known-bad control: with no reading (null, or none given) the prose is still asked again for the object (#1816)', async () => {
  for (const escalateReading of [() => Promise.resolve(null), undefined]) {
    const s = stub([PROSE, JSON.stringify({ answer: PROSE, escalate: true })]);
    const r = await aiReply(s.deps, { ...req, ...(escalateReading ? { escalateReading } : {}) });
    assertEquals(s.calls.length, 2);
    assertEquals(r.escalate, true, 'the object\'s own flag is kept');
  }
});

Deno.test('an action caller never takes prose on a reading: an action is the draft\'s own choice', async () => {
  const s = stub([PROSE, JSON.stringify({ answer: PROSE, action: 'none' })]);
  await aiReply(s.deps, { ...req, actions: [{ id: 'none', meaning: 'nothing' }], escalateReading: () => Promise.resolve(false) });
  assert(s.calls.length >= 2);
});
