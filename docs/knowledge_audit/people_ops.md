# Knowledge audit — Agent Ops (`people_ops`)

Measured 6 Sep 2026, 02:03–02:40 UTC, read-only against production `htdblwldjkcgjvmqkbeh`. Every number below was
measured by query in this session unless marked **verify**. Company-wide plumbing (how any of this reaches an agent at run
time) is in `company_wide.md`; this file only repeats the parts that change the verdict for these four employees.

## 0. The one fact that overrides every gap table below

**None of the four employees receives its profession knowledge at run time, and the same is true of all 54 active agents.**
`fn_agent_context(p_agent_key, p_max_chars)` renders `# LAYER 2 - YOUR PROFESSIONAL EXPERTISE` from `agent_knowledge`
rows at `layer in ('profession','state')`, but admits a piece only while
`length(out) + length(piece) <= own_cap + 2200` where `own_cap = least(cap/2, 6000)` (+ ~100 chars of owner-line pad).
By the time the loop runs, `out` already holds identity, genome, risk register, employee record, authority, KPIs,
workload, OS block, goals, objectives, findings and decisions — measured at **11,283–13,365 characters** across the 54
agents — so the guard (~8,300) can never pass. Measured: `LAYER 2` is empty for **54 of 54** active agents
(`scripts` probe: chars between the LAYER 2 and LAYER 1 headings = 0 for every agent). The one `profession` row each
of these four holds (666–768 chars, `validation_status = unvalidated`) is therefore never handed to the model.

The run-time path (`agent_brain`, `workflow_dispatch`, `agent_act`, `exec_agents`, `secretary_act`… all call
`fn_agent_context_capped(key, 24000, query)`) keeps the **first 19,500 characters** of that standing context and appends
at most **4,500 characters** retrieved for the question. `# LAYER 3 - LIVE OPERATIONAL STATE` begins at char
21,796–22,098 for 48 of 54 agents (the other 6, all in `supply`, have no LAYER 3 at all) and `# LAYER 4 - WHAT THIS
ORGANIZATION HAS LEARNED` at 21,808–24,831 — both beyond the cut. So at run time these employees get: identity block,
~7k of global Layer 1 (FAQ, constitution, pricing), and ≤4.5k of keyword-matched operating knowledge. No profession,
no live state, no learned layer. Every gap table below is measured against what *exists in the tables*; the run-time
prompt carries less than that.

## 1. Roster and persona records

| agent_key | org_agents.title (role) | seniority / tier | org_role.role_id | runtime_mode | authority_level | budget | reports to | hired |
|---|---|---|---|---|---|---|---|---|
| ops_director | Chief Operating Officer (Operations Director) | director / director | chief_operating_officer | scheduled_manager | execute_medium | 10,000 | ceo | 2026-07-26 |
| culture_performance_mgr | Culture & Performance Manager | specialist / director | culture_and_performance_manager | on_demand_specialist | advisory | 1,000 | ops_director | 2026-07-26 |
| learning_dev_mgr | Learning & Development Manager | specialist / director | learning_and_development_manager | on_demand_specialist | execute_low | 1,000 | ops_director | 2026-07-26 |
| recruitment_specialist | Recruitment Specialist | specialist / operations_specialist | recruitment_specialist | on_demand_specialist | execute_low | 0 | ops_director | 2026-07-26 |

- `org_agents.department = 'people_ops'` holds 9 rows; 4 are `active`. The other five (`hr_director`,
  `ai_director`, `docs`, `org_designer`, `project_coordinator`) are `available = false` and their `org_role` rows are
  `status = retired`, `runtime_enabled = false`. The department charter (from the context head) is "HR for an
  all-software staff: certifies each agent before it does real work, puts under-performers on an improvement plan,
  activates roles that own a real firing decision and parks the rest at zero cost, and owns model policy for the AI
  workforce."
