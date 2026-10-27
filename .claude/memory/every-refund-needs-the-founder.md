---
name: every-refund-needs-the-founder
description: "Founder ruling 17 Aug 2026 — every refund needs his approval at any amount, even AED 10. No window, ceiling or policy may approve one."
metadata: 
  node_type: memory
  type: project
  originSessionId: d089c73b-6b45-4e66-aa23-4b1eefd1aff0
  modified: 2026-08-17T22:20:01.618Z
---

**His words, 17 Aug 2026:** *"for refunds, change it into always. even for 10 AED it needs founder
approval."*

Given when I reported that `fn_refund_request` auto-approved a refund inside the window promised at
reveal and under `org_authority(customer_success, refund_within_window)` — live at **AED 2,000**.
He removed the threshold entirely rather than lowering it.

**What that path actually did, and why it mattered more than the money:** it wrote
`refunds.decided_by = 'policy:auto_window'` **and** `transactions.refund_status = 'approved'`. His
queue lists transactions where `refund_status = 'requested'`, so an auto-approved refund was never in
it — not held, not shown, not declined. It went past him. It had never fired only because `refunds`
has never held a row.

**Enforced in three places** (`scripts/sql/refunds_always_need_the_founder.sql`, PR #435, merged
2ce3fa6), because one mechanism is one edit from gone — see
[[a-disposition-in-prose-with-no-mechanism]]:

1. `fn_refund_request` always writes `'requested'`. `within_auto_window` is still recorded as a
   **fact** for him to weigh, and decides nothing.
2. `fn_refund_decide` refuses a decider that is not an ACTIVE row in `phase_c_founder_identity`.
   It used to accept any non-empty string.
3. `z00_refund_founder_decision_only` on `public.refunds` refuses any row reaching `'approved'`
   without a founder in `decided_by` — SQLSTATE 42501.

`org_authority` was deliberately left alone: `fn_autonomy_class`, `fn_ops_authority_check` and
`fn_os_portals_gates` read those rows for classification unrelated to approving a refund.

**How to apply:** this supersedes the older, vaguer "only Stripe refunds need approval" in
[[quotesdone-autonomy-and-staging-rules]] — it is *all* refunds, at *any* amount, and it is now a
database guard rather than a convention. Never reintroduce an amount-based or window-based
auto-approval, and if a future feature needs one, that is a founder question, not an engineering one.
