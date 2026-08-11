# SPEC #1 — `quotesdone archeticture.txt` (372 lines)
# SPEC #2 — `OS.txt`, the cross-OS contract (507 lines)

Audited 2026-08-11 13:20–13:50 UTC against production. No scorer was run for either; every verdict
below is a direct measurement.

| | PRESENT | PARTIAL | ABSENT | CONTRADICTED | total |
|---|---|---|---|---|---|
| Spec #1 | 41 | 17 | 6 | 1 | **65** |
| Spec #2 | 52 | 8 | 2 | 0 | **62** |

**Spec #2 is the best-implemented file in the contract.** It is reported first where that matters,
because the temptation in an audit is to report only failures.

---

# SPEC #1 — the architecture

## §1 Core philosophy (L3–L11)

| line | claim | verdict | evidence |
|---|---|---|---|
| 5 | "Do not build AI assistants." | PRESENT | there is no assistant abstraction; work arrives as `org_tasks` (834) and `agent_actions` (2,450), not as chat turns |
| 7 | "Do not build isolated AI agents." | PRESENT | `org_agents` 94 rows all carry `department` and `manager_key`; `review_chain` 1,557 rows prove cross-employee routing |
| 9 | ownership, accountability, initiative, collaboration, long-term objectives | PARTIAL | ownership PRESENT (`review_chain.stage='ownership'`, 241 `owned` decisions); accountability PRESENT (`os_audit_log` 9,293); collaboration PRESENT (`stage='collaboration'`); **initiative PARTIAL** — see §7 |

## §2 Company goal (L15–L33)

| line | claim | verdict | evidence |
|---|---|---|---|
| 17 | "Every employee works toward the same business objectives." | PARTIAL | `company_goals` 63 active, every one with `owner_dept`; `department_objective` 66; `fn_goal_cascade` trigger |
| 21–27 | the 7 example objectives | PARTIAL | revenue target exists as a goal row; **revenue is AED 0 and `transactions` is empty**, so 5 of the 7 (satisfaction, supplier satisfaction, RFQ completion, quotation conversion) have no measurable input |
| 29 | "Every decision … should support these objectives." | **CONTRADICTED** | **55 of the 63 active company goals carry no `measure_sql`.** 8 are measurable. A goal with no measure cannot be supported or missed — it can only be asserted. This is the same failure class as `least(100, NULL) = 100`: the instrument reports success on an unmeasured quantity. Contrast `os_objective`, where **50 of 50** carry `measure_sql` and 46 carry an actual value — the OS layer is measured and the company-goal layer is not |
| 33 | "Every employee should think like an owner." | PARTIAL | prose; nearest artefact is `review_chain.stage='ownership'` |

## §3 Employee attributes (L37–L56) and the closing instruction (L372)

L372 is the most checkable sentence in the file: *"define each one as an employee object with
structured attributes such as role, manager, direct reports, KPIs, authority limits, current
workload, goals, performance history, and improvement plan."*

| attribute | verdict | evidence |
|---|---|---|
| job title | PRESENT | `org_agents.title` |
| department | PRESENT | `org_agents.department`, all 25 populated |
| responsibilities | PARTIAL | `org_agents.responsibilities` — **80 of 94 populated, 14 blank** |
| authority | PRESENT | `org_authority` 518 rows, `fn_dept_authority`, `fn_authority_rank`, `fn_org_authority_guard` |
| KPIs | PARTIAL | no `org_agents` KPI column; `ai_quality_snapshots` 1,115 rows serve as performance history |
| long-term objectives | PRESENT | `os_objective` horizons `strategic`/`annual` |
| short-term objectives | PRESENT | `os_objective` horizons `quarterly`/`weekly`/`daily` |
| memory | PRESENT | `org_memory` 624, `agent_memory` 530, `institutional_memory` 362, `memory_promotions` 60 |
| initiative | PARTIAL | `fn_opportunity_scan`, `fn_evolution_scan`, `fn_strategy_scan` run on cron — the system proposes without being asked. But the founder-facing half is empty: **12 founder decisions ever, newest 13 July** |
| planning ability | PRESENT | `fn_dept_can_plan`, `department_objective` 66, `improvement_lifecycle` workflow 15 runs |
| collaboration | PRESENT | `review_chain.stage='collaboration'`, `fn_agent_handoff_inbox`, `fn_group_dispatch_report` |
| continuous learning | PRESENT | `fn_learning_loop_sweep`, `fn_task_lesson`, `fn_ingest_case_lessons`, `knowledge_lifecycle` workflow 11 runs |
| **manager** | PRESENT | `org_agents.manager_key` — **93 of 94 set, 1 unset (the CEO, correctly), and all 93 resolve to a real agent. Zero dangling references.** |
| **direct reports** | PRESENT | derivable from `manager_key`; the hierarchy is complete and acyclic |
| **current workload** | PRESENT | `org_agents.max_open_tasks` + `org_tasks` depth |
| **improvement plan** | PARTIAL | `org_agents.improvement_plan` — **67 of 94 populated, 27 blank** |

