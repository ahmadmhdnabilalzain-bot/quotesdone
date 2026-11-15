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
- Review 4 of the base branch (15 Nov), fixed in this branch: service_role cannot write the limit tables (revoked; TRUNCATE and
  commitment edits refused by trigger; a change waits a day from clock_timestamp()); money is committed only under READ
  COMMITTED (the advisory lock only serialises a fresh read there); the 3-argument fn_agent_may_act refuses money (refunds
  excepted); every recipient an authority action would reach (ask AND subject lead:N / email:x) passes the message gates on every
  path; coverage reads fn_supplier_target_by_trade_emirate and leads with the year-one milestone (one number); only the focus
  trades (decision_policy ceo_focus_trades) are confirmed.
- REVIEW_ceoplan (15 Nov), fixed: never trust a model's LABEL. The bet check reads what a bet does: seat = the channel's owner
  (a build order to it_engineer excepted); the words of what/how against every refused channel's act (ceo_growth_channel.act_terms,
  no negation is read away: rules belong in `legal`); every AED amount in the words is a cost, bounded by max_cost_aed; any founder
  ask in the words is refused and no bet is addressed to him; lead_ids only as a JSON array of whole numbers, and only the checked
  array is forwarded; an e-mail batch names its providers. Registrant/model text is shown only through fn_ceo_plan_clean_text, and
  the pack goes to the model labelled untrusted data.
- Learning starts at apply + the lag (a watermark of now() re-reads the seed's own trials). fn_ceo_plan_due holds a try-lock (a
  second caller is "busy"); fn_ceo_priors_update re-reads each watermark under the lock.
- fn_ceo_plan_request is the one door to a model call: cap first, every call counted, a revision once; a malformed answer is held.
- A probe must keep its own world: ceo_plan_week/ceo_own_decision carry `world`, planted spend is model_used 'zz-demo/...', the
  probe files its own seed copy with dates from now, and reads the limits in force. Run the real-world scenario (seed filed, real
  orders, real spend, a waiting limit change) before calling a probe isolated.
- A pricing call is the CEO's own decision (ceo_own_decision); trg_high_stakes_review no longer mails the founder a proposal.
- service_role cannot write ceo_standing_grant or decision_policy (a seat cannot grant itself authority or raise a cap).

Related: [[the-ceo-decides-inside-limits-held-as-data]], [[the-llm-understands-code-only-checks]],
[[whatsapp-supplier-invites-need-an-opt-in]].
