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
  const r = await modelSays(s.deps, { audience: 'supplier', lang: 'ar', message: 'make it 9000', situation: 'They asked to change their quotation price to AED 9000. pricing routine: {"ok":true,"old":10000,"new":9000}',
    subject: { fixture: true, phone: '+971500000021' } });
  assertEquals(r.text, 'Done: your quotation for the ZZ DEMO job is now AED 9,000.');
  // the facts ride in the turn itself, after the cached conversation (chat_history.ts, 18 Oct 2026), not in the system prompt
  assert(s.calls[0].input.includes('"new":9000'), 'the routine result is in the facts');
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

import { HELD_NOTICE, holdUnwritten, UNWRITTEN_SURFACE } from './model_says.ts';
Deno.test('no model: the held notice is sent (supplier in English) and the turn is filed for a model retry', async () => {
  const sent: string[] = []; const filed: Record<string, unknown>[] = [];
  const r = await holdUnwritten({ from: 'whatsapp:+971500000021', body: 'ZZ DEMO: هل تدفعون عمولة؟', messageSid: 'SMzz', audience: 'supplier', lang: 'ar',
    situation: 'a supplier asked about commission', why: 'no_model_answer', enabled: () => Promise.resolve(true),
    send: (t) => { sent.push(t); return Promise.resolve({ ok: true }); },
    rpc: (fn, a) => { filed.push({ fn, ...a }); return Promise.resolve({ data: 7, error: null }); } });
  assertEquals(sent, [HELD_NOTICE.en]);
  assertEquals(r.held_id, 7);
  assertEquals(filed[0].fn, 'fn_reason_hold');
  assertEquals(filed[0].p_surface, UNWRITTEN_SURFACE);
  assertEquals((filed[0].p_subject as Record<string, unknown>).phone, 'whatsapp:+971500000021');
  assert(String((filed[0].p_request as Record<string, unknown>).question).includes('a supplier asked about commission'));
});

Deno.test('the rate key reaches the gateway call, and the model\'s escalate flag comes back', async () => {
  const s = stub([JSON.stringify({ answer: 'I am sorry about this. Your payment is recorded against your request, and a person from our team now has your message and will contact you here today to resolve it with you. If you would like to speak to someone straight away, call or WhatsApp us on the number below during working hours.', escalate: true })]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'ZZ DEMO: you took my money and vanished', situation: 'a complaint', rateKey: 'wa:whatsapp:+971500000021' });
  assertEquals(s.calls[0].o.rateKey, 'wa:whatsapp:+971500000021');
  assertEquals(r.escalate, true);
});
