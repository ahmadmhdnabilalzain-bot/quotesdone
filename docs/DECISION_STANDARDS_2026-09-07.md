# Decision standards for all 54 employees — audit and build plan

7 September 2026. Written for the founder, who asked: *"apart from technical knowledge and academic
knowledge, we need to set standards for decisions … if I ask my CEO what he thinks I should do to
increase my revenue, based on what will he reply? … how did we decide that option A is better than B."*

No language model is involved anywhere in this plan. Everything below is data, arithmetic and code.

---

## 1. What the company has today (measured on production, 7 Sep 2026)

| Layer | What exists | Rows | Verdict |
|---|---|---|---|
| **Who may decide** | `employee_authority` (agent, action class, tier, AED threshold), `org_authority`, `founder_reserved_decision`, gates | 320 / 781 / — | **Strong.** 46 action classes; every employee's authority and money limit is explicit and enforced. |
| **Rules that forbid** | `phase_b_business_rule`, `decision_policy` (thresholds), `fn_company_hard_rules` | 54 / 39 | **Strong.** Hard rules refuse work at the kernel door, not in prose. |
| **A place to record a decision** | `decision_record` — problem, context, options, risks, benefits, recommendation, confidence, expected outcome, rollback plan, goal served, reversible, evidence, gate verdict, actual outcome | 12 | **Schema excellent, use almost nil.** 12 decisions in the company's life. 7 carry an outcome. |
| **A lighter decision log** | `decision_log` — actor, kind, decision, confidence, reasons, sources, alternatives | 2,098 | **Weak as a standard.** 1,474 of 2,098 give a reason; only **623 name an alternative**. 1,475 decisions have no recorded rejected option. |
| **Traceability** | `decision_trace`, kernel traces | 1,659 | **Strong.** Every system execution can be traced to its actor. |
| **What the company wants** | `company_goals` (with `measure_sql`, direction, target), `department_objective`, `employee_kpi` + history | 63 / 96 / 127 + 1,332 | **Good and measurable.** Goals compute themselves from live data. |

### Per employee, all 54 (measured 7 Sep 2026)

| Department | Employees | Decisions logged | Naming an alternative | Full decision records | Sourced profession knowledge rows | KPIs |
|---|---|---|---|---|---|---|
| product_eng | 6 | 691 | 106 | 0 | 36 | 18 |
| supply | 6 | 410 | 228 | 0 | 14 | 15 |
| exec | 3 | 53 | 28 | 0 | 10 | 11 |
| legal | 4 | 51 | 38 | 0 | 24 | 7 |
| customer_experience | 5 | 48 | 12 | 0 | 13 | 7 |
| data_intel | 7 | 37 | 25 | 0 | 12 | 14 |
| marketplace | 7 | 36 | 21 | 0 | 12 | 15 |
| finance | 5 | 21 | 10 | 0 | 27 | 9 |
| people_ops | 4 | 21 | 17 | 1 | 4 | 7 |
| growth | 7 | 4 | 2 | 0 | 7 | 18 |
| **Total** | **54** | **1,372** | **487** | **1** | **159** | **127** |

Read across that table and four things are true, none of them opinions:

- **32 of the 54 employees have never recorded a single decision.** Not one, ever. They include every
  seat in customer experience except the director, the whole of finance below the CFO, all of marketing,
  both trust and safety seats, four of the seven marketplace seats and three of the four people seats.
- **53 of the 54 have never once used the full decision record** — the schema with options, risks,
  rollback and expected outcome. It has been used once in the company's life, by people_ops.
- **Only 487 of 1,372 logged decisions name an alternative.** In 885 cases the company recorded what it
  chose without recording what it chose against, so no reasoning can be reconstructed afterwards.
- **Two departments make 80% of all decisions** (product engineering and supply). Growth, with seven
  employees and eighteen KPIs, has made four decisions in the company's existence.

Authority and KPIs are the exception and they are healthy: every one of the 54 has authority rows and
at least one KPI. The company knows who may decide. It has almost no record of anyone deciding.

