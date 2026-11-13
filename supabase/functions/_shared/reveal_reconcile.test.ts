// Run: deno test --node-modules-dir=none supabase/functions/_shared/reveal_reconcile.test.ts
// A fake Stripe and a fake book. The book behaves like recordRevealSale: one sale per quote (transactions.quote_id is
// unique), a second PaymentIntent on a sold quote is never written. Fixtures are ZZ DEMO shaped; nothing reaches Stripe.
import { assertEquals } from 'jsr:@std/assert@1';
import type { SaleArgs } from './reveal_sale.ts';
import { clampDays, invoiceCandidate, mergeCandidates, paymentIntentCandidate, reportable, sweepReveals, type SweepDeps, type Tx } from './reveal_reconcile.ts';

const NOW = 1_800_000_000;
const HOUR = 3600;
const inv = (id: string, quote: string, pi: string | null, o: Record<string, unknown> = {}) => ({
  id, object: 'invoice', status: 'paid', livemode: true, amount_paid: 30000, currency: 'aed', customer_email: 'zz-demo@example.invalid',
  created: NOW - 2 * HOUR, status_transitions: { paid_at: NOW - 2 * HOUR },
  metadata: { kind: 'reveal', flow: 'element', quote_id: quote, customer_id: 'c-zz', base_fee: '300', processing_fee: '0' },
  payments: { data: pi ? [{ payment: { type: 'payment_intent', payment_intent: pi } }] : [] }, ...o,
});
const pint = (id: string, quote: string | null, o: Record<string, unknown> = {}) => ({
  id, object: 'payment_intent', status: 'succeeded', livemode: true, amount: 30000, amount_received: 30000, currency: 'aed',
  created: NOW - 2 * HOUR, metadata: quote ? { quote_id: quote } : {}, ...o,
});

type World = { invoices: any[]; intents: any[]; book: Tx[]; refunded?: Record<string, number>; unreadable?: Set<string>; failRecord?: Set<string>; listDown?: boolean;
  modes?: ('live' | 'test')[]; fees?: Record<string, number>; notDemo?: Set<string> };

function deps(w: World, calls: { record: SaleArgs[]; lists: string[] } = { record: [], lists: [] }): SweepDeps {
  return {
    modes: w.modes ?? ['live'],
    list: async (_m, path) => {
      calls.lists.push(path);
      if (w.listDown) return null;
      const src = (path.startsWith('invoices') ? w.invoices : w.intents).filter((x) => (x.livemode !== false) === (_m === 'live'));
      const after = /starting_after=([^&]+)/.exec(path)?.[1];
      const from = after ? src.findIndex((x) => x.id === after) + 1 : 0;
      const page = src.slice(from, from + 2);              // pages of 2, so paging is exercised
      return { data: page, has_more: from + 2 < src.length };
    },
    invoicePayment: async (_m, id) => (w.invoices.find((i) => i.id === id)?.payments?.data?.[0]?.payment?.payment_intent ?? null),
    readPayment: async (_m, pi) => (w.unreadable?.has(pi) ? null
      : { status: 'succeeded', amount_received: 30000, amount_refunded: w.refunded?.[pi] ?? 0, fee_fils: 1234, fee_details: [{ type: 'stripe_fee' }] }),
    recordFee: async (tx, fee) => { (w.fees ??= {})[tx] = fee; },
    isDemoQuote: async (q) => !w.notDemo?.has(q),
    findTransactions: async (q) => w.book.filter((t) => q.invoices.includes(t.stripe_invoice_id!) || q.refs.includes(t.payment_ref!) || q.quotes.includes(t.quote_id!)),
    record: async (a) => {
      calls.record.push(a);
      if (w.failRecord?.has(a.quoteId)) return { error: 'quote not found: ' + a.quoteId };
      const had = w.book.find((t) => t.quote_id === a.quoteId);
      // reveal_sale.ts: an empty stripe_invoice_id on the existing sale is filled with the caller's invoice.
      if (had) { if (!had.stripe_invoice_id && a.invoiceId) had.stripe_invoice_id = a.invoiceId; return { id: had.id, created: false }; }
      const t = { id: 'tx-' + a.quoteId, quote_id: a.quoteId, payment_ref: a.paymentRef, stripe_invoice_id: a.invoiceId || null };
      w.book.push(t);
      return { id: t.id, created: true };
    },
  };
}

