import { assert, assertEquals } from 'jsr:@std/assert';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { dueFilter, isStale, NOT_OWNED_CHANNELS, OWNED_CHANNEL_FILTER, ownsChannel, selectQueue } from './channels.ts';

// The 2 Nov 2026 rows: queued 28 Oct 06:45Z, not_before 2 Nov 07:07Z, claimed 07:16Z. Under the old created_at rule they were
// 120 h old and held for good; they had been due for 9 minutes.
Deno.test('an invitation moved on by not_before is stale from when it fell due, not from when it was written', () => {
  const claimed = new Date('2026-11-02T07:16:27Z');
  const a = isStale('2026-10-28T06:45:01Z', '2026-11-02T07:07:05Z', true, 72, claimed);
  assert(!a.stale && a.hours > 0 && a.hours < 1, `due 9 minutes ago, measured ${a.hours} h`);
  assert(isStale('2026-10-28T06:45:01Z', null, true, 72, claimed).stale, 'a row with no not_before still ages from created_at');
  assert(isStale('2026-10-28T06:45:01Z', '2026-10-28T06:00:00Z', true, 72, claimed).stale, 'a not_before before created_at does not make a row younger');
});

// Review of #1787: only the lane's types may be measured from not_before, and nothing goes out more than 14 days after it was written.
Deno.test('a non-lane row ignores not_before, and every row is stale 14 days after it was written', () => {
  const now = new Date('2026-11-20T07:00:00Z');
  assert(isStale('2026-11-15T07:00:00Z', '2026-11-20T06:30:00Z', false, 72, now).stale, 'a notice re-held by not_before went out days late');
  assert(isStale('2026-11-05T07:00:00Z', '2026-11-20T06:30:00Z', true, 72, now).stale, 'an invitation re-held every 30 minutes went out 15 days late');
  assert(!isStale('2026-11-07T08:00:00Z', '2026-11-20T06:30:00Z', true, 72, now).stale, 'an invitation due 30 minutes ago and 13 days old is still sent');
});

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
