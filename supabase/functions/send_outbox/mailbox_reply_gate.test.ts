// deno test supabase/functions/send_outbox/mailbox_reply_gate.test.ts
// WHICH ROWS THE SUPPLIER-MAILBOX SEND GATE ASKS ABOUT, AND WHAT ITS ANSWER MEANS (customer_support, 11 Nov 2026, ruling 1633).
// The rows are the shapes measured on production: notification 129468 (the Azure reply: inbound_reply, kind
// supplier_mailbox_reply, no dedupe key), a seat's reply after this change (dedupe mailbox_auto_reply:...), a person's reply
// (mailbox_person_reply:...), and the follow-up a template answer promised (supplier_registration_reminder,
// supplier_reply_followup:15). The handler-level drills are R1633.1-3 in drill_send_faults.test.ts.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { askMailboxGate, mailboxReplyGated } from './mailbox_reply_gate.ts';

Deno.test('the Azure reply of 9 Nov (129468: inbound_reply, kind supplier_mailbox_reply, no dedupe key) is asked about', () => {
  assert(mailboxReplyGated({ type: 'inbound_reply', kind: 'supplier_mailbox_reply', dedupe_key: null }));
});
Deno.test('a seat reply, a person reply and a promised follow-up are asked about whatever their kind', () => {
  assert(mailboxReplyGated({ type: 'inbound_reply', kind: null, dedupe_key: 'mailbox_auto_reply:a@b.example:x:2026-11-11' }));
  assert(mailboxReplyGated({ type: 'inbound_reply', kind: null, dedupe_key: 'mailbox_person_reply:1874:1' }));
  assert(mailboxReplyGated({ type: 'supplier_registration_reminder', kind: null, dedupe_key: 'supplier_reply_followup:15' }));
});
Deno.test('every other row is not this gate\'s: a customer reply on info@, an invitation, a quote notice', () => {
  assertFalse(mailboxReplyGated({ type: 'inbound_reply', kind: null, dedupe_key: null }));
  assertFalse(mailboxReplyGated({ type: 'supplier_invite', kind: null, dedupe_key: null }));
  assertFalse(mailboxReplyGated({ type: 'quote_received', kind: null, dedupe_key: 'quote:1' }));
  assertFalse(mailboxReplyGated({ type: 'supplier_registration_reminder', kind: null, dedupe_key: 'registration_reminder:9' }));
});
Deno.test('the answer: allow is a send; a reason without allow is a final refusal; an rpc error is a wait, never a send', async () => {
  const rpc = (r: { data: unknown; error: { message: string } | null }) => () => Promise.resolve(r as never);
  assertEquals(await askMailboxGate(rpc({ data: { allow: true, reason: 'x' }, error: null }), 1), { send: true });
  assertEquals(await askMailboxGate(rpc({ data: { allow: false, reason: 'read as vendor_our_account' }, error: null }), 1),
    { send: false, refused: true, why: 'read as vendor_our_account' });
  assertEquals((await askMailboxGate(rpc({ data: null, error: null }), 1)).send, false, 'no answer is not a yes');
  const down = await askMailboxGate(rpc({ data: null, error: { message: 'function does not exist' } }), 1);
  assertEquals(down.send, false);
  assert(!down.send && !down.refused, 'an unreadable gate is not a refusal either: the row waits and is asked again');
});
