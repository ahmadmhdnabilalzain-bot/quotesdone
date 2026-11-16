> **Archived 16 Nov 2026** (simplification wave B, it_engineer): it describes the V3 certification and remediation programme of Aug 2026; the agent_brain, agent_train and os_api functions it ran on are gone from supabase/functions. History, not the build today.

# V3 CERTIFICATION — REMEDIATION HANDOFF (builder-facing, sanitized)

**Derived from result of record:** `V3-COR-0A782DA90B10` (sealed 2026-08-14T12:34:51Z)
**Sanitization:** this document contains no evaluator answer key, no gold answer text, no scoring
thresholds beyond the pass bars already published to the builder, no concealed scoring logic and no
certification question text. Competency gaps are given as codes and behaviours. **Learn the gap, do
not memorise the answer.** Category items are named by field key only; the clarifying-question
wording used by the exam is deliberately withheld.

---

## 0. Read this first

Overall weighted score **56.97%**. Zero of 96 roles, zero of 24 departments and zero of
86 categories certified. But **the ranking of the causes matters more than the score**: three
platform-level defects account for more lost points than every reasoning weakness combined, and two
of them are wiring, not intelligence. Fix those first — they are cheap, and they are currently
capping what any prompt or knowledge change can achieve.

---

## 1. Missing runtime connections — fix before anything else

| # | Defect | Blast radius | Evidence | Priority |
|---|---|---|---|---|
| 1 | **Tools are called but never return a result.** `tool_calls` non-empty on every row; `tool_results` empty on every row. | **2,284 / 2,284 questions.** Every answer was produced from prompt context alone. | `TOOL_NOT_CONNECTED` | **P0** |
| 2 | **No decision trace is written.** `decision_trace_id` null on every row. | **2,284 / 2,284.** Decision-trace completeness is 0%. Nothing in this runtime is auditable after the fact. | `TRACE_OR_OBSERVABILITY_FAILURE` | **P0** |
| 3 | **Output truncated on one model route.** 135 answers hit `finish_reason: length`; **100% of them on `anthropic/claude-sonnet-5`** — the tier used for consequential work. JSON never closes, structured output is lost, confidence/authority/escalation vanish. | 135 questions, concentrated in the highest-stakes roles. | `OUTPUT_CONTRACT_ERROR` | **P0** |
| 4 | **Provider route returns 502 with a valid body upstream.** 123 first responses failed; the failures are deterministic per model route, not per moment. | 123 questions; 5 roles scored 0 because **every** first response failed. | `INFRASTRUCTURE_FAILURE` / `RUNTIME_NOT_CONNECTED` | **P0** |

Agents most affected by (4), first responses: `followup` 44, `marketing` 32, `qa_manager` 15, `legal` 11, `trust_safety_mgr` 10, `supplier_verification` 3, `brief` 2, `ai_qa_specialist` 2, `fraud_analyst` 2, `security` 1, `analytics_director` 1.

**Until (1) and (2) are fixed, no re-test can measure tool-result interpretation or decision-trace
completeness at all.** Those two dimensions are currently NOT_EVALUABLE, not failing.

---

## 2. Role mapping

**59 of 96 certification roles share a runtime agent with another role**; 23 agents answer for two or
three roles, twelve of them across *different seniority tiers*. The affected roles are flagged
`ROLE_MAPPING_ERROR` in `V3_CERTIFICATION_RESULTS_BY_ROLE.csv` (column `agent_shared_across_roles`).

Consequence, visible in the scores: the reviewer/auditor and operations-specialist competencies are
the two weakest in the entire certification, because no agent is actually specialised to them.

| Code | Behaviour that is missing | Score |
|---|---|---|
| CMP-EV-07 | Seek a second, independent source before confirming a finding. | 5.56% |
| CMP-QA-02 | Define what "closed" means before opening the action. | 7.29% |
| CMP-HO-06 | Guard against replay and duplicate state. | 9.38% |
| CMP-HO-07 | Plan for the batch that half-succeeds. | 14.93% |
| CMP-HO-05 | Require proof the downstream step actually happened. | 26.39% |

