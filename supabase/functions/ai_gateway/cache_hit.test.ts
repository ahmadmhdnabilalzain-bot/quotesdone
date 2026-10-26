import { assert } from 'jsr:@std/assert';
import { cacheHitServesRoute } from './cache_hit.ts';

Deno.test('a cached answer from a superseded model is not served (run 0a717394 S19: gpt-6-luna replayed for intent_detection)', async () => {
  assert(!cacheHitServesRoute('openai/gpt-6-luna', 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5'));
  assert(cacheHitServesRoute('openai/gpt-6-luna-pro', 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5'));
  assert(cacheHitServesRoute('anthropic/claude-sonnet-5.5', 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5'));
  // a hit with no recorded model is never served (review of #1575)
  assert(!cacheHitServesRoute(null, 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5'));
  assert(!cacheHitServesRoute(undefined, 'openai/gpt-6-luna-pro', null));
  assert(!cacheHitServesRoute('', 'openai/gpt-6-luna-pro', null));
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(/hit\.hit === true && cacheHitServesRoute\(hit\.model, model, fallback\)/.test(src), 'the gateway must check the hit against the route');
});
