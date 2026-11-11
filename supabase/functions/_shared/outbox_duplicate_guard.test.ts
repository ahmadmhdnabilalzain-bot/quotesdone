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