**This is the cleanest result in the whole audit.** The employee object is real, the hierarchy has no
dangling manager, and `manager_key` is the one identity column in the database with **100%
referential integrity** — in a system where `model_policy_by_identity` has 0%.

## §4 Departments as teams, department heads, Chief of Staff, CEO (L60–L157)

| line | claim | verdict | evidence |
|---|---|---|---|
| 62 | "Departments should not consist of a single AI." | PARTIAL | 23 of 25 departments have ≥3 employees. **`payments` has 2** (`payments_manager`, `billing_specialist`) — the smallest team, and Payment is one of the two departments the contract gave no knowledge profile |
| 66–73 | the Marketing team example (6 named roles) | PRESENT | marketing has 7 rows / 6 active: `brand_mgr`, `marketing`, `marketing_analyst`, `marketing_content`, `marketing_copy`, `marketing_design`, `marketing_social` — director, analyst, designer, copywriter, social and content all present, matching the example role-for-role |
| 81 | "Every department has a manager." | PRESENT | **all 25 departments have at least one director/manager-seniority employee.** `seniority` domain is `chief, director, executive, lead, manager, senior, specialist` |
| 85–92 | the 8 manager responsibilities | PARTIAL | reviewing/approving/rejecting/revisions PRESENT (`review_chain` decisions: approve 993, hold 43, reject 4, request_revision 8); monitoring KPIs PRESENT; **coaching junior employees PARTIAL** — `improvement_plan` exists on 67 of 94, no coaching interaction is recorded |
| 100 | "The Chief of Staff oversees all departments." | PRESENT | a Chief of Staff exists in `org_agents`; `fn_chief_of_staff` routine; `review_chain.stage='cos_review'` is a real stage with rows |
| 111–128 | "The Chief of Staff should challenge departments" + the 6 challenge questions | PRESENT | `fn_challenge` exists and `review_chain` records 4 `reject` and 8 `request_revision` decisions **with reasons on 1,290 rows**. The scenario `five_posts_one_violation` in `scenario_library` is the spec's own five-posts example, authored verbatim |
| 136–151 | CEO responsibilities (10 items) | PARTIAL | monitor revenue PRESENT but revenue is 0; review department reports PRESENT (`board_reports` 147, `exec_reports` 233); approve budgets PRESENT (`fn_budget_set`, `department_budget` 25); set quarterly objectives PRESENT (`os_objective` quarterly=10); identify risks PRESENT (`fn_strategy_risk`) |
| 153 | "The CEO thinks months ahead. Not hours ahead." | PARTIAL | `os_objective` carries strategic and annual horizons; `exec_meeting_weekly` runs Mondays. The longest real forecast is `fn_finance_forecast`; `company_snapshot` retains **14 days** |

## §5 Review process (L159–L216)

| line | claim | verdict | evidence |
|---|---|---|---|
| 163–198 | the 8-step chain: create → director reviews → revise or submit → CoS checks 6 things → approve → publish | PRESENT | `review_chain` has exactly these stages: `drafted`, `dept_review`, `cos_review`, `approval`, `published`, plus `ownership` and `collaboration`. **1,557 rows.** The chain in the contract is the chain in the table |
| 202–214 | analyst collects analytics → department analyses → lessons recorded → future campaigns adjusted | PARTIAL | `campaign_publishing` workflow has 12 steps covering exactly this and **0 runs**. Marketing campaigns are paused at AED 0 |
| 216 | **"This review cycle should exist for every department."** | **PARTIAL** | `review_chain` covers **14 of 25 departments**. 11 departments have never produced a reviewed artefact |

## §6 Learning (L220–L233)

| line | claim | verdict | evidence |
|---|---|---|---|
| 222 | "Every completed task should generate learning." | PARTIAL | 834 `org_tasks`, **431 done**, and only **41 carry a `root_cause`**. `fn_task_lesson` exists (and is one of the 36 duplicated definitions) |
| 226–231 | the 6 learning questions | PARTIAL | "Did we achieve our KPI?" is answerable for 8 of 63 goals; "Did the customer respond positively?" has no customers |
| 233 | "respecting company policies and approved knowledge" | PRESENT | `fn_kb_submit_revision` → `fn_kb_gov_approve`; learning proposes, it does not overwrite approved knowledge |

