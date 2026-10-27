// answerFromBrief() against a fake gateway (SSE stream and JSON). No network, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert';
import { answerFromBrief, callBudget, MIN_CALL_MS, PER_CALL_MS, RESERVE_MS, type BriefCall } from './brief_answer.ts';

const C: BriefCall = { gateway: 'https://gw', secret: 's', fn: 'site_assistant', agent: 'customer_support', taskClass: 'visitor_chat',
  brief: 'The customer pays a 3% reveal fee. No card fee is added.', sys: 'rules', input: [{ role: 'user', content: 'what is the fee?' }], max: 500 };

const sse = (chunks: string[]) => new Response(new ReadableStream({ start(c) {
  for (const t of chunks) c.enqueue(new TextEncoder().encode('data: ' + JSON.stringify({ choices: [{ delta: { content: t } }] }) + '\n\n'));
  c.enqueue(new TextEncoder().encode('data: [DONE]\n\n')); c.close();
} }), { headers: { 'content-type': 'text/event-stream', 'x-qd-model': 'openai/gpt-6-luna' } });
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });

function gateway(replies: Response[]) {
  const bodies: Record<string, unknown>[] = [];
  const f = ((_u: string, init: RequestInit) => { bodies.push(JSON.parse(String(init.body))); return Promise.resolve(replies.shift() ?? json({ error: 'no more' }, 502)); }) as typeof fetch;
  return { f, bodies };
}

// prevented by: this test. One call, streamed: each checked sentence is emitted as it is written, the brief rides as
// sys_stable (the cacheable prefix), the model is always asked (try_faq false) and nothing is replayed (cache 0).
Deno.test('a correct answer streams sentence by sentence from one call', async () => {
  const g = gateway([sse(['The reveal fee ', 'is 3% of the quote. ', 'No card fee is added, and no VAT.'])]);
  const shown: string[] = [];
  const a = await answerFromBrief(C, (t) => shown.push(t), g.f);
  assertEquals(shown, ['The reveal fee is 3% of the quote. ', 'No card fee is added, and no VAT.']);
  assertEquals(a.reply, 'The reveal fee is 3% of the quote. No card fee is added, and no VAT.');
  assertEquals(g.bodies.length, 1);
  assertEquals([g.bodies[0].stream, g.bodies[0].sys_stable, g.bodies[0].try_faq, g.bodies[0].cache_ttl_min], [true, C.brief, false, 0]);
});

// prevented by: this test. A figure the brief does not state is never shown: the stream stops at that sentence and the
// MODEL rewrites with the correction named; code substitutes no text.
Deno.test('a wrong figure stops the stream and the model rewrites the answer', async () => {
  const g = gateway([sse(['Comparing quotes is free. ', 'The reveal fee is 5% of the quote. ', 'More text.']), json({ content: 'Comparing is free. The reveal fee is 3% of the quote you choose, with no card fee and no VAT.', model: 'openai/gpt-6-luna' })]);
  const shown: string[] = [];
  const a = await answerFromBrief(C, (t) => shown.push(t), g.f);
  assertEquals(shown, ['Comparing quotes is free. ']);
  assertEquals(a.reply, 'Comparing is free. The reveal fee is 3% of the quote you choose, with no card fee and no VAT.');
  assertEquals(a.rewrites, 1);
  const fix = (g.bodies[1].input as { content: string }[]).at(-1)!.content;
  assert(fix.includes('5') && /figure/.test(fix), 'the rewrite request names the figure');
});

Deno.test('a failed model climbs the ladder: unstreamed, then a counterpart of another family; none answers -> no text', async () => {
  const g1 = gateway([json({ error: 'all_models_failed' }, 502), json({ content: 'The reveal fee is 3%, with no card fee and no VAT.', model: 'google/gemini-3.8-flash' })]);
  const a1 = await answerFromBrief(C, () => {}, g1.f);
  assertEquals(a1.reply, 'The reveal fee is 3%, with no card fee and no VAT.');
  const g2 = gateway([json({ error: 'x' }, 502), json({ error: 'x' }, 502), json({ error: 'x' }, 502)]);
  const a2 = await answerFromBrief(C, () => {}, g2.f);
  assertEquals(a2.reply, '');
  assert(a2.error);
  assert('counterpart_model' in g2.bodies[2], 'the third call is routed to another family');
});

