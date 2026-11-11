// node --test src/lib/fetchRetry.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { retryRead, isReadAction } from './fetchRetry.ts';

const run = async (seq, read) => {
  let n = 0;
  globalThis.fetch = async () => { const s = seq[Math.min(n++, seq.length - 1)]; if (s === 'throw') throw new TypeError('Failed to fetch'); return { status: s }; };
  const r = await retryRead(() => fetch('x'), read).catch((e) => e);
  return { r, n };
};
test('read: throw then 502 then 200 lands on the 200', async () => { const o = await run(['throw', 502, 200], true); assert.equal(o.r.status, 200); assert.equal(o.n, 3); });
test('read: gives up after 2 retries and returns the last answer', async () => { const o = await run([546], true); assert.equal(o.r.status, 546); assert.equal(o.n, 3); });
test('KNOWN-BAD control: a write is never resent', async () => {
  const o = await run([502, 200], false); assert.equal(o.r.status, 502); assert.equal(o.n, 1);
  const t = await run(['throw', 200], false); assert.ok(t.r instanceof TypeError); assert.equal(t.n, 1);
});
test('a 400 or 401 is an answer, not a failure', async () => { const o = await run([401, 200], true); assert.equal(o.r.status, 401); assert.equal(o.n, 1); });
test('what counts as a read', () => {
  for (const a of ['state', 'my_inquiries', 'overview']) assert.ok(isReadAction({ action: a }), a);
  // the supplier's Inquiries tab (stage 2 run 4506ead8: a relay 502 on inquiries_list left it on "Something went wrong")
  for (const a of ['inquiries_list', 'inquiry_detail', 'inquiry_documents', 'me']) assert.ok(isReadAction({ action: a }), a);
  for (const a of ['save_customer', 'submit_quote', 'delete', '', 'reveal', 'get_x', 'list_y', 'review_start', 'review_message', 'review_submit', 'spec_fill']) assert.ok(!isReadAction({ action: a }), a);
});

// A STALLED READ IS ASKED A SECOND TIME (11 Nov 2026, it_engineer). Production kyc 'state' sat 24.9 s and 43.8 s on a warm
// isolate before its handler ran (handler 200 ms and 256 ms); see the HEDGE_MS note in fetchRetry.ts.
import { hedge, isHedgedRead, HEDGE_MS } from './fetchRetry.ts';
const never = () => new Promise(() => {});
const answer = (status, ms = 0) => new Promise((ok) => setTimeout(() => ok({ status }), ms));
const within = (p, ms) => Promise.race([p, new Promise((_, no) => setTimeout(() => no(new Error('still waiting after ' + ms + ' ms')), ms))]);

test('a stalled cheap read is answered by its hedge, not waited out', async () => {
  let n = 0;
  const send = () => (++n === 1 ? never() : answer(200));
  const t0 = Date.now();
  const r = await within(retryRead(send, true, 2, () => false, { action: 'state' }, 40), 1000);
  assert.equal(r.status, 200); assert.equal(n, 2); assert.ok(Date.now() - t0 >= 35, 'the hedge waits its turn');
});
test('a fast read goes out once', async () => {
  let n = 0;
  const r = await retryRead(() => { n++; return answer(200, 5); }, true, 2, () => false, { action: 'me' }, 200);
  assert.equal(r.status, 200); await new Promise((ok) => setTimeout(ok, 250)); assert.equal(n, 1);
});
test('KNOWN-BAD control: a write is never hedged, however slow', async () => {
  let n = 0;
  const r = await retryRead(() => { n++; return answer(200, 120); }, false, 2, () => false, { action: 'state' }, 20);
  assert.equal(r.status, 200); assert.equal(n, 1);
});
test('a read that reasons is never hedged', async () => {
  let n = 0;
  const r = await retryRead(() => { n++; return answer(200, 120); }, true, 2, () => false, { action: 'decision_support' }, 20);
  assert.equal(r.status, 200); assert.equal(n, 1);
});
test('the first good answer wins; a 503 waits for the other call', async () => {
  let n = 0;
  const r = await hedge(() => (++n === 1 ? answer(503, 60) : answer(200, 80)), 20);
  assert.equal(r.status, 200); assert.equal(n, 2);
});
test('a failure with nothing else out settles at once, so the retries still run', async () => {
  let n = 0;
  globalThis.fetch = async () => { n++; if (n === 1) throw new TypeError('Failed to fetch'); return { status: 200 }; };
  const t0 = Date.now();
  const r = await retryRead(() => fetch('x'), true, 2, () => false, { action: 'dashboard' }, 5000);
  assert.equal(r.status, 200); assert.equal(n, 2); assert.ok(Date.now() - t0 < 2000, 'retried after 400 ms, not after the hedge');
});
test('what is hedged', () => {
  assert.ok(HEDGE_MS > 1500 && HEDGE_MS <= 5000, 'above the measured p95 of these reads, well under the 20 s portal abort');
  for (const a of ['state', 'me', 'dashboard']) assert.ok(isHedgedRead({ action: a }) && isReadAction({ action: a }), a);
  for (const a of ['decision_support', 'insights', 'opportunities', 'whatsapp_choose', 'accept_terms', 'send_sms', 'save_profile', '']) assert.ok(!isHedgedRead({ action: a }), a);
});
