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
