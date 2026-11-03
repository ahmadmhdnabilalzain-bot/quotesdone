// deno test supabase/functions/send_outbox/m365_reply.test.ts
// A SUPPLIER'S REPLY IS ANSWERED FROM THE MAILBOX IT WROTE TO (sales_engineer, 3 Nov 2026). Replays the shape of
// notification 125121 (inbound_reply to info@hindco.co.in, answering inbound_messages 1829 that arrived in
// supplier@): with fn_inbox_send's new to_role + kind it is carried by the Microsoft 365 lane, threaded; a customer's
// reply is not; with the lane off, refused or at its ceiling it goes through Resend as before; invite_daily_cap never
// holds or counts it.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import {
  M365_HARD_CEILING, M365_OFF, M365_REPLY_KIND, afterRefusal, holdForM365, isMailboxReply, m365Carries, m365Mime, m365Step, replyMail, type M365,
} from './m365_lane.ts';
import { LANE_CAPPED_TYPES } from './invite_lane.ts';

const ON: M365 = { active: true, refused: false, mailbox: 'supplier@quotesdone.com', token: 'tok', why: 'token issued' };
const REFUSED: M365 = { active: false, refused: true, mailbox: 'supplier@quotesdone.com', token: '', why: 'refused: token refused (HTTP 401)' };
const SUPPLIER_MID = '<CA+zz-demo-probe@mail.gmail.com>';
// The row fn_inbox_send writes now for a message that came into supplier@ (to_role, lead_id and kind are new).
const reply = { type: 'inbound_reply', to_role: 'supplier', lead_id: 1, kind: M365_REPLY_KIND, to_email: 'zz-demo@example.invalid',
  subject: 'Re: A question about your work in the UAE', body: 'Hello,\n\nThank you.\n\nKind regards,\nThe QuotesDone Team', in_reply_to: SUPPLIER_MID };
const carried = (row: { type: string; kind: unknown; to_role: unknown }, enabled = true) =>
  m365Carries({ enabled, type: row.type, kind: row.kind, supplierSide: row.to_role === 'supplier' });
const unb64 = (s: string) => new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)));

Deno.test('a supplier-mailbox reply is carried by the Microsoft 365 lane and sent with In-Reply-To and References', () => {
  assert(isMailboxReply(reply));
  assert(carried(reply), 'the reply to a supplier@ conversation must leave from supplier@');
  assertEquals(m365Step({ reply: true, hold: holdForM365({ m365: ON, type: reply.type, cappedSentToday: 0, inviteCap: 20, m365SentToday: 0 }), sentThisRun: 0 }), 'send');
  const rm = replyMail(reply);
  assertEquals(rm.bad, []); assertEquals(rm.subject, reply.subject); assertEquals(rm.inReplyTo, SUPPLIER_MID);
  const head = unb64(m365Mime({ from: '"Ahmad Alzain, QuotesDone" <supplier@quotesdone.com>', to: reply.to_email, reply: '', subject: rm.subject, text: rm.text,
    unsub: '', unsubMailto: 'u@mail.quotesdone.com', messageId: '<qd-notif-1.2@quotesdone.com>', now: new Date(), inReplyTo: rm.inReplyTo })).split('\r\n\r\n')[0];
  assert(head.includes('\r\nIn-Reply-To: ' + SUPPLIER_MID + '\r\n'), head);
  assert(head.includes('\r\nReferences: ' + SUPPLIER_MID + '\r\n'), head);
  assert(head.startsWith('From: "Ahmad Alzain, QuotesDone" <supplier@quotesdone.com>'));
  assertFalse(/List-Unsubscribe/i.test(head), 'a reply carries no List-Unsubscribe');
  // a bare id is bracketed; a header break in it cannot inject a header
  const bare = unb64(m365Mime({ from: 'a@b.co', to: 'c@d.co', reply: '', subject: 's', text: 't', unsub: '', unsubMailto: '', messageId: '<m@q>', now: new Date(), inReplyTo: 'x@y\r\nBcc: evil@x.co' })).split('\r\n\r\n')[0];
  assertFalse(/^Bcc:/m.test(bare), bare);
  assert(bare.includes('In-Reply-To: <x@y Bcc: evil@x.co>'));
});

Deno.test('a customer-side reply (to_role NULL, no kind) is unchanged: never carried', () => {
  const customer = { ...reply, to_role: null, lead_id: null, kind: null };
  assertFalse(isMailboxReply(customer)); assertFalse(carried(customer)); assertFalse(carried(customer, false));
  // a supplier who wrote to ANOTHER mailbox (no kind): counted as a supplier, but keeps its Resend route
  assertFalse(carried({ ...reply, kind: null }));
  // the kind alone never moves a non-supplier row, nor any other type
  assertFalse(carried({ ...reply, to_role: 'customer' }));
  assertFalse(carried({ ...reply, type: 'quote_received' }));
  // and an invitation without the switch is still not carried (unchanged)
  assertFalse(carried({ type: 'supplier_invite', kind: null, to_role: 'supplier' }, false));
});

Deno.test('lane off, refused or at its ceiling: the reply goes through Resend as today, never held', () => {
  assertFalse(carried(reply, false), 'switch off: not carried, so the Resend route sends it as before');
  for (const m365 of [M365_OFF, REFUSED]) {
    const hold = holdForM365({ m365, type: reply.type, cappedSentToday: 0, inviteCap: 20, m365SentToday: 0 });
    assertEquals(m365Step({ reply: true, hold, sentThisRun: 0 }), 'resend');
    assertEquals(m365Step({ reply: false, hold, sentThisRun: 0 }), 'hold', 'an invitation is still held, never sent through Resend');
  }
  const ceiling = holdForM365({ m365: ON, type: reply.type, cappedSentToday: 0, inviteCap: 20, m365SentToday: M365_HARD_CEILING });
  assertEquals(ceiling, 'cap', 'the mailbox hard ceiling applies to replies');
  assertEquals(m365Step({ reply: true, hold: ceiling, sentThisRun: 0 }), 'resend');
  assertEquals(afterRefusal(true), 'resend', 'Graph refusing the reply sends it through Resend in the same run');
  assertEquals(afterRefusal(false), 'hold');
});

Deno.test('a reply is not counted in, held by or paced behind the invitation daily cap', () => {
  assertFalse(LANE_CAPPED_TYPES.includes('inbound_reply'), 'inbound_reply is not counted into cappedSentToday');
  // invite_daily_cap long reached (and 0): the reply still sends
  for (const inviteCap of [0, 20]) {
    assertEquals(holdForM365({ m365: ON, type: reply.type, cappedSentToday: 999, inviteCap, m365SentToday: 10 }), null);
    assertEquals(holdForM365({ m365: ON, type: 'supplier_invite', cappedSentToday: 999, inviteCap, m365SentToday: 10 }), 'cap');
  }
  // five lane sends already this run: an invitation is paced, a reply is not
  assertEquals(m365Step({ reply: true, hold: null, sentThisRun: 5 }), 'send');
  assertEquals(m365Step({ reply: false, hold: null, sentThisRun: 5 }), 'pace');
});

Deno.test('an empty reply body is refused, never sent blank', () => {
  assertEquals(replyMail({ ...reply, body: '  ' }).bad, ['the reply body is empty']);
  assertEquals(replyMail({ ...reply, subject: '' }).subject, 'Re: your message');
});
