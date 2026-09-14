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