Deno.test('a paid reveal invoice with no sale is recorded through recordRevealSale with its PaymentIntent', async () => {
  const w: World = { invoices: [inv('in_zz1', 'q1', 'pi_zz1')], intents: [], book: [] };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => x.outcome), ['recovered']);
  // 13 Nov 2026: the healed sale carries Stripe's own paid time, so its refund window counts from the payment, not the heal
  assertEquals(calls.record, [{ quoteId: 'q1', customerId: 'c-zz', baseFee: 300, processingFee: 0, totalCharged: 300, paymentRef: 'pi_zz1', invoiceId: 'in_zz1',
    paidAt: new Date(w.invoices[0].status_transitions.paid_at * 1000).toISOString() }]);
  assertEquals(w.book.length, 1);
});

Deno.test('idempotent: a second run over the same Stripe writes nothing and reports nothing', async () => {
  const w: World = { invoices: [inv('in_zz1', 'q1', 'pi_zz1')], intents: [], book: [] };
  await sweepReveals(deps(w), { days: 30, nowSec: NOW });
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => x.outcome), ['recorded']);
  assertEquals(calls.record.length, 0);
  assertEquals(reportable(r.outcomes), []);
});

Deno.test('a sale is matched by stripe_invoice_id, by payment_ref = pi, and by the old payment_ref = in_ fallback', async () => {
  const w: World = {
    invoices: [inv('in_a', 'qa', 'pi_a'), inv('in_b', 'qb', 'pi_b'), inv('in_c', 'qc', 'pi_c')], intents: [],
    book: [{ id: 'ta', quote_id: 'qa', payment_ref: 'pi_other', stripe_invoice_id: 'in_a' },
           { id: 'tb', quote_id: 'qb', payment_ref: 'pi_b', stripe_invoice_id: null },
           { id: 'tc', quote_id: 'qc', payment_ref: 'in_c', stripe_invoice_id: null }],
  };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => [x.key, x.outcome, x.transactionId]), [['in_a', 'recorded', 'ta'], ['in_b', 'recorded', 'tb'], ['in_c', 'recorded', 'tc']]);
  assertEquals(calls.record.length, 0);
});

Deno.test('the PaymentIntent is never replaced by the invoice id: an unreadable one is failed, not recorded', async () => {
  const w: World = { invoices: [inv('in_zz2', 'q2', null)], intents: [], book: [] };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => [x.outcome, x.error]), [['failed', 'the PaymentIntent behind the invoice could not be read']]);
  assertEquals(calls.record.length, 0);
  const w2: World = { invoices: [inv('in_zz3', 'q3', 'pi_zz3')], intents: [], book: [], unreadable: new Set(['pi_zz3']) };
  assertEquals((await sweepReveals(deps(w2), { days: 30, nowSec: NOW })).outcomes[0].outcome, 'failed');
});

Deno.test('a refund decides: in full is nothing to record, in part is for the accountant; neither writes a sale', async () => {
  const w: World = { invoices: [inv('in_f', 'qf', 'pi_f'), inv('in_p', 'qp', 'pi_p')], intents: [], book: [], refunded: { pi_f: 30000, pi_p: 1000 } };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => [x.key, x.outcome]), [['in_f', 'refunded'], ['in_p', 'refunded_unrecorded']]);
  assertEquals(calls.record.length, 0);
});

Deno.test('a quote already sold under another payment is a second payment, never a second sale, and never touches the first', async () => {
  // Review of #1841: the first sale's reference may be pi_, in_ (element_settle / webhook fallback) or null-invoice.
  for (const first of [{ payment_ref: 'pi_1st', stripe_invoice_id: 'in_1st' }, { payment_ref: 'in_1st', stripe_invoice_id: 'in_1st' },
                       { payment_ref: 'pi_1st', stripe_invoice_id: null }]) {
    const w: World = { invoices: [inv('in_2nd', 'qs', 'pi_2nd')], intents: [], book: [{ id: 'ts', quote_id: 'qs', ...first }] };
    const calls = { record: [] as SaleArgs[], lists: [] as string[] };
    const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
    assertEquals(r.outcomes.map((x) => [x.outcome, x.transactionId]), [['second_payment', 'ts']], JSON.stringify(first));
    assertEquals(calls.record.length, 0, 'recordRevealSale would stamp in_2nd onto the first sale');
    assertEquals(w.book, [{ id: 'ts', quote_id: 'qs', ...first }]);
    // ...so the next run still sees it, and once refunded in full it resolves.
    w.refunded = { pi_2nd: 30000 };
    assertEquals((await sweepReveals(deps(w), { days: 30, nowSec: NOW })).outcomes.map((x) => x.outcome), ['refunded']);
  }
  const cs: World = { invoices: [inv('in_x', 'qc', 'pi_x')], intents: [], book: [{ id: 'tc', quote_id: 'qc', payment_ref: 'cs_session', stripe_invoice_id: null }] };
  assertEquals((await sweepReveals(deps(cs), { days: 30, nowSec: NOW })).outcomes.map((x) => x.outcome), ['failed']);
});

