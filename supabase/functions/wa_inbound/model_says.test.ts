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
Deno.test('OpenRouter down: the held notice is sent (supplier in English) and the turn is filed for a model retry', async () => {
  const sent: string[] = []; const filed: Record<string, unknown>[] = [];
  const r = await holdUnwritten({ from: 'whatsapp:+971500000021', body: 'ZZ DEMO: هل تدفعون عمولة؟', messageSid: 'SMzz', audience: 'supplier', lang: 'ar',
    situation: 'a supplier asked about commission', why: 'no_model_answer', outage: true, enabled: () => Promise.resolve(true),
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

// prevented by: this test. Run 5 (qd_run:321d13ae, agent_runs 3793567) held a WhatsApp turn 73.7 s in serial model
// calls and still ended llm_failed. A hanging model now costs at most the reply budget: each call is given only the
// time left (never more than PER_CALL_MS), no call starts with under MIN_CALL_MS left, and the result is '' so the
// caller sends the held notice and queues the turn.
Deno.test('a hanging model ends the reply inside its budget, each call given only the time left', async () => {
  const timeouts: number[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    // the gateway honours the caller's timeout: it hangs until then and answers nothing
    llm: (_p: string, _s: string, _i: string, o: Record<string, unknown>) => {
      timeouts.push(Number(o.timeoutMs));
      return new Promise<LlmReply>((res) => setTimeout(() => res({ content: null, error: 'timeout' } as LlmReply), Number(o.timeoutMs)));
    },
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }),
  } as unknown as ThinkDeps;
  const r = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'how long does installation take?', situation: 'facts', budgetMs: 9_000 });
  assertEquals(r.text, '', 'no model answered: the caller sends the held notice');
  assert(r.ms < 10_000, `the turn took ${r.ms} ms against a 9 s budget`);
  assertEquals(timeouts.length, 1, 'no second call starts with under MIN_CALL_MS left');
  assert(timeouts[0] <= 9_000, `the call was given ${timeouts[0]} ms, more than the budget`);
  assert(r.attempts.some((a) => a.startsWith('deadline')), 'the attempts say the clock ran out: ' + r.attempts.join(','));
});

Deno.test('the default WhatsApp budget caps a reply call at 25 s', async () => {
  const s = stub([A('Installation of aluminium windows on a villa usually takes a few days, depending on the area.')]);
  const r = await modelSays(s.deps, { audience: 'customer', lang: 'en', message: 'how long?', situation: 'facts' });
  assert(r.text.length > 0);
  assert(Number(s.calls[0].o.timeoutMs) <= 25_000, 'a reply call keeps no more than 25 s');
});

Deno.test('the 45 s clock runs from arrival: time spent before the model call is taken off the budget', async () => {
  const { budgetLeft, WA_REPLY_BUDGET_MS, WA_SEND_MARGIN_MS } = await import('./model_says.ts');
  assertEquals(budgetLeft(1_000, 1_000), WA_REPLY_BUDGET_MS - WA_SEND_MARGIN_MS);
  assertEquals(budgetLeft(0, 30_000), WA_REPLY_BUDGET_MS - WA_SEND_MARGIN_MS - 30_000);
  assertEquals(budgetLeft(0, 90_000), 0);   // the budget is spent: no call starts and the turn is queued
  assertEquals(budgetLeft(0, 50_000), WA_REPLY_BUDGET_MS - WA_SEND_MARGIN_MS - 50_000);   // a 50 s routing still leaves the reply its time
});

Deno.test('no budget left: no model call starts and the text is empty, so the caller sends the held notice', async () => {
  const { deps, calls } = stub(['{"reply":"late answer"}']);
  const said = await modelSays(deps, { audience: 'customer', lang: 'en', message: 'hi', situation: 'x', budgetMs: 0 });
  assertEquals(calls.length, 0);
  assertEquals(said.text, '');
});

// founder_instruction 1339 (27 Oct 2026): "the engineer and customer support never replies without llm unless the server of
// open router is down". A model that answered and was refused: the turn is filed for the model, NO fixed notice goes out.
Deno.test('1339: model up, nothing safe to send: no code-written notice, the turn is still filed for the model', async () => {
  const sent: string[] = []; const filed: Record<string, unknown>[] = [];
  const r = await holdUnwritten({ from: 'whatsapp:+971500000022', body: 'ZZ DEMO: question', messageSid: 'SMzy', audience: 'customer', lang: 'en',
    situation: 'a customer asked a question', why: 'guard_refused', outage: false, enabled: () => Promise.resolve(true),
    send: (t) => { sent.push(t); return Promise.resolve({ ok: true }); },
    rpc: (fn, a) => { filed.push({ fn, ...a }); return Promise.resolve({ data: 8, error: null }); } });
  assertEquals(sent, [], 'a code-written notice went out while the model was up');
  assertEquals(r.notice, '');
  assertEquals(r.held_id, 8);
  assertEquals(filed[0].fn, 'fn_reason_hold');
});
Deno.test('1339: modelSays reports an outage only when no call reached a model', async () => {
  const mk = (res: unknown) => ({ gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }), llm: () => Promise.resolve(res) }) as unknown as ThinkDeps;
  assertEquals((await modelSays(mk({ content: null, error: 'gateway_http_502' }), { audience: 'visitor', lang: 'en', message: 'x', situation: 'y' })).outage, true);
  assertEquals((await modelSays(mk({ content: JSON.stringify({ answer: 'openrouter circuit_open' }), model: 'm' }), { audience: 'visitor', lang: 'en', message: 'x', situation: 'y' })).outage, false);
});
