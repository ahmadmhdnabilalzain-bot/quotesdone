# Role alignment — test evidence

Written 15 August 2026, production `htdblwldjkcgjvmqkbeh` and staging `pglpqrhvozwepymcuunn`.

Free verification first, and most of what follows cost nothing. The only money spent was a
deliberately capped staging smoke, reported in full below.

## What was run

| Suite | Result | Cost |
|---|---|---|
| `scripts/checks/workflow_ownership_alignment.test.mjs` | **60/60 on both projects** | zero |
| `scripts/checks/artifact_review_alias_cannot_self_approve.test.mjs` | **16/16 on both projects** | zero |
| `scripts/agents/role_caller_census.mjs` | 90 roles, **0 with no caller** | zero |
| `scripts/agents/role_runtime_smoke.mjs` (preconditions) | **270/270** on staging | zero |
| `scripts/agents/role_runtime_smoke.mjs --live=16` | 16 scenarios answered, 0 truncated | **AED 3.23** |

## What a registry assertion proves, and what it does not

A registry assertion proves the company is **wired** to do the right thing: the step exists, it has
one accountable owner, that owner resolves to a live employee with tools, knowledge, a KPI and a
forbidden-decision set. It does not prove the work happened. Only a run does that. The two are kept
apart deliberately below, because collapsing them is how a green suite comes to mean nothing.

## The thirteen workflows

Each asserts that the founder's named owners appear, resolve to a real employee, and appear **in
his order** — order matters, because the 14 August harness went green while proving nothing by
creating a row before the step that needed it missing. Each also asserts that no step in the chain
is owned by a knowledge overlay, which is how `domain specialist` came to own supplier selection.

| # | Scenario | Workflow | Result |
|---|---|---|---|
| 1 | customer inquiry without documents | `rfq_handling` | pass |
| 2 | customer inquiry with a drawing | `rfq_handling` | pass |
| 3 | multi-category MEP / fit-out inquiry | `rfq_handling` | pass |
| 4 | supplier onboarding and verification | `supplier_onboarding` | pass |
| 5 | supplier matching and idempotent dispatch | `rfq_handling` | pass |
| 6 | supplier-safe payload and redaction rejection | `rfq_handling` | pass |
| 7 | quotation submission and technical comparison | `rfq_handling` | pass |
| 8 | customer comparison and reveal | `payment` | pass |
| 9 | refund / dispute escalation | `refund` | pass |
| 10 | social content, artifact review, publish, learn | `campaign_publishing` | pass |
| 11 | revenue underperformance diagnosis | `metric_lifecycle` | pass |
| 12 | agent competency failure and remediation | `improvement_lifecycle` | pass |
| 13 | security incident and release block | `incident_response` | pass |

## Guards forced to fire

A new guard returning zero proves nothing. Each of these constructs the input that would make the
forbidden thing happen and asserts the refusal, inside an aborted transaction.

| Guard | Input | Result |
|---|---|---|
| `fn_artifact_review_valid` | author `visual_design`, reviewer `marketing_design` (one employee, two names) | **refused** |
| `fn_artifact_review_valid` | author `Visual Design Director` (the job title), reviewer `marketing_design` | **refused** |
| `fn_artifact_review_valid` | verdict `pass`, reviewer null | **refused** — the old guard permitted this |
| `fn_artifact_review_valid` | author `visual_design`, reviewer `ai_quality_reviewer` | **accepted**, stored as `marketing_design` / `ai_qa_specialist` |
| `trg_org_role_no_reserved_decision` | give the AI CEO `owned_decisions = ['set the reveal fee percentage']` | **refused** |
| `trg_step_run_actor_is_a_real_employee` | queue a step run with actor `Director` | **refused** |
| `a00_unsafe_match_eligibility` | assign an rfq-ready inquiry to a banned / blocked / closed / expired-licence supplier | **0 rows landed** |
| `a00_unsafe_match_eligibility` | assign the same inquiry to an eligible supplier | **1 row landed** |
| `trg_gate_incomplete_match` | assign an eligible supplier to a not-yet-ready inquiry | **0 rows landed** |

The accepted cases matter as much as the refusals: a guard that refuses everything is not a guard.

## The completion standard, item by item

| Standard | Evidence |
|---|---|
| all 90 roles have a necessity verdict | `FINAL_ROLE_NECESSITY_MATRIX.csv`, 90 rows, 0 blank |
| the two critical workflow gaps are closed | `rfq_handling` #10 (supplier-safe payload approval) and #11 (matching and dispatch) exist and have owners; neither existed before |
| category overlays remain on demand | 86 overlays, **0** with a runtime agent |
| broad specialists do not duplicate the 86 | all four are `on_demand_specialist`, and each forbids duplicating a category question bank, replacing the category specialist, and dispatching |
| visual and test creators do not approve themselves | `artifact.review` removed from the Visual Design Specialist's tools; authority `advisory`; the Test Automation Engineer no longer owns "blocking a release" and holds `execute_low` |
| tax responsibility is explicit | the Financial Controller's scope names VAT, corporate tax, revenue recognition, taxable supply, filing calendar; `tax_overlay_uae` is a `knowledge_overlay` with no runtime agent; **active employees 90 → 90** |
| founder-reserved policies enforced | 11 reserved decisions registered; no role owns one; the guard refuses even the AI CEO; the settings channel's 16 keys contain no reserved item |
| every active role has a caller | 20 → 0 across seven surfaces |
| every active role has tools, knowledge, KPIs, authority, traces | 0 roles missing any of them, on both projects |
| the core customer-to-quotation workflow has no unowned step | every `workflow_step` actor resolves, except two run-bound placeholders in `employee_task`, and no **live** step run carries one |
| the smoke suite passes within its cost cap | 16 live scenarios, AED 3.23, 0 truncated |