## §7 Planning, challenge, memory, improvement, culture, decisions (L237–L369)

| line | claim | verdict | evidence |
|---|---|---|---|
| 239–256 | employees plan without being asked; the 6-step marketing example | PARTIAL | `fn_opportunity_scan`, `fn_evolution_scan`, `fn_strategy_scan`, `fn_idea_score` run unprompted; `idea` table is **0 rows** so the "generate three improvement strategies" step has produced nothing |
| 262–278 | departments challenge one another; 5 named pairs | PRESENT | `fn_challenge`, `fn_decision_conflict_scan`; `scenario_library` holds `finance_rejects_budget` and `marketing_legal_disagree` — two of the five named pairs, authored from this section |
| 284–295 | company memory, 8 kinds | PARTIAL | previous work/mistakes/successes/decisions/lessons PRESENT; **customer preferences and supplier preferences** → `customer_preference` **0 rows**; internal discussions → `messages` **0 rows** |
| 301–321 | weekly department review with 7 sections | PARTIAL | `os_review` covers **all 10 OSes, 30 reviews**; department-level weekly review is not separately produced for the 25 departments |
| 327–342 | 10 company values; "Employees should reject work that conflicts" | PARTIAL | rejection is real (`review_chain` reject/request_revision with `violated_rule` column populated); the 10 values are not encoded as a checkable list |
| 348–361 | 8 decision steps; escalate only beyond authority or confidence | PRESENT | `fn_decide`, `decision_log` 1,479, `decision_policy` 28, `fn_should_escalate`, `fn_authorize`, `decision_log.confidence` since the 11 Aug fix. **All eight steps have an artefact** |
| 369 | "should not feel like software with AI features" | PARTIAL | prose. The company-internal loops behave as described; the business loops have never run |

---

# SPEC #2 — the Universal OS Blueprint

## The 10 Operating Systems (L369–L472) — PRESENT, exactly

`operating_system` holds **10 rows**, and they are the 10 named, in order:

```
leadership, commercial, marketplace, operations, technology,
finance, legal_gov, knowledge, intelligence, evolution
```

**All 10 carry a mission, a charter, an owner agent and a health score.** No extras, no omissions.

## The 17 blueprint components, per OS

| # | component | spec lines | verdict | evidence |
|---|---|---|---|---|
| 1 | Purpose | 5–18 | PRESENT | `operating_system.charter`, 10 of 10 |
| 2 | Mission (one sentence) | 19–25 | PRESENT | `operating_system.mission`, 10 of 10 |
| 3 | Objectives — strategic, annual, quarterly, weekly, daily | 27–35 | **PRESENT** | `os_objective` 50 rows = **exactly 10 per horizon across all five horizons**. All 50 carry `measure_sql`; 46 carry an `actual_value`. This is the single most completely satisfied requirement in the eight files |
| 4 | Responsibilities, "No other OS can own these" | 36–53 | **PRESENT** | `os_responsibility` 84 rows across all 10; **zero responsibilities owned by more than one OS** |
| 5 | Employees with role/authority/KPIs/knowledge/decision rights/escalation | 55–88 | PARTIAL | `os_department` maps all 25 departments, **each to exactly one OS, none unmapped**. Employee-level KPIs remain the gap noted in spec #1 |
| 6 | Knowledge Base, independent per OS; "Leadership should not duplicate … it queries Finance OS" | 89–109 | PRESENT | `os_knowledge_domain` 445 rows across all 10; `os_interface` 38 rows is the query surface the sentence asks for |
| 7 | Inputs (events) | 111–131 | PRESENT | `company_event` 1,112 rows, **987 in the last 7 days across 17 event types**; `event_subscription` 53 |
| 8 | Outputs — tasks, reports, decisions, approvals, recommendations, alerts, KPIs, knowledge updates | 133–151 | PRESENT | all eight have a table: `org_tasks`, `board_reports`/`exec_reports`, `decision_log`, `fn_approval_decide`, `fn_officer_recs`, `notifications`, `report_kpi_snapshots`, `kb_revisions` |
| 9 | Workflows | 153–185 | PARTIAL | `workflow` 14 rows carry an `os_key` and cover all 10 OSes. The Commercial example chain (Lead→Qualification→Proposal→Negotiation→Close→Handover→Customer Success) exists as `lead_to_customer` with 7 steps and **0 runs** |
| 10 | Decision Engine — 10 stages | 187–227 | PRESENT | Problem/Gather/Retrieve/Analyse/Risk/Options/Authority/Decide/Execute/Measure map to `fn_decide`, `fn_agent_context`, `fn_kb_retrieve`, `fn_strategy_risk`, `fn_decision_gate`, `fn_authorize`, `fn_execution_run`, `fn_outcome_evaluate`. **All ten stages have a named routine** |
| 11 | KPI Engine — Objectives→KPIs→Actual→Variance→Root Cause→Improvement Plan | 229–253 | PRESENT | `metric_lifecycle` workflow with 6 steps and **30 runs** — one of only five workflows that has actually run, and it implements this chain step for step |
| 12 | Memory — 7 kinds | 255–271 | PARTIAL | short-term (`fn_agent_context_capped`), long-term (`org_memory` 624), lessons, historical decisions (`decision_log` 1,479), failures/successes (`agent_runs.status`) all PRESENT. **"Best Practices" has no store** |
| 13 | Learning — task→outcome→performance→lessons→knowledge update→SOP update | 273–299 | PARTIAL | `knowledge_lifecycle` workflow 11 runs, `fn_sop_update` PRESENT. The chain is complete; only 41 of 431 done tasks travel it |
| 14 | Governance — the 5 questions | 301–313 | PRESENT | Can I decide? `fn_authorize`; Can I spend? `fn_budget_available` + `fn_check_spend`; Can I approve? `fn_approval_policy_match`; Should I escalate? `fn_should_escalate`; Who must review? `fn_pick_reviewer`. **All five answered by a named routine** |
| 15 | Collaboration — 4 questions, "No duplicated ownership" | 315–327 | PRESENT | `os_interface` 38; `fn_owning_os`; duplicated ownership measured at **0** |
| 16 | Health — 8 dimensions | 329–347 | PARTIAL | health score PRESENT on all 10; `fn_os_health`, `fn_health_index`. Of the 8 named, **capacity, backlog and automation** are computed; **cost per OS is not** — spend is tracked company-wide, not attributed per OS |
| 17 | Continuous Improvement — 5 weekly questions | 349–363 | PARTIAL | `os_review` 30 reviews across all 10 OSes; `fn_evolution_scan`. "What should be deleted?" has no producer — nothing proposes removal |

