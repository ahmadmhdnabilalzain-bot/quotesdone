// ONE LIST FOR THE MONEY DOOR (3 Sep 2026).
//
// stripe_webhook handles a fixed set of event types; stripe_setup registers and audits the Stripe
// endpoint for exactly that set. Until today the two lists were kept in step by hand — a branch added
// to the handler without the matching entry here meant Stripe never sent the event and the ledger
// silently never moved (the 2 Aug refund defect). Both functions now read this module: the handler
// branches on these arrays and the setup registers their union, so they cannot drift apart.
export const CHECKOUT_EVENTS = ['checkout.session.completed'] as const;
export const REFUND_EVENTS = ['charge.refunded', 'refund.created', 'refund.updated', 'refund.failed'] as const;
export const HANDLED_STRIPE_EVENTS: readonly string[] = [...CHECKOUT_EVENTS, ...REFUND_EVENTS];