## The capped staging smoke — what it actually measured

16 live scenarios on staging, on the cheap tiers only (`--live-tier=operations_specialist`, which
routes to `small` and `medium`). Never run against production.

| | |
|---|---|
| scenarios answered | 16 / 16 |
| model attempts | 75 |
| attempts that succeeded | 75 |
| **truncated outputs** | **0** |
| `finish_reason = tool_calls` | 45 of 62 in the first batch — the agents are calling tools, not answering blind |
| `finish_reason = length` | 4 (medium tier) — real ceiling pressure, visible rather than silent |
| average latency | 3.0 s |
| **cost** | **AED 3.23** (AED 2.44 for the first 13, AED 0.79 for the last 3) |
| prompt tokens | 686,740 |
| output tokens | 26,159 |

Preconditions were measured for **all 270** scenarios (90 roles × 3) at no cost, and all 270 pass:
canonical role id, active department, active manager, correct role knowledge, correct department
knowledge, correct tool policy, correct authority result, declared output contract.

## A false finding I nearly reported

The first look said "cost is not captured": `llm_attempt` had 666 rows and **0** with a `cost_aed`.
That was true of that table and false about the company. `ai_cost_log` holds **4,336 rows, all
4,336 priced**, AED 119.39 lifetime, against `agent_key`, `tier` and `task_class`.

The real gap was narrower and is now fixed. `ai_cost_log` records one row per **request**, costed
against the model that finally answered; `llm_attempt` is the per-**attempt** ledger, so when a
request climbs the fallback ladder the tokens burned by the attempts that failed first were
attributable to nothing. `fn_record_llm_attempt` already accepted `prompt_tokens`, `output_tokens`
and `cost_aed` — the gateway simply never passed them.

Verified by execution after the fix, in the same turn: **13 of 13 attempts carry tokens and a
cost** — AED 0.78788, 115,263 prompt tokens, 4,884 output tokens, attributed to `cs_onboarding`.

A check now re-derives the AED/USD ratio from what `fn_llm_log` actually produces and compares it
against `fn_usd_to_aed()`, so the two ledgers cannot quietly disagree about what one call cost.

## Findings that came out of the work

1. **The designer was the default reviewer of its own artifact.** `artifact_review` defaulted
   `reviewer_agent` to `marketing_design`, which is the Visual Design Director's own runtime key,
   and both self-review guards compared identities raw. `visual_design` and `marketing_design` are
   one employee; as strings they are not equal. Fourth instance of one root cause.
2. **A refused supplier was counted as a notified one.** The eligibility guard returns `null` on
   refusal — not an error — so `if (!error) inserted++` counted it as a contact, `routing.fanout`
   over-reported the RFQ's reach, and because the redispatch sweep only retries a fanout *recorded
   as* 0, an RFQ whose every match was refused could never be retried.
3. **Whoever took the reveal payment reconciled their own charge.** `payment` steps 2–4 and step 5
   were the same employee under two aliases: `Accountant` and `financial_controller` both resolve
   to `bookkeeper`.
4. **`employee_workflow` held 157 rows on production and 0 on staging**, so the two projects
   disagreed about who owns what — and it recorded ten owners for `rfq_handling`.
5. **One step run had sat queued since 10 August addressed to `Director`**, which resolves to no
   employee, so nothing could pick it up. Nothing failed and no watcher fired, because a queued row
   is a perfectly ordinary thing to be.
6. **A tool existed on staging and not on production** (`handoff_stalled`), so one project's agents
   could call something the other's could not.

## Observed, not claimed as a defect: decision-trace coverage

`v_executions_without_decision_trace` returns **847 of 851 rows on production** and 35 on staging.
That looks like a finding and is not reported as one, because the instrument has not been shown to
be measuring the right subject.

The view left-joins `action_execution` to `decision_trace` on `correlation_id`. `fn_execution_run`
writes both and its own comment says the view "stays empty for anything this engine produced" — and
the four production rows that DO carry a trace are from 6 August, the period that engine ran. Every
row since is from a different executor set (`action_worker`, `kb_deepen`, `cost_snapshot`,
`exec_agents`, `knowledge_exam`, `money_tests`, …) which does not go through `fn_execution_run`.
Production's most recent `decision_trace` is dated **15 August** and comes from the agent path,
which traces through `fn_write_decision_trace` in `agent_brain`.

So the honest reading is: **two populations that were never joined**, not 847 untraced decisions.
Establishing which of those executors is genuinely required to emit a trace is a separate piece of
work with its own scope, and it is recorded here rather than quietly fixed or quietly omitted.
Nothing in this workstream changed either side of it.

## Boundaries of these measurements

- The 13 workflow tests assert **registry** properties — owner, order, resolvability, no overlay
  owner. They do not assert that a live inquiry travelled the chain; production holds **0
  inquiries**, so that end-to-end path cannot be exercised there at all.
- The eligibility-guard probe runs on staging only, for the same reason, and reports SKIP rather
  than a pass on production. A pass asserted over absent data is how a check comes to mean nothing.
- The live smoke covered **16 of 270** scenarios, on the two cheapest tiers, on staging. It says
  nothing about the `director` or `reviewer_auditor` tiers, and nothing about answer quality —
  only that the runtime answers, calls tools, does not truncate, and records its cost.
- No independent certification question or answer key was read, referenced or used.
