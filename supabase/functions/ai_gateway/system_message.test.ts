// The system message carries the shared knowledge block and the caller's stable half as two cached blocks, the
// per-call rules uncached after them, and the 1-hour tier only when asked. No network.
import { assertEquals } from 'jsr:@std/assert';
import { systemMessage } from './system_message.ts';

Deno.test('shared, then stable, each with its own breakpoint; the volatile rules last and uncached; ttl 1h when asked', () => {
  const m = systemMessage({ shared: 'KNOWLEDGE', stable: 'COMPANY', sys: 'Reply in Arabic.', useCache: true, ttl: '1h' })!;
  assertEquals(m.content, [
    { type: 'text', text: 'KNOWLEDGE', cache_control: { type: 'ephemeral', ttl: '1h' } },
    { type: 'text', text: 'COMPANY', cache_control: { type: 'ephemeral', ttl: '1h' } },
    { type: 'text', text: 'Reply in Arabic.' },
  ]);
});
Deno.test('every other caller is unchanged: one cached stable block, the default 5-minute tier', () => {
  assertEquals(systemMessage({ shared: '', stable: 'S', sys: 'v', useCache: true, ttl: null })!.content,
    [{ type: 'text', text: 'S', cache_control: { type: 'ephemeral' } }, { type: 'text', text: 'v' }]);
  assertEquals(systemMessage({ shared: '', stable: '', sys: 'v', useCache: true, ttl: null })!.content,
    [{ type: 'text', text: 'v', cache_control: { type: 'ephemeral' } }]);
});
Deno.test('cache off: one plain string, in the same order; nothing to say: no system message', () => {
  assertEquals(systemMessage({ shared: 'K', stable: 'S', sys: 'v', useCache: false, ttl: '1h' })!.content, 'KSv');
  assertEquals(systemMessage({ shared: '', stable: '', sys: '', useCache: true, ttl: null }), null);
});

// prevented by: these tests (#1407 review). The 1-hour tier is asked for, never required.
import { sendWithTtlFallback, withoutTtl } from './system_message.ts';
const MSGS = [systemMessage({ shared: 'K', stable: 'S', sys: 'v', useCache: true, ttl: '1h' })!, { role: 'user', content: 'hi' }];
Deno.test('a route that refuses the ttl field gets the same request once more without it, breakpoints kept', async () => {
  const sent: unknown[][] = [];
  const r = await sendWithTtlFallback((m) => { sent.push(m);
    return Promise.resolve(sent.length === 1 ? new Response('{"error":{"message":"cache_control.ttl: Extra inputs are not permitted"}}', { status: 400 }) : new Response('{}', { status: 200 })); }, MSGS, '1h');
  assertEquals([r.status, sent.length], [200, 2]);
  assertEquals(sent[1], withoutTtl(MSGS));
  assertEquals((sent[1][0] as { content: { cache_control?: unknown }[] }).content.map((b) => b.cache_control),
    [{ type: 'ephemeral' }, { type: 'ephemeral' }, undefined]);
});
Deno.test('any other failure is not retried here; nothing is retried when no ttl was asked for', async () => {
  let n = 0;
  const bad = () => { n++; return Promise.resolve(new Response('{"error":"rate limited"}', { status: 429 })); };
  assertEquals((await sendWithTtlFallback(bad, MSGS, '1h')).status, 429);
  const ttl400 = () => { n++; return Promise.resolve(new Response('{"error":"ttl not allowed"}', { status: 400 })); };
  assertEquals((await sendWithTtlFallback(ttl400, MSGS, null)).status, 400);
  assertEquals(n, 2);
});

// prevented by: this test (18 Oct 2026, _shared/chat_history.ts). A long chat's earlier turns are the third cached block.
Deno.test('cache_history marks the turn before the newest, on the asked tier, and changes nothing else', async () => {
  const { withHistoryBreakpoint } = await import('./system_message.ts');
  const msgs = [{ role: 'user', content: 'turn 1' }, { role: 'assistant', content: 'reply 1' }, { role: 'user', content: [{ type: 'text', text: 'now' }, { type: 'image_url', image_url: { url: 'x' } }] }];
  const out = withHistoryBreakpoint(msgs, '1h');
  assertEquals(out[1].content, [{ type: 'text', text: 'reply 1', cache_control: { type: 'ephemeral', ttl: '1h' } }]);
  assertEquals(out[0], msgs[0]); assertEquals(out[2], msgs[2]);
  assertEquals(msgs[1].content, 'reply 1');   // the input is not mutated
  assertEquals(withHistoryBreakpoint([{ role: 'user', content: 'only' }], null), [{ role: 'user', content: 'only' }]);
});
