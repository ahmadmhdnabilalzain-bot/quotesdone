---
name: an-externally-issued-refund-is-a-fact-not-a-request
description: "Three originators — stripe_webhook, stripe_dashboard, stripe — must be exempt from every money guard on public.refunds, or the webhook loses our only record of real money leaving."
metadata: 
  node_type: memory
  type: project
  originSessionId: e91f68dd-ccad-4fba-8fd1-3cb4e80753e3
  modified: 2026-08-26T13:45:45.512Z
---

`public.fn_refund_settle` is the Stripe webhook path. It records a refund issued OUTSIDE this
platform and inserts with **no `transaction_id`**, because there may not be one. On 26 Aug 2026 the
new `a00_refund_amount_is_the_fee_paid` refused exactly that row with `23514 refund_names_no_payment`
— so a real refund from the Stripe dashboard would have gone unrecorded.

The estate already knew this and had already written it down, two files away, in
`fn_phase_c_refund_execution_requires_decision`:

> "A refund Stripe already issued is a FACT to be recorded, not a request to be approved; refusing
> the row would delete our only record of real money leaving, which is worse than admitting it."

**Before tightening anything on `public.refunds`, grep for that exemption list**
(`array['stripe_webhook','stripe_dashboard','stripe']`, matched on `lower(requested_by)`) and carry
it, read the same way, or the two guards drift into disagreeing about what an external refund is.
`fn_kernel_refund_ledger_state` counts these separately and has never counted them as
founder-approved, so exempting them concedes nothing.

Consequence worth remembering: **`refunds.transaction_id` must stay nullable.** Making it NOT NULL
looks like the root-cause fix for "a refund must name a payment" and it is not — it closes the
webhook path permanently.

Related: [[a-rule-at-intake-is-not-a-rule-at-the-decision]], [[every-refund-needs-the-founder]],
[[a-nullable-column-a-trigger-requires]].
