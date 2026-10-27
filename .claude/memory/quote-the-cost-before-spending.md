---
name: quote-the-cost-before-spending
description: "Standing rule from 15 Aug 2026 — state the estimated OpenRouter cost and WAIT for approval before any run that spends, however small."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 951680f6-998d-4578-b818-e62f587f57e4
  modified: 2026-08-15T02:47:04.093Z
---

Before **any** run that spends OpenRouter credit, state the estimated cost and **wait for his
answer**. No exceptions for "small", "capped", or "the brief asked for a smoke suite".

His words, 15 Aug 2026: *"later on when we do the tests thats when we actually use open router and
you have to tell me always before you apply how much would it cost"* — after a 16-scenario capped
smoke, which the brief itself had asked for.

**Why:** he is watching a balance, not a budget line. A number appearing after the fact gives him
no decision. A number before it does. This does not conflict with the "make the engineering call"
rule — spend is one of the three things that IS his: money, destructive production changes, and
facts only he holds.

**How to apply:** quote it as `N calls × observed AED/call = AED X (~USD Y)`, derived from
`ai_cost_log` for the same `fn` and tier, and name what the run would prove that a free check
cannot. Then stop and wait.

**And separate the two spenders when reporting**, because he will otherwise attribute all of it to
testing. Measured that same day, per hour, from `ai_cost_log`: the 16-scenario smoke cost USD 0.80
on staging, while the **production cron fleet** — `agent_brain`, `cos_execute`, `dept_plan`,
`dept_learn`, `exec_agents`, `analytics_recommend`, `knowledge_exam`, `action_worker`,
`workflow_dispatch` — spent USD 1.84 in the same three hours without anyone asking it to. Query
`ai_cost_log` grouped by hour and `fn` before answering any question about where the money went.

Related: [[a-30-day-total-is-not-a-run-rate]], [[the-tier-is-the-bill-not-the-prompt]].