Deno.test('two unrecorded payments of one quote in one run: one sale, one second payment', async () => {
  const w: World = { invoices: [inv('in_a1', 'qd', 'pi_a1'), inv('in_a2', 'qd', 'pi_a2', { status_transitions: { paid_at: NOW - HOUR } })], intents: [], book: [] };
  const r = await sweepReveals(deps(w), { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => [x.key, x.outcome]), [['in_a2', 'recovered'], ['in_a1', 'second_payment']]);
  assertEquals(w.book.length, 1);
});

Deno.test('a recovered sale gets the fee Stripe kept; the paid attempt is the one read, not a canceled one before it', async () => {
  const two = inv('in_pa', 'qp', null, { payments: { data: [{ status: 'canceled', payment: { payment_intent: 'pi_dead' } }, { status: 'paid', payment: { payment_intent: 'pi_live' } }] } });
  const w: World = { invoices: [two], intents: [], book: [] };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
  assertEquals(calls.record.map((a) => a.paymentRef), ['pi_live']);
  assertEquals(w.fees, { 'tx-qp': 1234 });
});

Deno.test('one payment, one outcome: a hosted-Checkout invoice and its PaymentIntent are not both reported', async () => {
  // Two paid sessions on one quote: nothing merges, so both invoices and both PaymentIntents are candidates.
  const w: World = { invoices: [inv('in_s1', 'qq', null), inv('in_s2', 'qq', null)], intents: [pint('pi_s1', 'qq'), pint('pi_s2', 'qq')],
    book: [{ id: 'tq', quote_id: 'qq', payment_ref: 'pi_s1', stripe_invoice_id: null }] };
  const r = await sweepReveals({ ...deps(w), invoicePayment: async (_m, id) => ({ in_s1: 'pi_s1', in_s2: 'pi_s2' } as Record<string, string>)[id] ?? null },
    { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.filter((x) => x.outcome === 'second_payment').length, 1);
});

Deno.test('live is read first with its own budget: test-mode payments that can never be recorded do not starve it', async () => {
  const dead = Array.from({ length: 4 }, (_, i) => ({ ...inv('in_t' + i, 'qt' + i, 'pi_t' + i), livemode: false }));
  const w: World = { modes: ['test', 'live'], invoices: [...dead, inv('in_live', 'qlive', 'pi_live', { status_transitions: { paid_at: NOW - 20 * 86400 } })],
    intents: [], book: [], failRecord: new Set(['qt0', 'qt1', 'qt2', 'qt3']) };
  const r = await sweepReveals(deps(w), { days: 30, nowSec: NOW, maxAttempts: 2 });
  assertEquals(r.outcomes.find((x) => x.key === 'in_live')?.outcome, 'recovered');
  assertEquals(r.outcomes.filter((x) => x.mode === 'test').map((x) => x.outcome).sort(), ['deferred', 'deferred', 'failed', 'failed']);
});

Deno.test('a TEST-mode payment whose quote is not a demo account writes no sale; a demo one is recorded; live never asks', async () => {
  const t = (id: string, q: string, pi: string) => ({ ...inv(id, q, pi), livemode: false });
  const w: World = { modes: ['test', 'live'], invoices: [t('in_tr', 'qreal', 'pi_tr'), t('in_td', 'qdemo', 'pi_td'), inv('in_lv', 'qlive', 'pi_lv')],
    intents: [], book: [], notDemo: new Set(['qreal', 'qlive']) };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
  assertEquals(Object.fromEntries(r.outcomes.map((x) => [x.key, x.outcome])), { in_tr: 'test_mode_not_demo', in_td: 'recovered', in_lv: 'recovered' });
  assertEquals(calls.record.map((a) => a.quoteId).sort(), ['qdemo', 'qlive']);
  assertEquals(w.book.some((x) => x.quote_id === 'qreal'), false);
  assertEquals(reportable(r.outcomes).filter((x) => x.outcome === 'test_mode_not_demo').length, 1);
});

Deno.test('a TEST-mode demo check that cannot be answered fails closed: no sale', async () => {
  const w: World = { modes: ['test'], invoices: [{ ...inv('in_tx', 'qx', 'pi_tx'), livemode: false }], intents: [], book: [] };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const d = deps(w, calls); d.isDemoQuote = async () => { throw new Error('rpc down'); };
  const r = await sweepReveals(d, { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => x.outcome), ['test_mode_not_demo']);
  assertEquals(calls.record.length, 0);
});

Deno.test('a recorder that refuses (quote gone) is failed with its reason', async () => {
  const w: World = { invoices: [inv('in_g', 'qg', 'pi_g')], intents: [], book: [], failRecord: new Set(['qg']) };
  const r = await sweepReveals(deps(w), { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => [x.outcome, x.error]), [['failed', 'quote not found: qg']]);
});

Deno.test('the hosted-Checkout PaymentIntent joins its invoice; a PaymentIntent with no invoice is its own candidate', async () => {
  const w: World = {
    invoices: [inv('in_h', 'qh', null)],
    intents: [pint('pi_h', 'qh'), pint('pi_solo', 'qsolo'), pint('pi_supplier', 'qx', { metadata: { kind: 'supplier_dues', quote_id: 'qx' } }), pint('pi_none', null)],
    book: [],
  };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW });
  assertEquals(r.outcomes.map((x) => [x.key, x.outcome, x.paymentIntent]), [['in_h', 'recovered', 'pi_h'], ['pi_solo', 'recovered', 'pi_solo']]);
  assertEquals(calls.record.map((a) => [a.quoteId, a.paymentRef, a.invoiceId]), [['qh', 'pi_h', 'in_h'], ['qsolo', 'pi_solo', '']]);
});

