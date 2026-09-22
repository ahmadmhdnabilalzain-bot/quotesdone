# Company brain — people_ops

*Written 7 September 2026. Every number below was read from production (`htdblwldjkcgjvmqkbeh`) between
08:03 and 08:40 UTC on 7 Sep 2026 before it was written down. Where the estate lacks something the words
are "does not exist", not a description of something that isn't there.*

**The founder's constraint, stated twice: nothing here may call a language model at run time.** Every
resolver in this section is SQL, arithmetic over stored rows, full-text and trigram matching, and
template composition. The one honest exception list is §9 of each seat.

---

## Department state, measured

`public.org_agents where department='people_ops'` holds **9 rows, 4 active**:

| agent_key | title | seniority | manager | routing_tier | hired |
|---|---|---|---|---|---|
| `ops_director` | Chief Operating Officer (role: Operations Director) | director | `ceo` | director | 2026-07-26 |
| `culture_performance_mgr` | Culture & Performance Manager | specialist | `ops_director` | director | 2026-07-26 |
| `learning_dev_mgr` | Learning & Development Manager | specialist | `ops_director` | director | 2026-07-26 |
| `recruitment_specialist` | Recruitment Specialist | specialist | `ops_director` | operations_specialist | 2026-07-26 |

Inactive in this department (`active=false`, kept as history): `ai_director`, `docs`, `hr_director`,
`org_designer`, `project_coordinator`. `hr_director` (Agent Workforce & Capability Director) is the seat
whose KPI row `ops_director` still carries — see §8 of ops_director.

**The certification programme, as it stands at 08:03 UTC today.** `role_certification` holds 105 rows across
the 54 active employees; `certification_exam_question` holds 2,080 questions and
`certification_exam_question_vector` 10,400 embedded rows. `certification_exam_result` holds **22 rows** —
5 distinct (employee, certification) sittings, by `bookkeeper`, `security`, `procurement`, `cs_support` and
`marketing_analyst`. **Zero have passed.** Scores measured: 15, 25 (ACCA, pass mark 50); 27.5, 42.5 (CISSP,
70); 27.5, 10 (MCIPS, 50); 35, 2.5 (HDI-SCA, 75); 25, 35 (GA4, 80). `certification_knowledge_gap` holds 23
rows, **all of them `bookkeeper`/ACCA**.

**No seat in people_ops has sat any exam.** `fn_certification_exam_summary()` returns `sat=0, passed=0,
failed=0, worst_areas=null` for all four. So wherever the brief asks for "the syllabus areas it failed",
the honest answer for this department is: **does not exist yet**. The bank, the sitter and the gap ledger
all exist; the sitting has not happened, and there is no cron that schedules it —
`fn_certification_exam_sit_all()` has no `cron.job` row, and job 132 `canon_eval_weekly`
(`fn_recert_rotate`) is **OFF**.

