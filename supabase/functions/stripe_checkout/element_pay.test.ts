// Run: deno test --node-modules-dir=none supabase/functions/stripe_checkout/element_pay.test.ts
// A recorder stands in for Stripe, so the test proves what is created, in what amount, and what is not.
import { assertEquals } from 'jsr:@std/assert@1';
import { payReveal, priceToken, type StripeCall } from './element_pay.ts';
import { feeBasisFromPreview } from '../_shared/reveal_fee.ts';

const card = (country: string | null, wallet: string | null = null) =>
  ({ type: 'card', card: { country, brand: 'visa', funding: 'credit', wallet: wallet ? { type: wallet } : null } });

function fakeStripe(preview: unknown, confirmStatus = 'succeeded') {
  const calls: { path: string; form?: Record<string, string> }[] = [];
  const stripe: StripeCall = async (path, form) => {
    calls.push({ path, form: form ? Object.fromEntries(form) : undefined });
    if (path.startsWith('confirmation_tokens/')) return { ok: true, status: 200, j: { payment_method_preview: preview } };
    if (path.startsWith('customers/search')) return { ok: true, status: 200, j: { data: [] } };
    if (path === 'customers') return { ok: true, status: 200, j: { id: 'cus_zzdemo' } };
    if (path === 'invoices') return { ok: true, status: 200, j: { id: 'in_zzdemo' } };
    if (path === 'invoiceitems') return { ok: true, status: 200, j: { id: 'ii_x' } };
    if (path.endsWith('/finalize')) {
      const total = calls.filter((c) => c.path === 'invoiceitems').reduce((s, c) => s + Number(c.form!.amount), 0);
      return { ok: true, status: 200, j: { amount_due: total, confirmation_secret: { client_secret: 'pi_zzdemo_secret_abc' } } };
    }
    if (path.endsWith('/confirm')) return confirmStatus === 'declined'
      ? { ok: false, status: 402, j: { error: { code: 'card_declined', decline_code: 'generic_decline' } } }
      : { ok: true, status: 200, j: { status: confirmStatus } };
    if (path.endsWith('/void')) return { ok: true, status: 200, j: {} };
    return { ok: false, status: 404, j: {} };
  };
  return { stripe, calls };
}
const args = (expectedTotalFils: number) => ({ ct: 'ctoken_zzdemo', quoteAmount: 10000, rate: 0.03, expectedTotalFils,
  email: 'zz.demo.buyer@example.invalid', qdCustomerId: 'c-zz', quoteId: 'q-zz', inquiryId: 'i-zz', supplierId: '1',
  requestRef: 'QD-ZZDEMO01', letter: 'A', returnUrl: 'https://quotesdone.com/me?reveal=q-zz' });

Deno.test('fee basis: a UAE card, and a UAE card inside Apple Pay, are domestic', () => {
  assertEquals(feeBasisFromPreview(card('AE')).basis, 'domestic');
  assertEquals(feeBasisFromPreview(card('ae', 'apple_pay')), { basis: 'domestic', card_country: 'AE', wallet: 'apple_pay', method: 'card', reason: 'card issued in AE' });
});

Deno.test('fee basis: a foreign card is international; an unknown method falls to the safest rate', () => {
  assertEquals(feeBasisFromPreview(card('GB')).basis, 'international');
  assertEquals(feeBasisFromPreview({ type: 'link' }).basis, 'international');
  assertEquals(feeBasisFromPreview(card(null)).basis, 'international');
  assertEquals(feeBasisFromPreview(null).basis, 'international');
});

Deno.test('every card pays the same AED 300 on an AED 10,000 quote: no card fee on any buyer', async () => {
  const uae = await priceToken(fakeStripe(card('AE')).stripe, 'ctoken_zzdemo', 10000, 0.03);
  const gb = await priceToken(fakeStripe(card('GB')).stripe, 'ctoken_zzdemo', 10000, 0.03);
  assertEquals(uae.ok && uae.priced.charge, { base_fee: 300, processing_fee: 0, total_charged: 300 });
  assertEquals(gb.ok && gb.priced.charge, { base_fee: 300, processing_fee: 0, total_charged: 300 });
});

Deno.test('a UAE card pays one invoice with exactly one line, the reveal fee, and confirms its own PaymentIntent', async () => {
  const f = fakeStripe(card('AE', 'apple_pay'));
  const r = await payReveal(f.stripe, args(30000));
  assertEquals(r.status, 'succeeded');
  assertEquals(f.calls.filter((c) => c.path === 'invoiceitems').map((c) => [c.form!.description, c.form!.amount]),
    [['Reveal fee (3% of AED 10000.00)', '30000']]);
  const inv = f.calls.find((c) => c.path === 'invoices')!.form!;
  assertEquals([inv['metadata[fee_basis]'], inv['metadata[card_country]'], inv['metadata[wallet]'], inv['metadata[total_charged]']], ['domestic', 'AE', 'apple_pay', '300']);
  assertEquals(Object.keys(inv).some((k) => /tax/.test(k)), false, 'no tax parameter on the invoice');
  assertEquals(f.calls.find((c) => c.path.endsWith('/confirm'))!.path, 'payment_intents/pi_zzdemo/confirm');
});

Deno.test('a total the customer was not shown is never charged: nothing is created at Stripe', async () => {
  const f = fakeStripe(card('GB'));
  const r = await payReveal(f.stripe, args(31220)); // shown a total that is not the reveal fee
  assertEquals(r.status, 'repriced');
  assertEquals(f.calls.map((c) => c.path), ['confirmation_tokens/ctoken_zzdemo']);
});

Deno.test('an unreadable reveal rate is refused and nothing is created at Stripe', async () => {
  for (const rate of [NaN, 0, undefined as unknown as number]) {
    const f = fakeStripe(card('AE'));
    const r = await payReveal(f.stripe, { ...args(0), rate });
    assertEquals([r.status, 'error' in r ? r.error : ''], ['failed', 'invalid_fee'], String(rate));
    assertEquals(f.calls.map((c) => c.path), ['confirmation_tokens/ctoken_zzdemo'], 'only the token is read');
  }
});

Deno.test('a declined card leaves no open invoice behind', async () => {
  const f = fakeStripe(card('AE'), 'declined');
  const r = await payReveal(f.stripe, args(30000));
  assertEquals(r.status, 'failed');
  assertEquals(f.calls.at(-1)!.path, 'invoices/in_zzdemo/void');
});

Deno.test('3-D Secure hands the client secret back instead of recording a sale', async () => {
  const r = await payReveal(fakeStripe(card('AE'), 'requires_action').stripe, args(30000));
  assertEquals(r.status === 'requires_action' && r.client_secret, 'pi_zzdemo_secret_abc');
});

Deno.test('a malformed token is refused before Stripe is asked', async () => {
  const f = fakeStripe(card('AE'));
  assertEquals((await priceToken(f.stripe, 'pm_card_visa', 10000, 0.03)).ok, false);
  assertEquals(f.calls, []);
});
