---
name: instruments-report-on-the-wrong-subject
description: "The recurring QuotesDone defect — a green number measures something other than the thing it names, because nothing separates \"measured zero\" from \"never measured\"."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0081aec4-fde6-48b7-8226-cd4e593cbe56
  modified: 2026-08-11T13:13:56.496Z
---

Nine of the fourteen contradictions in the 11 Aug 2026 word-by-word audit
(`docs/archive/audits/WORD_BY_WORD_2026_08_11/`) are one defect:

| the green number | what it actually measures |
|---|---|
| `scenario_library` 19/19 with `last_run` | `fn_scenario_run` checks the named departments are staffed. It never injects the failure — its own verdict text says so |
| observability healthy | zero events; `workflow_run` for `rfq_handling` = 0 |
| Company Health high on Executive Home | 55 of 63 active `company_goals` have no `measure_sql` |
| pack scorecard "100% ingested, 37 of 37 in use" | not embedding coverage (39%) and not which routine is called |
| `BOTH PROJECTS IN SYNC` | 418 = 418 tables. Staging has **255 empty tables to production's 96**, `board_advisor` 0 vs 7, `workflow_run` 7 vs 198 |
| `ai_cost_log.could_be_cheaper` | flagged 175 calls on the cheapest model and **0** on sonnet-5, which is 84% of spend |
| Row #3 126/152 | 152 of the 888 claims in the contract, and it rose while the codebase got worse |
| `least(100, NULL) = 100` | an unmeasured goal scoring as a perfect one |

**Why:** every one of these passes because a routine ran and returned something, and no surface
distinguishes a real zero from a quantity nobody measured.

**How to apply:** before trusting any green number, ask what it would report if the mechanism were
broken and the table empty. If the answer is the same, the number is not evidence. When adding or
reading a surface, a value derived from an empty table, an unmeasured goal or an unexercised
mechanism must say **"no data yet"** — never `0`, `100%`, `READY` or `IN SYNC`. Extends
[[checks-can-measure-row-age-not-mechanism]] and [[least-ignores-nulls-in-postgres]]; the parity
case is why [[green-pr-does-not-mean-deployable]] also matters.

14 Aug 2026, another instance: the agent_train grader extracted a case's required moves by
reading eight key names. The packaged families use twenty, so 7,906 of 17,890 cases — 44% of
the corpus, including EVERY role_cross_department and EVERY department_management case — came
back with no requirements and would have scored the employee zero. The instrument was reading
for the wrong keys, not measuring incompetence. Coverage 55.8% -> 74.4% once it learned the
real names. Ask what a scorer prints when its input is present but under a different name.