**The sitter is already deterministic**, which is why this plan can lean on it. Per
`scripts/sql/an_employee_sits_its_certification_exam_from_its_own_knowledge.sql`, for each question
`fn_certification_exam_sit` assembles the employee's own reachable evidence — `fn_agent_context(agent,
19500)`, `fn_ops_knowledge_search(department,…)`, its own `agent_knowledge` rows, `kb_chunks` matched by an
AND query on the stem — and scores each option as
`max over evidence docs of ts_rank_cd(doc, OR-of-that-option's-own-lexemes, 32) + 0.02 *
word_similarity(option, doc)`. Abstention thresholds: `c_min_support = 0.25`, `c_min_margin = 0.15`
(relative). An abstention records `chosen = null` and counts wrong. No random tiebreak, no model call.

**A defect found while measuring, which this plan must not build on top of.** Of the 46 syllabus-area
labels written on this department's 7 `role_certification` rows, **16 have no verbatim match** in
`certification_exam_question.syllabus_area` for the same certification, so a remediation plan keyed on the
certification row would never join the bank or the gap ledger:

| seat | certification | label with no question behind it |
|---|---|---|
| `ops_director` | PMP | Predictive Plan-Based Methodologies; Agile and Hybrid Approaches |
| `ops_director` | CSSBB | Design for Six Sigma *(bank says "Design for Six Sigma (DFSS) Frameworks and Methodologies")* |
| `culture_performance_mgr` | SHRM-SCP | HR Expertise People; HR Expertise Organization; HR Expertise Workplace |
| `culture_performance_mgr`, `learning_dev_mgr` | CPTD | Learning Technologies *(bank says "Technology Application")* |
| `learning_dev_mgr`, `recruitment_specialist` | SHRM-CP | Behavioral Competencies; People Knowledge Domain; Organization Knowledge Domain; Workplace Knowledge Domain |

Bank depth for this department's five certifications: PMP 40 questions / 3 areas; CSSBB 40 / 9;
SHRM-CP 40 / 17; SHRM-SCP 40 / 19; CPTD 40 / 20.

**Knowledge binding, measured.** `employee_knowledge_standard` defines a **12-layer** standard. All four
seats hold rows in **layers 1, 2, 4, 5 and 8 only** (ops_director 11 rows, the other three 10 each).
**Layers 3, 6, 7, 9, 10, 11 and 12 hold zero rows for every seat in this department** — Department,
Workflow, Decision, Experience, Improvement, KPI and AI-Self knowledge are unbound. `agent_knowledge`
module counts: `culture_performance_mgr` 10, `learning_dev_mgr` 8, `recruitment_specialist` 8,
`ops_director` 7 — all below the company standard of 14 (`company_goals.knowledge_modules_complete`);
company-wide only **9 of 54** active employees reach 14.

**Retrieval scope.** `fn_dept_scope('people_ops')` returns `{hr, knowledge, people_ops}`. `ops_knowledge`
holds 271 rows at `dept_key='hr'`, 8 at `people_ops`, 413 at `knowledge` (9,140 rows in total, all
`runtime_eligible`). Modules under hr+people_ops: professional_knowledge 50, exception_handling 44,
decision_rules 33, role 24, governance 20, controls 20, evidence 20, kpi 15, source_registry 11,
live_data 10, sop 10, scenario_test 8, org_task_lane 8, templates 5, events 1. Ten named decision rules
exist ("HR & People Operations rule 01 — Missing mandatory evidence" … "rule 10 — Material anomaly").

**Authority** (`employee_authority`, 320 rows company-wide, 11 for this department):

| seat | action_class | max_tier | threshold_aed |
|---|---|---|---|
| `ops_director` | `capability_exam`, `qa_gate`, `knowledge_acquire`, `knowledge_fill_gap`, `knowledge_fill` | autonomous | 10,000 |
| `culture_performance_mgr` | `role_define`, `capability_review` | autonomous | 1,000 |
| `learning_dev_mgr` | `role_define`, `capability_review` | autonomous | 1,000 |
| `recruitment_specialist` | `role_define`, `capability_review` | autonomous | 0 |

**Workflows** (`employee_workflow`): `employee_task` — `ops_director` approver, the other three owners.
`ops_director` is additionally a participant in `rfq_handling` and a step actor in `incident_response`.
`employee_task` has 17 steps and **0 founder gates**; company-wide the only founder-gated steps are the 2
in `refund`.

**Reputation** (`agent_reputation`, recomputed 2026-09-07 07:00 UTC, all four `trusted`):

| seat | score | correctness (n) | reliability (n) | collaboration (n) | cost_eff (n) | decision_quality (n) | learning_speed (n) |
|---|---|---|---|---|---|---|---|
| `ops_director` | 77.2 | 98.1 (127) | 89.8 (88) | 98.5 (164) | 23.3 (10) | 13.5 (21) | 50.0 **(0)** |
| `culture_performance_mgr` | 75.4 | 93.9 (36) | 90.7 (22) | 50.0 (0) | 50.0 (0) | 50.0 (0) | 50.0 **(0)** |
| `learning_dev_mgr` | 75.1 | 93.9 (36) | 89.6 (19) | 50.0 (0) | 50.0 (0) | 50.0 (0) | 50.0 **(0)** |
| `recruitment_specialist` | 74.4 | 92.2 (27) | 89.1 (18) | 50.0 (0) | 50.0 (0) | 50.0 (0) | 50.0 **(0)** |

A 50.0 on zero evidence is the prior, not a measurement. **`learning_speed` has zero evidence for every
seat in the department that owns learning.**

**Business reality this department is planning against** (measured 08:03 UTC): 1 customer, **0 inquiries,
0 quotes, 0 transactions, 0 reveals**, 1 approved supplier out of 22,265 `leads` rows, 54 active
employees, 2,466 `org_tasks` (0 open). `pricing_config`: reveal fee **3%** of quote value (promo and
standard, cap 99,999,999 AED), supplier registration **AED 1,000/year with the first 1,000 free**
(`supplier_charging_starts` is null), refund window 5 working days, chase at 3, bank settlement 7–14
working days, `category_open_min_suppliers` 10.

`company_goals` holds 64 rows. **people_ops owns exactly three**, and `revenue_annual` (AED 1,000,000,
annual) is owned by `finance`:

| goal | target | `goal_period` 2026-09 actual | status |
|---|---|---|---|
| `workflow_automation` | ≥ 98 % | 98.93 | on_track |
| `failed_workflows` | ≤ 0.5 % | 4.08 | at_risk |
| `sop_coverage` | 100 % | null | open — `no_measure_reason` = "NO INSTRUMENT EXISTS" |

My own count of `workflow_run` at 08:03: 1,486 done, 61 failed, 103 running, 84 cancelled — 61/1,547 =
**3.94 %** on the goal's own denominator. `workflow_step_run`: 1,715 done, 35 failed, 23,647 skipped,
1,616 queued, 104 ready.

**Machinery already scheduled** (235 `cron.job` rows, 134 active). ON: 8 `agent_onboarding_hourly`,
139 `self_review_weekly`, 140 `kpi_review_weekly`, 161 `reputation_weekly`, 184 `improvement_plan_daily`,
204 `learning_loop_sweep_hourly`, 205 `improvement_handover_hourly`, 250 `employee_kpi_measure_daily`,
282 `promotion_review_weekly`, 290 `employee_kpi_assign_daily`, 320 `knowledge_exam_retrieval_daily`.
OFF: 38 `learn_gaps_weekly`, 75 `ai_trainer_daily`, 96 `agent_learnings_weekly`, 128 `dept_learn_daily`,
132 `canon_eval_weekly`, 135 `knowledge_exam_loop`, 157 `os_improve_weekly`, 188 `memory_promotion_weekly`,
219 `capability_verify_daily`, 263 `scenario_staffing_weekly`.

**`org_onboarding` is stalled.** 16 rows, every one `status='onboarding'`, `l1_score=83.3` against
`pass_threshold=85`, `l2_at`/`l3_at`/`l4_at` null, `certified_at` null, `probation_reviews_done=0` of 3.

**The existing trainer is model-priced and must not be the basis of this plan.**
`agent_training_attempt` (164 rows) carries `model`, `input_tokens`, `output_tokens`, `cost_aed`.
Measured for this department: `recruitment_specialist` 3 practice attempts, 0 passed, 0 with a model,
AED 0; `learning_dev_mgr` 3 practice attempts, 0 passed, 0 with a model, AED 0. `agent_training_case`
holds 17,890 cases (families: case 7,026; category_case 4,816; role_adversarial 2,304; role_tool 1,152;
role_uncertainty 1,152; role_cross_department 768; department_management 672) and has **no `agent_key`
column** — cases bind by `scope_type`/`scope_key` (role 9,600; category 4,816; department 3,432;
company 42). The cases are a usable deterministic asset; the runner around them is not.

---

## `ops_director` — Chief Operating Officer

Responsibilities on file: "Owns process, quality and delivery across the company." He is also
`decision_policy.apex_backup` — the deputy-apex that catches an escalation that cannot resolve up the
line.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| OD-01 | Does this workflow definition ship, or go back? | gate | per new/changed `workflow` row | `product_eng`, any dept head | A broken `rfq_handling` step strands a paying customer between reveal and supplier contact |
| OD-02 | Which of the 61 failed `workflow_run` rows is one cause and which are 61? | diagnosis | weekly | `culture_performance_mgr`, CEO | Chasing 61 symptoms instead of one root; the 4.08 % stays at risk for another month |
| OD-03 | Is this department over its `dispatch_max_open_per_dept` (250) because of demand or because of a stuck step? | diagnosis | per back-pressure event | dispatcher | Raising the ceiling hides a stuck consumer; the queue silently grows |
| OD-04 | Should this `org_task` be assigned, blocked, cancelled or split? | allocation | ~150 people_ops tasks to date, hourly sweep | `fn_event_dispatch` | A cancelled task that mattered disappears with no owner |
| OD-05 | Which seat is the binding constraint on this quarter's throughput? | diagnosis | monthly | CEO, founder | Hiring or training the wrong seat; the queue does not move |
| OD-06 | Does this incident get a `qa_gate` hold on deploys, or not? | gate | per `incident_response` run | `product_eng`, `security` | Holding on a false alarm freezes delivery; not holding ships the fault again |
| OD-07 | Is `failed_workflows` at 4.08 % a process defect or an instrument defect? | diagnosis | monthly | founder via `goal_period` | Rewriting healthy workflows because the denominator counts cancelled runs wrongly |
| OD-08 | Which SOP is missing for a process we actually run? | diagnosis | quarterly | `learning_dev_mgr` | `sop_coverage` stays unmeasurable; a process runs on nobody's written rule |
| OD-09 | Should this `action_class` move from `supervised` to `autonomous`? | escalation | per authority review | `culture_performance_mgr` | Autonomy granted above competence; an irreversible action with no reviewer |
| OD-10 | Does this escalation stop here (apex_backup) or go to the CEO? | escalation | per unresolved escalation | any seat | An escalation to the founder that is not a refund breaks his standing boundary |
| OD-11 | Is this handoff stalled, or just slow? | diagnosis | 6-hourly (`handoff_watchdog_6h`) | `phase_d_handoff_contract` owners | A stalled RFQ handoff loses the 3 % reveal on that job |
| OD-12 | Which department's decision rules conflict with another's? | diagnosis | weekly (`decision_conflict_scan_weekly`) | `legal`, CEO | Two seats give a supplier opposite answers on the same day |
| OD-13 | Does this capability exam get scheduled now or after knowledge is filled? | sequencing | per employee | `learning_dev_mgr` | Sitting an exam against unbound knowledge produces a fail that measures the binder, not the employee |
| OD-14 | Should this cron be enabled, and at what schedule? | allocation | per new automation | `product_eng` | An hourly job on a company with 0 inquiries burns budget and noise |
| OD-15 | Is this a repeat failure that needs a remediation record, or a one-off? | diagnosis | per `process.repeated_failure` event | `agent_remediation` | The same failure recurs monthly with no owner |
| OD-16 | Which of two competing improvements gets the next slot? | allocation | weekly | `improvement_lifecycle` owners | The improvement that would have unblocked revenue waits behind cosmetics |
| OD-17 | Does this quality gate pass before ship? | gate | weekly (his own KPI, target 95 %) | `product_eng` | Shipping past the gate; his measured 100 % becomes a fiction |
| OD-18 | Is this seat's `max_open_tasks` (50) the right ceiling? | allocation | quarterly | `recruitment_specialist` | A seat throttled below its capacity, or drowned above it |
| OD-19 | Should a workflow step be automated, or does it need a human-role actor? | craft | per step design | `product_eng` | `workflow_automation` gamed by relabelling a gate rather than removing it |
| OD-20 | Which run failed because of a provider, and which because of us? | diagnosis | daily | `it_operations` | Blaming Stripe for our own null; the real fault ships again |
| OD-21 | Does this cross-department dispute resolve on decision rights, or escalate? | escalation | weekly | any two dept heads | Deadlock; the RFQ ages past the supplier's 24-hour response target |
| OD-22 | Is this `org_task` a duplicate of one closed inside `event_recur_cooldown_days` (7)? | gate | per event | `fn_event_dispatch` | Task spam; the real signal is buried |
| OD-23 | What is the current delivery lead time from RFQ to reveal? | forecast | monthly | CEO, founder | A promise to a customer the process cannot keep |
| OD-24 | Which step in `employee_task` (17 steps) is the slowest, and is it the one that matters? | diagnosis | monthly | `culture_performance_mgr` | Optimising step 3 while step 11 holds the queue |
| OD-25 | Does this deploy need a change window, or can it go now? | gate | per `change_deployment` run | `product_eng` | A deploy during the only hour a supplier is answering |
| OD-26 | Should this failing seat be deactivated, retrained, or left? | escalation | monthly | `culture_performance_mgr`, `recruitment_specialist` | Deactivating a seat whose failures were an unbound knowledge layer |
| OD-27 | Is the company's autonomous decision rate real, or is it counting acks? | diagnosis | monthly | CEO | A 90 % autonomy claim built on `auto_done` dismissals |
| OD-28 | Which workflow has steps nobody owns? | diagnosis | quarterly | `org_designer` (inactive) | A step that runs as nobody; the audit trail has a hole |
| OD-29 | Does this exception belong to people_ops or to the department that raised it? | allocation | per exception | `exception_handling` module | Exceptions pile in the wrong lane and age out |
| OD-30 | Is this KPI missing because the seat failed or because the measure is broken? | diagnosis | weekly (`kpi_review_weekly`) | every seat | Punishing a seat for a broken `measure_sql` |
| OD-31 | Should a new department be created, merged or retired? | allocation | quarterly | CEO | Ten departments where six would do; coordination cost with no revenue |
| OD-32 | What is this quarter's realistic throughput ceiling given 54 seats? | forecast | quarterly | founder | A revenue plan the org cannot physically serve |
| OD-33 | Does this supplier-side operational failure need a process change or a supplier action? | diagnosis | per `supplier_risk_*` action | `supply` | Changing our process to work around one bad supplier |
| OD-34 | Is this improvement worth its `workflow_reflection_steps_per_day` budget (2,000)? | allocation | weekly | `finance` | Reflection spend with 0 inquiries — the exact failure of 6 Aug 2026 |
| OD-35 | Which of the 11 seats missing `employee_knowledge` gets bound first? | sequencing | until 100 % | `learning_dev_mgr` | The binding KPI stays at 79.63 % and three seats keep missing |
| OD-36 | Does this scenario test count as evidence of readiness? | gate | per `scenario_test` record | `assurance` (inactive) | Readiness claimed on a fixture, not on production |
| OD-37 | Should this decision be recorded in `decision_trace`, and at what tier? | gate | per consequential decision | audit | An execution with no decision trace; `v_executions_without_decision_trace` grows |
| OD-38 | Is the org shape still fitted to the work? | allocation | quarterly | CEO | 5 inactive seats carrying live KPI rows — exactly what `ops_director` carries today |
| OD-39 | Which failure class repeats across departments (one number, three causes)? | diagnosis | monthly | CEO | One headline hiding three unrelated defects |
| OD-40 | Does this month's operating cost move need a process change? | forecast | monthly | `finance` | Cutting the automation that was paying for itself |

### 2. Domain logic (the models this seat reasons with)

**M-OD-1 — Workflow failure decomposition.**
`failure_rate(w) = 100 * failed(w) / nullif(failed(w)+done(w), 0)`, per `workflow_key`, per calendar
month, from `workflow_run` and `workflow_step_run`. Inputs: `workflow_run.status`, `workflow_run.workflow_key`,
`workflow_step_run.status`, `workflow_step_run.step_id → workflow_step`. Output: a ranked table of
(workflow, step, failure_rate, n) plus the company aggregate that `company_goals.failed_workflows`
measures. **Group per workflow and per step, never in aggregate** — the company number 4.08 % is one
number over 20 workflow definitions. **UNMEASURED:** `workflow_run` carries no failure *reason* column, so
the split between "provider fault", "our defect" and "input missing" is not derivable from this table; it
would need a `failure_class` on the run, which does not exist.

**M-OD-2 — Binding-constraint model.** `fn_binding_constraint(p_days integer)` already exists in
production. Its job: for a window, rank departments/seats by `queued + ready` step runs divided by
`done` step runs, i.e. arrival over service. Output: the one seat whose service rate caps the pipe.
**UNMEASURED:** with 0 inquiries there is no demand-driven arrival stream, so today the model ranks
reflection load only; it cannot be validated until inquiries exist.

**M-OD-3 — Queue health / back-pressure.** `open_ratio(dept) = open_tasks(dept) /
decision_policy.dispatch_max_open_per_dept (250)`. Inputs: `org_tasks` grouped by `dept_key, status`.
Output: per-department pressure and the age of the oldest non-done task. Measured now: people_ops has
19 assigned, 1 blocked, 43 cancelled, 87 done — `open_ratio = 0.08`. No department is at ceiling.

**M-OD-4 — Delivery lead time.** `lead_time(run) = finished_at - started_at` per `workflow_run`,
percentiled (p50/p90) per `workflow_key`. Inputs: `workflow_run`. **UNMEASURED for the money path:**
`rfq_handling` has 18 steps defined but the marketplace has 0 inquiries, so p50 RFQ→reveal lead time
**does not exist**; any number quoted for it today would be invented.

**M-OD-5 — Automation share.** Exactly the goal's own SQL, kept honest:
`100 * count(steps where gate is not 'founder' and the actor resolves to an org agent) / count(steps)`
over `workflow_step`. Measured 98.93 %. **The known way to game it** is to relabel a step's `actor_role`
rather than remove the manual gate; the seat therefore also tracks the raw count of founder-gated steps
(measured: 2, both in `refund`) and refuses to report a rise in the ratio that comes with no fall in the
gate count.

**M-OD-6 — Repeat-failure detector.** For a (title, dept_key) pair in `org_tasks`, count occurrences in
90 days; ≥3 makes it a repeat and mints an `agent_remediation` row. Inputs: `org_tasks`,
`agent_remediation` (32 rows today). Measured examples in this department: "test.failed on scheduled_run
kb_deepen" ×4, "…kb_embed" ×3, "…uptime" ×3, "…day_conductor" ×3.

**M-OD-7 — Decision-trace completeness.** `100 * executions_with_trace / executions`, from `decision_trace`
(1,659 rows) against `v_executions_without_decision_trace`. Output: the audit hole size.

**M-OD-8 — Capacity model for the seat itself.** `capacity(seat) = max_open_tasks (50) * turns_per_day`.
**UNMEASURED:** `turns_per_day` per seat does not exist as a stored figure; `agent_runs` records 36 ok /
7 error / 2 skipped runs for `ops_director` in total since 2026-07-26, which is a run log and not a
work-unit log (see MEMORY: `agent_runs` is a cron log, not an employee log).

### 3. Reasoning procedures

**OD-02 — "is this 61 failures or one?"**
1. Pull `workflow_run` where `status='failed'` in the window; join to `workflow_step_run` where
   `status='failed'` to get the failing step.
2. Group by (`workflow_key`, `step_id`). Sort by count desc.
3. If the top group holds ≥ 60 % of failures → verdict "one cause", name the step, open one
   `org_tasks` row against the step's owning department.
4. Else group by the day and by the hour: a spike confined to one hour is an incident, not a defect —
   cross-check `incident_watchdog_hourly` output for the same window.
5. If neither concentration holds, refuse to name a cause: emit "61 failures across N steps, no group
   above 60 %, need `failure_class` on `workflow_run` which does not exist" and open the instrument task.

**OD-07 — "process defect or instrument defect?"**
1. Recompute the goal's own `measure_sql` verbatim. Compare to `goal_period.actual_value` (4.08).
2. If they differ → instrument drift; the fault is the measure, not the process. Stop.
3. If they agree, test the denominator: count runs in `cancelled` and `running`. Measured: 84 cancelled,
   103 running, neither counted. A cancelled run that was cancelled *because it was failing* is a
   miscounted failure. **UNMEASURED:** `workflow_run` carries no cancellation reason, so this test cannot
   complete — the seat reports "cannot separate cancelled-because-failing from cancelled-by-design; the
   4.08 % is a floor, not a point estimate" rather than declaring the process healthy.

**OD-09 — "supervised → autonomous?"**
1. Gather: the `action_class`'s current `phase_c_action_class` row; the candidate seat's
   `agent_reputation` (score, tier, and the **evidence count** per dimension); its
   `certification_exam_result` history; its `employee_authority` row.
2. Hard gate: `decision_quality` evidence count must be ≥ 20 **and** the dimension score ≥ 70. Measured:
   `ops_director` has 21 evidence at 13.5 → **fails**; the other three have 0 evidence → **fails**.
3. Hard gate: the seat must hold a *passed* certification covering the class. Measured: 0 passes exist
   anywhere → every promotion to autonomous currently fails this gate.
4. Hard gate: the action must be reversible (`irreversible=false`) or already carry a founder gate.
5. All gates pass → grant, write `decision_record`. Any gate fails → refuse and name the failing gate.

**OD-10 — "does this escalation stop at apex_backup?"**
1. Read `decision_policy.founder_review_gates`. Measured: `["refund_decision","refund_outside_policy"]`.
2. If the escalation's `action_class` is in that list → route to the founder through
   `founder_mail_policy`, and only then.
3. Else read `decision_policy.action_autonomy` for the kind. `ack` → the sweep clears it. A role_id →
   hold with that role.
4. Else if the originating chain has already reached the CEO unresolved → `ops_director` decides, records
   in `decision_record`, and notifies. **Never** the founder.

**OD-13 — "exam now or knowledge first?"**
1. Read the candidate's `employee_knowledge` layer coverage against `employee_knowledge_standard`
   (12 required layers).
2. If any required layer has 0 rows → refuse to schedule. Measured: **all four people_ops seats fail
   this**, missing layers 3, 6, 7, 9, 10, 11, 12. Emit "knowledge first", open the binding task on
   `learning_dev_mgr`.
3. If layers are complete, check `agent_knowledge` module count ≥ 14. Measured: all four below.
4. Only with both satisfied, call `fn_certification_exam_sit(agent, certification)`.
5. Record which gate blocked, so a fail is never mistaken for incapacity when it was non-binding.

**OD-17 — "does this pass the quality gate?"**
1. Read `qa_results` for the 7-day window; the seat's KPI measures exactly
   `100 * passed / (passed+failed)` against a 95 % target (measured 100 %).
2. If the window holds **zero rows**, the answer is not 100 % — it is "no evidence". A zero-denominator
   pass rate is the classic dead-guard reading and the seat must report it as such.
3. Otherwise report the rate, name the failing suites, and hold ship on any suite tagged money, security
   or legal regardless of the aggregate.

**OD-35 — "which unbound seat first?"**
1. List the 11 active seats with no `employee_knowledge` row (measured: `channel_specialist`,
   `bi_analyst`, `billing_specialist`, `payments_manager`, `moderation_specialist`, `trust_safety_mgr`,
   `doc_intel_manager`, `inquiry_router`, `red_view_alerter`, `supplier_coverage`, `supplier_retention`).
2. Score each by revenue proximity: does the seat own a step in `rfq_handling`, `payment`,
   `supplier_onboarding` or `lead_to_customer`? Those first.
3. Tie-break on `agent_reputation` evidence count (fewest evidence = least observed = highest risk).
4. Emit an ordered list with the binding SQL for each; **do not** bind more than the daily quota the
   knowledge lane can validate.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| OD-J1 | A pass-rate denominator is 0 | report "no evidence", never 100 % | Zero cannot tell a dead guard from an idle system |
| OD-J2 | A headline improves with no change in the underlying count | reject the improvement | Automation share rose while founder gates stayed at 2 = relabelling |
| OD-J3 | `action_class` is irreversible and the seat's `decision_quality` evidence < 20 | refuse autonomy | An irreversible action decided on a prior, not a measurement |
| OD-J4 | An escalation is not `refund_decision`/`refund_outside_policy` | never route to the founder | Founder ruling 17 Aug 2026, restated 5 Sep 2026 |
| OD-J5 | A fix makes the headline number fall | ship it anyway and say so | Never weaken a check to keep a number green |
| OD-J6 | A cron would run hourly while the marketplace has 0 inquiries | refuse; schedule daily or demand-linked | 6 Aug 2026: a reflection queue took the AI bill from ~1 to 11–15 AED/day with zero customers |
| OD-J7 | A seat fails an exam while any required knowledge layer is empty | verdict is "not measurable", not "incapable" | The instrument was measuring the binder |
| OD-J8 | Two departments' decision rules give opposite answers | freeze both, resolve on decision rights, then unfreeze | A supplier told two things in one day is a trust loss we cannot buy back |
| OD-J9 | A task title repeats ≥ 3 times in 90 days | mint a remediation record, do not re-close | Re-closing is documenting, not performing |
| OD-J10 | A department is above `dispatch_max_open_per_dept` | investigate the consumer before raising the ceiling | Raising the ceiling hides a stuck step |
| OD-J11 | An improvement scores well but sits off the revenue path while revenue is 0 | defer it | Reflection spend against no demand is the measured failure mode |
| OD-J12 | A deploy touches money, auth or the refund ladder | require the quality gate green **and** a named rollback | The refund ladder is the founder's own ruling of 6 Sep 2026 |
| OD-J13 | An inactive seat still carries a live KPI row | fix the org, not the KPI | `ops_director` carries `hr_director`'s KPI today — the org is stale, the number is not wrong |
| OD-J14 | A metric has `no_measure_reason` set | never report a value for it | `sop_coverage` has no instrument; a number would be invented |
| OD-J15 | A supplier-side failure suggests a process change | change the supplier relationship first | `matching_strike_limit` is 3 for exactly this reason |

### 5. Technical knowledge

The workflow engine: `workflow`, `workflow_run`, `workflow_step`, `workflow_step_run`, and the sweeps
`workflow_start_due` (195), `workflow_step_sweep_10min` (247), `workflow_dispatch_10min` (255). The task
bus: `org_tasks` (columns `dept_key, objective_id, status, tier, needs_founder, action_class, attempts,
root_cause, assigned_agent, priority`), `fn_event_dispatch`, `org_task_assign_hourly` (262),
`org_task_sla_watch_daily` (286). The kernel cron wrapper `fn_kernel_cron_exec(jobid)` and
`fn_kernel_wrap_and_enable_cron`. The handoff contracts `phase_d_handoff_contract` (159 rows),
`handoff_watchdog_6h` (289), `v_handoff_stalled`, `v_handoff_without_contract`. The decision spine
`decision_trace` (1,659), `decision_log` (935), `decision_record` (12), `decision_policy` (39 keys, listed
above). The escalation spine `v_internal_escalation_queue`, `agent_remediation`,
`remediation_escalate_consume_daily` (281). Objectives: `os_objective` (50 rows, each with its own
`measure_sql` and `actual_value`), `department_objective` (96), `goal_period`,
`os_objective_measure_daily` (194), `dept_objective_measure_daily` (249).

**What must be stored so he can act without asking:** the current `decision_policy` snapshot; the
`founder_review_gates` list; the per-workflow failure and lead-time tables; the list of steps with no
resolvable actor; the repeat-failure register; the department queue ratios; the authority matrix
(`employee_authority` + `phase_c_action_class`). All of these are tables or one SQL statement away today.

### 6. Academic knowledge

Certifications on file for this seat: **PMP** (PMI, pass mark 61, areas People / Process / Business
Environment / Predictive Plan-Based Methodologies / Agile and Hybrid Approaches) and **CSSBB** (ASQ, pass
mark 73, 8 areas named on the row). **Syllabus areas failed: does not exist** — this seat has never sat an
exam. Two PMP labels and one CSSBB label on the row have no questions behind them (see the department
table above); that is a data defect to fix before the first sitting, not a knowledge gap.

Disciplines that generalise, each with a lawful primary source we may ingest:

- **Queueing theory and Little's Law** (`L = λW`) — the arithmetic behind OD-03, OD-05, OD-23, OD-32.
  Source: NIST/SEMATECH *e-Handbook of Statistical Methods* (US Department of Commerce, public domain).
- **Statistical process control** — control limits, run rules, special vs common cause; the discipline
  behind OD-02 and OD-39. Source: the same NIST e-Handbook, chapter 6.
- **Process quality management systems** — ISO 9001:2015 clause structure (context, leadership, planning,
  support, operation, performance evaluation, improvement). Source: the ISO Online Browsing Platform's
  freely published preview and the ISO/TC 176 public guidance documents.
- **IT service management** — incident, problem, change and request practices. Source: the ITIL 4
  practice names as published by PeopleCert/AXELOS's public glossary, plus **ISO/IEC 20000-1** clause
  headings from the ISO OBP preview.
- **Risk management vocabulary** — ISO 31000:2018 principles and framework, ISO OBP preview.
- **Reliability and incident practice** — Google's *Site Reliability Engineering* books, published free
  online by the authors under a licence permitting reading and citation; and NIST SP 800-61r2
  *Computer Security Incident Handling Guide* (public domain).
- **Measurement and instrument validity** — the "construct validity" literature summarised in the
  **OECD Handbook on Constructing Composite Indicators** (OECD/JRC, freely published).
- **UAE operating context** — Federal Decree-Law No. 33 of 2021 on the Regulation of Labour Relations and
  its Executive Regulations, from the UAE Ministry of Human Resources and Emiratisation and the official
  UAE Legislation portal; Dubai DET licensing rules from the DET portal. (The company holds DET licence
  1633275, expiring 24 Jun 2027, and is below the AED 375,000 VAT threshold.)

Never ingest a copyrighted exam study text (PMBOK, the ASQ handbook, SHRM's Learning System). The bank we
already own — 40 PMP and 40 CSSBB questions — is the exam-side asset.

### 7. Corporate knowledge

He must hold, and today mostly does not: the founder's hard rules (`fn_company_hard_rules()`, rendered
into every head by `fn_agent_context`); the refund ladder as ruled on 6 Sep 2026 — 3 % reveal refunded,
AED 250 supplier admin fee, 9 % **per annum** interest, chase at 3 working days, founder's final call on
day 5, banks 7–14 working days (lives in `decision_policy.refund_policy_founder_decision_2026_09_06` and
`pricing_config`); that the **only** founder approval is a refund; that the company holds DET licence
1633275 and is not VAT-registered until the AED 375,000 threshold (lives in `company_registration`,
rendered as `qd-company:*` records by `fn_company_self_knowledge_sync()` every 15 minutes, cron 292);
pricing (`pricing_config`); the ten decision rules for HR & People Operations in `ops_knowledge`; the
escalation matrix and department decision rights YAMLs in `ops_knowledge.decision_rules`; the AI
constitution (`ai_constitution`, `company_constitution`); institutional memory (`institutional_memory`,
1,973 rows) and org memory (`org_memory`, 968).

He hands to: `learning_dev_mgr` (knowledge binding and exams), `culture_performance_mgr` (performance
verdicts and calibration), `recruitment_specialist` (role definition), `product_eng` (workflow and cron
changes), `legal` (anything on the `legal_triggers` list), `finance` (anything at or above
`financial_review_aed` = AED 10,000).

**History he must not forget:** the 6 Aug 2026 reflection-spend incident; the 14 Aug 2026 measurement
correction that moved reflection cost from AED 0.086 to AED 0.146 per step; the 2 Sep 2026 lifting of all
phase freezes; the retirement of mirror gates (production proves properties; never emit a CSV to green a
check). **Layer 9 (Experience) holds zero rows for this seat**, so none of that history is bound to him
today — it lives in `decision_policy` descriptions and in `institutional_memory`, which he does not read.

### 8. One-year plan

**Objective.** Make the company's delivery machine able to carry paid RFQ traffic without a human in the
loop, and make its own numbers honest.

**His slice of AED 1,000,000: AED 0 direct.** This seat books no revenue. The reveal fee is 3 % of quote
value, so AED 1,000,000 of reveal revenue requires **AED 33,333,333 of revealed quote value** across the
year. The average quote value on this marketplace **does not exist** (0 quotes), so the number of RFQs
behind that figure cannot be computed today without inventing it. What can be stated: `rfq_handling` has
18 defined steps and 0 runs to date; every one of those RFQs passes through workflows this seat owns, and
at the measured 3.94 % run-failure rate roughly 1 job in 25 would fail somewhere in the pipe.
**His accountable slice is therefore: the failure rate that revenue passes through, not the revenue.**

**The two metrics he owns** (both already instrumented): `failed_workflows` ≤ 0.5 % (measured 4.08 %,
at_risk) and `workflow_automation` ≥ 98 % (measured 98.93 %, on_track). The third, `sop_coverage`, he
cannot own until an instrument exists.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** Add a `failure_class` column to `workflow_run` so OD-01/02/07/20 can complete —
  without it the 4.08 % cannot be decomposed and every remedy is a guess. Build the `sop_coverage`
  instrument: a `process_catalogue` table joined to the 10 `sop` records in `ops_knowledge`, so the goal
  stops reading null. Fix the 16 orphan syllabus labels. Target: `failed_workflows` ≤ 2.0 %.
- **Q2 (Dec 2026–Feb 2027).** Drive `failed_workflows` to ≤ 0.5 % on a decomposed, per-workflow basis.
  Bind layers 3, 6, 7, 9, 10, 11 and 12 for the four people_ops seats (§3 of `learning_dev_mgr`), then sit
  PMP and CSSBB. Target: both exams sat with a recorded score, whatever it is.
- **Q3 (Mar–May 2027).** `rfq_handling` p50 lead time measured on real traffic and held under the 24-hour
  supplier-response target in `company_goals.supplier_response_time`. Autonomy promotions decided on
  measured `decision_quality`, which requires ≥ 20 evidence rows per candidate.
- **Q4 (Jun–Aug 2027).** Sustain both owned metrics for three consecutive months; retire the 5 inactive
  seats' live KPI rows so no active seat carries a dead seat's target.

**Capacity check.** Honest answer: **this seat's work cannot produce revenue, and its current capacity is
unmeasured.** `agent_runs` shows 36 successful runs since 26 July 2026 — a cron log, not a work log; there
is no stored figure for tasks completed per day per seat. `max_open_tasks` is 50 and the department's open
ratio is 0.08, so nothing is queue-bound today. The binding constraint on AED 1,000,000 is not this seat:
it is 1 approved supplier and 0 inquiries.

**Dependencies.** `product_eng` (schema change for `failure_class`, cron enablement),
`learning_dev_mgr` (knowledge binding before any exam), `supply` and `growth` (supplier and demand — the
actual revenue constraint), `finance` (the AED 1,000,000 goal is theirs; this seat only protects the pipe).

### 9. What this seat cannot do without a model

1. **Reading a free-text failure note and classifying its cause.** Deterministically we can count and
   group; assigning "provider fault" vs "our defect" from a prose `note` needs either a model or a
   `failure_class` column written at the point of failure. **The column is the right answer** — it is
   cheaper, auditable and available offline. Nothing here requires a model.
2. **Writing a new SOP from scratch for a process nobody has documented.** Deterministically the seat can
   *detect* the missing SOP (a process with runs and no `sop` record) and open the task; composing the
   prose is either a human/founder act or a template fill from the workflow's own step list. A
   step-list-driven template is sufficient and is what this plan specifies.
3. Nothing else. Every one of OD-01 … OD-40 resolves on tables, thresholds and arithmetic.

---

## `culture_performance_mgr` — Culture & Performance Manager

Responsibilities on file: "Owns adherence to the AI constitution and company values; runs performance
review." In a company of AI employees, this is the seat that **calibrates judgement** — that decides
whether a seat's verdicts are trustworthy, and whether a low score means low capability or a broken
instrument.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| CP-01 | Is this employee's KPI miss a capability problem or an instrument problem? | diagnosis | weekly, 127 KPI rows | every seat, `ops_director` | Retraining a seat whose `measure_sql` was wrong; the real defect survives |
| CP-02 | Does this seat's `agent_reputation` score reflect evidence or the 50.0 prior? | diagnosis | weekly (`reputation_weekly`) | `ops_director`, CEO | Promoting on a prior; three seats here sit at 50.0 on zero evidence |
| CP-03 | Is this employee ready for a performance verdict at all? | gate | monthly per seat | `ops_director` | A verdict on a seat with no bound knowledge measures the binder |
| CP-04 | Does this decision violate the AI constitution? | gate | per consequential decision | any seat | A constitution that is never enforced is decoration |
| CP-05 | Two seats scored the same case differently — which is calibrated? | diagnosis | per disagreement | `ops_director` | Both keep deciding; suppliers and customers get inconsistent answers |
| CP-06 | Should this employee's improvement plan change? | craft | daily (`improvement_plan_daily`) | the employee | 54 of 54 carry a plan; a stale plan is worse than none |
| CP-07 | Is this seat over- or under-confident relative to its outcomes? | diagnosis | monthly | `ops_director` | Over-confidence at `confidence_min` 0.6 means it acts where it should ask |
| CP-08 | Does a failed exam justify a performance downgrade? | gate | per exam result | `learning_dev_mgr` | 0 of 5 sittings passed company-wide; downgrading everyone would be measuring the exam |
| CP-09 | Which values violation is material and which is noise? | diagnosis | weekly | `legal`, `ops_director` | Alert fatigue; the material one is dismissed with the 1,012 dismissed security alerts |
| CP-10 | Is this seat's `correctness` measured on enough cases to act on? | gate | per promotion/demotion | `recruitment_specialist` | A 93.9 % on 36 cases is not the same claim as 98.1 % on 127 |
| CP-11 | Should this seat be promoted a tier? | escalation | weekly (`promotion_review_weekly`) | the seat, `ops_director` | Authority above competence |
| CP-12 | Should this seat be demoted or deactivated? | escalation | monthly | `ops_director` | Deactivating a seat whose failures were unbound knowledge |
| CP-13 | Is this department's KPI attainment falling for one reason or several? | diagnosis | monthly | CEO | One number, three causes |
| CP-14 | Does this outcome record grade the decision or the luck? | diagnosis | daily (`outcome_evaluate_daily`) | `ops_director` | Rewarding a bad decision that happened to work |
| CP-15 | Which calibration case should be added to the bank this month? | craft | monthly | `learning_dev_mgr` | A bank that never sees the cases we actually get wrong |
| CP-16 | Is the company's autonomy rate a measure of capability or of `auto_done` sweeps? | diagnosis | monthly | CEO, founder | 355 `incident/auto_done` rows are a sweep, not a judgement |
| CP-17 | Does this handoff show a collaboration failure? | diagnosis | 6-hourly | `ops_director` | A stalled handoff read as one seat's slowness |
| CP-18 | Is a seat's `cost_efficiency` low because it is wasteful or because it does expensive work? | diagnosis | monthly | `finance` | Cutting the seat that does the only expensive-but-necessary work (`ops_director`: 23.3) |
| CP-19 | Should this KPI be retired or replaced? | craft | quarterly | `ops_director` | A KPI nobody can move stays red forever and teaches nothing |
| CP-20 | Is this improvement plan text actually actionable? | craft | monthly | the employee | The current plans are generated strings; an unactionable plan is a compliance tick |
| CP-21 | Which seat's judgement should be trusted on a tie? | allocation | per tie | `ops_director` | The louder seat wins instead of the calibrated one |
| CP-22 | Does this seat need supervision reinstated? | escalation | per incident | `ops_director` | An autonomous seat repeating a fault |
| CP-23 | Is a values rule being applied consistently across departments? | diagnosis | quarterly | `legal` | Selective enforcement destroys the constitution's authority |
| CP-24 | Does this decision need a `decision_trace` row it does not have? | gate | daily | audit | An execution nobody can reconstruct |
| CP-25 | Which of this quarter's KPI misses were structural (target above capability)? | diagnosis | quarterly | CEO, founder | Punishing seats for a target the company set impossibly |
| CP-26 | Should the confidence floor move from 0.6? | craft | quarterly | `ops_director` | Too high and everything escalates; too low and it acts blind |
| CP-27 | Is a seat's silence a fault or an idle system? | diagnosis | 6-hourly (`agent_silence_watch`) | `ops_director` | Zero cannot tell a dead guard from an idle system |
| CP-28 | Does this seat's peer feedback (`collaboration`) have any evidence? | gate | monthly | `recruitment_specialist` | Three seats here have 0 collaboration evidence and a 50.0 score |
| CP-29 | Which lesson from `institutional_memory` should be promoted to a rule? | craft | weekly | `learning_dev_mgr` | Lessons stay as prose nobody reads; the mistake repeats |
| CP-30 | Is the performance review itself calibrated against outcomes? | diagnosis | quarterly | founder | A review process that predicts nothing |
| CP-31 | Does this seat's improvement plan cite a root cause that is real? | gate | monthly | `ops_director` | The plans currently cite "target above current capability: attainment 73.3 %" for four different seats |
| CP-32 | Should a seat's `max_open_tasks` be cut on a quality signal? | allocation | monthly | `ops_director` | Throughput protected at the cost of correctness |

### 2. Domain logic

**M-CP-1 — Posterior reputation, with evidence gating.** The estate already computes
`agent_reputation` as a posterior against a prior of 50 with `prior_weight = 5`. The model this seat adds
is the **evidence gate**: a dimension with `evidence.<dimension> = 0` is *not a score*, and any decision
that reads it must refuse. Inputs: `agent_reputation.evidence` (jsonb, carries per-dimension counts),
`agent_reputation.<dimension>`. Measured: 4 of 6 dimensions carry 0 evidence for
`culture_performance_mgr`, `learning_dev_mgr` and `recruitment_specialist`; `ops_director` carries
evidence on 5 of 6 but `learning_speed` is 0 for all four.

**M-CP-2 — KPI attainment and verdict.** `attainment = 100 * actual_value / target_value` for
`direction='at_least'` goals (inverted for `at_most`); `verdict = MET | MISSED` at 100. Inputs:
`employee_kpi`, `employee_kpi_history` (1,332 rows). Measured for this department: 7 KPI rows, 3 MET.
The three MISSED rows are the *same underlying measure* — 79.63 % binding — carried by three seats.
**A model that treats them as three independent misses is wrong**; the department has one defect, not
three.

**M-CP-3 — Instrument-validity test.** Before any KPI verdict is acted on:
`re-run measure_sql now → compare to employee_kpi.actual_value`; then test the denominator for zero; then
test whether the measure references a table with zero rows in the window. Output: `{valid, drifted,
no_evidence, denominator_zero}`. A verdict is only issued on `valid`.

**M-CP-4 — Structural-miss classifier (deterministic bands).** Already present in the improvement-plan
text: attainment ≥ 90 → "near-miss performance"; 60–90 → "target above current capability"; < 60 →
"structural or instrument". Inputs: `employee_kpi_history.attainment`. Measured: 79.6 % attainment on the
binding KPI for three seats → band "target above current capability".

**M-CP-5 — Calibration score.** For a seat that issues verdicts, compare its verdict to the eventual
outcome: `calibration = 100 * agreements / decisions_with_outcome`. Inputs: `decision_trace`,
`outcome_evaluate_daily`'s outcome records. **UNMEASURED:** the count of decisions with a recorded outcome
per seat is not exposed as a per-seat table today; `agent_evals` holds 49 snapshot rows with a `kpis`
jsonb, not per-decision outcomes. **A per-seat calibration figure does not exist.**

**M-CP-6 — Consistency across departments.** For a rule (e.g. a `legal_trigger`), count enforcement
events per department per 1,000 decisions; flag any department more than 2× off the median. Inputs:
`agent_actions` (kind, status), `org_tasks`. Measured distribution of dispositions: `security_alert`
dismissed 1,012; `incident` auto_done 355; `handoff` done 187; `licence_expiring` auto_done 150. The
1,012 dismissals are the single largest disposition in the estate and are the first thing this model
must examine.

**M-CP-7 — Values/constitution adherence.** A decision is checked against the constitution clauses in
`ai_constitution` / `company_constitution` by lexeme match on the clause's own trigger terms, exactly as
the exam scorer works (`ts_rank_cd` over the decision's stated reason, `word_similarity` tiebreak). Output:
`{clause_id, support_score, verdict}` with the same abstention thresholds (0.25 support, 0.15 relative
margin) — below them the answer is "cannot tell", never "compliant".

### 3. Reasoning procedures

**CP-01 — "capability or instrument?"**
1. Run M-CP-3 on the KPI. If `drifted`, `no_evidence` or `denominator_zero` → verdict "instrument", open a
   task on the measure's owner, stop. No performance consequence.
2. If valid, run M-CP-4 to band the attainment.
3. If the same `metric` string is MISSED by ≥ 3 seats simultaneously → verdict "one company defect",
   name it once. Measured today: exactly this — "Employees with complete KPI, authority and knowledge
   binding" at 79.63 % is MISSED by `ops_director`, `culture_performance_mgr`, `learning_dev_mgr` and
   `recruitment_specialist`.
4. Only a valid, seat-specific, non-shared miss becomes a performance verdict.

**CP-02 — "score or prior?"**
1. Read `agent_reputation.evidence` for the seat.
2. Any dimension with count 0 → mark that dimension `NO EVIDENCE` in the memo; do not print the 50.0.
3. Compute a coverage figure: `dimensions_with_evidence / 6`. Measured: `ops_director` 5/6;
   the other three **2/6**.
4. If coverage < 4/6 the seat's aggregate `score` is not usable for promotion, demotion or trust routing.
   Report that plainly and name what evidence stream is missing.

**CP-03 — "ready for a verdict?"**
1. Gate 1: `employee_knowledge` covers all 12 required layers. Measured: fails for all four seats here.
2. Gate 2: `agent_knowledge` module count ≥ 14. Measured: fails for all four.
3. Gate 3: the KPI passed M-CP-3.
4. Gate 4: the seat has ≥ 20 evidence rows on the dimension being judged.
5. Any gate fails → "not ready for a verdict", with the failing gate named and the owning seat tasked.
   This is the honest posture for **every seat in people_ops today**.

**CP-05 — "which of two disagreeing seats is calibrated?"**
1. Pull both seats' `agent_reputation.correctness` **and its evidence count**.
2. If either has < 20 evidence → no calibrated answer; escalate to `ops_director` on decision rights
   rather than on reputation.
3. If both qualify, prefer the higher `correctness`; if within 5 points, prefer the seat whose
   `employee_authority` covers the action class; if still tied, escalate.
4. Record the tie-break used in `decision_record` so the rule is auditable.

**CP-08 — "does a failed exam justify a downgrade?"**
1. Read the result's `method` and the pass mark. Read the seat's knowledge-layer coverage at the time of
   sitting.
2. If any required layer was empty → the exam measured the binder. **No downgrade.** Open a binding task.
3. If layers were complete, read the per-area breakdown in `certification_knowledge_gap`; a fail
   concentrated in ≤ 2 areas is a knowledge gap (remediate); a fail spread evenly across ≥ 6 areas is a
   capability question (escalate to `recruitment_specialist` for a role review).
4. Measured today: 0 of 5 sittings passed and the failures are *broad* (`bookkeeper` holds 23 open gaps
   across 23 ACCA areas, 21 of them at 0 %). Under this procedure the correct verdict for that seat is
   "capability question", and the correct verdict for people_ops is "not yet measured".

**CP-14 — "decision or luck?"**
1. For an outcome record, retrieve the `decision_trace` row that produced it, and the evidence that was
   available *at decision time* (the trace's own inputs, not today's tables).
2. Score the decision against the judgement rules that applied then. A decision that followed the rules
   and produced a bad outcome is a **good decision, bad outcome** — record it as such and do not penalise.
3. A decision that broke a rule and produced a good outcome is a **rule violation** — record it and
   penalise; the next draw will not be so kind.
4. **UNMEASURED:** `decision_trace` does not store a frozen snapshot of the evidence available at the
   time, so step 1 is only partly reconstructible today. Say so in the memo rather than grading blind.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| CP-J1 | A reputation dimension has 0 evidence rows | never quote its score | 50.0 is the prior, and a prior is not a measurement |
| CP-J2 | ≥ 3 seats miss the same `metric` in the same cycle | one company defect, one owner | Three verdicts on one defect is three wrong verdicts |
| CP-J3 | A KPI's `measure_sql` re-run disagrees with its stored `actual_value` | instrument fault, no performance consequence | The instrument was measuring the wrong subject |
| CP-J4 | A seat failed an exam with an unbound knowledge layer | no downgrade | The exam measured the binder |
| CP-J5 | A promotion is proposed on coverage < 4/6 reputation dimensions | refuse | Authority granted on two observations |
| CP-J6 | A metric can only move by an action nobody owns | retire or reassign the metric | An unmovable red number teaches nothing and hides the real ones |
| CP-J7 | An `auto_done` disposition is counted as an autonomous decision | reject the count | A sweep clearing a queue is not judgement |
| CP-J8 | A values verdict scores below the abstention thresholds (0.25 / 0.15) | "cannot tell", never "compliant" | Same standard as the exam scorer; a guess is not a verdict |
| CP-J9 | A seat's silence coincides with zero inbound work | not a fault | Zero cannot tell a dead guard from an idle system |
| CP-J10 | A good outcome followed a broken rule | penalise the decision anyway | Rewarding luck teaches the wrong rule |
| CP-J11 | An improvement plan cites a root cause not derivable from a table | reject the plan | The current four plans all cite the same generated band |
| CP-J12 | A demotion would remove the only seat covering an action class | escalate to `ops_director` first | A correctness fix that opens a coverage hole |
| CP-J13 | Enforcement of a rule differs > 2× between departments | freeze enforcement, audit both | Selective enforcement voids the constitution |
| CP-J14 | The founder is the subject of a performance question | do not answer it | Not this seat's remit; the constitution governs employees |
| CP-J15 | A calibration figure is asked for and `decision_trace` lacks decision-time evidence | say it does not exist | Never state what you have not measured |

### 5. Technical knowledge

`agent_reputation` (columns `correctness, reliability, cost_efficiency, learning_speed, collaboration,
score, tier, decision_quality, evidence` — the `evidence` jsonb carries `prior`, `prior_weight`, `total`,
`method='posterior'`, `dimensions_with_evidence` and a per-dimension count) and `fn_reputation_recompute`,
`fn_reputation_hold_state`, cron 161. `employee_kpi` / `employee_kpi_history` (`attainment`, `verdict`,
`measured_on`) with `employee_kpi_measure_daily` (250) and `employee_kpi_assign_daily` (290);
`kpi_review_weekly` (140); `self_review_weekly` (139); `promotion_review_weekly` (282);
`fn_improvement_plan_refresh` + `improvement_plan_daily` (184); `fn_improvement_handover` +
`improvement_handover_hourly` (205). The constitution tables `ai_constitution`, `company_constitution`,
`v_constitution`; `ai_governance_review`, `governance_rule`, `governance_policy`. Decision spine:
`decision_trace`, `decision_log`, `decision_record`, `v_decision_intelligence`, `v_decision_matrix`,
`v_executions_without_decision_trace`. Outcome grading: `outcome_evaluate_daily` (143). Memory:
`institutional_memory` (1,973), `org_memory` (968), `agent_memory` (975), `memory_promotions` (60),
`v_memory_promotion_candidates`, `v_peer_lessons`. Full-text and trigram mechanics as used by the exam
scorer (`to_tsvector`, `ts_rank_cd(…, 32)`, `pg_trgm.word_similarity`) — this seat reuses the identical
scorer for constitution adherence so the two never disagree on method.

### 6. Academic knowledge

Certifications on file: **SHRM-SCP** (SHRM, pass mark 70; row names Leadership and Navigation, Business
Acumen, HR Expertise People/Organization/Workplace, Ethical Practice, Consultation — the three "HR
Expertise" labels have no questions behind them) and **CPTD** (ATD, pass mark 70; row names Instructional
Design, Training Delivery and Facilitation, Learning Technologies, Evaluating Impact, Talent Strategy and
Management, Performance Improvement, Coaching — "Learning Technologies" has no questions behind it; the
bank calls it "Technology Application"). **Syllabus areas failed: does not exist** — never sat.

Theory that generalises, with lawful primary sources:

- **Psychometrics and measurement validity** — reliability, construct validity, criterion validity.
  Source: the **Standards for Educational and Psychological Testing** overview material published openly
  by APA/AERA/NCME, and the **OECD Handbook on Constructing Composite Indicators**.
- **Calibration and scoring rules** — Brier score, proper scoring rules, reliability diagrams. Source:
  the **NIST/SEMATECH e-Handbook** and the **WMO** publicly published forecast-verification methods
  (WMO/WWRP verification guidance), which is the cleanest public treatment of calibration.
- **Bayesian updating with a prior** — exactly the posterior the estate already computes. Source:
  NIST e-Handbook chapter 6.6 (Bayesian reliability), public domain.
- **Signal detection and base rates** — why a 1,012-row dismissal pile is a base-rate problem. Source:
  NIST e-Handbook; **ISO 31000:2018** risk vocabulary (ISO OBP preview).
- **Goal setting and performance management theory** — objective decomposition, the perils of a single
  measure. Source: OECD public-sector performance-management publications (freely published), and
  the **GRI Standards** (freely downloadable) for how a public metric must be defined to be auditable.
- **Organisational justice and consistency of enforcement** — the fairness constraints that make a rule
  hold. Source: the **ILO** conventions and recommendations database (public), and the UAE
  Federal Decree-Law No. 33 of 2021 for the local floor.
- **Ethics for autonomous systems** — Source: **ISO/IEC 42001:2023** (AI management systems) clause
  headings from the ISO OBP preview, and **NIST AI Risk Management Framework 1.0** (public domain), which
  maps directly onto what this seat enforces.

### 7. Corporate knowledge

The AI constitution and company values (`ai_constitution`, `company_constitution`); the founder's hard
rules through `fn_company_hard_rules()`; the ruling that **only refunds** reach the founder; that phase
freezes were removed totally on 2 Sep 2026; that mirror gates are retired — production proves properties,
and a CSV is never emitted to green a check; the deterministic-band root-cause vocabulary already written
into the four improvement plans; the 12-layer knowledge standard; the authority matrix and its thresholds
(AED 0 / 1,000 / 10,000); `decision_policy.confidence_min` 0.6; `financial_review_aed` 10,000;
`auto_action_max_aed` **0** — agents never move money.

Hands to: `learning_dev_mgr` (a gap that is knowledge), `recruitment_specialist` (a gap that is the role),
`ops_director` (a gap that is the process, and every escalation), `legal` (anything on `legal_triggers`).

**History it must not forget:** that on 6 Sep 2026 an exam whose grader could not tell a differently
worded correct answer from a wrong one wrote 268 "corrections" into 79 employees' knowledge, and those
rows had to be quarantined. That is this seat's founding lesson about instruments.
**It is not bound today** — Layer 9 holds zero rows for this seat, and `institutional_memory` is not in
its head.

### 8. One-year plan

**Objective.** Make every performance number in the company either evidenced or explicitly marked
"no evidence", and make judgement calibration a measured quantity rather than a prior.

**Slice of AED 1,000,000: AED 0 direct.** This seat sells nothing. Its contribution is that the seats that
*do* touch the 3 % reveal fee — `inquiry_router`, `quote_evaluation`, the supply seats — are trusted on
evidence rather than on a 50.0 prior. Today four of those seats have no `employee_knowledge` at all
(`inquiry_router`, `doc_intel_manager`, `supplier_coverage`, `supplier_retention` are among the 11), so
**no trust claim about the revenue path is currently supportable.**

**Metrics it owns.** (a) Reputation evidence coverage: `dimensions_with_evidence / 6` averaged over active
seats — measured today 2/6 for three of its own four seats; target ≥ 5/6. (b) Its existing KPI,
"Employees with complete KPI, authority and knowledge binding", target 100 %, measured **79.63 %** — the
gap is exactly the 11 named seats with no `employee_knowledge` row. (c) A new, currently non-existent
metric: share of performance verdicts that passed the instrument-validity test (M-CP-3) before issue.

**Quarterly milestones.**
- **Q1.** Bind `employee_knowledge` for the 11 seats → the 79.63 % KPI reaches 100 %. Stand up the
  evidence gate so no report ever prints a 50.0 prior as a score. Start writing a `learning_speed`
  evidence stream (today: zero rows for every seat in this department).
- **Q2.** Instrument-validity test wired ahead of every KPI verdict; the four people_ops seats sit their
  certifications with a recorded score. Constitution adherence scored with the exam scorer's own
  thresholds.
- **Q3.** Calibration measured for the top ten decision-making seats — which requires `decision_trace` to
  store decision-time evidence, which it does not today.
- **Q4.** Three consecutive months where every issued verdict cites an evidence count and a validated
  instrument.

**Capacity check.** The work is arithmetic over 54 employees, 127 KPI rows and 96 reputation rows —
comfortably inside one seat. **The slice is achievable; the revenue is not this seat's to produce.** What
would make its contribution real is upstream: suppliers and inquiries, neither of which exists at the
volume the plan needs.

**Dependencies.** `learning_dev_mgr` (binding and exams), `ops_director` (schema changes to
`decision_trace`, cron enablement), `product_eng` (the `learning_speed` evidence stream), `recruitment_specialist`
(role reviews that follow a capability verdict).

### 9. What this seat cannot do without a model

1. **Judging whether a free-text improvement-plan sentence is genuinely actionable.** Deterministically it
   can check that the plan cites a KPI id, a root-cause band and a named next action — structure, not
   quality. That structural check is what this plan specifies and it is enough.
2. **Reading an open-ended values complaint written in prose and deciding which clause it engages.** The
   lexeme scorer with abstention handles the clear cases and honestly abstains on the rest; the abstained
   cases go to `ops_director` as a human-shaped escalation, not to a model.
3. Nothing else.

---

## `learning_dev_mgr` — Learning & Development Manager

Responsibilities on file: "Owns knowledge coverage and exam performance across every employee." This is
the seat that owns the certification programme built today.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| LD-01 | Is this employee ready to sit certification X? | gate | per employee per certification, 105 pairs | `ops_director` | A fail that measures the knowledge binder, not the employee |
| LD-02 | Which syllabus area does this employee actually lack? | diagnosis | per exam result | the employee | Remediating the wrong area; the resit fails identically |
| LD-03 | Which source fills this gap lawfully? | craft | per open gap, 23 today | `legal` | Ingesting a copyrighted study text; a licence breach for a training file |
| LD-04 | Should this employee resit now or after ingestion? | sequencing | per gap closure | `culture_performance_mgr` | Burning a sitting on unchanged knowledge |
| LD-05 | Which of the 12 knowledge layers is missing for this seat? | diagnosis | weekly | `ops_director` | Layers 3, 6, 7, 9, 10, 11, 12 are empty for all four people_ops seats and nobody has said so |
| LD-06 | Is this `agent_knowledge` row real knowledge or an exam artefact? | gate | per fill | `culture_performance_mgr` | The 6 Sep 2026 incident: 268 rows written on a "wrong" verdict, quarantined |
| LD-07 | Does this employee meet the 14-module standard? | gate | monthly | `data_intel` (goal owner) | 9 of 54 do; claiming otherwise fails `knowledge_modules_complete` |
| LD-08 | Which question in the bank is bad (everyone abstains on it)? | diagnosis | per sitting | — | A bad question depresses every score and looks like a knowledge gap |
| LD-09 | Is this certification the right one for this role? | craft | per role change | `recruitment_specialist` | Certifying a seat against a syllabus its work never touches |
| LD-10 | Should a new certification be added to a seat? | allocation | quarterly | `recruitment_specialist` | `recruitment_specialist` holds 1 certification where its peers hold 2 |
| LD-11 | Which syllabus labels on a certification row have no questions behind them? | diagnosis | per bank change | `ops_director` | 16 of 46 labels in this department; a plan keyed on them joins nothing |
| LD-12 | Is a low exam score the employee's or the retrieval's? | diagnosis | per result | `culture_performance_mgr` | Blaming the employee for a corpus that does not contain the answer |
| LD-13 | Which knowledge is stale and needs review? | sequencing | daily (`knowledge_decay_daily`) | `data_intel` | An employee acting on a superseded rule |
| LD-14 | Should this record be quarantined? | gate | per validation failure | `culture_performance_mgr` | A wrong record in LAYER 4 rendered as what the organisation has learned |
| LD-15 | Which training case family fits this competency gap? | allocation | per gap | `ops_director` | Practising the wrong thing; 17,890 cases and no routing |
| LD-16 | Is the department's retrieval scope correct for this seat? | diagnosis | quarterly | `data_intel` | people_ops scope is `{hr, knowledge, people_ops}`; a wrong scope examines a seat on lifts |
| LD-17 | Has the onboarding ladder stalled, and where? | diagnosis | hourly (`agent_onboarding_hourly`) | `ops_director` | 16 rows sit at L1 83.3 against a threshold of 85, with L2–L4 never attempted |
| LD-18 | Which employee is the highest-value one to certify next? | sequencing | monthly | `ops_director` | Certifying a seat off the revenue path first |
| LD-19 | Does this knowledge gap need an external source or an internal one? | craft | per gap | `data_intel` | Paying attention outward when the answer is in `ops_knowledge` |
| LD-20 | Is `learning_speed` measurable for this seat yet? | gate | monthly | `culture_performance_mgr` | Zero evidence for all four seats; a 50.0 quoted as a learning rate |
| LD-21 | Should the pass mark for an internal sitting differ from the real body's? | craft | per certification | `ops_director` | Copying ACCA's 50 or GA4's 80 without asking what our bank can support |
| LD-22 | Which module is missing for a seat below the 14-module standard? | diagnosis | monthly | the employee | Adding modules that duplicate rather than fill |
| LD-23 | Does this record belong to this department's scope? | gate | per bank top-up | — | The 6 Sep 2026 finding: the CTO examined on Warehousing & 3PL, people_ops on bakery equipment |
| LD-24 | Is a repeated wrong answer a knowledge gap or a bad distractor? | diagnosis | per question | — | Fixing the employee when the option set is the fault |
| LD-25 | What does an abstention mean here — no knowledge, or indistinguishable options? | diagnosis | per abstention | `culture_performance_mgr` | Both count wrong; only one is a knowledge gap |
| LD-26 | Should this employee's knowledge be re-embedded? | sequencing | continuous (`kb_embed_backfill`) | `data_intel` | Retrieval misses because the vector is stale |
| LD-27 | Which lesson in `institutional_memory` should become bound knowledge? | craft | weekly | `culture_performance_mgr` | 1,973 lessons nobody's head contains |
| LD-28 | Does a certification need re-sitting on age? | sequencing | annual | `ops_director` | `fn_recert_rotate` exists; cron 132 is OFF, so nothing ages |
| LD-29 | Is this seat's improvement plan tied to a real syllabus gap? | gate | monthly | `culture_performance_mgr` | Plans currently cite an attainment band, not a syllabus area |
| LD-30 | Which department has the weakest knowledge coverage? | diagnosis | monthly | `ops_director` | The weakest coverage is where the next customer complaint comes from |
| LD-31 | Should knowledge be bound at awareness, working or expert depth? | craft | per binding | `recruitment_specialist` | Expert depth everywhere is a corpus nobody can retrieve through |
| LD-32 | Is a question's correct option actually supported by our corpus? | gate | per bank addition | — | A question we cannot answer from our own knowledge is unanswerable by design |
| LD-33 | Which employee regressed between sittings? | diagnosis | per resit | `culture_performance_mgr` | A regression read as noise; measured: `bookkeeper` 15 → 25, `security` 27.5 → 42.5, `cs_support` 35 → 2.5, `procurement` 27.5 → 10 |
| LD-34 | Does the training case bank cover this role at all? | gate | quarterly | `recruitment_specialist` | 9,600 role-scoped cases; coverage per role is unverified |

### 2. Domain logic

**M-LD-1 — Readiness gate.** `ready(agent, cert) = layers_complete(agent) AND modules(agent) ≥ 14 AND
bank_areas(cert) ≥ 3 AND every area named on the certification row exists in the bank`. Inputs:
`employee_knowledge` × `employee_knowledge_standard`, `agent_knowledge`, `certification_exam_question`,
`role_certification.syllabus_areas`. Measured: **0 of 4 people_ops seats are ready**, and 16 of 46 area
labels fail the fourth clause.

**M-LD-2 — Gap ranking.** For a sitting, per syllabus area: `score_pct = 100 * correct / asked`; rank
ascending; weight by the area's question share in the bank (an area with 2 questions is a weaker signal
than one with 12). Inputs: `certification_knowledge_gap`, `certification_exam_result.weakest_areas`,
`certification_exam_question` counts per area. Measured for the whole estate: 23 gap rows, all
`bookkeeper`/ACCA, 21 of them at 0 %.

**M-LD-3 — Retrieval-sufficiency test (the honest half of a fail).** For a missed question, re-run the
retrieval the sitter used and check whether the corpus contains *any* document scoring above
`c_min_support` (0.25) for the correct option. If not, the corpus cannot support the answer and the miss
is a **corpus gap**, not an employee gap. Inputs: `fn_agent_context`, `fn_ops_knowledge_search`,
`agent_knowledge`, `kb_chunks`, and the same `ts_rank_cd(…, 32)` scoring. This is the single most
important model this seat owns, and it is pure SQL.

**M-LD-4 — Bad-question detector.** A question where ≥ 70 % of sittings abstain (`chosen is null`), or
where the correct option's best support is below 0.25 for every sitter, is a **bank defect**. Inputs:
`certification_exam_result.answers` (jsonb), `certification_exam_question`. `fn_bump_exam_question(id)`
already exists to retire one.

**M-LD-5 — Layer coverage.** `coverage(agent) = distinct layer_no present / 12`. Measured: 5/12 for all
four people_ops seats (layers 1, 2, 4, 5, 8).

**M-LD-6 — Module depth.** `modules(agent) = count(agent_knowledge)` against the company standard of 14.
Measured distribution over 54 active seats: 3→1 agent, 4→2, 5→1, 6→2, 7→5, 8→10, 9→6, 10→5, 11→3, 12→8,
13→2, 14→2, 17→1, 19→1, 22→1, 25→1, 26→1, 32→1, 35→1. **9 of 54 (16.7 %) meet the standard.**

**M-LD-7 — Ingestion plan.** `fn_certification_ingestion_plan()` and `fn_certification_gap_sources(agent,
cert, area)` already exist: for an open gap, they name the sources that could close it. The judgement this
seat adds is the **licence gate** (see LD-J3).

**M-LD-8 — Learning speed.** `speed = Δ score_pct / days between sittings`, per (agent, certification).
Measured pairs available today: `bookkeeper` ACCA 15 → 25 (+10) over ~1.2 hours; `security` CISSP
27.5 → 42.5 (+15) over ~9 minutes; `procurement` MCIPS 27.5 → 10 (−17.5); `cs_support` HDI-SCA
35 → 2.5 (−32.5); `marketing_analyst` GA4 25 → 35 (+10). **Two of five regressed.** For people_ops
**no pairs exist at all**, which is why `agent_reputation.learning_speed` has zero evidence.

### 3. Reasoning procedures

**LD-01 — "ready to sit?"**
1. Layer coverage = 12/12? Measured 5/12 → **refuse**, name layers 3, 6, 7, 9, 10, 11, 12, and open the
   binding task with the exact `employee_knowledge` inserts required.
2. Modules ≥ 14? Measured 7–10 → **refuse**, name the shortfall.
3. Every `role_certification.syllabus_areas` label present in the bank? Measured: fails for all four →
   **refuse**, name the orphan labels, open the bank-repair task.
4. All pass → call `fn_certification_exam_sit(agent, cert)`, record the result, then run LD-02.
5. The refusal text names the blocking gate and the task id. Never a guess, never a partial sitting.

**LD-02 / LD-12 — "whose fault is a miss?"**
1. For each missed question, run M-LD-3 (retrieval sufficiency).
2. Corpus cannot support the correct option → **corpus gap**. Route to LD-03 (source selection).
   The employee is not marked down.
3. Corpus supports it but the employee's own `agent_knowledge` and head do not → **employee gap**.
   Write a `certification_knowledge_gap` row and route to remediation.
4. Corpus supports it, the employee reaches it, and the margin was below 0.15 → **indistinguishable
   options**; run M-LD-4 on that question before touching the employee.
5. Report the three counts separately. A single "score 27.5 %" is one number with three causes.

**LD-03 — "which source, lawfully?"**
1. Call `fn_certification_gap_sources(agent, cert, area)` for candidates already known to the estate.
2. Filter by licence class, in this order of preference: (a) a standards body's own freely published
   preview or glossary; (b) a regulator's published text (UAE MoHRE, UAE Legislation portal, DET);
   (c) a public dataset or public-domain government handbook (NIST, OECD, ILO); (d) an internal
   `ops_knowledge` record we authored.
3. **Reject** any copyrighted study text — PMBOK, the ASQ handbook, the SHRM Learning System, the ATD
   *Talent Development Body of Knowledge*. Refuse and say why; do not paraphrase around it.
4. Ingest through `fn_certification_gap_ingest`, tagging `source_type` and `source_authority`.
5. Re-run M-LD-3 for the same question. If the corpus now supports the answer, and only then, schedule
   the resit.

**LD-05 — "which layer is missing, and what fills it?"**
1. Left-join `employee_knowledge_standard` (12 rows) to the seat's `employee_knowledge`.
2. For each missing layer, read `binds_via`: `knowledge_domain` → bind a domain at the right depth;
   `workflow` → bind from `employee_workflow`; `kpi` → bind from `employee_kpi`; `memory` → bind from
   `institutional_memory` / `org_memory`; `company` → the `qd-company:*` records;
   `runtime` → these are computed at answer time and need a resolver, not a row.
3. Measured for this department: layers 3 (Department) and 6 (Workflow) and 11 (KPI) are all bindable
   **today** from existing tables — `ops_knowledge` at `{hr, knowledge, people_ops}`, `employee_workflow`
   (6 rows for these seats), `employee_kpi` (7 rows). Layers 7, 10, 12 are `runtime` and need the
   resolvers this document specifies. Layer 9 (Experience) needs `institutional_memory` promotion, which
   is cron 188 and is **OFF**.

**LD-17 — "where has onboarding stalled?"**
1. Read `org_onboarding`. Measured: 16 rows, all `status='onboarding'`, `l1_score` 83.3 vs
   `pass_threshold` 85, `l2_at`/`l3_at`/`l4_at` null, `certified_at` null, `probation_reviews_done` 0/3.
2. The ladder is stalled at L1 **below threshold**, which means no row can advance and none ever will
   without either more knowledge or a threshold decision.
3. Verdict: this is not 16 individual failures; it is one gate at 83.3 vs 85 across the board. Route one
   task to `ops_director`, not sixteen.
4. Do **not** lower `pass_threshold` to clear it. That is weakening a check.

**LD-33 — "did this employee regress?"**
1. Order the seat's `certification_exam_result` rows by `sat_at` for the same certification.
2. A fall of more than 5 points between consecutive sittings is a regression.
3. Before recording it against the employee, check whether the bank changed between sittings
   (`certification_exam_question.created_at`) and whether any of its knowledge was quarantined in the
   interval (`agent_knowledge.validation_status`). A regression that follows a quarantine is the
   quarantine, not the employee.
4. Measured today: `cs_support` 35 → 2.5 and `procurement` 27.5 → 10 both regressed; both need step 3 run
   before any verdict.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| LD-J1 | Any required knowledge layer is empty | refuse to schedule the exam | The result would measure the binder |
| LD-J2 | The corpus cannot support the correct option above 0.25 | corpus gap, not employee gap | The question is unanswerable from what we hold |
| LD-J3 | A source is a copyrighted exam study text | refuse, name the lawful alternative | A licence breach for a training file is not worth a syllabus area |
| LD-J4 | An exam verdict is "wrong" (not "not covered") | never write a fill from it | 6 Sep 2026: 268 such rows were quarantined across 79 employees |
| LD-J5 | A record is outside the seat's `fn_dept_scope` | never ask it in that seat's exam | The CTO was examined on Warehousing & 3PL |
| LD-J6 | ≥ 70 % of sitters abstain on a question | retire the question before judging anyone | A bad distractor set is a bank defect |
| LD-J7 | A certification row names an area the bank does not hold | fix the row or the bank before sitting | 16 of 46 labels in this department |
| LD-J8 | Onboarding is stalled at one gate for every row | one task, one decision | 16 rows at 83.3 vs 85 is one gate, not 16 failures |
| LD-J9 | Clearing a stall would require lowering a pass mark | refuse | Never weaken a check to turn a gate green |
| LD-J10 | `learning_speed` is asked for with < 2 sittings | say it does not exist | Zero evidence for every seat in this department |
| LD-J11 | A resit is proposed with no intervening ingestion | refuse | The same knowledge produces the same answers; the sitter is deterministic |
| LD-J12 | Knowledge would be bound at expert depth in a domain the seat only observes | bind at awareness | An unretrievable corpus is a slower wrong answer |
| LD-J13 | A gap could be closed from `ops_knowledge` we already hold | never go external | 9,140 runtime-eligible rows already exist |
| LD-J14 | A regression follows a quarantine | attribute it to the quarantine | The instrument changed; the employee may not have |
| LD-J15 | The next certification would go to a seat off the revenue path while revenue is 0 | defer it | Certify `inquiry_router` before certifying a reflection seat |

### 5. Technical knowledge

The certification programme end to end: `role_certification` (105), `certification_exam_question` (2,080),
`certification_exam_question_vector` (10,400), `certification_exam_result` (22),
`certification_knowledge_gap` (23); the routines `fn_certification_exam_sit`,
`fn_certification_exam_sit_semantic`, `fn_certification_exam_sit_all`, `fn_certification_resit`,
`fn_certification_exam_summary`, `fn_certification_exam_compare`, `fn_certification_gaps_refresh`,
`fn_certification_gap_ingest`, `fn_certification_gap_sources`, `fn_certification_ingestion_plan`,
`fn_recert_rotate`, `fn_exam_pick_agent`, `fn_exam_revert`, `fn_exam_record_in_scope`,
`fn_exam_or_tsquery`, `fn_bump_exam_question`. The knowledge exam: `fn_knowledge_exam_sit`,
`fn_knowledge_exam_summary`, `fn_knowledge_exam_retrieval` (cron 320, ON). The knowledge estate:
`ops_knowledge` (9,140 rows; `scope_type`, `dept_key`, `module`, `record_type`, `authority_tier`,
`runtime_eligible`, `deterministic`, `embedding_gte`, `tsv`), `agent_knowledge` (2,556;
`layer`, `validation_status`, `review_due`, `supersedes_id`, `embedding_gte`), `employee_knowledge` (900),
`employee_knowledge_standard` (12), `kb_chunks`, `fn_ops_knowledge_search`, `fn_dept_scope`,
`fn_dept_module_scope`, `fn_knowledge_gaps`, `fn_knowledge_gap_deterministic`,
`fn_dispatch_agent_knowledge_gaps`, `fn_learning_loop_sweep` (cron 204, ON), `fn_assign_training`.
Embedding: **gte-small in-region via `kb_embed` is free** (crons 108, 242, 271, 315) — OpenRouter is not
involved and must not be. Scoring mechanics: `ts_rank_cd(…, 32)` bounded into [0,1),
`pg_trgm.word_similarity`, abstention at support 0.25 and relative margin 0.15.

### 6. Academic knowledge

Certifications on file: **CPTD** (ATD, rank 1, pass mark 70) and **SHRM-CP** (SHRM, rank 2, pass mark 70).
The SHRM-CP row's four domain-level labels (Behavioral Competencies, People/Organization/Workplace
Knowledge Domain) have **no questions behind them**; CPTD's "Learning Technologies" likewise.
**Syllabus areas failed: does not exist** — never sat.

Theory, with lawful primary sources:

- **Instructional design and evaluation** — the four-level evaluation hierarchy (reaction, learning,
  behaviour, results) and its critiques. Source: the **US Office of Personnel Management** and
  **GAO** publicly published training-evaluation guidance (public domain), plus **ISO 21001:2018**
  (educational organisation management systems) clause headings from the ISO OBP preview.
- **Item response theory and classical test theory** — item difficulty, discrimination, distractor
  analysis; this is the mathematics behind M-LD-4. Source: the **NIST/SEMATECH e-Handbook** and the
  openly published **AERA/APA/NCME Standards** summary material.
- **Spacing, retrieval practice and forgetting curves** — why `knowledge_decay_daily` exists. Source:
  the **National Center for Education Research / IES Practice Guides** (US Department of Education,
  public domain), which publish the effect sizes directly.
- **Information retrieval** — tf-idf, BM25, rank normalisation, precision/recall at k; the mathematics of
  `ts_rank_cd` and of M-LD-3. Source: **NIST TREC** proceedings and the TREC evaluation methodology
  (public domain), plus **PostgreSQL's own documentation** on text search ranking (open licence).
- **Vector retrieval and embedding evaluation** — recall@k, the limits of nearest-neighbour. Source:
  the **MTEB** public benchmark methodology and the public model card for `gte-small`. The estate's own
  lesson stands above the literature: a nearest neighbour is always found, so corroborate by lexemes and
  never trust a bare cosine.
- **Competency frameworks** — Source: the **European Skills, Competences, Qualifications and Occupations
  (ESCO)** classification, freely published by the European Commission, and **O*NET** (US Department of
  Labor, public domain) — both are lawful, structured, machine-readable competency taxonomies we may
  ingest wholesale.
- **UAE training and labour context** — Federal Decree-Law No. 33 of 2021 and MoHRE guidance, from the
  official portals.

### 7. Corporate knowledge

The founder's rule of 6 Sep 2026 that gave this seat its programme, verbatim in the SQL header: *"test all
agents. if they dont pass them all, then their knowledge is simply not enough."* The deterministic sitter
and why it never calls a model. The 6 Sep 2026 quarantine incident in full. The 12-layer standard and its
`binds_via` column. The company's own knowledge renderer `fn_company_self_knowledge_sync()` (cron 292,
every 15 minutes) and the rule that a permanent company fact goes in a **table** first and is rendered
from there. `fn_company_hard_rules()` and `fn_agent_context` (both overloads live in
`scripts/sql/every_head_carries_the_licence_and_tax_status.sql`). That embedding is free and OpenRouter is
held. That DET licence 1633275 expires 24 Jun 2027 and there is no VAT registration below AED 375,000 —
never to be asked again.

Hands to: `culture_performance_mgr` (a gap that has become a performance question),
`recruitment_specialist` (a gap that is the wrong role), `ops_director` (schema, cron, scope changes),
`data_intel` (corpus and embedding), `legal` (source licensing).

**History it must not forget:** that the exam once examined the catalogue instead of the staff; that a
lexeme grader cannot distinguish a differently worded correct answer from a wrong one; that 1,204 of the
2,095 null-department `ops_knowledge` rows are supplier-category route files and must never enter a
non-marketplace seat's bank.

### 8. One-year plan

**Objective.** Every active employee holds all 12 knowledge layers, meets the 14-module standard, and has
a recorded certification result whose failures are attributable to a named, closable syllabus area.

**Slice of AED 1,000,000: AED 0 direct.** The chain from this seat to revenue is: knowledge bound →
exam sat → gap named → gap closed → the seat that routes an RFQ or evaluates a quote answers correctly →
a reveal happens at 3 % of quote value. **Every link after the first is currently at zero.** The honest
statement is that this seat's contribution is a precondition for revenue and cannot be attributed a share
of it. AED 1,000,000 at a 3 % reveal fee needs AED 33,333,333 of revealed quote value; the average quote
value **does not exist** (0 quotes), so no per-RFQ figure can be derived without inventing one.

**Metrics it owns.** (a) Layer coverage: `distinct layer_no / 12` averaged over 54 active seats —
measured 5/12 for this department; target 12/12. (b) `knowledge_modules_complete` (company goal, owner
`data_intel`, this seat's work): **16.7 %** of active seats at ≥ 14 modules; target 100 %.
(c) Certification results recorded: **0** for people_ops, 5 sittings and 0 passes company-wide; target
every active seat sat at least once with an attributable failure profile.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** Repair the 16 orphan syllabus labels. Bind layers 3, 6 and 11 for all 54 seats
  from tables that already hold the data (`ops_knowledge` by `fn_dept_scope`, `employee_workflow`,
  `employee_kpi`). Build M-LD-3 as a routine so every miss is classified corpus/employee/distractor.
  Sit the first people_ops exams. Enable cron 132 (`canon_eval_weekly`) only once M-LD-4 exists.
- **Q2 (Dec 2026–Feb 2027).** Layers 9, 10, 12 resolved — 9 by promoting `institutional_memory`
  (cron 188 currently OFF), 10 and 12 by the runtime resolvers in this document. Close the top gap in
  every seat on the revenue path first (LD-J15). Target: 100 % layer coverage, ≥ 60 % of seats at 14
  modules.
- **Q3 (Mar–May 2027).** All 54 seats sat; every failure attributed. First measured `learning_speed`
  values written, which unblocks `agent_reputation`'s dead dimension.
- **Q4 (Jun–Aug 2027).** Recertification rotation running; no seat older than its `review_due`.

**Capacity check.** The sittings are SQL: 40 questions per certification, 105 pairs, deterministic and
free. That is trivially inside one seat. **The binding constraint is not this seat's capacity — it is the
corpus.** M-LD-3 will, on the measured evidence (0 of 5 sittings passed, scores as low as 2.5 %), classify
a large share of misses as corpus gaps, and closing those needs `data_intel` ingestion capacity and
`legal` source clearance. **The slice is achievable; the timeline depends on a department this seat does
not own.**

**Dependencies.** `data_intel` (ingestion and embedding), `legal` (source licensing),
`ops_director` (scope, cron, schema), `culture_performance_mgr` (verdicts on the results),
`recruitment_specialist` (when a gap means the role is wrong, not the knowledge).

### 9. What this seat cannot do without a model

1. **Writing new exam questions.** The 2,080 questions exist; generating genuinely new, well-formed
   distractors from a syllabus is a generative act. **Deterministic alternative that this plan uses
   instead:** mine questions from records we already hold — a record's title and structured fields yield a
   templated stem, and the distractors come from *sibling records in the same module*, which is exactly
   how a real distractor works. That is enough to keep the bank growing without a model.
2. **Summarising an ingested standard into a teaching note.** We can store the primary text and retrieve
   the passage; composing a shorter explanation is generative. **Alternative:** cite the passage. An
   employee reading the clause verbatim is better evidenced than one reading a paraphrase.
3. **Judging whether two differently worded answers mean the same thing.** This is the exact failure of
   6 Sep 2026. Lexeme overlap cannot do it and neither can embeddings reliably. **This plan does not try:**
   a "wrong" verdict never writes knowledge, only "not covered" does. The limitation is handled by
   abstention, not by a model.

---

## `recruitment_specialist` — Recruitment Specialist

Responsibilities on file: "Identifies capability gaps and defines new employee roles to fill them."
In a company of AI employees, recruiting means **deciding that a capability is missing, defining the seat
that would hold it, and proving the seat earns its place** — not sourcing candidates.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| RS-01 | Is this a missing capability or an unbound existing seat? | diagnosis | per gap signal | `ops_director` | Creating a seat to do what an unbound seat already owns; 11 seats have no knowledge bound |
| RS-02 | Should a new seat be created? | allocation | monthly | `ops_director`, CEO | A 55th employee with no measurable KPI; the estate already carries 5 inactive seats |
| RS-03 | Which department does this new seat belong to? | allocation | per new seat | `ops_director` | A seat whose retrieval scope never contains its own work |
| RS-04 | What certifications should this role hold? | craft | per new/changed role | `learning_dev_mgr` | `recruitment_specialist` itself holds 1 where peers hold 2 |
| RS-05 | What knowledge domains does this role need, at what depth? | craft | per new seat | `learning_dev_mgr` | Expert depth everywhere; an unretrievable corpus |
| RS-06 | What KPI will this seat be measured on, and can it be measured? | gate | per new seat | `culture_performance_mgr` | "Employee has no measurable KPI" is already an open finding against this department |
| RS-07 | What authority does this seat get, and at what AED threshold? | gate | per new seat | `ops_director` | Authority above competence on day one |
| RS-08 | Which workflows does this seat own, participate in, or approve? | craft | per new seat | `ops_director` | A seat with no workflow binding is a seat with no work |
| RS-09 | Should this seat be deactivated? | escalation | quarterly | `ops_director` | 5 inactive seats still carry live KPI rows |
| RS-10 | Is the org shape still fitted to the work? | diagnosis | quarterly | CEO | Ten departments for a company with 0 inquiries |
| RS-11 | Which capability gap is closest to revenue? | sequencing | monthly | `ops_director`, `finance` | Filling a reflection gap while the revenue path is unstaffed |
| RS-12 | Does this seat duplicate another's responsibilities? | diagnosis | per new seat | `ops_director` | Two seats answering the same supplier differently |
| RS-13 | Should two seats merge? | allocation | quarterly | `ops_director` | Coordination cost with no throughput gain |
| RS-14 | What does this role's improvement plan need to say on day one? | craft | per new seat | `culture_performance_mgr` | A generated plan that cites a band, not a gap |
| RS-15 | Is this capability better solved by a seat or by a routine? | allocation | per gap | `product_eng` | Hiring a seat to do arithmetic a trigger could do |
| RS-16 | Does this role need a `role_certification` the bank cannot support? | gate | per role definition | `learning_dev_mgr` | A certification with no questions behind it; 16 such labels exist today |
| RS-17 | What is this seat's `max_open_tasks` ceiling? | allocation | per new seat | `ops_director` | Every seat defaults to 50 with no capacity evidence |
| RS-18 | Which `routing_tier` does this seat sit in? | allocation | per new seat | `ops_director` | Work routed to a director that a specialist should hold |
| RS-19 | Does this seat need an `org_role` identity for accountability? | gate | per new seat | `legal`, audit | An action with no accountable `role_id` fails the kernel |
| RS-20 | Is a repeated escalation evidence of a missing seat? | diagnosis | monthly | `ops_director` | The same escalation lands on the apex every week |
| RS-21 | Which seat should absorb a deactivated seat's KPI rows? | allocation | per deactivation | `culture_performance_mgr` | `ops_director` still carries `hr_director`'s KPI |
| RS-22 | Does this department have too few seats for its objective count? | diagnosis | quarterly | `ops_director` | An objective with no owner is an objective that does not move |
| RS-23 | What is the onboarding path for a new seat? | craft | per new seat | `learning_dev_mgr` | 16 rows stuck at L1; a new seat joins the same stall |
| RS-24 | Should this seat be promoted in seniority? | escalation | weekly (`promotion_review_weekly`) | the seat | Seniority as reward rather than as scope |
| RS-25 | Which skill in `skills_matrix` is below the level the role needs? | diagnosis | monthly | `learning_dev_mgr` | 695 ratings, none tied to a required level |
| RS-26 | Does a supplier-side capability gap need a seat or a supplier? | allocation | per coverage gap | `supply` | Building an internal seat for what a supplier does better |
| RS-27 | Is this role definition specific enough to be examined against? | gate | per role definition | `learning_dev_mgr` | A role nobody can certify |
| RS-28 | What handoff contracts does this seat owe and hold? | craft | per new seat | `ops_director` | `v_handoff_without_contract` grows |
| RS-29 | Which seat is the single point of failure for an action class? | diagnosis | quarterly | `ops_director` | One seat's demotion opens a coverage hole |
| RS-30 | Does the company need this capability now, or at a revenue milestone? | sequencing | quarterly | founder, CEO | Staffing for 25,000 RFQs while 0 exist |

### 2. Domain logic

**M-RS-1 — Gap-vs-binding discriminator.** For a claimed capability gap, test in order:
(a) does an active seat's `responsibilities` text match the capability by lexeme (`ts_rank_cd` over
`org_agents.responsibilities`, threshold 0.25)? (b) if yes, is that seat *bound* — `employee_knowledge`
non-empty, `employee_authority` covering the action class, `employee_workflow` non-empty? Inputs:
`org_agents`, `employee_knowledge`, `employee_authority`, `employee_workflow`. Output: `binding_gap` |
`capability_gap` | `covered`. Measured: **11 active seats fail the binding test on knowledge alone**, so
today the prior strongly favours `binding_gap`.

**M-RS-2 — Role completeness template.** A role is defined only when all nine slots are filled, each from
a named table: `agent_key`, `title`, `department` (must be a `fn_dept_scope` key), `manager_key`,
`seniority`, `routing_tier`, `max_open_tasks`, `responsibilities`, and an `org_role.role_id` for
accountability. Then: ≥ 1 `employee_kpi` row **with a `measure_sql` that returns a non-null value today**;
≥ 1 `employee_authority` row; ≥ 1 `employee_workflow` row; `employee_knowledge` rows covering all 12
layers; ≥ 1 `role_certification` whose every syllabus label exists in the bank. Output: a completeness
score out of 14 checks and the list of unmet ones.

**M-RS-3 — Seat-versus-routine test.** A capability belongs in a routine, not a seat, when its decision
procedure is fully enumerable and its inputs are all in tables — i.e. when it has no judgement rules that
require a threshold the company has not set. Inputs: the proposed taxonomy for the seat. Output:
`routine` | `seat`. This is the test that keeps headcount honest in a company where a seat costs tokens.

**M-RS-4 — Revenue proximity.** `proximity(seat) = 1` if the seat owns or approves a step in
`rfq_handling` (18 steps), `payment` (8), `lead_to_customer` (8), `customer_registration` (8) or
`supplier_onboarding` (9); `2` if it participates; `3` otherwise. Inputs: `employee_workflow`,
`workflow_step`. Measured: `ops_director` is proximity 2 (participant in `rfq_handling`); the other three
people_ops seats are proximity 3. Used to order every "which first" question.

**M-RS-5 — Objective-to-owner coverage.** `unowned(dept) = department_objective rows with no active seat
whose responsibilities match`. Inputs: `department_objective` (96 rows), `os_objective` (50),
`org_agents`. Output: objectives with no owner — the honest definition of "we need a seat here".

**M-RS-6 — Duplication detector.** Pairwise `word_similarity` over `org_agents.responsibilities` within a
department; any pair above 0.6 is a merge candidate. Deterministic, uses `pg_trgm` already installed.

**M-RS-7 — Capacity per seat.** `headroom(seat) = max_open_tasks - open_tasks(seat)`. Inputs:
`org_agents.max_open_tasks` (50 for every seat in this department), `org_tasks.assigned_agent`.
**UNMEASURED:** every seat carries the same default 50 and there is no observed completion rate per seat,
so the ceiling is a convention, not a capacity figure. Say so rather than planning against it.

### 3. Reasoning procedures

**RS-01 — "missing capability, or unbound seat?"**
1. Run M-RS-1(a). If an active seat's responsibilities match above 0.25, go to (b).
2. Run M-RS-1(b). If that seat is unbound → verdict **`binding_gap`**; the answer is not a new seat, it is
   an `employee_knowledge` / `employee_authority` / `employee_workflow` row. Route to `learning_dev_mgr`.
3. If bound and still failing → this is a *performance* question, not a recruitment one. Route to
   `culture_performance_mgr`.
4. Only if no seat matches at all → **`capability_gap`**, continue to RS-02.
5. Measured posture today: 11 active seats are unbound on knowledge, so step 2 is the expected outcome for
   most gap signals and a new seat should be rare.

**RS-02 — "should a new seat exist?"**
1. Run M-RS-3. `routine` → refuse the seat, write the routine specification, hand to `product_eng`.
2. Run M-RS-5: does the capability map to an unowned `department_objective`? If not, there is no objective
   to hold it and the seat has no measurable purpose. Refuse.
3. Run M-RS-2. If any of the 14 checks cannot be satisfied *before* creation — particularly a
   `measure_sql` that returns non-null today — refuse. The open finding "Employee has no measurable KPI"
   exists because this gate was not applied.
4. Run M-RS-4. If proximity 3 and the company still has 0 inquiries → defer to a revenue milestone and say
   which one.
5. All pass → define the seat, with every one of the 14 slots filled and cited.

**RS-04 / RS-16 — "which certifications?"**
1. Map the role's domains (`employee_knowledge.domain_key`) to certifications already in the bank —
   measured: **52 certifications, 40 questions each, 2,080 in total**.
2. Prefer a certification whose bank areas overlap the role's domains by ≥ 3 areas.
3. **Gate:** every `syllabus_areas` label written on the new row must exist verbatim in
   `certification_exam_question.syllabus_area` for that certification. Measured: this gate would have
   caught all 16 orphan labels in this department.
4. Rank 1 = the certification closest to the role's daily decisions; rank 2 = the adjacent discipline.
   Measured: `recruitment_specialist` has **no rank 2** while its three peers do — its own most defensible
   recruitment recommendation is a second certification for itself, and the natural candidate already in
   the bank is **CPTD** (20 areas) or **SHRM-SCP** (19 areas).

**RS-09 / RS-21 — "deactivate, and who absorbs the KPI?"**
1. A seat is a deactivation candidate when it has 0 `agent_runs` in 90 days **and** 0 owned workflow steps
   **and** its objectives are covered by another seat (M-RS-5).
2. Before deactivating, list its `employee_kpi` rows and reassign each to the seat that will actually move
   the number — not to whoever manages the department.
3. Measured failure of step 2: `hr_director` is inactive and `ops_director` still carries its
   "HR Director — primary objective" KPI at 79.63 %, MISSED. `ops_director` also carries
   "Project Coordinator — primary objective". Two of `ops_director`'s three KPI rows belong to seats that
   no longer exist.
4. Verdict template: "deactivate X; reassign KPI k to Y because Y owns the workflow step that moves it;
   if no seat owns that step, retire the KPI."

**RS-11 — "which gap first?"**
1. Score every open gap by M-RS-4 proximity, then by the number of `department_objective` rows it unblocks,
   then by whether it is a `binding_gap` (cheap) or a `capability_gap` (expensive).
2. Measured ordering today: the 11 unbound seats include `inquiry_router`, `doc_intel_manager`,
   `supplier_coverage`, `supplier_retention` and `payments_manager` — all on or adjacent to the revenue
   path, all `binding_gap`, all cheap. **They come before any new seat.**

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| RS-J1 | An existing seat's responsibilities match the capability and it is unbound | bind it, never create a seat | A new seat inherits the same unbound estate |
| RS-J2 | A proposed KPI's `measure_sql` returns null today | refuse the seat | "Employee has no measurable KPI" is already an open finding |
| RS-J3 | The capability's procedure is fully enumerable from tables | write a routine, not a seat | A seat that does arithmetic costs tokens forever |
| RS-J4 | A proposed `role_certification` label has no questions in the bank | refuse the row | 16 such labels exist and none can ever be examined |
| RS-J5 | The seat is revenue-proximity 3 and the marketplace has 0 inquiries | defer to a named revenue milestone | Staffing for 25,000 RFQs while 0 exist |
| RS-J6 | A seat is deactivated with live KPI rows | reassign or retire each row first | `ops_director` carries two dead seats' KPIs today |
| RS-J7 | Two seats' responsibilities exceed 0.6 similarity | propose a merge before proposing a hire | Two answers to one supplier |
| RS-J8 | A new seat would be the sole holder of an action class | require a named backup before creation | A single point of failure created deliberately |
| RS-J9 | A role definition is too vague to generate exam questions against | refuse it | An uncertifiable role cannot be held to a standard |
| RS-J10 | `max_open_tasks` is proposed at the default 50 with no capacity evidence | state it is a convention, not a measurement | Never state what you have not measured |
| RS-J11 | A capability gap is claimed from a single escalation | require ≥ 3 occurrences in 90 days | One escalation is an incident, not a structural gap |
| RS-J12 | Creating the seat would raise the department count above the objective count it owns | refuse | Departments without objectives are coordination cost |
| RS-J13 | A supplier could hold the capability better than a seat | recommend the supplier | The company is a marketplace; it should use one |
| RS-J14 | A promotion is proposed without a widened scope | refuse | Seniority is scope, not reward |
| RS-J15 | The seat would be created before its 12 knowledge layers can be bound | delay creation until they can | It would join the 11 already unbound |

### 5. Technical knowledge

`org_agents` (every column: `agent_key, department, role, kind, active, title, manager_key, seniority,
responsibilities, max_open_tasks, improvement_plan, hired_at, available, unavailable_until,
unavailable_reason, routing_tier`), `org_agent_alias`, `org_role`, `org_role_alias`,
`org_role_identity`, `org_role_committee`, `v_org_role_full`, `v_role_identity_collision`,
`phase_c_role_binding`, `role_permissions`, `role_isolation_decision` (70 rows), `taxonomy_role`.
The binding tables: `employee_kpi`, `employee_authority`, `employee_knowledge`,
`employee_knowledge_standard`, `employee_workflow`, `skills_matrix` (695 rows: `agent_key, skill, rating,
evidence`). Objectives: `department_objective` (96), `os_objective` (50), `company_goals` (64),
`goal_period`. Onboarding: `org_onboarding` (`l1_score … l4_score`, `pass_threshold`,
`probation_reviews_required`), `fn_onboarding_gate`, `fn_onboarding_ingest_runs`, cron 8.
Capability: `fn_capability_verify` (cron 219, OFF), `fn_capability_enrich_sweep`,
`fn_phase_d_capability_request_open` / `_result_accept` / `_state`, `fn_phase_d_capability_answer`.
Handoffs: `handoff_contract`, `phase_d_handoff_contract` (159), `v_handoff_without_contract`.
Authority classes: `phase_c_action_class`, `agent_action_kind_policy`, and
`decision_policy.action_autonomy` (the per-kind disposition map, in which **no kind routes to the
founder**). The kernel rule that an `accountable_role_id` must be a real `org_role.role_id`.

**What must be stored so it can act alone:** the 14-check role template as a routine; the current
unowned-objective list; the revenue-proximity ranking; the certification-to-domain map; the duplication
matrix; the list of action classes with a single holder.

### 6. Academic knowledge

Certification on file: **SHRM-CP** (SHRM, rank 1, pass mark 70). Its six labels include four
(Behavioral Competencies, People/Organization/Workplace Knowledge Domain) with **no questions behind
them**, leaving only Communication and Relationship Management examinable.
**There is no rank-2 certification for this seat — it does not exist**, and this seat is the only one in
the department holding a single certification. **Syllabus areas failed: does not exist** — never sat.

Theory, with lawful primary sources:

- **Job analysis and role design** — task-KSA analysis, the basis of M-RS-2. Source: **O*NET**
  (US Department of Labor, public domain) — a complete, machine-readable occupational taxonomy with tasks,
  skills, knowledge and work activities; and **ESCO** (European Commission, freely published).
- **Organisation design** — span of control, coordination cost, the conditions under which a unit should
  split or merge. Source: **OECD** public-governance working papers (freely published) and the
  **ISO 30414:2018** human-capital reporting metric definitions from the ISO OBP preview — the cleanest
  public list of what a workforce metric must contain to be auditable.
- **Selection validity and adverse impact** — why a selection rule must be job-related and consistently
  applied. Source: the **US EEOC Uniform Guidelines on Employee Selection Procedures** (public domain,
  cited here for method only, not as governing law) and, as the law that does govern us,
  **UAE Federal Decree-Law No. 33 of 2021** and its Executive Regulations from the MoHRE and UAE
  Legislation portals.
- **Capacity and staffing arithmetic** — Erlang and Little's Law applied to a work queue; the mathematics
  behind M-RS-7. Source: **NIST/SEMATECH e-Handbook**.
- **Competency-level scales** — awareness / working / expert, and how to tie a rating to evidence.
  Source: **ESCO**'s skill-reusability levels and **O*NET**'s level anchors, both public.
- **AI system roles and accountability** — who is accountable for an autonomous action. Source:
  **ISO/IEC 42001:2023** clause headings (ISO OBP preview) and the **NIST AI Risk Management
  Framework 1.0** (public domain), whose "Govern" function maps directly onto `org_role` accountability.

### 7. Corporate knowledge

The company's shape: 54 active employees across 10 departments with active seats, 5 inactive seats in
people_ops alone. The founder's standing rulings: only refunds reach him; agents never move money
(`auto_action_max_aed` = 0); AED 10,000 is the financial review line; every notification other than a
refund is routed by `fn_founder_mail_route` to one owned org task. That an accountable role must resolve
through the alias registry or the kernel refuses. The pricing model it is staffing against: 3 % reveal
fee, AED 1,000/year supplier registration with the first 1,000 free, and therefore **AED 0 of supplier
registration revenue until supplier 1,001**. The 12-layer standard. The `matching_strike_limit` of 3 and
`category_open_min_suppliers` of 10, which define what "enough supply" means before a category opens.

Hands to: `ops_director` (creation, deactivation, authority), `learning_dev_mgr` (knowledge binding and
certification design), `culture_performance_mgr` (performance rather than recruitment questions),
`legal` (anything touching employment law framing), `product_eng` (when the answer is a routine).

**History it must not forget:** that `org_designer` and `hr_director` were both deactivated and their KPI
rows were not reassigned; that "Employee has no measurable KPI" and "Agent failing repeatedly" are the two
findings that sit against this department's inactive seats; that the estate has been built-but-empty
before, and a new seat with no bound knowledge repeats it.

### 8. One-year plan

**Objective.** Every capability the AED 1,000,000 plan needs is held by a seat that is bound, measurable
and certifiable — and no seat exists that a routine could replace.

**Slice of AED 1,000,000: AED 0 direct, and the honest statement is stronger than that.** The revenue
identity is `revenue = revealed_quote_value × 0.03` plus supplier registration, which is
`max(0, suppliers − 1000) × AED 1,000/year`. With 1 approved supplier, supplier registration contributes
**AED 0 for the whole of year one unless supply passes 1,000 approved suppliers** — and
`company_goals.suppliers_verified` targets 2,000 while the measured count is 1. So AED 1,000,000 must come
almost entirely from reveals: **AED 33,333,333 of revealed quote value.** The average quote value on this
marketplace **does not exist** (0 quotes), so the RFQ count behind that figure cannot be computed today.
This seat's contribution is to make sure the seats that stand between an inquiry and a reveal —
`inquiry_router`, `quote_evaluation`, `doc_intel_manager`, `payments_manager`, the supply seats — are
staffed, bound and measurable. **Four of those are among the 11 seats with no `employee_knowledge` row.**

**Metrics it owns.** (a) Role completeness: share of active seats passing all 14 checks in M-RS-2 —
measurable today, and no seat in people_ops passes it (all fail the 12-layer check). (b) Its existing KPI
"Employees with an improvement plan", target 80 %, measured **100 %** (54/54) — **MET, and arguably
already saturated**; it should be replaced by (a). (c) Unowned objectives: `department_objective` rows
with no matching active seat.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** Reassign or retire the KPI rows of the 5 inactive people_ops seats — starting
  with the two dead seats' KPIs `ops_director` carries. Run M-RS-1 across every open capability signal and
  convert the `binding_gap` findings into binding tasks rather than hires. Define a rank-2 certification
  for this seat from the existing bank. Replace KPI (b) with KPI (a).
- **Q2 (Dec 2026–Feb 2027).** Role completeness ≥ 80 % of active seats. Every action class has a named
  backup holder. The duplication matrix run and any merge proposed.
- **Q3 (Mar–May 2027).** Staffing decisions taken against **measured** demand for the first time — the
  first quarter in which `inquiries` is non-zero is the first quarter M-RS-7 means anything.
- **Q4 (Jun–Aug 2027).** No unowned `department_objective`; no seat created in the year that a routine
  could have replaced.

**Capacity check.** The work is a handful of decisions a month over 54 rows. **Comfortably inside one
seat, and the slice is achievable — but it is a capability slice, not a revenue slice, and it should not
be reported as revenue.** The plain statement the founder asked for: *this department cannot produce AED
1,000,000. It can make sure the departments that can are staffed by seats that answer correctly with
OpenRouter switched off.* What would make the revenue slice real is upstream and outside this department:
approved suppliers above `category_open_min_suppliers` in real categories, and inquiries.

**Dependencies.** `ops_director` (every creation, deactivation and authority grant),
`learning_dev_mgr` (binding and certification), `culture_performance_mgr` (the performance verdicts that
distinguish a capability gap from a performance problem), `supply` and `growth` (whose demand and supply
numbers are the only thing that makes any staffing figure real).

### 9. What this seat cannot do without a model

1. **Writing a fresh `responsibilities` paragraph for a genuinely novel role.** Deterministic alternative
   used here: compose it from the slots — the objective it owns, the workflows it holds, the action
   classes it may take, the domains it must know. That produces a precise role statement, which is what
   an exam and a KPI need anyway; prose fluency is not a requirement.
2. **Reading an open-ended founder instruction and deciding it implies a new capability.** The founder's
   instructions arrive as text. Deterministically this seat can only act on signals already in tables
   (repeated escalations, unowned objectives, unbound seats). A free-text instruction that names no table
   is a human decision routed to `ops_director`, not a model call.
3. Nothing else.

---

## Department summary for the founder

Four seats, all active, all `trusted` on reputation, **none of them measurable in the way this plan
requires today**:

- **Nothing in this section needs a language model at run time.** Every resolver above is SQL, arithmetic,
  Postgres full-text with the exam's own thresholds, and template composition. The three §9 lists name
  only tasks we deliberately solve another way.
- **The certification programme exists and is deterministic, but no people_ops seat has sat an exam.**
  105 certification assignments, 2,080 questions, 5 sittings, **0 passes company-wide**. 16 of this
  department's 46 syllabus labels have no questions behind them.
- **Knowledge binding is the blocking defect.** All four seats hold 5 of 12 required layers, and 7–10 of
  the 14 required modules. Until layers 3, 6, 7, 9, 10, 11 and 12 are bound, an exam result measures the
  binder, and a performance verdict measures the exam.
- **Three of the department's four KPI misses are one defect**, not three: 79.63 % binding completeness,
  caused by 11 named seats with no `employee_knowledge` row.
- **The department's own owned goals:** `workflow_automation` 98.93 % (on track), `failed_workflows`
  4.08 % against a 0.5 % target (at risk, and not decomposable until `workflow_run` carries a
  `failure_class`), `sop_coverage` with no instrument at all.
- **Revenue.** This department books nothing. AED 1,000,000 at a 3 % reveal fee needs AED 33,333,333 of
  revealed quote value; with 1 customer, 1 approved supplier and 0 inquiries, and with supplier
  registration free below 1,000 suppliers, **no part of the target is currently reachable through
  people_ops, and no per-RFQ figure can be computed without inventing the average quote value, which does
  not exist.** The department's honest slice is the failure rate, the binding completeness and the
  certification evidence that the revenue-earning seats depend on.