## The Cross-OS Communication Contract (L473–L501)

The 10-step chain, measured step by step:

| step | verdict | evidence |
|---|---|---|
| Event Created | PRESENT | `fn_emit_event`, `company_event` 1,112 |
| Event Bus | PRESENT | `event_delivery` 1,601 |
| Relevant OSes Subscribe | PARTIAL | `event_subscription` 53 rows — but it is keyed by **`agent_key`, not `os_key`**. The contract says operating systems subscribe; employees do. Functionally equivalent today, structurally a deviation from the sentence |
| Each OS Assesses Impact | PRESENT | `event_assessment` 1,026 |
| Each OS Creates Internal Tasks | PRESENT | `org_tasks` 834 |
| Each OS Executes Within Its Authority | PRESENT | `fn_org_task_autonomy_brake`, `fn_authorize` |
| Results Returned | PRESENT | `event_rollup` 871 |
| Chief of Staff Consolidates | PRESENT | `fn_chief_of_staff`, `fn_event_consolidate` |
| CEO Updates Priorities | PRESENT | `strategic_review` workflow, **19 runs** |
| Knowledge OS Captures Lessons | PRESENT | `knowledge_lifecycle` workflow, 11 runs |
| Intelligence OS Updates KPIs | PRESENT | `metric_lifecycle` workflow, 30 runs |

| line | claim | verdict | evidence |
|---|---|---|---|
| 501 | **"No OS should call another OS directly for business logic."** | PRESENT | `fn_org_task_cross_os_guard` exists and is the enforcement point. This is a prohibition with a guard, which is the strongest form a contract line can take |
| 505 | "Do not implement these as ten folders or ten groups of agents." | PRESENT | they are 10 rows in `operating_system` with 17 populated component tables hanging off them, not 10 directories |

## Where spec #2 falls short

Only two ABSENT verdicts in 62 claims:

1. **Cost per OS (L345).** Health reports 7 of 8 dimensions. OpenRouter spend is attributed by
   `fn_ai_cost_attribute` to an agent, never rolled up to an OS, so "which OS costs the most" cannot
   be answered — which is exactly the question a $8.68 balance makes urgent.
2. **"What should be deleted?" (L363).** No routine proposes removal. `fn_evolution_scan` proposes
   additions and improvements only. In a codebase carrying 58 redundant SQL definitions, 28,521
   duplicate knowledge chunks and one dead function, the absence of a delete-proposer is not
   academic.
