// answerFromBrief() against a fake gateway (SSE stream and JSON). No network, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert';
import { answerFromBrief, type BriefCall } from './brief_answer.ts';

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
  const g = gateway([sse(['The reveal fee ', 'is 3% of the quote. ', 'No card fee is added.'])]);
  const shown: string[] = [];
  const a = await answerFromBrief(C, (t) => shown.push(t), g.f);
  assertEquals(shown, ['The reveal fee is 3% of the quote. ', 'No card fee is added.']);
  assertEquals(a.reply, 'The reveal fee is 3% of the quote. No card fee is added.');
  assertEquals(g.bodies.length, 1);
  assertEquals([g.bodies[0].stream, g.bodies[0].sys_stable, g.bodies[0].try_faq, g.bodies[0].cache_ttl_min], [true, C.brief, false, 0]);
});

// prevented by: this test. A figure the brief does not state is never shown: the stream stops at that sentence and the
// MODEL rewrites with the correction named; code substitutes no text.
Deno.test('a wrong figure stops the stream and the model rewrites the answer', async () => {
  const g = gateway([sse(['Comparing quotes is free. ', 'The reveal fee is 5% of the quote. ', 'More text.']), json({ content: 'Comparing is free. The reveal fee is 3% of the quote you choose.', model: 'openai/gpt-6-luna' })]);
  const shown: string[] = [];
  const a = await answerFromBrief(C, (t) => shown.push(t), g.f);
  assertEquals(shown, ['Comparing quotes is free. ']);
  assertEquals(a.reply, 'Comparing is free. The reveal fee is 3% of the quote you choose.');
  assertEquals(a.rewrites, 1);
  const fix = (g.bodies[1].input as { content: string }[]).at(-1)!.content;
  assert(fix.includes('5') && /figure/.test(fix), 'the rewrite request names the figure');
});

Deno.test('a failed model climbs the ladder: unstreamed, then a counterpart of another family; none answers -> no text', async () => {
  const g1 = gateway([json({ error: 'all_models_failed' }, 502), json({ content: 'The reveal fee is 3%.', model: 'google/gemini-3.8-flash' })]);
  const a1 = await answerFromBrief(C, () => {}, g1.f);
  assertEquals(a1.reply, 'The reveal fee is 3%.');
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
