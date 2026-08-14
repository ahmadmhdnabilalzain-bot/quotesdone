# Department workflow results — ten canonical departments

Measured on **production `htdblwldjkcgjvmqkbeh`**, 14 Aug 2026, 15:18–17:10 UTC (19:18–21:10 Dubai).

No independent V3 certification question or answer key was read, referenced or used. Every
scenario below is derived from the role contracts already in the database — `org_role.owned_decisions`,
`forbidden_decisions`, `activation_conditions`, `output_contracts`, `escalation_targets` — and from
`department_objective`, `employee_authority` and `ops_knowledge`.

## What could and could not be executed

Section 7 asks for one real workflow per department, proven along the chain
**company objective → department objective → accountable manager → assigned role → knowledge and
tools → execution → independent review → KPI outcome → management response → closure**.

Every link in that chain except **execution** is a property of the runtime that can be measured
without calling a model, and all of them were. **Execution itself could not run**: all 90
accountable roles route to `anthropic/claude-sonnet-5` (large tier), and OpenRouter returns
**HTTP 402 Payment Required** for that model — measured directly at both 8000 and 4000 `max_tokens`,
and again through the live runtime (`agent_brain` returned its friendly fallback string at HTTP 200
while `llm_attempt` recorded `class_key = insufficient_credit`, `breaker_state = opened_by_this`).

The small tier (`google/gemini-3.1-flash-lite`) succeeds at the same token size, so this is not a
dead key or an outage. It is credit, and it is the founder's call — see the closure report.

**I did not lower `max_tokens` to squeeze large-tier calls under the affordable ceiling.** Measured
over seven days of successful large-tier calls, p95 output is 3,499 tokens and the maximum is 5,976.
Cutting the reservation to what is currently affordable would truncate real answers mid-sentence,
and section 4 counts truncation as a failure. Making the run green that way would have been
fabricating a pass. I also did not reroute the 90 roles to a cheaper tier for the same reason: all
24 Reviewer/Auditor rows in the pack name a large model deliberately, and a reviewer on the cheap
model is a green check that means nothing.

## The chain, per department

| department | dept objectives | accountable roles | independent reviewers in-dept | authority rows | dept knowledge | open tasks | reviewer when the head authors | MTD spend / budget (AED) |
|---|---|---|---|---|---|---|---|---|
| assurance | 7 | 5 | 3 | 22 | 246 | 49 | `ai_qa_specialist` | 6.40 / 110 |
| customer_experience | 7 | 7 | 0 | 17 | 92 | 18 | `brief` (escalated out) | 0.00 / 120 |
| data_intel | 5 | 11 | 1 | 20 | 170 | 43 | `knowledge_validator` | 12.14 / 160 |
| exec | 10 | 5 | 0 | 15 | 168 | 115 | **none — refused** | 147.77 / 560 |
| finance | 8 | 7 | 0 | 27 | 170 | 27 | `brief` (escalated out) | 0.00 / 80 |
| growth | 9 | 12 | 0 | 45 | 179 | 63 | `brief` (escalated out) | 0.04 / 120 |
| legal | 4 | 7 | 4 | 19 | 94 | 23 | `compliance_mgr` | 0.00 / 80 |
| marketplace | 24 | 17 | 1 | 88 | 420 | 57 | `supplier_verification` | 1.24 / 380 |
| people_ops | 8 | 8 | 0 | 28 | 241 | 32 | `brief` (escalated out) | 16.76 / 110 |
| product_eng | 3 | 11 | 1 | 25* | 25 | 4 | `model_evaluator` | 0.00 / 90 |

\* product_eng authority rows measured as 38 including roles whose employees sit in other departments.

Every department: has at least one department objective, an accountable manager that resolves to an
active employee, at least one runtime-eligible department-knowledge record reachable through
`fn_dept_scope`, authority rows, and a reviewer path that never returns the author.

## Three findings that are not failures, and one that is open

**1. Five departments have no independent reviewer of their own, and that is not a hole.**
`assurance` (3), `legal` (4), `data_intel` (1), `marketplace` (1) and `product_eng` (1) hold all ten
independent-reviewer roles. When the head of `customer_experience`, `finance`, `growth` or
`people_ops` authors work, `fn_pick_reviewer` escalates the review **out of the department** to
`brief`, the Chief of Staff. That is independence by a stronger definition than a departmental
colleague, and it is what the function is designed to do. I did not create five reviewer roles to
make a count go green — the structure is frozen, and inventing a reviewer inside a department is
weaker than escalating outside it.

**2. `exec` returns no reviewer at all, and that is correct.** The CEO role has no
`manager_role_id`, because above the AI chief executive is the founder, who is a person and not an
`org_role`. `fn_pick_reviewer('exec', 'ceo')` therefore returns `reviewer: null` with the basis
"escalate rather than approve it". The company refuses to approve the CEO's own work rather than
letting it self-approve. Requiring a manager row there would mean inventing an AI above the chief
executive to satisfy a check.

**3. `exec` holds 115 of the company's 431 open tasks** and 147.77 AED of 187 AED month-to-date
spend against its 560 AED budget (26%). It is the busiest and most expensive department, and the
one whose backlog most blocks `dept_plan`. `fn_dept_can_plan` reports `can_plan: true` for
`marketplace` on the weekly-floor rule ("last self-plan never — planning regardless of backlog"),
so the planner is not permanently wedged; the stale-task backlog is the founder's, by his own
standing decision.

**4. OPEN: the behavioural half of every workflow is unrun.** Execution, independent review of a
real artefact, KPI movement and management response all require the model. They are blocked on
credit, not on code. The harnesses that run them exist and were exercised end to end against the
live runtime — `scripts/agents/role_runtime_smoke.mjs` and
`scripts/agents/overlay_and_review_registers.mjs` — and each records the upstream refusal as
measured evidence rather than assuming it.

## What was proven about the workflows without the model

- **Company objective → department objective**: all ten departments carry at least one
  `department_objective` row (3 to 24 each, 85 total).
- **Accountable manager**: 89 of 90 accountable roles resolve to an active manager; the 90th is the
  CEO, whose manager is the founder.
- **Assigned role → knowledge**: every department resolves department-shared knowledge through
  `fn_dept_scope`, which is what makes the merge survivable — `marketplace` reaches 420 records
  including everything tagged to the five keys it absorbed.
- **Tools and authority**: every department has authority rows, and every independent reviewer holds
  `review_block` at `autonomous` (asserted by the behavioural suite).
- **Independent review**: proven for all ten departments including under an alias — see section 3 of
  the closure report, where passing the author under an alias previously defeated the guard in all
  ten and now defeats it in none.
- **KPI and closure**: `least()`/`greatest()` null-handling and the unmeasurable-metric path are
  covered by existing behavioural tests (an unmeasurable category metric reports null and a reason,
  never 100).
