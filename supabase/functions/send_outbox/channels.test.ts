import { assert, assertEquals } from 'jsr:@std/assert';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { NOT_OWNED_CHANNELS, OWNED_CHANNEL_FILTER, ownsChannel, selectQueue } from './channels.ts';

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
Deno.test('the queue request carries BOTH the status filter and the channel filter', async () => {
  let url = '';
  const fake: typeof fetch = (input) => {
    url = input instanceof Request ? input.url : String(input);
    return Promise.resolve(new Response('[]', { status: 200, headers: { 'Content-Type': 'application/json' } }));
  };
  const client = createClient('http://postgrest.invalid', 'test-key-not-a-secret', { global: { fetch: fake }, auth: { persistSession: false } });
  const { data, error } = await selectQueue(client, 40);
  assertEquals(error, null);
  assertEquals(data, []);
  const ors = new URL(url).searchParams.getAll('or');
  assertEquals(ors, ['(status.eq.queued,status.eq.pending,status.is.null)', '(channel.is.null,channel.not.in.(sms,whatsapp))']);
  assertEquals(new URL(url).searchParams.get('limit'), '40');
  assertEquals(new URL(url).searchParams.get('order'), 'created_at.asc');
});
