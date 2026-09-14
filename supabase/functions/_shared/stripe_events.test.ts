// The webhook's choice of signing secret (stripe_events.ts). A wrong answer here is how a test-mode
// payment could be booked as a real one, so each case is pinned.
import { assertEquals } from 'jsr:@std/assert@1';
import { signingSecretFor, stripeEventMode } from './stripe_events.ts';

const secrets = { live: 'whsec_LIVE', test: 'whsec_TEST' };

Deno.test('a live event is verified by the live secret only', () => {
  assertEquals(stripeEventMode({ livemode: true }), 'live');
  assertEquals(signingSecretFor('live', secrets), 'whsec_LIVE');
});

Deno.test('a test event is verified by the test secret only', () => {
  assertEquals(stripeEventMode({ livemode: false }), 'test');
  assertEquals(signingSecretFor('test', secrets), 'whsec_TEST');
});

Deno.test('an event that states no boolean livemode gets no secret, so it cannot verify', () => {
  for (const e of [{}, { livemode: 'true' }, { livemode: 1 }, { livemode: null }, null, undefined, 'x']) {
    assertEquals(stripeEventMode(e), null, JSON.stringify(e));
    assertEquals(signingSecretFor(stripeEventMode(e), secrets), '');
  }
});

Deno.test('a mode whose secret is not configured gets an empty secret, never the other mode\'s', () => {
  assertEquals(signingSecretFor('test', { live: 'whsec_LIVE', test: '' }), '');
  assertEquals(signingSecretFor('live', { live: '', test: 'whsec_TEST' }), '');
});