---

## 3. Failed competencies, ranked

Codes are stable; use them as remediation tickets.

| Code | Competency (behaviour to build) | Score | Dimension |
|---|---|---|---|
| `CMP-SC-12` | Archetype: incomplete comparison basis — competency withheld by design. | 2.08% | domain_judgment |
| `CMP-CAT-ROUTE:quantities_by_type` | Route-specific technical dimension: quantities_by_type | 2.44% | domain_judgment |
| `CMP-EV-07` | Seek a second, independent source before confirming a finding. | 5.56% | domain_judgment |
| `CMP-QA-02` | Define what "closed" means before opening the action. | 7.29% | domain_judgment |
| `CMP-UC-03` | Pair every target with the metric it could damage. | 7.81% | uncertainty_calibration |
| `CMP-CAT-ROUTE:single_line_and_interfaces` | Route-specific technical dimension: single_line_and_interfaces | 8.20% | domain_judgment |
| `CMP-CA-05` | Break a rate down before acting on it. | 8.33% | domain_judgment |
| `CMP-SC-10` | Archetype: ambiguity resolution — competency withheld by design. | 8.33% | domain_judgment |
| `CMP-HO-06` | Guard against replay and duplicate state. | 9.38% | domain_judgment |
| `CMP-CA-06` | Tie two records together before trusting either. | 13.89% | domain_judgment |
| `CMP-BZ-01` | Link the local decision to the department objective AND to the company revenue target. | 14.76% | company_and_revenue_context |
| `CMP-HO-07` | Plan for the batch that half-succeeds. | 14.93% | domain_judgment |
| `CMP-EV-05` | Say who gathers which evidence before the next decision point. | 21.35% | evidence_and_tool_use |
| `CMP-SC-11` | Archetype: degraded-mode operation — competency withheld by design. | 21.88% | domain_judgment |
| `CMP-HO-05` | Require proof the downstream step actually happened. | 26.39% | domain_judgment |
| `CMP-SC-06` | Archetype: non-compliant request — competency withheld by design. | 27.08% | domain_judgment |
| `CMP-CAT-ROUTE:electrical_load` | Route-specific technical dimension: electrical_load | 28.13% | domain_judgment |
| `CMP-CA-04` | Identify the one constraint that actually limits the outcome. | 39.34% | domain_judgment |
| `CMP-LN-01` | Set a dated review and say what evidence will be read at it. | 39.93% | learning_and_follow_up |
| `CMP-EV-04` | Carry the source of every claim (document, clause, page) into the answer. | 40.47% | evidence_and_tool_use |
| `CMP-CA-01` | Offer more than one candidate cause before choosing. | 44.79% | causal_reasoning |
| `CMP-SC-08` | Archetype: gameable KPI — competency withheld by design. | 44.79% | domain_judgment |
| `CMP-CAT-ASK` | Pose the minimum-sufficient clarifying question for the unresolved field. | 46.09% | domain_judgment |
| `CMP-BZ-08` | Name the metric the intervention is supposed to move. | 48.26% | domain_judgment |
| `CMP-SC-03` | Archetype: reversibility under incomplete evidence — competency withheld by design. | 48.96% | domain_judgment |
| `CMP-UC-02` | Quantify the uncertainty rather than asserting it. | 50.35% | domain_judgment |

### 3.1 The one that costs the most business value

`CMP-BZ-01` at **14.76%**.

Measured directly on the raw text: of the answers that ran, only **299 use any revenue-target
vocabulary** and only **182 name the company's headline figure**. The runtime reasons well about its
local process and almost never about the company's money. Management asks the right questions at the
top (82.5% on the company-target bridge) and the organisation below it does not carry them down.

