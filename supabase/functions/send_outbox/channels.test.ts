import { assert, assertEquals } from 'jsr:@std/assert';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { dueFilter, NOT_OWNED_CHANNELS, OWNED_CHANNEL_FILTER, ownsChannel, selectQueue } from './channels.ts';

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

// The real supabase-js builder with a fetch that records the request and never touches a network.
// This proves the second .or() is appended, not overwriting the status filter: both reach PostgREST,
// which ANDs repeated top-level params.
Deno.test('the queue request carries the status, channel AND due filters', async () => {
  let url = '';
  const fake: typeof fetch = (input) => {
    url = input instanceof Request ? input.url : String(input);
    return Promise.resolve(new Response('[]', { status: 200, headers: { 'Content-Type': 'application/json' } }));
  };
  const client = createClient('http://postgrest.invalid', 'test-key-not-a-secret', { global: { fetch: fake }, auth: { persistSession: false } });
  const now = new Date('2026-09-22T05:00:00.000Z');
  const { data, error } = await selectQueue(client, 40, now);
  assertEquals(error, null);
  assertEquals(data, []);
  const ors = new URL(url).searchParams.getAll('or');
  assertEquals(ors, ['(status.eq.queued,status.eq.pending,status.is.null)', '(channel.is.null,channel.not.in.(sms,whatsapp))',
    '(not_before.is.null,not_before.lte.2026-09-22T05:00:00.000Z)']);
  assertEquals(new URL(url).searchParams.get('limit'), '40');
  assertEquals(new URL(url).searchParams.get('order'), 'created_at.asc');
});

// 22 Sep 2026: a spread supplier invitation is not selected before its not_before, and a row with none
// (every other notification) always is. The NULL branch is required: without it every legacy row would
// be dropped, exactly as the channel filter's NULL branch above.
Deno.test('the due filter keeps NULL not_before and bounds the rest by now', () => {
  const f = dueFilter(new Date('2026-09-22T05:00:00.000Z'));
  assertEquals(f, 'not_before.is.null,not_before.lte.2026-09-22T05:00:00.000Z');
  assert(f.startsWith('not_before.is.null,'));
});
