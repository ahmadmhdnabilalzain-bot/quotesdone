// node --test src/components/portal/supplier/awaitingReply.test.mjs
// Branch nightly 41623020490 (3 Nov 2026): "the engineer never answered the typed prices" - the answer of a re-asked turn
// lands in the thread later and the chat polled only during a review. This fails if the chat stops reading the thread
// while the supplier waits, or polls forever.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { awaitingReply, AWAIT_REPLY_MS } from './awaitingReply.ts';

const at = Date.parse('2026-11-03T12:00:00Z');
const msg = (role, ageMs) => ({ role, created_at: new Date(at - ageMs).toISOString() });
const th = (messages, extra = {}) => ({ state: 'changes_requested', reviewing: false, messages, ...extra });

test('waits while the supplier spoke last, recently', () => {
  assert.equal(awaitingReply(th([msg('sales_engineer', 9e4), msg('supplier', 10_000)]), at), true);
});
test('does not wait once the engineer answered, after 5 minutes, during a review, or once submitted', () => {
  assert.equal(awaitingReply(th([msg('supplier', 2e4), msg('sales_engineer', 1e4)]), at), false);
  assert.equal(awaitingReply(th([msg('supplier', AWAIT_REPLY_MS + 1)]), at), false);
  assert.equal(awaitingReply(th([msg('supplier', 1e4)], { reviewing: true }), at), false);
  assert.equal(awaitingReply(th([msg('supplier', 1e4)], { state: 'submitted' }), at), false);
  assert.equal(awaitingReply(null, at), false);
});
test('the chat polls the thread while it waits for the engineer', () => {
  const src = readFileSync(new URL('./QuoteReviewChat.tsx', import.meta.url), 'utf8');
  assert.match(src, /const waitingFor = awaitingReply\(th\);/);
  assert.match(src, /if \(!waitingFor \|\| busy\) return;\s*const h = setInterval\(async \(\) => \{ const n = \+\+seq\.current; adopt\(await qr\.thread\(token, inquiryId, lang\), n\); \}, 4000\);/);
});
