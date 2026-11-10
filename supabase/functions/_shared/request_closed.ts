// WHICH REQUEST STATUSES ARE THE END OF A REQUEST — one list for every edge function (sales_engineer, customer-journey
// audit 10 Nov 2026).
//
// The database closes a request in five ways: completed (hired), closed, cancelled (the customer), expired (reached no
// supplier in 14 days: fn_sales_engineer_closes_unreached_requests, which e-mails the customer "We have closed your
// request") and lost. Every SQL reader says so in one list — fn_sales_engineer_stalled_inquiry_rescue, the unreached
// sweep itself: ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost'), where 'revealed' is a live deal and
// not an end. Seven copies of a shorter list in the portals and the edge functions knew only three of them, so a request
// the customer had been told was closed still took notes that were mailed to suppliers (customer_api rfq_note), still
// took supplier questions (messages_api clarify_ask) and still counted as open on the dashboard (customer_portal).
// The portal's twin is src/components/me/requestStatus.ts; scripts/checks/one_list_says_a_request_is_closed.test.mjs
// holds both equal to each other and to the SQL list.
export const CLOSED_REQUEST_STATUSES = ['completed', 'closed', 'cancelled', 'expired', 'lost'] as const;

/** True when the request's status is the end of it: nothing more may be asked, noted or counted as open on it. */
export const isClosedRequest = (status: unknown): boolean =>
  (CLOSED_REQUEST_STATUSES as readonly string[]).includes(String(status ?? ''));
