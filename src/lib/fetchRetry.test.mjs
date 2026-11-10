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
