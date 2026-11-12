// Ruling 1631: the same message to the same person is sent once. Replays the 10 Nov 2026 seed-list double send.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { duplicateNote, duplicateOf, messageKey, recentSends, windowFrom, type OutboxRow } from './outbox_duplicate_guard.ts';

const now = Date.parse('2026-11-10T21:31:40Z');
const first: OutboxRow = { id: 101, channel: 'email', type: 'supplier_invite_seed', to_email: 'Seed.Box@Example-Seed.test', subject: 'Quote requests in the UAE',
  body: 'Hello,\n\nWe send quote requests…', created_at: '2026-11-10T21:30:57Z', sent_at: '2026-11-10T21:30:58Z', status: 'sent' };
const again: OutboxRow = { ...first, id: 202, to_email: 'seed.box@example-seed.test', body: 'Hello,  We send quote requests…', created_at: '2026-11-10T21:31:39Z', sent_at: null, status: 'sending' };

Deno.test('the 10 Nov repeat (same seed, same text, 42 s later) is refused and names the earlier row', () => {
  const hit = duplicateOf(again, [first], 10, now);
  assertEquals(hit?.id, 101, 'before 11 Nov nothing compared a row with what had just gone to that person: 6 went out twice');
  assert(duplicateNote(hit!, now).includes('#101'));
});

Deno.test('a different text is never a duplicate: a new sign-in code, another quote, another person, another channel', () => {
  assertEquals(duplicateOf({ ...again, body: 'Your code is 482913' }, [{ ...first, body: 'Your code is 119044' }], 10, now), null);
  assertEquals(duplicateOf({ ...again, subject: 'Quote 2 of 3' }, [first], 10, now), null);
  assertEquals(duplicateOf({ ...again, to_email: 'other@example-seed.test' }, [first], 10, now), null);
  assertEquals(duplicateOf({ ...again, channel: 'whatsapp' }, [first], 10, now), null);
  assertEquals(duplicateOf({ ...again, type: 'founder_alert' }, [first], 10, now), null);
});

Deno.test('outside the window it is a new message; a row is never its own duplicate; no recipient is never compared', () => {
  assertEquals(duplicateOf(again, [first], 0.5 /* floored to 1 min */, Date.parse('2026-11-10T21:33:00Z')), null);
  assertEquals(duplicateOf(first, [first], 10, now), null);
  assertEquals(messageKey({ id: 1, body: 'x' }), '');
  // WhatsApp: the number is compared on its last nine digits, as the estate identifies a phone
  const wa1: OutboxRow = { id: 1, channel: 'whatsapp', type: 'quote_ready', to_phone: '+971 50 123 4567', body: 'A new quote arrived', created_at: '2026-11-10T21:31:00Z', status: 'sent' };
  assertEquals(duplicateOf({ ...wa1, id: 2, to_phone: '0501234567', created_at: '2026-11-10T21:31:30Z' }, [wa1], 10, now)?.id, 1);
});

Deno.test('the window setting: junk is the default, a value is capped at a day', () => {
  assertEquals(windowFrom(undefined), 10); assertEquals(windowFrom('abc'), 10); assertEquals(windowFrom('30'), 30); assertEquals(windowFrom('99999'), 1440);
});

Deno.test('an unreadable history returns null, so the outbox sends as before and says it could not check', async () => {
  const failing = { from: () => ({ select: () => ({ in: () => ({ in: () => ({ gte: () => ({ limit: () => Promise.resolve({ data: null, error: { message: 'timeout' } }) }) }) }) }) }) };
  assertEquals(await recentSends(failing, [again], 10), null);
  const throwing = { from: () => { throw new Error('reset'); } };
  assertEquals(await recentSends(throwing, [again], 10), null);
  assertEquals(await recentSends(failing, [{ id: 9 }], 10), [], 'no recipient: nothing to read');
});

