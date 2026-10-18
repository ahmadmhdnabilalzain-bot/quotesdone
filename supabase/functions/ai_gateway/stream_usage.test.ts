// The streamed call's usage is read from OpenRouter's final SSE chunk, bytes pass through unchanged, and an
// abandoned stream cancels upstream. No network.
import { assert, assertEquals } from 'jsr:@std/assert';
import { cacheTokens, tapUsage, type StreamSeen } from './stream_usage.ts';

const enc = new TextEncoder();
const CHUNKS = [
  ': OPENROUTER PROCESSING\n\n',
  'data: {"id":"gen-1","choices":[{"delta":{"content":"Hello. "}}]}\n\n',
  'data: {"id":"gen-1","choices":[{"delta":{"content":"World."},"finish_reason":"stop"}]}\n\ndata: {"id":"gen-1","choices":[],"us',
  'age":{"prompt_tokens":15000,"completion_tokens":300,"cost":0.0123,"prompt_tokens_details":{"cached_tokens":14000,"cache_write_tokens":0}}}\n\n',
  'data: [DONE]\n\n',
];
const source = (chunks: string[], onCancel?: () => void) => new ReadableStream<Uint8Array>({
  start(c) { for (const s of chunks) c.enqueue(enc.encode(s)); },   // left open: a cancel must reach it
  cancel() { onCancel?.(); },
});

Deno.test('the final chunk usage, id and finish reason are read; every byte passes through', async () => {
  let seen: StreamSeen | null = null;
  const src = new ReadableStream<Uint8Array>({ start(c) { for (const s of CHUNKS) c.enqueue(enc.encode(s)); c.close(); } });
  const out = await new Response(tapUsage(src, (s) => { seen = s; })).text();
  assertEquals(out, CHUNKS.join(''));
  await new Promise((r) => setTimeout(r, 0));
  const s = seen as unknown as StreamSeen;
  assertEquals([s.id, s.finish, s.cancelled, s.usage?.prompt_tokens, s.usage?.completion_tokens, s.usage?.cost], ['gen-1', 'stop', false, 15000, 300, 0.0123]);
  assertEquals(cacheTokens(s.usage), { cachedIn: 14000, cacheWrite: 0 });
});

Deno.test('a caller that abandons the stream cancels upstream, and the ledger is still told', async () => {
  let cancelled = false; let seen: StreamSeen | null = null;
  const rd = tapUsage(source(CHUNKS.slice(0, 2), () => { cancelled = true; }), (s) => { seen = s; }).getReader();
  await rd.read();
  await rd.cancel('figure check failed');
  await new Promise((r) => setTimeout(r, 0));
  assert(cancelled, 'upstream generation is stopped');
  assertEquals((seen as unknown as StreamSeen).cancelled, true);
  assertEquals((seen as unknown as StreamSeen).usage, null);
});

Deno.test('cache tokens: nested first, flat names as a fallback, unknown (null) when there is no usage block', () => {
  assertEquals(cacheTokens({ cache_read_input_tokens: 5, cache_creation_input_tokens: 7 }), { cachedIn: 5, cacheWrite: 7 });
  assertEquals(cacheTokens(null), { cachedIn: null, cacheWrite: null });
});

Deno.test('a stream that closes normally with no usage chunk is ok, with unknown (null) tokens, never zero', async () => {
  let seen: StreamSeen | null = null;
  const body = CHUNKS.slice(0, 2).concat(['data: {"id":"gen-2","choices":[{"delta":{},"finish_reason":"stop"}]}\n\n', 'data: [DONE]\n\n']);
  const src = new ReadableStream<Uint8Array>({ start(c) { for (const s of body) c.enqueue(enc.encode(s)); c.close(); } });
  await new Response(tapUsage(src, (s) => { seen = s; })).text();
  await new Promise((r) => setTimeout(r, 0));
  const s = seen as unknown as StreamSeen;
  // the gateway books ok = !s.error: no error here, so the breaker is not touched
  assertEquals([s.error, s.cancelled, s.usage, s.finish], [null, false, null, 'stop']);
  assertEquals(cacheTokens(s.usage), { cachedIn: null, cacheWrite: null });
});