- `org_role.responsibilities` is one sentence each ("Owns process, quality and delivery across the company"; "Owns
  adherence to the AI constitution and company values; runs performance review"; "Owns knowledge coverage and exam
  performance across every employee"; "Identifies capability gaps and defines new employee roles to fill them").
- All four roles carry the same nine tools (`capability_exam, capability_review, idea_submit, knowledge_acquire,
  knowledge_fill, knowledge_fill_gap, qa_gate, role_define, self_review`) and near-identical `knowledge_scopes`.
  Two of those scopes — `knowledge` and `people_ops` — name **no row in `knowledge_domain`** (measured for all four
  roles); the scope binds nothing.
- `employee_authority`: ops_director 5 autonomous classes at AED 10,000 (capability_exam, knowledge_acquire,
  knowledge_fill, knowledge_fill_gap, qa_gate); culture_performance_mgr and learning_dev_mgr 2 each
  (capability_review, role_define, AED 1,000); recruitment_specialist 2 (same, AED 0).
- `org_role_identity` (packaged V2/V3 roles bound to the agent): ops_director 4 packaged roles
  (`hr-and-people-operations-director`, `hr-and-people-operations-analyst-controller`,
  `administration-and-operations-director`, `administration-and-operations-reviewer-auditor`);
  learning_dev_mgr and culture_performance_mgr 1 each (`hr-and-people-operations-operations-specialist` — the same
  package for both); recruitment_specialist 2 (that one plus `strategy-performance-and-evolution-operations-specialist`).

## 2. Knowledge inventory by source

### 2a. `agent_knowledge` (the only source `LAYER 2` and the exam read)

| agent | rows | chars | profession rows | experience rows | of which exam fills | exam fills that are supplier-category YAML | real (non-exam) experience |
|---|---|---|---|---|---|---|---|
| ops_director | 7 | 10,079 | 1 (666 chars, unvalidated, 2026-08-06) | 6 | 6 | 3 | 0 |
| culture_performance_mgr | 9 | 18,094 | 1 (768) | 8 | 8 | 2 | 0 |
| learning_dev_mgr | 8 | 15,667 | 1 (706) | 7 | 7 | 1 | 0 |
| recruitment_specialist | 8 | 14,708 | 1 (673) | 7 | 7 | 3 | 0 |

The single profession row per agent is a good ~120-word paragraph (e.g. ops_director: "Flow, not utilisation, is the
target… backlog per head is the honest load figure… a rising founder-decision share is an authority defect"). Everything
else in the table was written by the retrieval exam's auto-fill (`topic like 'exam:%'`, source `ops_knowledge:<id>`):
e.g. culture_performance_mgr now "knows" `source_route_manifest.json` for *Lifts & Escalator Suppliers* and
`06_RESEARCH_AND_ESCALATION_POLICY.yaml` for *property-management-companies*; ops_director holds
`specialist_manifest.yaml` for *insulation-suppliers* and `rfq_quality_gate.yaml` for *hvac-suppliers*. Across the
company, 147 of the 508 exam fills are supplier-category route files written into non-marketplace employees.

### 2b. `employee_knowledge` curriculum (12-layer standard) — `v_employee_knowledge_compliance`

All four: **INCOMPLETE, 5 of 12 layers bound** (company-wide: 54 of 54 INCOMPLETE, mean 3.8 layers).
Domains bound: ops_director 11 (`operations/expert/L1`, five company domains at L2, `customer_success`, `engineering`,
`procurement` at awareness/L4, `quotesdone_os/working/L5`, `communication/working/L8`); the three specialists 10 each
(`hr/expert/L1`, same L2 set, `ai_engineering` and `operations` at awareness/L4, L5, L8). Nothing is bound at L3
(department), L6 (workflow), L7 (decision), L9 (experience), L10 (improvement), L11 (KPI), L12 (AI self).

### 2c. `ops_knowledge` (9,132 rows, 100 % embedded)

- Rows with `dept_key = 'people_ops'`: **8** — all `decision_playbook`, all of the form "<event> in people_ops — the
  org_task lane determination" (event routing, 2.3–3.2k chars each). No HR/L&D/performance domain playbook carries
  this dept_key.
- Rows with `dept_key = 'hr'` (reachable because `fn_dept_scope('people_ops') = {hr, knowledge, people_ops}`):
  **271 rows** — yaml 66 (264k chars), md 24 (209k), knowledge_domain 20, operational_application 20,
  control_requirements 20, data_and_evidence 20, failure_mode_case 28, decision_rule 10, standard_operating_procedure 10,
  exception_playbook 10, metric_definition 9, department_scenario 8, live_data_binding 10, operational_template 5,
  agent_role 4, csv 2, json 4, event_subscription 1. By module: professional_knowledge 50 (226k chars),
  exception_handling 44, decision_rules 33 (183k), role 24, governance 20, evidence 20, controls 20, kpi 15,
  source_registry 11, live_data 10, sop 10, scenario_test 8, templates 5.
- Rows reachable through the packaged roles (`role_key = any(org_role_identity.packaged_role_id)`):
  ops_director 104 rows / 288,578 chars; recruitment_specialist 52 / 147,384; learning_dev_mgr and
  culture_performance_mgr 26 / 72,678 each. **0** of those rows are of an actionable kind
  (decision_playbook / decision_rule / SOP / exception_playbook) — role-scoped rows are md/yaml/failure_mode_case/agent_role.
- Actionable rows in the whole `people_ops` scope for `fn_apply_playbook` / `fn_ops_knowledge_match`: **98**
  (hr 30 + knowledge 60 + people_ops 8); company-scope actionable rows: 0.
- `ops_knowledge` full-text depth probes (rows matching): OKR 58, "exam design" 132, persona 51, prompt engineering 14,
  capacity planning 8, improvement plan 7, MOHRE 3, competency framework 0, Kirkpatrick 0.

### 2d. `kb_chunks` (deep corpus, ~2.65 M rows; category-scoped, no department column)

Nearest categories (from `kb_category_stats`): `hr` 36,886 chunks (standard 21,298, reference 14,189, guide 862,
regulation 525, document 12); `human-resources-and-recruitment` 23,587 (standard 22,411, qd_kb_pack 1,176);
`education-and-training-support` 9,606; `facilities-management-and-support-services` 27,748. Full-text hits across the
corpus: MOHRE 575, "labour law decree 33" 88, OKR 251, Kirkpatrick 439, capacity planning 391, competency framework 155,
prompt engineering 352, "LLM evaluation" 1,615, "agent persona" 0. The material exists; whether it *reaches* these
agents is the plumbing question: `kb_chunks` is ~95.9 % un-embedded (pg_stats `null_frac` 0.9588; sampled id ranges
600k–2.62M are 0 % embedded; only the first ~120k ids — `qd_kb_pack`, `document`, `generated`, `library`, `memory` —
are embedded), so the vector half of `kb_search` cannot see the `standard`/`reference`/`regulation` chunks above; only
the keyword half can.
`dept_library` (the `LAYER 2b` source): legal 451, marketplace 361, assurance 318, finance 290, company 36 —
**people_ops 0**, so LAYER 2b is never emitted for these four.

### 2e. `fn_agent_context('<agent>', 22000)` — what exists in the head (2-arg, uncapped)

| agent | chars | sections | LAYER 2 content | LAYER 1 globals | LAYER 3 starts | LAYER 4 items |
|---|---|---|---|---|---|---|
| ops_director | 30,496 | 39 | empty | 17 topics (FAQ truncated at 1,500 of 197,956) | 21,996 | 4 (all exam fills: specialist_manifest.yaml, output_contracts.yaml, rfq_quality_gate.yaml, CoS scenario 01) |
| culture_performance_mgr | 30,596 | 37 | empty | 17 | 22,096 | 1 (source_route_manifest.json) |
| learning_dev_mgr | 30,584 | 39 | empty | 17 | 22,084 | 3 (quote_comparison_contract.yaml + 2 people_ops lane determinations) |
| recruitment_specialist | 30,296 | 37 | empty | 17 | 21,796 | 2 |

Section list (identical for all four): identity, genome, risk register, employee record, authority, KPIs, workload,
Operations OS, company goals, department objectives, open findings, decisions on record, LAYER 2 (empty), LAYER 1
(brand wording, document branding, AI Constitution, response structure, governance gate, retrieve-before-answering,
RFQ completeness, Pricing & fees LIVE, Company FAQ, 5 × AI-explainability, `company:self_knowledge`, canon:core,
brand essentials), LAYER 3 live state, LAYER 4 learned, OS objectives measured, workflows in flight, "how your
department is defined in the target operating model" (maps `people_ops → admin_operations, hr_people`: 20 SOPs,
20 decision rules, 20 exception playbooks, 18 KPIs, 3 handoffs, 10 templates — pointer only: "Full text: select
fn_ops_department_context('people_ops', <topic>)").
The `company:self_knowledge` block in LAYER 1 is the `agent_knowledge._global` row last updated **2026-08-16**
("10 departments, 90 brain agents, 132 category sales agents… 0 open tasks", still listing an `assurance`
department); the live 15-minute `fn_company_self_knowledge_sync` writes `ops_knowledge` `qd-company:*` rows (44 rows,
effective 2026-09-06), which this path never reads — see `company_wide.md` §3.

Query-aware path, measured with an aborted-transaction probe:
`fn_agent_context_capped('learning_dev_mgr', 24000, 'design a remediation curriculum for an employee whose knowledge
exam score is below 40 percent')` → 24,155 chars: standing head trimmed at 19,500 (marker at 19,532), then only
`# LAYER 2c` (5 keyword-matched `ops_knowledge` rows, 700 chars each). No 2b (no dept_library), and 2d/2f/2g
(role knowledge, deterministic rules, live-data facts) are cut by the 4,500-char tail reserve.
Uncapped 3-arg `fn_agent_context('ops_director', 24000, 'capacity planning for the agent workforce…')` → 41,091
chars with 2b @32,578, 2c @33,465, 2d @36,346, 2f @37,655, 2g present — so the layers exist; the cap removes them.
`fn_agent_context_v3('ops_director','plan',<same query>,null,22000)` returns 319,604 chars of JSON against a
22,000 budget (`knowledge_count` 70): company_core 2 records (one is `CLAUDE_INGESTION_PROMPT_V2.md`), role_knowledge
4, department_knowledge 4, company_wide_knowledge 6 (six copies of `00_DEPARTMENT_MASTER.md`), field_corpus 12 (SHRM
BASK 2025 and HRM textbook chapters — this is the one place real HR field knowledge surfaces), deterministic_rules 60
(admin_operations control_requirements, 188k chars), live_data_required 34 (mostly Supplier Knowledge bindings).

## 3. Measured competence

| agent | exam answers (all time) | correct | score | verdicts | last exam | kb_usage_log 30d | agent_runs 7d | review_chain 30d |
|---|---|---|---|---|---|---|---|---|
| ops_director | 20 | 5 | **25 %** | correct 5, partial 8, not_covered 6, wrong 1 | 2026-09-05 | 34 rows (all `context assembly: 63 knowledge record(s)` / work orders) | ok 25, error 2, skipped 2 | approve 111, owned 24, null 37, reject 0 |
| culture_performance_mgr | 16 | 5 | **31 %** | correct 5, not_covered 5, wrong 4, partial 2 | 2026-09-05 | 0 | ok 6 | approve 36, owned 12, null 12 |
| learning_dev_mgr | 16 | 4 | **25 %** | correct 4, wrong 6, not_covered 3, partial 3 | 2026-09-05 | 0 | ok 5 | approve 36, owned 12, null 12 |
| recruitment_specialist | 16 | 5 | **31 %** | correct 5, not_covered 5, wrong 4, partial 2 | 2026-09-05 | 0 | ok 5 | approve 27, owned 9, null 9 |

- The two ops_director errors (3 Sep) are "The model returned nothing… Prompt was 36,750 characters" — the paid hold,
  not a knowledge failure. Review pass rate for all four is 100 % of decided reviews (0 reject, 0 request_revision);
  `artifact_review` has 0 rows in 30 days company-wide, so no artefact-quality signal exists.
- What the exam measures for these four (see `company_wide.md` §4): question bank = 10–14 questions each, **all** of the
  form "What does the company's operating knowledge say about: <ops_knowledge title>?", generated by
  `fn_knowledge_exam_sit` from `ops_knowledge` rows where `dept_key = 'people_ops'` (8 rows) **or `dept_key is null`**
  (2,095 rows, 1,204 of them supplier-category route files). The 271 `hr` rows are never sampled because the
  generator compares `dept_key = org_agents.department` and does not go through `fn_dept_scope`. So
  culture_performance_mgr was examined on *Renewal And Governance (business development)*, *bakery-equipment
  rfq_quality_gate.yaml*, *lifts-and-escalator source_route_manifest.json*; the grader then wrote those into its
  experience layer as "learned".
- The grader is a lexeme-overlap check against `agent_knowledge` only (`_exam_corpus` = the agent's rows + `_global`);
  it never looks at `ops_knowledge`, `kb_chunks` or the packaged role rows. A score of 25 % therefore means "25 % of
  randomly sampled ops_knowledge titles have ≥60 % lexeme overlap with something in this agent's 7–9 agent_knowledge
  rows" — it is not a measure of HR/L&D competence in either direction.
- `canon_eval_runs` (the model-graded suite): 29 runs over 16 agents, last 2026-08-10, none for these four.
  `org_role.evaluation_suite` names `eval_operating_cadence`, `eval_performance_review`, `eval_learning_design`,
  `eval_recruitment`; no table or row holding those suites was found (`information_schema` search for `%eval%` /
  `%certif%`).

## 4. Senior-staff standard and gap tables

Standard applied: what a top senior person in the role knows without looking it up, at a UAE company whose staff are
AI agents (so "HR" is persona design, capability certification, performance management of agents, model policy and
cost; UAE labour law/MoHRE applies only where a human is involved — today the founder alone).
"Today" columns cite what is in the tables; recall from §0 that at run time the agent sees less.

Routes: `agent_knowledge:profession` = authored paragraphs handed in LAYER 2 (once §0 is fixed);
`ops_knowledge(dept_key=people_ops, record_type=…)` = department operating knowledge reachable by
`fn_ops_knowledge_match`/`fn_apply_playbook`; `dept_library(people_ops)` = LAYER 2b; `employee_knowledge` = curriculum
binding; `kb_chunks` = deep corpus (needs embedding to be retrievable by meaning).

### 4a. ops_director — Chief Operating Officer / Agent Ops director

| domain | required depth | today + evidence | what to ingest + route | size | pri |
|---|---|---|---|---|---|
| Capacity planning for AI staff (max_open_tasks, backlog per head, cron/executor capacity, queue ageing, cost per run) | expert; can compute load and decide headcount/parking from live tables | 1 profession paragraph names the right numbers but is never delivered (§0). LAYER 3 live state exists (open_tasks, overdue, agent_errors_24h, cron_failures_24h) but starts at char 21,996 → cut at run time. `ops_knowledge` "capacity planning" 8 hits; no SOP. | Authored SOP "Weekly capacity review" with the exact SQL/RPC to read (org_tasks by dept, agent_runs 7d, cron 232 jobs), decision thresholds (park/split/merge) and the org_designer monthly questions (now retired role) → `ops_knowledge` SOP + decision_rule, dept_key `people_ops`; bind `operations` at L3 | 3 SOPs + 4 rules, ~12k chars | P1 |
| Org design for an AI workforce (department scope map, merges, role lifecycle, `fn_dept_scope`, packaged roles, activation/parking at zero cost) | expert | `org-people_ops` and `qd-company:workflows` describe the org; nothing explains the 10→22 dept_key crosswalk (`fn_dept_scope`), why `people_ops` maps to `hr/knowledge`, or the parking rule. 5 retired roles in its own dept with no record of why. | One authored "How the org is shaped and changed" doc: dept scope map, role status lifecycle, retire/park/reactivate criteria, what a merge does to handoffs (memory: a merge that collapses a handoff is refused) → `ops_knowledge` md + decision_rule | ~8k chars | P1 |
| KPI / OKR system for agents (cascade goals→dept→KPI, `measure_sql`, targets, cadence, attainment bands) | expert | KPIs are listed in the head with targets; 58 `ops_knowledge` OKR hits but none is a design method; its own KPI is a mis-labelled inherited one ("HR Director — primary objective" at 79.63 %). | KPI design SOP (what a KPI needs: measure_sql, unit, cadence, goal link), attainment-band rules, the root-cause vocabulary already used by improvement plans ("deterministic band, no model call") → SOP + decision_rule, people_ops | ~6k | P1 |
| Performance management of agents (review_chain, exam, error rate, improvement plans, restriction/reactivation) | expert | Owned by culture_performance_mgr; ops_director's authority list includes `performance_review`, `improvement_plan_refresh`, `kpi_assign` but no playbook for when to restrict a role. `hr` dept has 10 decision rules/10 SOPs/10 exception playbooks (generic "missing mandatory evidence → needs_info"). | Decision playbook "Under-performing agent": inputs (KPI attainment, exam, error rate, review outcomes), bands, actions (improvement plan → restrict to advisory → park), evidence contract → `ops_knowledge` decision_playbook, people_ops | ~5k | P1 |
| Evaluation / exam design | working | See learning_dev_mgr; ops_director owns `capability_exam` authority but the exam is the lexeme grader described in §3. | Shared with learning_dev_mgr row | — | P2 |
| Hiring = persona design and onboarding of new AI staff | working | `role_define` tool; no persona template in knowledge; `org_role` schema (owned/forbidden decisions, activation conditions, output contracts) is the de-facto template but not described anywhere the agent reads. | Persona specification standard (one doc) → `ops_knowledge` SOP; see recruitment_specialist | ~4k | P2 |
| Model policy and AI cost (tiers, hold, cache, cost per department) | expert (charter says it owns model policy) | Nothing in its knowledge names the routing tiers, the paid hold (kernel K12), the ~900-token gateway cap or cost per run; LAYER 3 shows `agent_errors_24h` only. | Authored "Model policy" doc from `model_routing_policy` rows (5 exist, company scope) + ai_cost_log reading SOP → profession row + SOP | ~5k | P1 |
| Process quality: SOP coverage, SLAs, quality gates, workflow failure rate | expert | Head shows "Failed workflows below 0.5% — currently 9.89 (at_risk)" and "100% SOP coverage — not yet measured"; no procedure to act on either. `sop` module in hr has 10 rows. | SOP "Workflow failure triage" (read workflow_step_run failed/skipped, classify, route) and "SOP coverage measurement" → SOP + decision_rule | ~6k | P1 |
| UAE labour law / MoHRE (humans only) | awareness | `ops_knowledge` MOHRE 3 rows; `kb_chunks` MOHRE 575 / Decree-Law 33 88 (keyword-reachable only). | Bind `hr` at L4 awareness with one 1-page summary "when a human is involved, Legal owns it" → agent_knowledge profession row | ~1.5k | P3 |
| Knowledge lifecycle (decay, curator, exam loop, embedding backlog) | working | Its OS "owns knowledge" but nothing tells it which crons are paused or that `kb_chunks` is 96 % un-embedded. | The `company_wide.md` §5/§6 tables as an `ops_knowledge` md record refreshed by cron | ~4k | P2 |

P1 count: **6**.

### 4b. culture_performance_mgr — Culture & Performance Manager

| domain | required depth | today + evidence | what to ingest + route | size | pri |
|---|---|---|---|---|---|
| Performance review method for AI employees (KPI attainment, review_chain outcomes, exam, error/skip rates, calibration across departments) | expert | 1 profession paragraph (768 chars, "judge on the audit trail") — never delivered (§0). `hr` has 9 metric_definitions and 15 kpi rows but no review procedure. Its own KPI attainment is 73.3 % with the note "target above current capability". | SOP "Quarterly agent performance review" with the exact sources (employee_kpi, review_chain 30d, knowledge_exam_results, agent_runs), scoring bands, calibration rule, output = improvement_plan text → `ops_knowledge` SOP + decision_rule, people_ops; bind `hr` L3 | ~8k | P1 |
| Constitution and values adherence measurement (policy_rules lint, chat_violations, escalation misuse, founder-paging) | expert | LAYER 1 has the AI Constitution (1,863 chars) and governance gate; nothing on *how to measure* adherence. `policy_rules` (forbid_regex) and `review_chain.violated_rule` exist but no procedure reads them. | SOP "Behavioural audit": which tables record violations, thresholds, what a breach triggers → SOP + exception_playbook | ~5k | P1 |
| Improvement-plan design and follow-up | expert | `improvement_plan` text is generated deterministically per agent; no knowledge on plan structure, review cadence, or closure criteria. | Decision playbook "Improvement plan lifecycle" (open → 30-day check → close/escalate) → decision_playbook | ~4k | P1 |
| Culture for an AI workforce (values in `company_vision`, "smart engine not AI", brand voice) | working | Present in LAYER 1 (values, brand essentials) — reachable. | none | — | — |
| Root-cause taxonomy for KPI misses | working | The head already carries "Root cause (deterministic band, no model call)" bands. | Short reference of the bands and the fix per band → profession row | ~2k | P2 |
| HR field knowledge (performance psychology, feedback, motivation) | awareness | `field_corpus` in v3 surfaces HRM textbook chapters (Work Motivation for Performance) — but only on the v3 path, which no runtime caller uses directly. | Embedding backlog fix (company-wide) makes `hr` corpus vector-retrievable | — | P3 |

P1 count: **3**.

### 4c. learning_dev_mgr — Learning & Development Manager

| domain | required depth | today + evidence | what to ingest + route | size | pri |
|---|---|---|---|---|---|
| Curriculum design against the 12-layer `employee_knowledge_standard` | expert | Profession row says "agent_knowledge at layer profession is the curriculum" (706 chars, undelivered). 54/54 agents INCOMPLETE at 3.8/12 layers; no procedure to bind L3/L6/L7/L9–L12. | SOP "Bind an employee's 12 layers": what each layer binds via (knowledge_domain / workflow / runtime / memory / kpi), how to verify with `v_employee_knowledge_compliance` → SOP, people_ops | ~6k | P1 |
| Exam and item design (validity, scoping to the role, difficulty, reference answers, grading rubric) | expert | The exam bank it "owns" is template questions sampled from the wrong population (§3); 506 of 591 active-agent questions are the template; `Kirkpatrick` 0 in ops_knowledge (439 in kb_chunks, keyword only). | Decision rule "A question is valid only if its source record is in the examinee's `fn_dept_scope` or packaged roles" + SOP "Exam item writing" + the remediation contract (wrong verdict → correction or quarantine) → decision_rule + SOP | ~6k | P1 |
| Remediation design for a failed evaluation | expert | `owned_decisions` says so; no playbook; the only remediation today is the auto-fill that writes the reference answer into the agent (including category YAML). | Decision playbook "Remediation after a failed exam": diagnose (missing source vs missing binding vs stale), fix route, re-test window → decision_playbook | ~4k | P1 |
| Knowledge sources and routing (agent_knowledge vs ops_knowledge vs kb_chunks vs dept_library; what reaches which layer; embedding status) | expert | Nothing in its knowledge describes the plumbing; `docs/expertise/AGENT_KNOWLEDGE_PATH.md` exists in the repo (not measured whether ingested — **verify**). | Ingest `company_wide.md` §3 as an ops_knowledge md record + the repo doc → md, people_ops | ~8k | P1 |
| Knowledge freshness policy (decay, review_due, curator, source_freshness) | expert | `knowledge_decay_daily` runs but every `agent_knowledge.review_due` is in the future (0 past due, 0 stale) so it has never decayed anything; curator paused. Agent does not know this. | Freshness SOP with the actual review cadences per layer → SOP | ~3k | P2 |
| Certification pipeline (`docs/expertise/ROLE_CERTIFICATION_MAP.csv`, cert targets, canon_eval) | working | Repo has the map and pilot; `canon_eval_runs` last 2026-08-10; not in the agent's knowledge. | Ingest the certification map summary → md record | ~4k | P2 |
| L&D field knowledge (adult learning, spaced review, transfer measurement) | awareness | kb_chunks `education-and-training-support` 9.6k chunks, un-embedded. | Company-wide embedding fix | — | P3 |

P1 count: **4**.

### 4d. recruitment_specialist — Recruitment Specialist (persona design for new AI staff)

| domain | required depth | today + evidence | what to ingest + route | size | pri |
|---|---|---|---|---|---|
| Persona specification (org_role fields: responsibilities, owned/forbidden decisions, activation conditions, required inputs, output contracts, tools, knowledge_scopes, authority, model_policy, evaluation_suite) | expert | Profession row (673 chars) states "a hire here is a specification, not a search" and lists the fields — undelivered. `ops_knowledge` persona 51 hits (mostly category personas); "agent persona" 0 in kb_chunks. | SOP "Define a new AI role" = the org_role contract field by field, with the guard rules (fn_org_authority_guard change_reason; Phase A dept/role counts are frozen — a PACR is needed for a new canonical role) → SOP + decision_rule | ~6k | P1 |
| Capability-gap detection (work with no accountable owner, executors with no role, repeated escalations to founder) | expert | `owned_decisions`: "sourcing approach and candidate specification"; the retired org_designer's questions are gone; no procedure names the sources (workflow steps without actor, org_tasks refused for missing executor — 10 such in 7d). | Decision playbook "Is this a missing role or a missing authority?" with the queries → decision_playbook | ~4k | P1 |
| Onboarding and certification of a new agent (knowledge binding, exam before real work, probation) | expert | The TOM section says hr_people sends `agent_onboarding_certification` handoffs; the agent has no SOP for it. | SOP "Onboard and certify" (bind 12 layers, seed profession row, sit exam, set `available`) → SOP | ~4k | P1 |
| Knowledge-pack sourcing for a new role (which V2/V3 packs exist, how ingestion runs, what a pack must contain) | working | `knowledge_ingestion_run` and `docs/expertise/CORPUS_INGESTION.md` exist; not in the agent's knowledge. | md record summarising pack structure and ingestion command | ~3k | P2 |
| Model policy per role and cost of a seat | working | none | Shared with ops_director model-policy doc | — | P2 |
| Human recruitment / UAE labour market, MoHRE, visas | awareness (humans only) | kb_chunks `human-resources-and-recruitment` 23.6k chunks; `hr-and-recruitment-agencies` trade 16. | 1-page "humans are hired by the founder; Legal owns compliance" → profession row | ~1k | P3 |

P1 count: **3**.

## 5. Reasoning gap (all four)

- **No reasoning is measured.** The only running evaluator is the lexeme-overlap retrieval exam; `canon_eval_runs`
  (model-graded) stopped 2026-08-10; the `evaluation_suite` names in `org_role` resolve to nothing.
- **The deterministic reasoning layer has nothing people-ops-specific to bind.** `fn_apply_playbook` scopes to
  `fn_dept_scope('people_ops') = {hr, knowledge, people_ops}` (98 actionable rows) — but the 8 `people_ops` playbooks are
  event-routing determinations and the 30 `hr` actionable rows are generic package rules ("Missing mandatory evidence →
  needs_info"). Over the last 7 days, 8 of 1,861 `workflow_step_run` outputs reference a playbook (`worked_by`/`playbook`
  key), 1,609 record `used_llm = false`, and 405 carry `used_llm_basis = "paid provider held"`. Nothing in these four
  agents' scope encodes *how to decide* an under-performance case, a capacity case, a persona case or a remediation
  case — those are the P1 rows above.
- **The learned layer is polluted, not empty.** 7–8 "experience" rows per agent are exam auto-fills; 1–3 per agent are
  supplier-category YAML. A senior person's judgement layer (lessons from real decisions) has 0 rows; `decision_log`
  outcomes are "not yet recorded" in the head.
- **Run-time truncation removes the live numbers a director reasons from** (§0): open tasks, overdue, error counts,
  cron failures are in LAYER 3, which sits past the 19,500-char cut for all four.

## 6. What could not be measured

- Whether `docs/expertise/AGENT_KNOWLEDGE_PATH.md`, `CORPUS_INGESTION.md` and `ROLE_CERTIFICATION_MAP.csv` were ever
  ingested into `ops_knowledge` (not searched by source_path) — **verify**.
- Artefact quality (`artifact_review` has 0 rows in 30 days for anyone).
- How often `kb_search` (the kb_chunks path) returns 0 results — `kb_usage_log` stores query text only; see
  `company_wide.md` §3 for the proxy that exists.
- The exact `kb_chunks` un-embedded count (a full count exceeds the 8 s statement timeout); the estimate is from
  `pg_stats` plus five sampled id ranges.
