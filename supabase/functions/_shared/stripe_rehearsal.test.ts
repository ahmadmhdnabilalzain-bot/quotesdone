// deno test supabase/functions/_shared/stripe_rehearsal.test.ts
// The payment duty drops a Stripe object from reconciliation only when it is a provable rehearsal:
// TEST mode AND a reserved demo payer email. LIVE is never dropped, whatever the object carries.
import { isRehearsal, refundPayer, sessionPayer } from './it_duty_readings.ts';

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
