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
export const HANDLED_STRIPE_EVENTS: readonly string[] = [...CHECKOUT_EVENTS, ...FAILED_CHECKOUT_EVENTS, ...REFUND_EVENTS, ...INVOICE_EVENTS];

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
