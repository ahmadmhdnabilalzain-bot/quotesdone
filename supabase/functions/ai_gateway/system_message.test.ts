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

// prevented by: these tests (it_engineer, 3 Nov 2026). The history breakpoint is on the DEFAULT 5-minute tier (the 1-hour
// tier writes at 2x and a chat's history is read back within minutes or never); the brief blocks keep the 1-hour tier,
// and Anthropic wants the longer tier first, which system-before-messages gives.
Deno.test('the gateway marks the history on the default tier, whatever tier the brief asked for', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const calls = [...src.matchAll(/withHistoryBreakpoint\(([^)]*)\)/g)].map((m) => m[1]);
  assertEquals(calls, ['convo, null']);
});

// THE BRIEF IS SENT ONCE ON EVERY ROUTE (it_engineer, 3 Nov 2026). gpt-6-luna-pro fallback calls report ~2x Sonnet's
// prompt tokens for the same reply (ai_cost_log 30 Oct-3 Nov: wa_inbound median 279,614 vs 143,548). Measured: the same
// ratio holds where no brief is sent at all (knowledge_validation 2.53x, resilience_ping 1.84x), so it is that model's own
// token count, not a second copy. This pins the copy count on both shapes the gateway can send (cached blocks for
// Claude, one plain string where the route does not cache).
Deno.test('the brief appears exactly once in the system message, cached or not', () => {
  const brief = '<<<FILE knowledge/brief/company.md>>>\nTHE CORE\n<<<END>>>';
  for (const useCache of [true, false]) {
    const m = systemMessage({ shared: brief, stable: 'PACK AND COMPANY BLOCK', sys: 'rules', useCache, ttl: '1h' })!;
    const text = typeof m.content === 'string' ? m.content : m.content.map((b) => b.text).join('');
    assertEquals(text.split('THE CORE').length - 1, 1, 'useCache ' + useCache);
    assertEquals(text.split('PACK AND COMPANY BLOCK').length - 1, 1, 'useCache ' + useCache);
  }
});
