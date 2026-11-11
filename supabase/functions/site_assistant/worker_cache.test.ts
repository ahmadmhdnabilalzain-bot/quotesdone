// site_assistant/worker_cache.ts: the published FAQ (~170 KB), the widget limits and the gateway credential are read once
// per worker per TTL, not on every turn (it_engineer, 11 Nov 2026, load test; see the module header for the measurement).
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock --allow-read=. supabase/functions/site_assistant/worker_cache.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { FAQ_TTL_MS, LIMITS_TTL_MS, ttlMemo } from './worker_cache.ts';

Deno.test('twelve turns arriving together cause ONE read, and the next read is after the TTL', async () => {
  let now = 1_000_000, reads = 0;
  const get = ttlMemo(60_000, async () => { reads++; await new Promise((r) => setTimeout(r, 5)); return ['row'] as string[]; }, undefined, () => now);
  const all = await Promise.all(Array.from({ length: 12 }, () => get()));
  assertEquals(reads, 1);
  assert(all.every((v) => v[0] === 'row'));
  now += 59_999; await get(); assertEquals(reads, 1, 'still fresh');
  now += 1; await get(); assertEquals(reads, 2, 'read again once the TTL passed');
  now -= 10_000; await get(); assertEquals(reads, 3, 'a clock that went backwards reads again rather than trusting the entry');
});

Deno.test('a failed, empty or rejected read is not kept: the next turn reads again', async () => {
  let reads = 0; let answer: unknown = null;
  const get = ttlMemo(60_000, async () => { reads++; return answer as string[] | null; }, (v) => Array.isArray(v) && v.length > 0);
  assertEquals(await get(), null); await Promise.resolve();
  answer = []; assertEquals(await get(), []); await Promise.resolve();
  answer = ['ok']; assertEquals(await get(), ['ok']); await Promise.resolve();
  assertEquals(await get(), ['ok']);
  assertEquals(reads, 3, 'null and [] were read again; the good answer was kept');
  let boom = true; let r2 = 0;
  const flaky = ttlMemo(60_000, async () => { r2++; if (boom) throw new Error('down'); return 'v'; });
  await flaky().catch(() => {}); await Promise.resolve(); await Promise.resolve();
  boom = false; assertEquals(await flaky(), 'v'); assertEquals(r2, 2);
});

Deno.test('index.ts reads the FAQ, the limits and the credential only through the cache', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const code = src.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
  assertEquals((code.match(/from\('company_faq'\)/g) ?? []).length, 1, 'one FAQ read in the file');
  assert(/const publishedFaqs = ttlMemo\(FAQ_TTL_MS,[^]*?from\('company_faq'\)/.test(code), 'the FAQ read is not inside publishedFaqs');
  assert(/faqs = await publishedFaqs\(\)/.test(code), 'a turn reads the FAQ table directly again');
  assert(/const limitRows = ttlMemo\(LIMITS_TTL_MS,/.test(code) && /const lim = await secNums\(\);/.test(code), 'the limits are read per turn again');
  assertEquals((code.match(/sec\('cred_fn_ai'\)/g) ?? []).length, 1, 'the credential is read outside gatewayKey');
  assert(/const gatewayKey = ttlMemo\(LIMITS_TTL_MS, \(\) => sec\('cred_fn_ai'\)/.test(code));
  assert(FAQ_TTL_MS <= 60_000 && LIMITS_TTL_MS <= 60_000, 'an edit must reach the widget within a minute');
});
