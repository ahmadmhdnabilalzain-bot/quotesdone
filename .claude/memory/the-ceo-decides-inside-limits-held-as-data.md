---
name: the-ceo-decides-inside-limits-held-as-data
description: "15 Nov 2026, ledger 1696/1701 — the CEO has full authority and the objective is profit, first supplier coverage; nothing waits on the founder; hard limits are data in code, not prompt text"
metadata:
  type: project
---

Founder, 15 Nov 2026, ledger 1696: "CEO is having full authority. He can do whatever is needed to achieve the target we have
for the company. He doesnt rely on me in anything. He is fully responsible about his decisions and their outcomes".
Ledger 1701: "I want to be profitable and that should be the main concern for the CEO. So to achieve that: 1 we need enough
registered suppliers to be able to start a customer campaign later to fulfill their inquiries. So the ceo need to find a way.
And thats why i want him to be able to take actions and give tasks to the agent".

**What it means for any build:**
- No path asks or waits on the founder (no ask_founder, no "needs the founder" choice, no escalation to him). The CEO decides,
  the decision is recorded with its reason, and the founder reads it once a day as information (kind `ceo_daily_summary`).
  The CEO's own late hand-overs are in the CEO's own queue. The IT engineer's questions go to the CEO; only a destructive
  production deploy stays outside the authority check (settled the same day).
- The hard limits live in code and data, never in a prompt: `company_limit_change` (per-action and daily AED; append-only; the
  CEO changes one with a reason and it takes effect 24 hours later), `company_spend_commitment` (checked and written under one
  lock), and the existing message gates (consent, suppressions, opt-out, inbox placement) read for a named recipient.
- The objective is data: `supplier_coverage_target` per trade per emirate, read daily against `fn_supplier_coverage`; the CEO's
  loop orders seats through the pool (`ceo.order`) with a measured outcome, the leads and a due date.
- On 15 Nov production had 0 real inquiries, so there is no customer demand to read; the proposal comes from the waitlist and
  the sales engineer's recruitment decisions, with the target at the company's opening level (10). Coverage read 4 of 1,440.

Files: `scripts/sql/the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql`,
`scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql`,
`scripts/sql/the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql`; runbook `docs/runbooks/apply-the-shared-pool.md`.
Related: [[refunds-belong-to-the-ceo]], [[launch-governance-loop-closed]], [[autonomous-company-is-the-standard]].
