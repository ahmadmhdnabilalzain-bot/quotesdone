---
name: the-tier-is-the-bill-not-the-prompt
description: 76% of AI spend is the large tier on 38% of calls; routine_employee_reasoning already exists at medium tier and nothing points at it. Worth AED 80-120/month and still undecided.
metadata: 
  node_type: memory
  type: project
  originSessionId: 0ac5c5e2-c087-483c-b4d1-2cb949855d6b
  modified: 2026-08-14T04:15:02.245Z
---

Measured 14 Aug 2026, production, 30 days: AED 211.41 across 3,258 calls and 51 call sites.

| tier | calls | AED | % |
|---|---|---|---|
| large (sonnet-5/opus-4.8) | 1,251 | 161.49 | **76.4%** |
| medium (haiku/gemini-3.5-flash) | 1,096 | 27.41 | 13.0% |
| small (gemini-3.1-flash-lite) | 751 | 1.40 | 0.7% |

**The large tier is ~5x medium's unit price and does 38% of the calls for 76% of the money.** No
large call site is expensive because of what it sends — prompt caching, prompt shrinking and
killing duplicate tasks together are worth roughly AED 12/month against this.

`model_policy.routine_employee_reasoning` (medium, gemini-3.5-flash) **already exists** and its own
rationale says it "replaces the current blanket large-tier agent_reasoning", then adds *"this row
exists and does not take over"*. Nothing routes to it. Switching the routine loop is worth an
estimated **AED 80–120/month** — more than everything else in the audit combined by 4x.

**Not done, deliberately, and it is the open item.** It is a genuine quality trade-off, not a
defect, and it should be staged: recurring `kpi.missed` / `test.failed` / `content.published` tasks
first; founder-facing and customer-facing paths never. Full working in
`docs/audits/AI_SPEND_2026_08_14.md` §7.

Do not re-derive the spend shape from scratch next session — re-measure the totals, then go
straight to this. Related: [[constant-length-is-not-constant-bytes]] (the caching half, done).