Deno.test('send_outbox and send_whatsapp both run the guard before a message leaves', async () => {
  for (const f of ['../send_outbox/index.ts', '../send_whatsapp/index.ts']) {
    const src = await Deno.readTextFile(new URL(f, import.meta.url));
    assert(/duplicateOf\(/.test(src) && /recentSends\(/.test(src), f + ' compares each row with what was just sent');
    assert(/status: 'cancelled', last_error: duplicateNote\(earlier\)/.test(src), f + ' cancels the repeat and names the earlier row');
  }
});

// THE EVENT IS PART OF THE MESSAGE (sales_engineer, 12 Nov 2026; final audit customer_journey M8, integration finding 4).
// The audit's run: every new_quote notice on a request had one subject and body; by the text-only key 6 of 8 would have been
// cancelled for a real customer. The rows below are that notice as supplier_api notifyNewQuote writes it.
const NQ = (id: number, quote: string, at: string): OutboxRow => ({ id, channel: 'email', type: 'new_quote', to_email: 'zz-demo-customer@example.invalid',
  subject: 'You have a new quote on QuotesDone', body: 'A supplier submitted a quote for your request: ZZ DEMO wall panels. Log in to view the full quotation and compare.',
  inquiry_id: 'aaaaaaaa-0000-4000-8000-000000000001', quote_id: quote, created_at: at, sent_at: at, status: 'sent' });
const at2 = Date.parse('2026-11-11T23:41:30Z');

Deno.test('a second supplier\'s quote on the same request is a new event, not a duplicate, on e-mail and WhatsApp', () => {
  const a = NQ(1, 'q-supplier-1', '2026-11-11T23:38:45Z');
  const b = NQ(2, 'q-supplier-2', '2026-11-11T23:40:10Z');
  assertEquals(duplicateOf(b, [a], 10, at2), null, 'the text-only key cancelled the second supplier\'s notice');
  assertEquals(duplicateOf({ ...b, channel: 'whatsapp', to_email: null, to_phone: '+971500000094' }, [{ ...a, channel: 'whatsapp', to_email: null, to_phone: '+971500000094' }], 10, at2), null);
});

Deno.test('the same event told twice is still refused: the same quote retried after a 502, the seed list queued twice', () => {
  const a = NQ(1, 'q-supplier-1', '2026-11-11T23:38:45Z');
  assertEquals(duplicateOf({ ...a, id: 9, created_at: '2026-11-11T23:39:30Z', sent_at: null, status: 'sending' }, [a], 10, at2)?.id, 1);
  // a row read back from the table carries nulls where a row built in code leaves the fields out: the same event
  assertEquals(duplicateOf({ ...again, inquiry_id: undefined }, [{ ...first, inquiry_id: null, quote_id: null, dedupe_key: null }], 10, now)?.id, 101);
});

Deno.test('two requests, two codes, a reply after a holding line: each is its own message', () => {
  const inv = (id: number, inq: string): OutboxRow => ({ id, channel: 'email', type: 'new_inquiry', to_email: 'zz-sup@example.invalid', subject: 'A new request matches your services',
    body: 'A customer posted a request that matches your services. Log in to quote.', inquiry_id: inq, created_at: '2026-11-11T23:30:00Z', status: 'sent' });
  const at3 = Date.parse('2026-11-11T23:35:00Z');
  assertEquals(duplicateOf({ ...inv(2, 'inq-2'), created_at: '2026-11-11T23:31:00Z' }, [inv(1, 'inq-1')], 10, at3), null);
  assertEquals(duplicateOf({ ...inv(2, 'inq-1'), created_at: '2026-11-11T23:31:00Z' }, [inv(1, 'inq-1')], 10, at3)?.id, 1, 'the same request announced twice');
  const hold: OutboxRow = { id: 5, channel: 'whatsapp', type: 'holding_notice', to_phone: '+971500000001', body: 'Thank you, we are looking into it.', created_at: '2026-11-11T23:40:00Z', status: 'sent' };
  assertEquals(duplicateOf({ id: 6, channel: 'whatsapp', type: 'support_reply', to_phone: '+971500000001', body: 'Your request 165437 has 4 quotes.', created_at: '2026-11-11T23:40:20Z' }, [hold], 10, at2), null);
  assertEquals(duplicateOf({ ...hold, id: 7, created_at: '2026-11-11T23:40:40Z' }, [hold], 10, at2)?.id, 5, 'the holding line twice');
  // two rows that each name their own event by dedupe_key are two events
  assertEquals(duplicateOf({ ...again, dedupe_key: 'missing_specs:2:7' }, [{ ...first, dedupe_key: 'missing_specs:1:7' }], 10, now), null);
});

Deno.test('the history read brings the event columns the key compares', async () => {
  let cols = '';
  const reader = { from: () => ({ select: (c: string) => { cols = c; return { in: () => ({ in: () => ({ gte: () => ({ limit: () => Promise.resolve({ data: [], error: null }) }) }) }) }; } }) };
  await recentSends(reader, [first], 10);
  for (const c of ['inquiry_id', 'quote_id', 'dedupe_key']) assert(cols.split(',').includes(c), c + ' is not read, so every recent row would look event-less');
});

// ONE NOTICE PER SUPPLIER PER EVENT (review of 12 Nov 2026, finding 5). fn_edit_inquiry writes one identical
// quote_requirements_changed row per quote; quote_spec_released is written per option. A supplier with three options is
// told once: his own options are not three events. A customer's notices about two suppliers' quotes stay two.
Deno.test('a supplier with three options is told once that the requirements changed', () => {
  const rc = (id: number, quote: string, at: string): OutboxRow => ({ id, channel: 'email', type: 'quote_requirements_changed', to_role: 'supplier', to_email: 'zz-sup@example.invalid',
    subject: 'The customer changed the requirements of a request you quoted', body: 'Please review your quote.', inquiry_id: 'inq-1', quote_id: quote, created_at: at, status: 'sent' });
  const a = rc(1, 'q-opt-1', '2026-11-11T23:40:00Z');
  assertEquals(duplicateOf(rc(2, 'q-opt-2', '2026-11-11T23:40:00Z'), [a], 10, at2)?.id, 1);
  assertEquals(duplicateOf(rc(3, 'q-opt-3', '2026-11-11T23:40:01Z'), [a], 10, at2)?.id, 1);
  assertEquals(duplicateOf({ ...rc(4, 'q-opt-1', '2026-11-11T23:40:01Z'), inquiry_id: 'inq-2' }, [a], 10, at2), null, 'another request is another event');
});

// THE HOLDING ROW OF #1953 (merged 12 Nov 2026): wa_inbound/holding.ts writes it as requester 'platform', first status 'skipped',
// dedupe_key 'wa_holding:<last9>:<bucket>', and claims one row per person per quiet window by that unique key. The guard's
// event key reads the same key: two holding rows of one window are one event (refused); of two windows, two events (each
// window's own claim decides). The a00 insert trigger acts on queued inserts only, so a 'skipped' claim row is never touched.
Deno.test('a #1953 holding row: one window is one event, two windows are two', () => {
  const hold = (id: number, bucket: number, at: string): OutboxRow => ({ id, channel: 'whatsapp', type: 'wa_holding_notice', to_phone: '+971500000001', to_role: null,
    body: 'Thank you, we are looking into it.', dedupe_key: 'wa_holding:500000001:' + bucket, created_at: at, sent_at: at, status: 'sent' });
  const now = Date.parse('2026-11-12T23:50:00Z');
  assertEquals(duplicateOf({ ...hold(2, 98100, '2026-11-12T23:49:00Z'), status: 'skipped', sent_at: null }, [hold(1, 98100, '2026-11-12T23:45:00Z')], 10, now)?.id, 1);
  assertEquals(duplicateOf({ ...hold(2, 98101, '2026-11-12T23:49:00Z'), status: 'skipped', sent_at: null }, [hold(1, 98100, '2026-11-12T23:45:00Z')], 10, now), null);
});
