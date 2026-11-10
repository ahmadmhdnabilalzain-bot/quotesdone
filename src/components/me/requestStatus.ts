// WHICH REQUEST STATUSES ARE THE END OF A REQUEST — the portal's copy of supabase/functions/_shared/request_closed.ts
// (sales_engineer, customer-journey audit 10 Nov 2026). The database closes a request as completed, closed, cancelled,
// expired (reached no supplier in 14 days; the customer is e-mailed "We have closed your request") or lost. The portal
// knew three of them, so an expired request read "Matching" with a Cancel button, an open question box and the
// add-missing-specs form. scripts/checks/one_list_says_a_request_is_closed.test.mjs holds this list equal to the edge
// functions' and to the SQL's.
export const CLOSED_REQUEST_STATUSES = ['completed', 'closed', 'cancelled', 'expired', 'lost'] as const;

/** True when the request's status is the end of it. */
export const isClosedRequest = (status: unknown): boolean =>
  (CLOSED_REQUEST_STATUSES as readonly string[]).includes(String(status ?? ''));
