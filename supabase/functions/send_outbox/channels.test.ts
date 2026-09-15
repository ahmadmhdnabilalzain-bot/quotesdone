import { assert, assertEquals } from 'jsr:@std/assert';
import { NOT_OWNED_CHANNELS, OWNED_CHANNEL_FILTER, ownsChannel } from './channels.ts';

Deno.test('send_outbox owns email and NULL-channel rows, never sms or whatsapp', () => {
  assert(ownsChannel(null));
  assert(ownsChannel(undefined));
  assert(ownsChannel('email'));
  assert(!ownsChannel('sms'));
  assert(!ownsChannel('whatsapp'));
});

Deno.test('the query filter excludes every channel the loop refuses, and keeps NULL', () => {
  assertEquals(OWNED_CHANNEL_FILTER, 'channel.is.null,channel.not.in.(sms,whatsapp)');
  for (const c of NOT_OWNED_CHANNELS) assert(OWNED_CHANNEL_FILTER.includes(c) && !ownsChannel(c));
});
