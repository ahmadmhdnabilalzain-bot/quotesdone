// A DELIVERY REPORT IN THE SUPPLIER MAILBOX LEAVES THE REVIEW QUEUE ONCE ITS OWNER HAS ACTED (2 Nov 2026; customer_support).
// MEASURED: six Exchange reports (inbound_messages 1611-1614, 1617, 1618) were owned by customer_support and still read
// needs_review = true, so they sat in the founder's Inbox after their addresses were suppressed.
//
// WHAT FAILS IF THE CAUSE RETURNS: the bounce branch stamps the owner without clearing needs_review (the definition before
// this file, which this test replays as the known-bad control), or the person / founder branches start clearing it (a
// person's reply must stay in review until answered).
//   node --test scripts/checks/a_delivery_report_in_the_supplier_mailbox_leaves_the_review_queue.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'a_delivery_report_in_the_supplier_mailbox_leaves_the_review_queue';
const read = (f) => readFileSync(join(REPO, f), 'utf8').replace(/\r\n/g, '\n');
const fix = read(`scripts/sql/${NAME}.sql`);
const before = read('scripts/sql/every_reply_and_bounce_in_the_supplier_mailbox_has_an_owning_seat.sql');

/** The routine's body, comments removed, split into the bounce branch and everything after it. */
export function branches(text) {
  const open = text.search(/create\s+or\s+replace\s+function\s+public\.fn_supplier_mailbox_mail_gets_its_owner\s*\(/i);
  const a = text.indexOf('$fn$', open) + 4;
  const body = text.slice(a, text.indexOf('$fn$', a)).replace(/--[^\n]*/g, '');
  const cut = body.search(/if public\.fn_is_founder_own_inbox\(v_from\)/i);
  return { bounce: body.slice(0, cut), rest: body.slice(cut), body };
}
export function problems(text) {
  const { bounce, rest } = branches(text);
  const out = [];
  if (!/update public\.inbound_messages set owner_role = v_owner, needs_review = false where id = m\.id/.test(bounce)) out.push('the bounce branch does not leave the review queue');
  if (/needs_review/.test(rest)) out.push('a person\'s or the founder\'s reply would leave the review queue');
  return out;
}

test('known-bad control: the definition before this file leaves a delivery report in the review queue', () => {
  assert.deepEqual(problems(before), ['the bounce branch does not leave the review queue']);
});
test('the fix clears only the bounce branch', () => assert.deepEqual(problems(fix), []));
test('the fix changes nothing else: the two bodies are equal once the one change is undone', () => {
  const undo = branches(fix).body.replace(', needs_review = false where id = m.id', ' where id = m.id');
  assert.equal(undo.replace(/\s+/g, ' '), branches(before).body.replace(/\s+/g, ' '));
});
test('the routine stays revoked and the file is in MANIFEST', () => {
  assert.match(fix, /revoke execute on function public\.fn_supplier_mailbox_mail_gets_its_owner\(bigint, jsonb, boolean\) from public, anon, authenticated;/);
  assert.ok(read('scripts/sql/MANIFEST.txt').split('\n').includes(`scripts/sql/${NAME}.sql`));
});
test('the backfill is the six named reports and nothing broader', () => {
  const upd = /update public\.inbound_messages set needs_review = false\s+where id in \(([^)]*)\)([^;]*);/i.exec(fix);
  assert.ok(upd);
  assert.deepEqual(upd[1].split(',').map((s) => s.trim()), ['1611', '1612', '1613', '1614', '1617', '1618']);
  assert.match(upd[2], /owner_role = 'customer_support'/);
  assert.match(upd[2], /replied_at is null/);
  assert.match(upd[2], /fn_inbound_is_bounce/);
});
