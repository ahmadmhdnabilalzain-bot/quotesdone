// Pins the demo-identity rule. The same cases are asserted against public.fn_is_demo_email /
// fn_is_demo_phone by scripts/checks/demo_identities_never_reach_a_real_person.test.mjs, so the
// TypeScript and SQL answers cannot drift apart silently.
import { assertEquals } from 'jsr:@std/assert@1';
import { isDemoEmail, isDemoPhone, stripeKeyNames } from './demo_identity.ts';

Deno.test('reserved domains are demo, real domains are not', () => {
  for (const e of ['qd-ab12-cust0@example.invalid', 'x@example.com', 'x@EXAMPLE.ORG', 'x@sub.example.net',
                   'x@foo.test', 'x@localhost', 'x@a.example']) assertEquals(isDemoEmail(e), true, e);
  for (const e of ['management@quotesdone.com', 'x@gmail.com', 'x@example.co', 'x@myexample.com',
                   'x@example.com.ae', '', null, undefined]) assertEquals(isDemoEmail(e), false, String(e));
});

Deno.test('only the +971 50 000 00xx block is a demo mobile', () => {
  for (const p of ['+971500000001', '+971 50 000 0099', '971500000042', '+971-50-000-00-07']) assertEquals(isDemoPhone(p), true, p);
  for (const p of ['+971501234567', '+971500000100', '+97150000001', '+9715000000012', '0500000001', '', null])
    assertEquals(isDemoPhone(p), false, String(p));
});

Deno.test('a demo account is served only the test key pair, a real one only the live pair', () => {
  assertEquals(stripeKeyNames(true), { secret: 'stripe_secret_key_test', publishable: 'stripe_publishable_key_test', mode: 'test' });
  assertEquals(stripeKeyNames(false), { secret: 'stripe_secret_key', publishable: 'stripe_publishable_key', mode: 'live' });
});
