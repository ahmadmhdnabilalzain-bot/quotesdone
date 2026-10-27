// Pins the demo-identity rule. The same cases are asserted against public.fn_is_demo_email /
// fn_is_demo_phone by scripts/checks/demo_identities_never_reach_a_real_person.test.mjs, so the
// TypeScript and SQL answers cannot drift apart silently.
import { assertEquals } from 'jsr:@std/assert@1';
import { isDemoEmail, isDemoPhone, isFixtureLead, stripeKeyNames } from './demo_identity.ts';

// A fixture registration files no supplier_registered notice, so no handoff and no org_task (13 Oct 2026).
Deno.test('a fixture supplier is recognised by any one marker; a real supplier by none', () => {
  for (const l of [{ is_demo: true }, { company_name: 'ZZ DEMO Walk 79399dc7 en mobile 0' }, { company_name: '  zz demo x' },
                   { email: 'qd-79399dc7-sup0@example.invalid' }, { claimed_by: 'a@x.test' }, { tags: ['qd_demo', 'qd_run:79399dc7'] }])
    assertEquals(isFixtureLead(l), true, JSON.stringify(l));
  for (const l of [null, undefined, {}, { company_name: 'Al Zz Demolition LLC', email: 'ops@realco.ae', tags: ['lead'] },
                   { is_demo: false, company_name: 'Crescent Building Ltd', email: 'info@crescent.ae' }])
    assertEquals(isFixtureLead(l), false, JSON.stringify(l));
});

Deno.test('reserved domains are demo, real domains are not', () => {
  for (const e of ['qd-ab12-cust0@example.invalid', 'x@example.com', 'x@EXAMPLE.ORG', 'x@sub.example.net',
                   'x@foo.test', 'x@localhost', 'x@a.example']) assertEquals(isDemoEmail(e), true, e);
  for (const e of ['management@quotesdone.com', 'x@gmail.com', 'x@example.co', 'x@myexample.com',
                   'x@example.com.ae', '', null, undefined]) assertEquals(isDemoEmail(e), false, String(e));
});

// 22 Sep 2026: the local form 050 000 00xx is the same block (0500000097 read as real on customers.is_demo).
Deno.test('only the +971 50 000 00xx block is a demo mobile, in international or local form', () => {
  for (const p of ['+971500000001', '+971 50 000 0099', '971500000042', '+971-50-000-00-07', '0500000001', '050 000 0097']) assertEquals(isDemoPhone(p), true, p);
  for (const p of ['+971501234567', '+971500000100', '+97150000001', '+9715000000012', '0501234567', '050000001', '05000000012', '', null])
    assertEquals(isDemoPhone(p), false, String(p));
});

Deno.test('a demo account is served only the test key pair, a real one only the live pair', () => {
  assertEquals(stripeKeyNames(true), { secret: 'stripe_secret_key_test', publishable: 'stripe_publishable_key_test', mode: 'test' });
  assertEquals(stripeKeyNames(false), { secret: 'stripe_secret_key', publishable: 'stripe_publishable_key', mode: 'live' });
});
