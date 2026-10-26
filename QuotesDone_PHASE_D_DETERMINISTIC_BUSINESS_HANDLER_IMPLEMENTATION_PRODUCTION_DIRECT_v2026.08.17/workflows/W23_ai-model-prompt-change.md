# W23 — AI/model/prompt change

- **Domain:** ai
- **Criticality:** critical
- **Profile:** change_control_cycle
- **Primary object:** `ai_change`
- **Accountable role:** `ai_director`
- **Start event:** AI capability/change request
- **Required end state:** Evaluated model/prompt/retrieval change
- **Founder boundary:** Evaluator separation and no answer-key leakage

## Purpose

Design, implement and independently evaluate model, prompt, retrieval or routing changes before release.

## Steps

| # | Step | Name | Type | Accountable role | Contributors | Reviewer | Pass successor |
|---:|---|---|---|---|---|---|---|
| 1 | `W23-S01` | Open AI change request | intake | `ai_director` |  |  | `W23-S02` |
| 2 | `W23-S02` | Define behavioral and cost acceptance | decision | `ai_director` | product_optimisation_engineer; product_manager |  | `W23-S03` |
| 3 | `W23-S03` | Design AI architecture change | analysis | `ai_architect` | solution_architect; knowledge_engineer |  | `W23-S04` |
| 4 | `W23-S04` | Implement prompt/agent/retrieval change | execution | `agent_prompt_engineer` | backend_engineer; ai_architect |  | `W23-S05` |
| 5 | `W23-S05` | Run internal regression and cost analysis | review | `product_optimisation_engineer` | test_automation_engineer |  | `W23-S06` |
| 6 | `W23-S06` | Conduct independent model evaluation | review | `model_evaluation_reviewer` |  |  | `W23-S07` |
| 7 | `W23-S07` | Conduct workflow-level AI QA | review | `ai_quality_assurance_reviewer` | relevant_business_owner |  | `W23-S08` |
| 8 | `W23-S08` | Approve release-candidate handoff | decision | `ai_director` |  | qa_release_management_director | `W23-S09` |
| 9 | `W23-S09` | Close AI change cycle | closure | `ai_director` |  |  | `WORKFLOW_COMPLETE` |

## Phase D requirement

For every step populate the handler matrix and prove actual caller, authoritative handler, typed contract, object mutations, rules/gates, state, idempotency, failure, review/handoff, trace and external-effect policy.

## Workflow acceptance

- deterministic happy path reaches required end state;
- failure/block path is visible;
- cancellation leaves no active derived work;
- replay creates no duplicate effect;
- no live external effect;
- no paid inference;
- no founder approval except a specific refund in W17.