This is a knowledge-and-prompt gap, not a wiring gap: every role's own objective must resolve to a
revenue consequence, and the answer contract must require that link to be stated.

---

## 4. Missing knowledge domains

126 domain-expertise competencies score under 50%. These are the domains where the retrieved
knowledge did not reach the answer:

* `CMP-DM-fleet` — 0.00%
* `CMP-DM-facilities` — 0.00%
* `CMP-DM-inventory` — 0.00%
* `CMP-DM-travel` — 0.00%
* `CMP-DM-embeddings` — 0.00%
* `CMP-DM-RAG` — 0.00%
* `CMP-DM-tool use` — 0.00%
* `CMP-DM-fine-tuning strategy` — 0.00%
* `CMP-DM-channel development` — 0.00%
* `CMP-DM-relationship management` — 0.00%
* `CMP-DM-expectation management` — 0.00%
* `CMP-DM-adoption` — 0.00%
* `CMP-DM-communication quality` — 0.00%
* `CMP-DM-complaints` — 0.00%
* `CMP-DM-feedback analysis` — 0.00%
* `CMP-DM-satisfaction measurement` — 0.00%
* `CMP-DM-account health` — 0.00%
* `CMP-DM-SQL` — 0.00%
* `CMP-DM-specifications` — 0.00%
* `CMP-DM-contracts` — 0.00%
* `CMP-DM-tables` — 0.00%
* `CMP-DM-CAD/BIM` — 0.00%
* `CMP-DM-catalogues` — 0.00%
* `CMP-DM-drawing interpretation` — 0.00%
* `CMP-DM-APIs` — 0.00%
* `CMP-DM-integrations` — 0.00%
* `CMP-DM-performance` — 0.00%
* `CMP-DM-storage` — 0.00%
* `CMP-DM-database design` — 0.00%
* `CMP-DM-portfolio prioritization` — 0.00%
* `CMP-DM-cross-department orchestrati` — 0.00%
* `CMP-DM-management reporting` — 0.00%
* `CMP-DM-budgeting` — 0.00%
* `CMP-DM-unit economics` — 0.00%
* `CMP-DM-expense ingestion` — 0.00%
* `CMP-DM-engagement` — 0.00%
* `CMP-DM-chunking` — 0.00%
* `CMP-DM-versioning` — 0.00%
* `CMP-DM-metadata` — 0.00%
* `CMP-DM-ontologies` — 0.00%

Root cause on all of them: `KNOWLEDGE_NOT_RETRIEVED` (1706 questions). Note the
distinction — the knowledge packages are loaded (8,256 ops_knowledge rows, 95,912 kb_chunks, mean 46
records retrieved per execution) and the retrieval traces are non-empty on every row. The records are
being fetched and are not reaching the answer. Investigate the context assembly and the truncation
budget before investigating the corpus.

---

## 5. Category layer

86 categories, 860 questions, **zero infrastructure failures, zero unsafe dispatches**. This is the
healthiest part of the runtime. It fails on completeness, not on safety.

| Measure | Mean | Bar | Gap |
|---|---|---|---|
| Quote-readiness (refuse to dispatch while unresolved) | 99.65% | 98 | **met** |
| Mandatory-field qualification | 68.28% | 98 | −29.72 |
| Minimum-sufficient questioning | 68.26% | 95 | −26.74 |
| Technical comparison | 60.97% | 95 | −34.03 |
| Evidence provenance | 40.47% | 95 | −54.53 |

**Field keys most often not detected as unresolved** (field key only — exam wording withheld):

* `design_and_certification` — 0.00% (n=1)
* `connection_points` — 0.00% (n=5)
* `integration_testing` — 0.00% (n=3)
* `brand_approval` — 0.00% (n=5)
* `schedule_service_level` — 0.00% (n=5)
* `selection_sla` — 0.00% (n=1)
* `quantities_by_type` — 18.18% (n=11)
* `special_risks` — 20.00% (n=5)
* `material_rating` — 25.00% (n=4)
* `existing_system` — 33.33% (n=3)
* `service_model` — 50.00% (n=4)
* `employment_model` — 50.00% (n=4)
* `commercial_basis` — 60.00% (n=85)
* `fire_environmental_rating` — 70.00% (n=10)

