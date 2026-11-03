// ONE LIST FOR THE MONEY DOOR (3 Sep 2026).
//
// stripe_webhook handles a fixed set of event types; stripe_setup registers and audits the Stripe
// endpoint for exactly that set. Until today the two lists were kept in step by hand — a branch added
// to the handler without the matching entry here meant Stripe never sent the event and the ledger
// silently never moved (the 2 Aug refund defect). Both functions now read this module: the handler
// branches on these arrays and the setup registers their union, so they cannot drift apart.
export const CHECKOUT_EVENTS = ['checkout.session.completed'] as const;
// 14 Sep 2026: a reveal checkout that expired or whose delayed payment failed is handed to the sales
// engineer (payment.failed), who tells the customer nothing was charged. Without these two the
// customer who abandoned a payment heard nothing at all.
export const FAILED_CHECKOUT_EVENTS = ['checkout.session.expired', 'checkout.session.async_payment_failed'] as const;
export const REFUND_EVENTS = ['charge.refunded', 'refund.created', 'refund.updated', 'refund.failed'] as const;
// 14 Sep 2026 (agent: accountant): the reveal-fee Invoice is finalised a beat after the session
// completes, so its PDF often is not there on checkout.session.completed. These two events carry
// the finished invoice and let the handler file it without waiting for a manual resend.
export const INVOICE_EVENTS = ['invoice.finalized', 'invoice.paid'] as const;
// 14 Sep 2026 (agent: accountant, duty 7): a chargeback is recorded the moment Stripe opens it and
// answered with evidence before its due_by (scripts/sql/the_accountant_answers_every_card_dispute_before_stripe_closes_it.sql).
// Unhandled, Stripe closes an unanswered dispute as lost.
export const DISPUTE_EVENTS = ['charge.dispute.created', 'charge.dispute.updated', 'charge.dispute.closed',
  'charge.dispute.funds_withdrawn', 'charge.dispute.funds_reinstated'] as const;
// WHERE A REFUND EVENT'S REFUNDS ARE (22 Sep 2026, it_engineer). refund.* carries the refund itself.
// charge.refunded carries the Charge, and on current Stripe API versions the Charge no longer embeds
// its `refunds` list. MEASURED 21 Sep 2026: all 3 charge.refunded deliveries (17:09, 17:57, 21:11Z)
// arrived without it, were logged 'REFUND EVENT WITH NO REFUND OBJECT' at error level and quarantined,
// while the refund.created of the same second had already settled the refund. 'lookup' means: ask
// Stripe for the charge's refunds (GET /v1/refunds?charge=) rather than call a well-formed event broken.
// deno-lint-ignore no-explicit-any
export function refundsInEvent(type: string, o: any): { refunds: any[] } | { lookup: string } | { none: true } {
  if (Array.isArray(o?.refunds?.data) && o.refunds.data.length) return { refunds: o.refunds.data };
  if (o?.object === 'refund') return { refunds: [o] };
  if (type === 'charge.refunded' && o?.object === 'charge' && typeof o?.id === 'string' && o.id) return { lookup: o.id };
  return { none: true };
}
export const HANDLED_STRIPE_EVENTS: readonly string[] = [...CHECKOUT_EVENTS, ...FAILED_CHECKOUT_EVENTS, ...REFUND_EVENTS, ...INVOICE_EVENTS, ...DISPUTE_EVENTS];

// WHICH SIGNING SECRET MAY VERIFY AN EVENT (14 Sep 2026, agent: accountant). Stripe signs `livemode`
// inside the payload, so the mode an event claims chooses exactly ONE secret, and stripe_webhook
// accepts the event only if that secret verifies it. There is no second try with the other mode's
// secret: a test delivery can never be accepted as live, nor the reverse. Pure, so it is tested alone
// (stripe_events.test.ts).
export type StripeMode = 'live' | 'test';
// deno-lint-ignore no-explicit-any
export function stripeEventMode(event: any): StripeMode | null {
  if (event?.livemode === true) return 'live';
  if (event?.livemode === false) return 'test';
  return null;
}
export function signingSecretFor(mode: StripeMode | null, secrets: { live: string; test: string }): string {
  return mode === 'live' ? secrets.live : mode === 'test' ? secrets.test : '';
}

// WHETHER AN UNFINISHED REVEAL CHECKOUT IS NEWS TO THE CUSTOMER (3 Nov 2026, accountant, gap #7). An expired session
// took no money, but the customer may have paid the same quote in ANOTHER session or tab, or the Payment Element, and
// Stripe expires the abandoned one up to a day later. Measured 3 of 3 runs (acpay01-03): a quote already revealed and
// paid got a checkout.session.expired for its other tab, and the customer was written "Your reveal payment did not
// complete ... nothing was charged". A quote that has a recorded sale is told nothing about a session it did not need.
// deno-lint-ignore no-explicit-any
export function unfinishedRevealIsNews(session: any, quoteAlreadyPaid: boolean): boolean {
  return Boolean(session?.metadata?.quote_id) && session?.payment_status !== 'paid' && !quoteAlreadyPaid;
}
