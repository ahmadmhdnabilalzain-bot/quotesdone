---
name: rating-solicitation-timing
description: "SUPERSEDED 9 Sep 2026 — Support emails the customer 3 weeks after the reveal date. Was: after the revealed quote's own stated duration."
metadata: 
  node_type: memory
  type: project
  originSessionId: 3b7766ae-d5e8-47ac-a4c7-b309a8da2194
  modified: 2026-09-09T01:55:12.062Z
---

The rating request (email + WhatsApp, 1–5 plus a short written reason) fires after the
**duration stated on the quote the customer revealed**, measured from the reveal — not a fixed
~3 months. Founder, 2026-08-08: "it depends on the duration mentioned on the quotes received.
once the customer reveal a specific quote, the duration will be mentioned there. so if its a week
for example, then we ask the customer after 7 working days." The wait is an estimate of when the
job is done, so it scales with job size.

**Why:** an earlier reading of the spec assumed a fixed 90-day delay. That would ask for a rating
on a one-week job eleven weeks late, and on a nine-month fit-out while it is still running.

**How to apply:** the selector joins reveal timestamp + quote duration, not `completed_at + 90d`.
The founder asked for a demo quote with a reveal and a **1-hour** duration so the flow can be
tested end to end before it is built fully. Related: [[quotesdone-definition-of-done]],
[[quotesdone-autonomy-and-staging-rules]].


---

## SUPERSEDED 9 September 2026

The founder: *"supplier rating should be from customers after they tried them. **support should send an
email after 3 weeks from the reveal date**"*

So: a fixed **21 days from revealed_at**, configurable, and **Support sends it** — the message is a
channel action and Support owns the pipe. Not the quote duration, not 90 days, not at the reveal
moment.

Measured the same day, which is why he raised it: `reviews` 0 rows · `leads.app_rating` 0 ·
`leads.app_reviews` 0 — **nobody has ever been rated on this platform**. `supplier_reputation` is a
VIEW over `reviews`, so it already returns `review_count` 0 and `overall` null for all 22,264
suppliers; his "reputation should be zero cause no supplier is verified" was already true in the data.

What is NOT zero: **4,477 leads carry a scraped Google rating, average 4.57** (1,741 from Maps).
`customer_api:254` `ratingOf()` prefers the QuotesDone rating when `app_reviews > 0` and otherwise
falls back to Google, **labelled `source: 'Google'`**. Keep that label. A scraped rating must never
be presented as one earned here — see [[sales-and-support-divide-by-surface-and-by-truth]].

The two numbers are kept as **separate keys** in the portal report — `rating_earned_here`
(true_zero) and `rating_from_directory` (derived_not_earned) — never one field that could be read
as "your rating".