Deno.test('bounded: nothing inside the grace period, at most maxRecords recorded, at most maxPages pages read', async () => {
  const recent = inv('in_new', 'qn', 'pi_new', { status_transitions: { paid_at: NOW - 60 } });
  const w: World = { invoices: [inv('in_1', 'q1', 'pi_1'), inv('in_2', 'q2', 'pi_2'), inv('in_3', 'q3', 'pi_3'), recent], intents: [], book: [] };
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  const r = await sweepReveals(deps(w, calls), { days: 30, nowSec: NOW, maxRecords: 2 });
  assertEquals(r.too_recent, 1);
  assertEquals(r.outcomes.map((x) => x.outcome).sort(), ['deferred', 'recovered', 'recovered']);
  const w2: World = { invoices: [inv('in_1', 'q1', 'pi_1'), inv('in_2', 'q2', 'pi_2'), inv('in_3', 'q3', 'pi_3')], intents: [], book: [] };
  const r2 = await sweepReveals(deps(w2), { days: 30, nowSec: NOW, maxPages: 1 });
  assertEquals(r2.modes.live.truncated, true);
  assertEquals(r2.outcomes.length, 2);
});

Deno.test('the window is N days of created[gte], clamped to 1..90, and an unreadable Stripe is reported, not empty', async () => {
  const calls = { record: [] as SaleArgs[], lists: [] as string[] };
  await sweepReveals(deps({ invoices: [], intents: [], book: [] }, calls), { days: 7, nowSec: NOW });
  assertEquals(calls.lists[0], `invoices?status=paid&limit=100&created[gte]=${NOW - 7 * 86400}&expand[]=data.payments`);
  assertEquals([clampDays(0), clampDays(500), clampDays('x'), clampDays(14)], [1, 90, 30, 14]);
  const r = await sweepReveals(deps({ invoices: [], intents: [], book: [], listDown: true }), { days: 7, nowSec: NOW });
  assertEquals(r.modes.live.basis, 'unreadable');
});

Deno.test('candidates: only a paid invoice or a succeeded PaymentIntent that names a quote, never a supplier payment', () => {
  assertEquals(invoiceCandidate(inv('in_x', 'q', 'pi_x', { status: 'open' }), 'live'), null);
  assertEquals(invoiceCandidate(inv('in_x', '', 'pi_x'), 'live'), null);
  assertEquals(invoiceCandidate(inv('in_x', 'q', 'pi_x', { metadata: { kind: 'supplier_registration', quote_id: 'q' } }), 'live'), null);
  assertEquals(paymentIntentCandidate(pint('pi_x', 'q', { status: 'requires_payment_method' }), 'live'), null);
  // Two loose PaymentIntents on one quote are two payments: neither is folded into the invoice.
  const c = mergeCandidates([invoiceCandidate(inv('in_m', 'qm', null), 'live')!],
    [paymentIntentCandidate(pint('pi_m1', 'qm'), 'live')!, paymentIntentCandidate(pint('pi_m2', 'qm'), 'live')!]);
  assertEquals(c.map((x) => [x.key, x.paymentIntent]), [['in_m', null], ['pi_m1', 'pi_m1'], ['pi_m2', 'pi_m2']]);
});
