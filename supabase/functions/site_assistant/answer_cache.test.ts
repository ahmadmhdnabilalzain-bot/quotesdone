// The widget's exact answer cache (answer_cache.ts). Run: deno test supabase/functions/site_assistant/answer_cache.test.ts
import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert';
import { cachedReply, cacheKey, normalise, storeReply, TASK_CLASS } from './answer_cache.ts';

const knowledge = { faqs: [{ id: 30, answer: 'The reveal fee is 3%.' }], passages: [{ citation: 'FAQ 30', content: 'The reveal fee is 3%.' }], company: 'pricing: 3%' };
const base = { message: 'How much does it cost to reveal a supplier?', lang: 'en', path: '/', audience: 'unknown', knowledge };

// A fake of the gateway's cache routines with their real semantics: exact by key, semantic only with an embedding.
function fakeCache() {
  const rows = new Map<string, { response: string; task_class: string }>();
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = (fn: string, args: Record<string, unknown>) => {
    calls.push({ fn, args });
    if (fn === 'fn_llm_cache_store') rows.set(String(args.p_key), { response: String(args.p_response), task_class: String(args.p_task_class) });
    if (fn === 'fn_llm_cache_lookup') {
      const r = rows.get(String(args.p_key));
      return Promise.resolve({ data: r ? { hit: true, kind: 'exact', response: r.response } : { hit: false }, error: null });
    }
    return Promise.resolve({ data: null, error: null });
  };
  return { rpc, rows, calls };
}

Deno.test('the same question, however typed, is the same key; another language, page or audience is not', async () => {
  const k = await cacheKey(base);
  assertEquals(await cacheKey({ ...base, message: '  how much does it COST to reveal a supplier ' }), k);
  assertEquals(normalise('كَمْ تكلفة كشف المورد؟'), normalise('كم تكلفة كشف المورد'));
  assertNotEquals(await cacheKey({ ...base, lang: 'ar' }), k);
  assertNotEquals(await cacheKey({ ...base, path: '/supplier' }), k);
  assertNotEquals(await cacheKey({ ...base, audience: 'supplier' }), k);
  assertEquals(await cacheKey({ ...base, path: '/?utm=x' }), k);
});

Deno.test('a cached approved answer is served on the second ask, from the exact path only', async () => {
  const c = fakeCache();
  const k = await cacheKey(base);
  assertEquals(await cachedReply(c.rpc, k), null);
  await storeReply(c.rpc, k, 'The reveal fee is 3%, with no card fee.', 'model-x');
  assertEquals(await cachedReply(c.rpc, await cacheKey({ ...base, message: 'how much does it cost to reveal a supplier' })), 'The reveal fee is 3%, with no card fee.');
  const lookups = c.calls.filter((x) => x.fn === 'fn_llm_cache_lookup');
  assert(lookups.every((x) => x.args.p_embedding === null && x.args.p_task_class === TASK_CLASS));   // never a semantic hit
});

Deno.test('a change to an FAQ, a retrieved passage or the company figures invalidates the answer', async () => {
  const c = fakeCache();
  await storeReply(c.rpc, await cacheKey(base), 'old answer', null);
  const changed = [
    { ...knowledge, faqs: [{ id: 30, answer: 'The reveal fee is 4%.' }] },
    { ...knowledge, passages: [{ citation: 'FAQ 30', content: 'The reveal fee is 4%.' }] },
    { ...knowledge, company: 'pricing: 4%' },
  ];
  for (const k of changed) assertEquals(await cachedReply(c.rpc, await cacheKey({ ...base, knowledge: k })), null);
});

Deno.test('a failed cache read is a miss, never an error', async () => {
  assertEquals(await cachedReply(() => Promise.reject(new Error('down')), 'k'), null);
  await storeReply(() => Promise.reject(new Error('down')), 'k', 'x', null);
});