Deno.test('the caller rule (reply guard) is part of the check', async () => {
  const g = gateway([sse(['Our AI answers that. ']), json({ content: 'Our Smart Engine answers that.' })]);
  const a = await answerFromBrief({ ...C, check: (t) => /\bAI\b/.test(t) ? ['it says AI'] : [] }, () => {}, g.f);
  assertEquals(a.reply, 'Our Smart Engine answers that.');
});

// prevented by: this test (zero tolerance). A whole reply that states the reveal fee but not "no card fee / no VAT"
// is rewritten by the model once it is complete; the widget then replaces what it showed (reset).
Deno.test('a reveal fee stated without "no card fee, no VAT" is rewritten after the stream', async () => {
  const g = gateway([sse(['The reveal fee is 3% of the quote. ']), json({ content: 'The reveal fee is 3% of the quote, with no card fee and no VAT.' })]);
  const a = await answerFromBrief(C, () => {}, g.f);
  assertEquals(a.reply, 'The reveal fee is 3% of the quote, with no card fee and no VAT.');
  assertEquals(a.rewrites, 1);
  assert(/no card fee/.test((g.bodies[1].input as { content: string }[]).at(-1)!.content));
});

// prevented by: this test (live photo test, 13 Oct 2026). A reply cut off by the output limit is never shown as finished:
// the unfinished tail is held back and the model writes the whole answer again; a truncated retry is never used.
Deno.test('a cut-off stream is rewritten, and a truncated answer is never used', async () => {
  const cut = new Response(new ReadableStream({ start(c) {
    c.enqueue(new TextEncoder().encode('data: ' + JSON.stringify({ choices: [{ delta: { content: 'I can see an old plan. There are no dimensions or' } }] }) + '\n\n'));
    c.enqueue(new TextEncoder().encode('data: ' + JSON.stringify({ choices: [{ delta: { content: '' }, finish_reason: 'length' }] }) + '\n\n'));
    c.close();
  } }), { headers: { 'content-type': 'text/event-stream' } });
  const shown: string[] = [];
  const g = gateway([cut, json({ content: 'I can see an old plan without dimensions. Please send them.' })]);
  const a = await answerFromBrief(C, (t) => shown.push(t), g.f);
  assertEquals(shown, ['I can see an old plan. ']);
  assertEquals(a.reply, 'I can see an old plan without dimensions. Please send them.');
  const g2 = gateway([json({ error: 'x' }, 502), json({ content: 'Half an ans', truncated: true }), json({ content: 'A whole answer.' })]);
  assertEquals((await answerFromBrief(C, () => {}, g2.f)).reply, 'A whole answer.');
});

// prevented by: this test. A rate-limited sender is not retried on other models; the caller shows its notice.
Deno.test('a rate-limited sender stops at once', async () => {
  const g = gateway([json({ ok: false, error: 'rate_limited' }, 429)]);
  const a = await answerFromBrief(C, () => {}, g.f);
  assertEquals([a.reply, a.error, g.bodies.length], ['', 'rate_limited', 1]);
});

// prevented by: this test (ruling 1200). A photo with the message reaches the model as an image part of the latest turn.
Deno.test('a photo rides on the latest message as an image part', async () => {
  const g = gateway([sse(['A wardrobe fits that wall. '])]);
  await answerFromBrief({ ...C, images: ['data:image/jpeg;base64,AAAA'] }, () => {}, g.f);
  const last = (g.bodies[0].input as { content: unknown }[]).at(-1)!.content as { type: string }[];
  assertEquals(last.map((p) => p.type), ['text', 'image_url']);
});