The 32 who have never decided: channel_specialist, cs_onboarding, cs_retention, cs_support, bi_analyst,
market_analyst, process_improvement_mgr, supplier_analyst, billing_specialist, bookkeeper,
payments_manager, brand_mgr, marketing_analyst, marketing_content, marketing_design, marketing_social,
optimisation_eng, moderation_specialist, trust_safety_mgr, doc_intel_manager, inquiry_router,
quote_evaluation, rfq_qualification_mgr, rfq_success, culture_performance_mgr, learning_dev_mgr,
recruitment_specialist, backend_engineer, qa_manager, red_view_alerter, partnerships_mgr,
supplier_retention.

### What is missing — and this is the whole of the founder's question

1. **No decision-type catalogue.** Nothing says *what kinds of decisions this seat makes*. A decision arrives as free text and is handled ad hoc.
2. **No criteria and no weights.** Nothing anywhere states what "better" means. There is no objective function, so "A is better than B" is currently an opinion with no arithmetic behind it.
3. **No option catalogue.** Nothing enumerates the moves available in a domain. Options are invented per case, so two employees facing the same situation can consider different sets.
4. **No quantitative model of the business.** No revenue identity, no elasticities, no capacity or liquidity constraints, no payback arithmetic. Without a model, an expected effect cannot be computed at all.
5. **No constraint filter at decision time.** The hard rules refuse *actions*; nothing eliminates *options* before they are compared.
6. **No sensitivity.** Nothing records what would have changed the answer — the single most useful line in any real decision memo.
7. **No calibration.** 7 outcomes on 12 records; nothing scores whether an employee's confidence was justified, so nobody's judgement improves with evidence.
8. **No independent review of a decision.** Workflows have reviewers; decisions do not.

**In one sentence:** the company knows *who* may decide and *what is forbidden*, and it records that a decision happened — but it has no shared definition of *better*, no menu of moves, and no model to compute an effect. That is why a deep question gets a shallow answer.

---

## 2. The standard to build

A decision, for every employee, becomes a **computed object** with eight mandatory parts. Nothing is
free text; every part is a row.

| # | Part | Where it comes from |
|---|---|---|
| 1 | **Frame** — decision type, owner, reversibility, authority tier, money at stake, deadline | `decision_type` catalogue × `employee_authority` |
| 2 | **Objective** — what this decision is trying to move, and the weight of each criterion | `decision_criteria` (weights sum to 1, founder-approved per type) |
| 3 | **Options** — the feasible set, drawn from a catalogue, never invented per case | `decision_lever` catalogue, filtered by constraints |
| 4 | **Evidence** — the measured value of every input, with its source and age | live tables, `measure_sql`, cited by record id |
| 5 | **Model** — the arithmetic that turns a lever into an expected effect | `fn_model_*` per domain (below) |
| 6 | **Score** — each option scored per criterion, weighted, ranked, with the gap to the runner-up | computed |
| 7 | **Sensitivity** — which single input, if wrong, flips the ranking; and by how much it must be wrong | computed |
| 8 | **Record** — chosen, rejected-with-reason, assumptions, rollback, expected outcome, review date | `decision_record`, mandatory |

**The rule that makes it honest:** if the evidence for an input is missing or older than the type's
tolerance, the decision is not made. It returns *"cannot decide: input X is unmeasured"* and opens the
task to measure it. An employee that guesses is worse than one that says it cannot answer.

---

## 3. The models each decision needs (pure arithmetic, live inputs)

These four models are the "smartness". They are small, they are code, and every number in them is
measured from the estate.

**Revenue model.** `revenue = customers × RFQs per customer × reveal rate × average quote value × 3%`.
Every factor is a live measurement with a history. Each factor has levers attached (see below), and a
lever's expected effect is expressed as a change to one factor with an explicit elasticity and a
confidence interval — where no elasticity has been measured yet, it is declared *unmeasured* and the
option is ranked as unknown rather than optimistic.

**Supply liquidity model.** A category is transactable only at ≥ 10 verified suppliers (founder rule).
For each category: verified suppliers, quote rate, response time. This model produces the binding
constraint: demand levers cannot pay back while liquidity is below threshold.

**Unit economics and payback.** Cost per acquired customer, contribution per reveal, payback period in
weeks, against the AED 30/day cap and the current cash position. Kills any option whose payback exceeds
the runway.

**Risk and reversibility.** Each option carries: reversible or one-way, worst credible loss, regulatory
exposure, founder boundary touched. A one-way door with material loss is auto-escalated to the founder
regardless of the score, because that is his standing rule.

