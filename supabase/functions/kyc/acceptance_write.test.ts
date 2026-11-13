// An acceptance of the terms is recorded, or the person is told it was not (kyc/acceptance_write.ts, 13 Nov 2026).
// Replays the 13 Nov failure: the write cancelled by the 8 s statement timeout while a rehearsal held a lock.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { isBlip, recordAcceptance, TERMS_NOT_RECORDED, type WriteResult } from './acceptance_write.ts';

const TIMEOUT: WriteResult = { data: null, error: { message: 'canceling statement due to statement timeout', code: '57014' } };
const ROW: WriteResult = { data: [{ id: 1 }], error: null };
const noSleep = () => Promise.resolve();
const scripted = (answers: (WriteResult | Error)[]) => {
  let n = 0;
  const write = () => { const a = answers[Math.min(n++, answers.length - 1)]; return a instanceof Error ? Promise.reject(a) : Promise.resolve(a); };
  return { write, calls: () => n };
};

Deno.test('the 13 Nov case: a write cancelled every time is NOT recorded, after 3 tries, with its cause', async () => {
  const s = scripted([TIMEOUT]);
  const r = await recordAcceptance(s.write, [800, 2000], noSleep);
  assertEquals(r.ok, false);
  assertEquals(s.calls(), 3);
  if (!r.ok) assertMatch(r.reason, /statement timeout/);
});

Deno.test('a blip that clears is recorded on the retry, once', async () => {
  const s = scripted([TIMEOUT, ROW]);
  const r = await recordAcceptance(s.write, [800, 2000], noSleep);
  assertEquals(r.ok && r.attempts, 2);
  assertEquals(s.calls(), 2);
});

Deno.test('a write that matched no row is not an acceptance, and is not retried', async () => {
  const s = scripted([{ data: [], error: null }]);
  const r = await recordAcceptance(s.write, [800, 2000], noSleep);
  assertEquals(r.ok, false);
  assertEquals(s.calls(), 1);
  if (!r.ok) assertMatch(r.reason, /no row/);
});

Deno.test('a refusal that is not a blip (a guard trigger) is not retried; a dropped connection is', async () => {
  const guard = scripted([{ data: null, error: { message: 'new row violates check constraint', code: '23514' } }]);
  assertEquals((await recordAcceptance(guard.write, [1, 1], noSleep)).ok, false);
  assertEquals(guard.calls(), 1);
  const dropped = scripted([new Error('fetch failed'), ROW]);
  assertEquals((await recordAcceptance(dropped.write, [1, 1], noSleep)).attempts, 2);
  assert(isBlip('canceling statement due to lock timeout') && isBlip('HTTP 503') && !isBlip('error near line 512'));
});

Deno.test('what the person reads is plain, in both languages, retryable, and never says the account is complete', () => {
  assertEquals(TERMS_NOT_RECORDED.code, 'terms_not_recorded');
  assert(TERMS_NOT_RECORDED.retryable);
  assertMatch(TERMS_NOT_RECORDED.message, /not complete yet[\s\S]*press the button again/);
  assert(TERMS_NOT_RECORDED.message_ar.length > 20);
});

Deno.test('kyc accept_terms reads both writes through recordAcceptance and answers terms_not_recorded, never ok, when it fails', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const writes = [...src.matchAll(/recordAcceptance\(\(\) => admin\.from\('(leads|customers)'\)\.update\(/g)].map((m) => m[1]);
  assertEquals(writes.sort(), ['customers', 'leads']);
  assertEquals((src.match(/if \(!w\.ok\) return await termsNotRecorded\(kind, email, w\);/g) ?? []).length, 2);
  // the shape that let the 13 Nov customer through: an acceptance update whose result nobody reads
  assert(!/^\s*await admin\.from\('(?:leads|customers)'\)\.update\(\{?\s*(?:rec|tos_accepted_at)/m.test(src), 'an acceptance write whose result is discarded');
});
