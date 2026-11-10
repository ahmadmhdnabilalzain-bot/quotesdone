# How a customer request ends (sales_engineer, 10 Nov 2026)

The default operating policy, decided on the IT/CEO side under the founder's "no decision goes to me" (ledger 1596, the
session's technical delegation; founder ruling 1608 asked for the audit that found the gap). Every number is a
`public.decision_policy` row: change the row to tune it, never the code. The database enforces it in
`fn_sales_engineer_request_outcomes`, run every 6 hours as the seat duty `sales_engineer.request_outcomes`
(`scripts/sql/a_request_that_reached_suppliers_ends_expired_lost_or_completed_and_everyone_is_told.sql`).

A "part" is a request with no per-trade children, or one child of a split request. A split's parent is closed once every
part has closed.

| the part | when | becomes | who is told |
|---|---|---|---|
| reached nobody | 14 days after posting | `expired` ("we are still registering suppliers", or, if the matcher never answered and every re-match failed, "a fault on our side") | the customer |
| the matcher did not answer | on `rematch_backoff_minutes` (10 tries over ~6 days) | matched again; never closed while the re-match runs | the customer, once it reaches suppliers |
| reached suppliers, no quote | `request_no_quote_expiry_days` = 21 after the first supplier was sent it | `expired`, "no matched supplier quoted in time"; a `coverage_gap` action for its trade and emirate | the customer and every matched supplier |
| quoted, no reveal, cancel or hire | `request_quoted_reminder_days` = 14 after the LAST quote | one reminder | the customer |
| the same | `request_quoted_lost_days` = 30 after the LAST quote | `lost` | the customer and every matched supplier |
| revealed, no hire or completion | `request_revealed_close_days` = 60 after the last reveal | `completed`, outcome `completed_without_award` | the customer, and every matched supplier except the one revealed |
| the same, follow-up answered "not yet" | within `request_revealed_not_yet_grace_days` = 30 of that answer | stays open | — |
| the follow-up answered "yes, hired" | at once | `completed`, outcome `hired` (`fn_customer_followup_answer`) | the losing suppliers |

A late "I hired this supplier" still records after an automatic close: `complete_inquiry` awards while
`hired_supplier_id` is null. Customers are written in the request's language, suppliers in English, through
customer_support's doors (`fn_customer_support_duty_send`, `fn_customer_support_takes_delivery`), each once.
An intake (the request conversation) left in `needs_info` or `ready` for `intake_abandoned_days` = 30 is marked
`expired` with no message; any new turn on it carries on as before.