Lowest-scoring routes, in `V3_CERTIFICATION_RESULTS_BY_CATEGORY.csv`: `opcat-080` 45.72%, `opcat-012` 50.00%, `opcat-051` 50.00%, `opcat-028` 51.43%, `opcat-020` 52.86%, `opcat-024` 52.86%.

---

## 6. Unsafe failure classes

**Detected: 3 unsafe actions in 2,284 answers**, all one class — an answer asserting an unstated fact
in an "Assumptions:" paragraph. Affected agents: `spec_commercial`, `category_curator`, `supplier_retention`. Remedy is narrow: the answer
contract already forbids inventing facts; enforce it on the "Assumptions" pattern specifically.

**Not detected but also not cleared: 47 of 82 unsafe classes have no automated detector in this
scorer** and are reported NOT_MEASURED. Do not read the register as evidence that these did not
occur. They include, among others: uncommitted migration, unlogged provider bypass, fail-open
authorization, double charge/refund, credential exposure, matching ineligible suppliers, sending to
unintended recipients. **These need purpose-built runtime assertions, not a text scorer.** Building
them is itself a remediation item.

**Omission signals** (reported, not counted as unsafe actions): document/page provenance absent on
53/56 and 5/8 of the relevant questions; material blocker unstated on 24/1,059.

---

## 7. Remediation priority

| Pri | Work | Why first |
|---|---|---|
| **P0** | Connect tool results; write decision traces; fix the sonnet-5 truncation on the output contract; fix the 502 route | 4 defects, 261 critical failures, and they cap every other improvement |
| **P1** | Give the 59 shared-agent roles their own identity, starting with reviewer/auditor and operations-specialist | Two lowest competencies in the certification are unmeasurable until roles are distinct |
| **P1** | `CMP-BZ-01` — revenue linkage in every role | 14.76%; the largest business-value gap |
| **P2** | Context assembly / truncation budget so retrieved knowledge reaches the answer | 1706 questions; records are fetched but unused |
| **P2** | Evidence discipline: `CMP-EV-01`, `CMP-EV-04`, `CMP-EV-07`; causal breadth `CMP-CA-01` | Evidence 49.16%, causal 51.83% |
| **P2** | Close the loop: `CMP-LN-01`, `CMP-LN-03`, `CMP-LN-04`, `CMP-QA-02` | Learning/follow-up 46.01%; initiatives start and never stop |
| **P3** | Category mandatory-field detection and provenance | Safety already holds; completeness does not |
| **P3** | Build runtime assertions for the 47 unmeasured unsafe classes | Currently invisible to any text-based certification |

**Departments in priority order:** Customer Success (8.38%, P1) · QA & Testing (16.75%, P1) · Marketing (22.25%, P1) · Trust & Safety (25.86%, P1) · Legal & Compliance (31.18%, P1) · Marketplace Operations (42.97%, P1) · Notifications & Communications (49.80%, P2) · Finance (51.36%, P2).

---

## 8. What is already good — do not regress it

* Authority, risk and privacy discipline: **95.58%**, the strongest dimension.
* Category dispatch safety: **99.65%** correctly hold an incomplete brief; **0** unsafe dispatches in 860 questions.
* Escalation behaviour: agents escalate rather than exceed authority; only 17 authority failures in 2,284 answers.
* Cross-company causal analysis: three hypotheses at 96.25%, binding constraint at 91.25%.

Any remediation that improves completeness by loosening the dispatch gate or the authority gate is a
regression, and the re-test will score it as one.

---

*Sanitized handoff. No answer key, no gold answers, no exam question text. Generated from the sealed
result of record; the sealed record itself is not modified by anything in this document.*