---

## 4. The founder's own example, worked

**"What should I do to increase revenue?"** — what the CEO would compute, with no model call:

1. **Decompose** revenue into the identity above and read today's value of each factor from live data.
2. **Locate the binding constraint.** Today: verified suppliers per category is 0 against a threshold of
   10, so reveal rate is structurally 0 and every demand lever multiplies by zero.
3. **Enumerate the levers** attached to each factor from the catalogue — supplier invitation from the
   existing lead list, category concentration, paid demand, pricing, activation of dormant customers —
   each with cost, lead time and its constraint.
4. **Filter** by constraints: cash, the AED 30/day cap, the founder's held switches, the legal rules.
5. **Score** each surviving lever on the weighted criteria: expected contribution, payback weeks,
   confidence of the elasticity, reversibility, effort.
6. **Answer**: *"The binding constraint is supply liquidity. Until at least three categories reach 10
   verified suppliers, no demand spend can convert, so the ranked action is supplier invitation from the
   1,x00 leads we hold, concentrated in the two categories with the most inbound demand. Second is
   nothing — deliberately. The decision flips if verified suppliers in any category exceed 10, or if the
   measured invitation acceptance rate falls below y%."*

That answer contains the option set, the arithmetic, the constraint, the rejected alternatives and the
condition that would change it. It is exactly what the founder is asking for, and none of it needs a
language model.

**A deeper judgement call** — say, *"should we cut the reveal fee to 2% to win volume?"* — runs the same
machine: it is a pricing lever, its effect is a revenue-identity change with an elasticity the company
has never measured, so the model returns *unmeasured*, the standard forbids a guess, and the honest
output is a designed experiment: which categories, what sample, how long, and what result would justify
the change permanently. That is the difference between a judgement and an opinion.

---

## 5. Build plan

Each phase is deterministic code, applied to production and proven by execution. No phase needs the
paid model, and none of it waits on the founder except where marked.

| Phase | What is built | Proven by |
|---|---|---|
| **A. The frame** | `decision_type` catalogue (~40 types across the 10 departments, each with owner role, reversibility, tolerance for stale evidence, required criteria) mapped to `employee_authority`; every one of the 54 employees ends with its named decision types | a check: 0 employees with no decision type; 0 types with no owner |
| **B. The standard of "better"** | `decision_criteria` and weights per type; the four founder boundaries encoded as hard filters; a written default weight set per department for the founder to amend | a check: weights sum to 1 per type; every type names ≥ 3 criteria |
| **C. The models** | `fn_model_revenue`, `fn_model_supply_liquidity`, `fn_model_unit_economics`, `fn_model_risk` — each reading live tables, each declaring which inputs are unmeasured | each model reproduces today's actuals from live data; unmeasured inputs listed, not defaulted |
| **D. The levers** | `decision_lever` catalogue per domain: cost, lead time, factor moved, elasticity (measured or unmeasured), constraint, reversibility | a check: every lever names the factor it moves and its evidence |
| **E. The decision engine** | `fn_decide(type, context)` → feasible options, scores, ranking, sensitivity, rejected-with-reason, written rationale assembled from the numbers; writes `decision_record` | an aborted-transaction probe for each department; the CEO revenue question answered end to end |
| **F. Refusal** | the "cannot decide: input X unmeasured" path, and the task it opens | a probe that removes an input and asserts refusal rather than a guess |
| **G. Review and calibration** | independent reviewer per decision class; scheduled outcome check per decision; a calibration score per employee (was its confidence justified) | outcomes recorded against the 12 existing records; calibration reported per employee |
| **H. Escalation** | one-way doors with material loss and anything touching a founder boundary route to the founder, everything else does not | the existing founder-mail policy, extended to decisions |

**What is needed from the founder:** only one thing, in phase B — a look at the default criterion weights
per department (what the company should trade off against what), which arrive as a one-page table to
amend or accept. Everything else is engineering.

**What this does not give you.** It does not give an employee taste, or the ability to notice a lever
nobody put in the catalogue. That is what the reasoning model adds when it is switched on, and it will
propose options *into* this machine rather than replacing it — the arithmetic, the constraints and the
record stay exactly as they are.
