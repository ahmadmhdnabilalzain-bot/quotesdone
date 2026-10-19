// deny is on every OpenRouter request, existing provider fields survive, and the exception list cannot grow silently.
import { assertEquals } from 'jsr:@std/assert';
import { DATA_COLLECTION_EXCEPTIONS, withDataDeny } from './provider_privacy.ts';

Deno.test('deny is merged in and keeps existing provider fields', () => {
  assertEquals(withDataDeny({ model: 'x' }, 'openai/gpt-6-luna-pro').provider, { data_collection: 'deny' });
  assertEquals(withDataDeny({ provider: { order: ['Azure'] } }, 'anthropic/claude-opus-5.5').provider,
    { order: ['Azure'], data_collection: 'deny' });
});
Deno.test('the exception list is empty (measured 19 Oct 2026); adding a model needs this test changed', () => {
  assertEquals([...DATA_COLLECTION_EXCEPTIONS], []);
});
Deno.test('index.ts applies withDataDeny to the payload before the OpenRouter fetch', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const at = src.indexOf("fetch('https://openrouter.ai/api/v1/chat/completions'");
  const deny = src.indexOf('withDataDeny(payload, m);');
  if (at < 0 || deny < 0 || deny > at) throw new Error('withDataDeny(payload, m) must run before the OpenRouter fetch');
});