// ── THE TURN'S CLOCK (27 Oct 2026, customer_support / it_engineer) ──────────────────────────────────────────────────
// prevented by: these tests. The portal turn took 58-150 s on production and one hit the 150 s edge wall as a 504; the
// ladder here had no bound at all. With a deadline every call is bounded and none starts too late.
Deno.test('with a deadline the gateway is told how long we wait and the fetch stops waiting then', async () => {
  const inits: RequestInit[] = [];
  const f = ((_u: string, init: RequestInit) => { inits.push(init); return Promise.resolve(sse(['Fine. '])); }) as typeof fetch;
  await answerFromBrief({ ...C, deadline: Date.now() + 60_000 }, () => {}, f);
  const b = JSON.parse(String(inits[0].body));
  assert(b.client_timeout_ms > MIN_CALL_MS && b.client_timeout_ms <= PER_CALL_MS, 'client_timeout_ms is this call\'s share: ' + b.client_timeout_ms);
  assert(inits[0].signal instanceof AbortSignal, 'the fetch carries an abort signal');
});

Deno.test('without a deadline nothing changes: no client_timeout_ms, no abort signal (the widget as it was)', async () => {
  const inits: RequestInit[] = [];
  const f = ((_u: string, init: RequestInit) => { inits.push(init); return Promise.resolve(sse(['Fine. '])); }) as typeof fetch;
  await answerFromBrief(C, () => {}, f);
  assertEquals(JSON.parse(String(inits[0].body)).client_timeout_ms, undefined);
  assertEquals(inits[0].signal, undefined);
});

Deno.test('no call starts with less than MIN_CALL_MS left: the ladder stops and the caller gets no text, at once', async () => {
  let calls = 0;
  const f = (() => { calls++; return Promise.resolve(sse(['Fine. '])); }) as typeof fetch;
  const t0 = Date.now();
  const a = await answerFromBrief({ ...C, deadline: Date.now() + MIN_CALL_MS - 1000 }, () => {}, f);
  assertEquals(calls, 0);
  assertEquals(a.reply, '');
  assert(a.attempts.every((x) => /deadline/.test(x)), a.attempts.join(' | '));
  assert(Date.now() - t0 < 500);
});

Deno.test('a stream that hangs is cut at its budget, never shown as the answer, and the next rung answers in time', async () => {
  // the first call streams one sentence then never ends (a model stuck mid-answer); the abort signal must end it
  const hung = (init: RequestInit) => new Response(new ReadableStream({ start(c) {
    c.enqueue(new TextEncoder().encode('data: ' + JSON.stringify({ choices: [{ delta: { content: 'Half an answer. ' } }] }) + '\n\n'));
    init.signal?.addEventListener('abort', () => c.error(new DOMException('aborted', 'AbortError')));
  } }), { headers: { 'content-type': 'text/event-stream' } });
  const replies = [(i: RequestInit) => hung(i), () => json({ content: 'The whole answer.', model: 'anthropic/claude-sonnet-5.5' })];
  const f = ((_u: string, init: RequestInit) => Promise.resolve(replies.shift()!(init))) as typeof fetch;
  const t0 = Date.now();
  // budget: the stream keeps RESERVE_MS back for the next rung, so with RESERVE_MS + MIN_CALL_MS + 1 s left it gets ~9 s
  const a = await answerFromBrief({ ...C, deadline: Date.now() + RESERVE_MS + MIN_CALL_MS + 1000 }, () => {}, f);
  const ms = Date.now() - t0;
  assertEquals(a.reply, 'The whole answer.');
  assert(/stream:failed stream cut/.test(a.attempts[0]), a.attempts.join(' | '));
  assert(ms >= MIN_CALL_MS + 900 && ms < RESERVE_MS + MIN_CALL_MS + 1000, 'cut at its budget with time left for the next rung, took ' + ms);
});

Deno.test('callBudget: a share of the time left, capped per call, zero when too little is left', () => {
  const now = 1_000_000;
  assertEquals(callBudget(undefined, now), null);
  assertEquals(callBudget(now + 120_000, now), PER_CALL_MS);
  assertEquals(callBudget(now + 20_000, now), 20_000);
  assertEquals(callBudget(now + MIN_CALL_MS - 1, now), 0);
  assertEquals(callBudget(now + 20_000, now, RESERVE_MS), 20_000 - RESERVE_MS);   // room kept for the next rung
  assertEquals(callBudget(now + 15_000, now, RESERVE_MS), 15_000);                // too little for both: all of it
});
