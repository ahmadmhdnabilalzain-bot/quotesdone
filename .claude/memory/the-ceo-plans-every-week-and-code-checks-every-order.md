---
name: the-ceo-plans-every-week-and-code-checks-every-order
description: "15 Nov 2026, ledger 1705/1706/1709 — the CEO reasons a weekly plan on Opus from one planning pack; code checks every bet (channel verdict, message gates, limits, rulings) before it is a ceo.order; no hire, the founder works his own network and is told who is stuck"
metadata:
  type: project
---

Founder, 15 Nov 2026, ledger 1705/1706 (voice): "instead of him just telling me issues, he need to find solutions ... Shall I
hire? ... How can I get leads? ... Is it safe? If not, what's the alternative? ... KPI ... is about actually taking action".
Ledger 1709 (voice): no hire. The founder personally messages and calls his own network from his own number with
https://quotesdone.com/portal?join=1&utm_source=founder&utm_medium=whatsapp&utm_campaign=2026-11 (first touch is kept by
src/lib/firstTouch.ts and written to marketing_first_touch at registration).

**How the CEO plans (scripts/sql/the_ceo_thinks_plans_and_orders_every_week.sql, ceo_agent/plan.ts):**
- One pack, `fn_ceo_planning_pack(days)`: funnel by step and channel, registrations by first-touch source per day, the founder's
  people by step, placement by provider, replies and how each was handled, coverage and the operating target, demand, the pool,
  spend against limits and runway, each seat's board and open orders, rulings, the channel register, capabilities, last plan vs
  outcome. A section that fails says why; the pack never fails.
- Weekly (Monday 07:00 Dubai) on `ceo_strategic_planning` (Opus, effort high, 8,000 tokens); daily on
  `routine_employee_reasoning` only when code finds an anomaly. Cap: `decision_policy ceo_planning_loop.week_aed_cap` (AED 8).
- The model proposes; code files (ledger 1663): `fn_ceo_plan_bet_check` refuses a refused channel (with its alternative), a
  recipient the gates refuse, money over the limits, a seat that takes no ceo.order, a measure code cannot read, a date outside
  12 hours to 6 weeks, a capability nobody has (only a build order may name it), invitations while switched off, a duplicate
  open order, any ask of the founder. One revision, then refused bets are dropped and recorded.
- `ceo_growth_channel` holds each channel's verdict (safe / safe_if / refused), rule, rulings, alternative, and its Beta prior,
  learned daily from recorded outcomes with a lag and a watermark (never a window twice).
- The first plan (week of 16 Nov) is DATA (`ceo_plan_week` kind seed), filed by the loop's first run: the founder's network is
  bet 1; operating target 30 verified in three Dubai focus trades by 20 Dec (`ceo_operating_target`).
- The forecast no longer offers "tell_founder": a forecast decision is `ceo_own_decision`. Compliance re-checks are one monthly
  directive to the it_engineer (nothing updates compliance_sources.last_checked_at; 72 self-addressed ones were unmeetable).
- Invitations never go to Microsoft or Yahoo (ruling 1537, whatever GlockApps says): the register refuses that channel by rule.

Related: [[the-ceo-decides-inside-limits-held-as-data]], [[the-llm-understands-code-only-checks]],
[[whatsapp-supplier-invites-need-an-opt-in]].
