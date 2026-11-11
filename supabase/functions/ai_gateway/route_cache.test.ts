// A counterpart call is cached by the model it calls (ai_gateway/route_cache.ts). The failing input is the measured one:
// conversation_reply, base primary Luna Pro (cache false), counterpart Luna Pro, picked reviewer Sonnet 5.5 (cache true).
import { assertEquals } from 'jsr:@std/assert@1';
import { cacheOfTheCalledModel, registrySupportsCache } from './route_cache.ts';

const REGISTRY: Record<string, boolean> = { 'anthropic/claude-sonnet-5.5': true, 'openai/gpt-6-luna-pro': false, 'qwen/qwen3.8-flash': false };
const supports = (m: string) => Promise.resolve(m in REGISTRY ? REGISTRY[m] : null);

Deno.test('the 10 Nov case: a Sonnet pick on a Luna-primary class is sent with cache breakpoints', async () => {
  const route = { model: 'anthropic/claude-sonnet-5.5', cache: false };   // what fn_ai_route_review_for returned
  assertEquals(route.cache === true, false, 'the old rule (route.cache) sent it uncached');
  assertEquals(await cacheOfTheCalledModel(route, 'openai/gpt-6-luna-pro', true, supports), true);
});

Deno.test('the reverse: an Anthropic-primary class whose pick is another family gets no Anthropic cache_control', async () => {
  assertEquals(await cacheOfTheCalledModel({ model: 'qwen/qwen3.8-flash', cache: true }, 'anthropic/claude-sonnet-5.5', true, supports), false);
});

Deno.test('without a counterpart, with the switch off, or with an unreadable registry the route decides, as before', async () => {
  assertEquals(await cacheOfTheCalledModel({ model: 'anthropic/claude-sonnet-5.5', cache: false }, null, true, supports), false);
  assertEquals(await cacheOfTheCalledModel({ model: 'openai/gpt-6-luna-pro', cache: true }, null, true, supports), true);
  assertEquals(await cacheOfTheCalledModel({ model: 'anthropic/claude-sonnet-5.5', cache: false }, 'openai/gpt-6-luna-pro', false, supports), false);
  assertEquals(await cacheOfTheCalledModel({ model: 'x/unknown', cache: true }, 'openai/gpt-6-luna-pro', true, supports), true);
  assertEquals(await cacheOfTheCalledModel({ model: 'anthropic/claude-sonnet-5.5', cache: false }, 'openai/gpt-6-luna-pro', true, () => Promise.reject(new Error('down'))), false);
});

Deno.test('the registry is read once per model per worker, and a failed read is null', async () => {
  let reads = 0;
  const admin = { from: (t: string) => { assertEquals(t, 'model_registry'); return { select: () => ({ eq: (_c: string, m: string) => ({ maybeSingle: () => {
    reads++; return m === 'boom' ? Promise.reject(new Error('x')) : Promise.resolve({ data: m === 'anthropic/claude-sonnet-5.5' ? { supports_cache: true } : null, error: null });
  } }) }) }; } };
  const s = registrySupportsCache(admin);
  assertEquals(await s('anthropic/claude-sonnet-5.5'), true);
  assertEquals(await s('anthropic/claude-sonnet-5.5'), true);
  assertEquals(reads, 1);
  assertEquals(await s('nope/none'), null);
  assertEquals(await s('boom'), null);
});
