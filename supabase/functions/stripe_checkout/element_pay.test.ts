// Run: deno test --node-modules-dir=none supabase/functions/stripe_checkout/element_pay.test.ts
// deno-lint-ignore-file no-explicit-any
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
    if (path.startsWith('invoices?customer=')) return { ok: true, status: 200, j: { data: [] } };
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
  const piMd = f.calls.find((c) => c.path === 'payment_intents/pi_zzdemo' && c.form)!.form!;
  assertEquals([piMd['metadata[fee_basis]'], piMd['metadata[card_country]'], piMd['metadata[wallet]'], inv['metadata[total_charged]']], ['domestic', 'AE', 'apple_pay', '300']);
  assertEquals(Object.keys(inv).some((k) => /tax/.test(k)), false, 'no tax parameter on the invoice');
  assertEquals(f.calls.find((c) => c.path.endsWith('/confirm'))!.path, 'payment_intents/pi_zzdemo/confirm');
  assertEquals(f.calls.find((c) => c.path === 'payment_intents/pi_zzdemo')!.form!.statement_descriptor_suffix, 'RVZZDEMO01');
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

// ---- gap #7 (3 Nov 2026, accountant): two tabs, one quote --------------------------------------------------------
// A Stripe that keeps idempotency keys, invoices and PaymentIntents, and confirms a PaymentIntent once. Measured
// in Stripe test mode before the fix (acpay01-03): two tokens made two invoices and BOTH were charged.
function statefulStripe(declineFirst = false) {
  const byKey = new Map<string, unknown>(); const invoices: any[] = []; const pis: Record<string, any> = {};
  let n = 0; let declines = declineFirst ? 1 : 0;
  const tick = () => new Promise((r) => setTimeout(r, 1));
  const stripe: StripeCall = async (path, form, idem) => {
    await tick();
    if (idem && byKey.has(idem)) return byKey.get(idem) as any;
    const done = (res: any) => { if (idem) byKey.set(idem, res); return res; };
    if (path.startsWith('confirmation_tokens/')) return { ok: true, status: 200, j: { payment_method_preview: card('AE') } };
    if (path.startsWith('customers/search')) return { ok: true, status: 200, j: { data: [{ id: 'cus_zzdemo' }] } };
    if (path.startsWith('invoices?customer=')) return { ok: true, status: 200, j: { data: invoices.map((x) => ({ ...x })) } };
    if (path === 'invoices') { const inv = { id: 'in_' + (++n), status: 'draft', metadata: Object.fromEntries([...form!].filter(([k]) => k.startsWith('metadata[')).map(([k, v]) => [k.slice(9, -1), v])), pi: 'pi_' + n, amount_due: 0 }; invoices.push(inv); pis[inv.pi] = { status: 'requires_payment_method', confirms: 0 }; return done({ ok: true, status: 200, j: { id: inv.id } }); }
    if (path === 'invoiceitems') { const inv = invoices.find((x) => x.id === form!.get('invoice'))!; inv.amount_due += Number(form!.get('amount')); return done({ ok: true, status: 200, j: { id: 'ii_' + inv.id } }); }
    const m = path.match(/^invoices\/(in_\d+)\/(finalize|void)$/);
    if (m) { const inv = invoices.find((x) => x.id === m[1])!; if (m[2] === 'void') { inv.status = 'void'; pis[inv.pi].status = 'canceled'; return { ok: true, status: 200, j: {} }; }
      inv.status = 'open'; return done({ ok: true, status: 200, j: { amount_due: inv.amount_due, confirmation_secret: { client_secret: inv.pi + '_secret_x' } } }); }
    const p = path.match(/^payment_intents\/(pi_\d+)(\/confirm)?$/);
    if (p) {
      const pi = pis[p[1]];
      if (!p[2]) return form ? done({ ok: true, status: 200, j: {} }) : { ok: true, status: 200, j: { status: pi.status } };
      if (pi.status !== 'requires_payment_method') return done({ ok: false, status: 400, j: { error: { type: 'invalid_request_error', code: 'payment_intent_unexpected_state' } } });
      if (declines-- > 0) return done({ ok: false, status: 402, j: { error: { type: 'card_error', code: 'card_declined', decline_code: 'generic_decline' } } });
      pi.status = 'succeeded'; pi.confirms++; invoices.find((x) => x.pi === p[1])!.status = 'paid';
      return done({ ok: true, status: 200, j: { status: 'succeeded' } });
    }
    return { ok: false, status: 404, j: {} };
  };
  return { stripe, invoices, pis };
}

Deno.test('two tabs paying one quote at once are charged ONCE and both see that one payment', async () => {
  const f = statefulStripe();
  const [a, b] = await Promise.all([payReveal(f.stripe, { ...args(30000), ct: 'ctoken_tab1' }), payReveal(f.stripe, { ...args(30000), ct: 'ctoken_tab2' })]);
  const charged = Object.values(f.pis).filter((x: any) => x.status === 'succeeded');
  assertEquals(charged.length, 1, 'exactly one PaymentIntent was charged');
  assertEquals([a.status, b.status], ['succeeded', 'succeeded']);
  assertEquals((a as any).payment_intent, (b as any).payment_intent);
  // A third press after the payment: nothing is invoiced or charged again.
  const c = await payReveal(f.stripe, { ...args(30000), ct: 'ctoken_tab3' });
  assertEquals(c.status, 'already_paid');
  assertEquals(f.invoices.length, 1);
});

Deno.test('a declined card voids its invoice and the next attempt gets a fresh one, never the void one', async () => {
  const f = statefulStripe(true);
  const first = await payReveal(f.stripe, { ...args(30000), ct: 'ctoken_try1' });
  assertEquals(first.status, 'failed');
  const second = await payReveal(f.stripe, { ...args(30000), ct: 'ctoken_try2' });
  assertEquals(second.status, 'succeeded');
  assertEquals(f.invoices.map((x) => x.status), ['void', 'paid']);
});
