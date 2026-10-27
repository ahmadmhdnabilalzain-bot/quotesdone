---
name: a-30-day-total-is-not-a-run-rate
description: "AED 211/30d hid AED 890/month accelerating; always plot the daily series. And the biggest waste is repeat output on unchanged input, not the model tier."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0ac5c5e2-c087-483c-b4d1-2cb949855d6b
  modified: 2026-08-14T05:01:40.868Z
---

14 Aug 2026, the spend audit. The brief and my own first pass both worked from "AED 210.38 over 30
days". Plotting it by day changed every conclusion:

    5 Aug 0.44 | 6-9 Aug 12-17/day | 10 Aug 22.58 | 11 Aug 38.00 | 12 Aug 21.54 | 13 Aug 29.30

**Nearly half the 30-day total landed in the last four days.** The real trailing rate was AED
29.7/day ≈ 890/month and rising — 4x the headline. The 30-day total also carried a caller-
attribution bug fixed on 9 Aug: 209 of 258 `ceo` rows were pre-fix, making `agent_brain` look like
51% of spend when over four days it was 26%.

**How to apply:** never reason about cost, throughput or failure from a single window total. Group
by day and look at the shape. Then split by the deploy timestamp of any fix inside the window (see
[[a-check-held-open-by-pre-fix-rows]] — same lens, applied to money).

**And the second lesson, which was worth more than the tier.** The instinct was to save money by
routing to a cheaper model. What actually paid was finding work that carried NO INFORMATION:

* `exec_agents` filed 44-45 reports per officer over four days — ~11 a day each, six officers —
  while the marketplace took 0 inquiries, 0 quotes, 0 trades. Only the NEWEST per officer is ever
  read. Guard on the INPUT (metrics unchanged since the last report for this period ⇒ no model
  call), never on the clock, so a real change still reports instantly. ~AED 120/month.
* `fn_event_dispatch` re-minted a task every hour for a condition that stays true.
* `agent_brain` sent back the employee's own previous 20,000-character deliverable in its live
  snapshot.

Ask of any recurring cost: **is the input different from last time?** If not, the output cannot be.
That question found ~AED 230/month and cost nothing in quality. The tier trade-off
([[the-tier-is-the-bill-not-the-prompt]]) is still open and still the founder's call.
