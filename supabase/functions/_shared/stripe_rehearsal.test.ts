// deno test supabase/functions/_shared/stripe_rehearsal.test.ts
// The payment duty drops a Stripe object from reconciliation only when it is a provable rehearsal:
// TEST mode AND a reserved demo payer email. LIVE is never dropped, whatever the object carries.
import { isRehearsal, refundPayer, sessionPayer, splitRehearsals } from './it_duty_readings.ts';

const demoS = { id: 'cs_test_demo', customer_details: { email: 'qd-t-c1@example.invalid' } };
const realS = { id: 'cs_test_real', customer_details: { email: 'buyer@realco.ae' } };
const demoR = { id: 're_demo', charge: { billing_details: { email: 'qd-t-c1@example.invalid' } } };
const realR = { id: 're_real', charge: { billing_details: { email: 'buyer@realco.ae' } } };
const ids = (xs: { id: string }[]) => xs.map((x) => x.id).join(',');

Deno.test('the reading keeps every non-rehearsal for the books and records the rehearsals', () => {
  const t = splitRehearsals('test', 'sk_test_x', [demoS, realS], [demoR, realR]);
  eq(ids(t.sessions), 'cs_test_real', 'test sessions kept');
  eq(ids(t.refunds), 're_real', 'test refunds kept');
  eq(t.rehearsal.sessions.join(','), 'cs_test_demo', 'rehearsal sessions recorded');
  eq(t.rehearsal.refunds.join(','), 're_demo', 'rehearsal refunds recorded');
  const l = splitRehearsals('live', 'sk_live_x', [demoS, realS], [demoR, realR]);
  eq(ids(l.sessions) + '|' + ids(l.refunds), 'cs_test_demo,cs_test_real|re_demo,re_real', 'live keeps everything');
  eq(l.rehearsal.sessions.length + l.rehearsal.refunds.length, 0, 'live records no rehearsal');
});

Deno.test('a live key stored under the test name drops nothing', () => {
  for (const k of ['sk_live_x', 'rk_live_x', '']) {
    const m = splitRehearsals('test', k, [demoS], [demoR]);
    eq(ids(m.sessions) + '|' + ids(m.refunds), 'cs_test_demo|re_demo', `key ${k.slice(0, 7)}`);
  }
  eq(ids(splitRehearsals('test', 'rk_test_x', [demoS], []).sessions), '', 'restricted test key');
});

const eq = (a: unknown, b: unknown, m: string) => {
  if (a !== b) throw new Error(`${m}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
};

Deno.test('a test session paid by a demo account is a rehearsal', () => {
  eq(isRehearsal('test', sessionPayer({ customer_details: { email: 'qd-abc-customer1@example.invalid' } })), true, 'customer_details');
  eq(isRehearsal('test', sessionPayer({ customer_email: 'zz.demo@example.com' })), true, 'customer_email');
});

Deno.test('a test object with a real or missing payer still raises', () => {
  eq(isRehearsal('test', sessionPayer({ customer_details: { email: 'buyer@realco.ae' } })), false, 'real email');
  eq(isRehearsal('test', sessionPayer({})), false, 'no email');
  eq(isRehearsal('test', sessionPayer({ customer_email: 'a@example.invalid.attacker.com' })), false, 'suffix trick');
  eq(isRehearsal('test', sessionPayer({ metadata: { demo: 'true', qd_run: 'x' } })), false, 'metadata alone proves nothing');
});

Deno.test('LIVE is never a rehearsal, even with a demo email or demo metadata', () => {
  eq(isRehearsal('live', 'qd-abc-customer1@example.invalid'), false, 'live + demo email');
  eq(isRehearsal('live', sessionPayer({ customer_email: 'x@example.com', metadata: { demo: 'true' } })), false, 'live + everything');
});

Deno.test('a refund is judged by its charge payer', () => {
  eq(isRehearsal('test', refundPayer({ charge: { billing_details: { email: 'qd-t-c1@example.invalid' } } })), true, 'billing_details');
  eq(isRehearsal('test', refundPayer({ charge: { billing_details: { email: null }, customer: { email: 'qd-t-c1@example.invalid' } } })), true, 'customer');
  eq(isRehearsal('test', refundPayer({ charge: 'ch_unexpanded' })), false, 'unexpanded charge');
  eq(isRehearsal('live', refundPayer({ charge: { receipt_email: 'qd-t-c1@example.invalid' } })), false, 'live refund');
});
