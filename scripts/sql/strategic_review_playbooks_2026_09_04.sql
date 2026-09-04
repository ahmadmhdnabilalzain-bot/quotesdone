-- THE STRATEGIC REVIEW HAS NO AUTHORED PLAYBOOK, SO ITS STEPS PARK (MASTER_PLAN A1 / §4.2), 4 Sep 2026.
--
-- MEASURED on production at 09:13 UTC, before this file. `strategic_review` (trigger goal.at_risk,
-- 6 steps): 24 runs — 6 done (all in August, on the model), 10 failed, 8 running. Of the 8 running:
--   * step 1 "Evidence: KPI scoreboard, OS health, goal periods" closes model-off in 5 runs through
--     executor:ai_health. In TWO runs (621fe1ac, 90a12fe6) its action_execution was cancelled by
--     fn_action_invoke_dispatch with invoker='refused' — "the queuing employee (intel_director) is
--     blocked from autonomous action by an open remediation" — on 3 Sep 01:17. That block has since
--     cleared (fn_agent_autonomy_blocked('intel_director') = blocked:false today), but a refused
--     execution is never re-queued by fn_workflow_step_sweep, so the step is the dispatcher's, and
--     the dispatcher parked it: attempts=3, disposition='awaiting_model'.
--   * step 2 "Generate options with cost and risk for each" closed in 3 runs on
--     standard_operating_procedure "SOP 07 — Cost Optimization" at cosine 0.854-0.870, corroborated by
--     3 of 8 step terms — a nearest ACTIONABLE record that shares the word "cost", not the company's
--     procedure for generating options. In run 34bcb1e8 it parked instead.
--   * step 3 "Test options against the priority hierarchy" parked in all three runs that reached it
--     (e6b5823b, 8a479fd6, c447a1cf): "no corroborated actionable match: nearest is decision_rule
--     'Strategy, Performance & Evolution rule 09 …'".
--   * steps 4-6 have never been reached under the deterministic applier.
--
-- The applier is correct and is not touched here: fn_apply_playbook demands an ACTIONABLE record kind,
-- cosine >= 0.85 and keyword corroboration from the step's own words. What was missing is the KNOWLEDGE —
-- nobody had ever written down how this company runs a strategic review. This file writes it: one
-- record per step, authored from the routines the process actually reads.
--
-- WHAT EACH RECORD IS BUILT FROM (all measured on this database, not asserted):
--   * the trigger — fn_emit_metric_alerts() raises goal.at_risk per department, once a day, from the
--     v_bi_scorecard rows whose state is OFF_TARGET, carrying failing_metrics and goals_at_risk;
--   * the computed metrics — fn_bi_snapshot()/v_bi_scorecard, fn_os_health() and org_departments.health_fn,
--     fn_goal_period_refresh()/goal_period joined to company_goals, and fn_strategy_metrics()
--     (under-supplied categories, coverage, funnel via fn_marketplace_analytics) — the AI Strategy
--     Officer's own rpc, which exec_agents skips the model on when metricsFingerprint is unchanged;
--   * the north-stars — the ten rows of org_departments.north_star, quoted verbatim;
--   * the priority hierarchy — the six ranks of public.priority_hierarchy, bound by company_constitution
--     article 4, quoted rank by rank so step 3's test is a filter over data, not a judgement;
--   * the decision record — the columns of public.decision_record, and org_authority(exec, exec_review)
--     = advisory, so step 4 produces a document and executes nothing;
--   * the cascade — department_objective.status/superseded_by and org_tasks, routed by the north-star
--     that owns the failing metric;
--   * the outcome record — outcome_record's baseline/grading columns, and the learning obligation of
--     company_constitution article 14 and hierarchy rank 6.
-- Each record carries an EXPLICIT ESCALATION RULE naming what it does NOT cover and where that goes
-- (the pending review_queue row the deterministic close already raises, then the ~5% model path when
-- the founder's paid-provider hold lifts). None of them closes a question the model must answer.
--
-- SCOPING. Steps 2-6 are the Office of the CEO's (cpo, brief, ceo all resolve to dept 'exec'), so they
-- are department-scoped to exec. Step 1 is performed by intel_director, whose fn_dept_scope is
-- (analytics, data_intel, intelligence, knowledge_eng) — an exec-scoped record is invisible to it. It
-- is therefore scoped by ROLE, dept_key null and role_key 'data-analytics-and-intelligence-director'
-- (held by intel_director alone), with scope_key 'executive_office' recording the owner. That is not
-- cosmetic: MEASURED with the same free gte-small the runtime uses, the step-1 record scores 0.900-0.925
-- against the OTHER five steps' needs, and would have out-ranked the step-4 record (0.9252 vs 0.9217)
-- on run c447a1cf's context had exec been able to see it. Role scope is what keeps each step's own
-- record the one that wins.
--
-- MEASURED with the same free gte-small the runtime uses (kb_embed query mode, no writes, no paid call):
-- each record against the need workflow_dispatch actually builds — name + " — " + step + " — " + run
-- context — for every context now running. Each record is its own step's highest-scoring record inside
-- its own scope, and the proof is committed as scripts/kb/probe_strategic_review_playbooks.mjs.
--
-- Two orderings had to be engineered rather than hoped for, and both are recorded because the numbers
-- are close enough to matter:
--   * the step 1 record scores 0.900-0.925 against the OTHER five steps' needs and out-ranked the step 4
--     record (0.9252 vs 0.9217) on run c447a1cf's context. Role scope, not prose, is what keeps it out of
--     the other five: exec cannot see it at all.
--   * the step 2 record, with its option-source list (under-supplied categories, coverage gaps, funnel
--     leaks) inside the embedded first 1200 characters, beat the step 4 record on a supplier-heavy
--     context by 0.0006 — and did in fact close step 4 of run 8a479fd6 at 09:33 UTC on 4 Sep. The list
--     now sits after a paragraph defining what counts as an option, so it falls outside the embedded
--     head: re-measured, the step 2 record scores 0.885-0.894 on the step 4 needs against the step 4
--     record's 0.903-0.928. The wrongly-closed step is re-opened at the bottom of this file.
-- Cross-workflow bleed was measured too: against metric_lifecycle steps 1/2/3/6, employee_task step 4 and
-- change_deployment step 1, the highest of all six records is 0.843 — below the 0.85 floor, so none of
-- them can be applied to another packet's workflow.
--
-- Idempotent: record_id is fixed, a changed content checksum resets embedding_gte to null and
-- embedding_status to 'pending' so cron 315 (kb_embed_ops_knowledge, every minute) re-embeds it.
--
--   node scripts/apply_sql.mjs scripts/sql/strategic_review_playbooks_2026_09_04.sql --apply --ddl

begin;

insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, role_key, module, record_type, title, content,
  structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
  version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness, confidentiality,
  runtime_eligible, deterministic, supersession_state, embedding_status, layer,
  effective_date, checksum, source_type, source_authority)
select
  e->>'record_id', 'department', 'executive_office',
  nullif(e->>'dept_key', ''), nullif(e->>'role_key', ''),
  'strategic_review', e->>'record_type', e->>'title', e->>'content',
  e->'structured_data', '{}'::text[], 'active', 'author_verified', 'supervised', 'medium', '1.0',
  array(select jsonb_array_elements_text(e->'keywords')), '{}'::text[], e->'escalation_rule',
  'AE', 'current', 'internal',
  true, true, 'current', 'pending', 'decision_playbook',
  current_date, md5(e->>'content'), 'authored_expert', 'quotesdone_office_of_the_ceo'
from jsonb_array_elements($qd_sr_playbooks$[
 {
  "record_id": "ops-exec-strategic-review-step-1-evidence",
  "step_no": 1,
  "dept_key": null,
  "role_key": "data-analytics-and-intelligence-director",
  "record_type": "standard_operating_procedure",
  "title": "Strategic review and re-prioritisation — step 1: evidence from the KPI scoreboard, OS health and goal periods",
  "content": "PROCESS: Strategic review and re-prioritisation. STEP 1 OF 6 — Evidence: KPI scoreboard, OS health, goal periods.\n\nThe EVIDENCE step: assemble the KPI scoreboard, the OS health snapshot and the goal periods. The evidence is MEASURED, never narrated — every number below is read from a routine or a view that already runs, so this step is worked with no model call.\n\nREAD, IN THIS ORDER.\n1. KPI SCOREBOARD — public.v_bi_scorecard, after public.fn_bi_snapshot() has taken the measurement. Each row carries metric_key, label, domain, owner_dept, value, target, direction, state and taken_at. The rows whose state is OFF_TARGET are the failing metrics of this review; they are the same rows public.fn_emit_metric_alerts() read when it raised the goal.at_risk event that opened this run, so the evidence and the trigger cannot disagree.\n2. OS HEALTH — public.fn_os_health(), plus the department health view named in org_departments.health_fn (fn_ws_company, fn_ws_finance, fn_ws_marketplace, fn_ws_marketing, fn_ws_knowledge, fn_ws_customers, fn_ws_operations, fn_ws_governance, fn_ws_ai). A red view is evidence, not yet a conclusion.\n3. GOAL PERIODS — public.goal_period (goal_key, horizon, period_label, target_value, actual_value, owner_dept, status) after public.fn_goal_period_refresh(), joined to public.company_goals for the deadline, the unit, the direction and the owning department.\n4. THE STRATEGY OFFICER'S COMPUTED METRICS — public.fn_strategy_metrics(): under-supplied categories (90-day demand in inquiries against the distinct suppliers actually quoting), coverage (category_specs with engineered requirements, active qualification_playbooks, regulation category tags) and the funnel from public.fn_marketplace_analytics(). These are the same numbers the AI Strategy Officer files on, and exec_agents compares them with metricsFingerprint: when the metrics are byte-identical to the report already filed for this period, no synthesis is commissioned and no model is called. Unchanged numbers are a finding, not a gap.\n\nTHE YARDSTICK IS THE DEPARTMENT NORTH-STAR. Read every failing metric against the north-star of the department that owns it (org_departments.north_star): Office of the CEO — AED 1,000,000 by 31 August 2027, with every department's north-star measured and owned; Supply — matchable verified suppliers per category; Demand — qualified RFQs per AED of Meta spend; Marketplace Ops — percent of RFQs with at least one fit, and quote pass-rate; Finance and Collections — reveal-fee revenue collected and days-to-collect; Customer Experience — complaint-resolution time and ratings collected; Trust, Safety and Compliance — fraud and PII incidents, licence validity; Platform and Reliability — uptime, and time from a red view to a founder alert; Data and Experimentation — KPI freshness, experiments landed, knowledge accuracy; Agent Ops — agents certified and KPI coverage.\n\nHOW A STALLED NORTH-STAR IS FLAGGED. A north-star is STALLED, not merely off target, when any of these holds and the evidence pack must say which: (a) its scoreboard row has been OFF_TARGET on every snapshot for the review window and actual_value in goal_period has not moved between period_labels; (b) v_bi_scorecard.taken_at for the owning metric is older than the measurement cadence, so the number is stale rather than bad — a freshness defect belongs to Data and Experimentation, not to a re-prioritisation; (c) the row carries a non-null error, in which case the metric is UNMEASURED and must be reported as unmeasured, never as zero and never as failing.\n\nWHAT THIS STEP HANDS ON. A dated evidence pack naming, per failing metric: metric_key, label, owner_dept, value, target, direction, state, taken_at, the goal_period rows for the goals at risk, the red health views, and the stalled/stale/unmeasured verdict above. Step 2 turns that pack into options; the CEO officer at step 4 decides against it.\n\nWHEN THIS STEP GENUINELY NEEDS THE MODEL — an ESCALATION RULE, not a close. This procedure covers the assembly of the evidence. It does NOT cover a causal narrative about WHY a number moved when no measurement explains it. If the pack cannot attribute a failing metric to a measured cause, the step still closes on this procedure with the numbers and an explicit 'cause not established by measurement' line, and the pending review_queue row raised by the deterministic close is the escalation: a reviewer routes the narrative to the ~5 percent model path when the founder's paid-provider hold lifts. Never invent the cause to make the pack read complete.",
  "structured_data": {
   "process": "strategic_review",
   "step_no": 1,
   "step": "Evidence: KPI scoreboard, OS health, goal periods",
   "computed_inputs": [
    "public.fn_bi_snapshot() then public.v_bi_scorecard (metric_key, label, owner_dept, value, target, direction, state, taken_at, error)",
    "public.fn_os_health() and org_departments.health_fn per department",
    "public.fn_goal_period_refresh() then public.goal_period joined to public.company_goals",
    "public.fn_strategy_metrics() — under_supplied, coverage, funnel via public.fn_marketplace_analytics()"
   ],
   "stalled_north_star_test": [
    "OFF_TARGET on every snapshot in the window AND goal_period.actual_value unchanged between period_labels",
    "v_bi_scorecard.taken_at older than the cadence -> STALE (a Data and Experimentation defect, not a re-prioritisation)",
    "v_bi_scorecard.error is not null -> UNMEASURED; report as unmeasured, never as zero"
   ],
   "hands_to": "step 2 (options) and, through it, the CEO officer at step 4",
   "model_escalation": "causal narrative for an unexplained move — recorded as an open review, never invented"
  },
  "keywords": [
   "strategic review",
   "re-prioritisation",
   "evidence",
   "kpi scoreboard",
   "os health",
   "goal period",
   "north-star",
   "v_bi_scorecard",
   "fn_strategy_metrics"
  ],
  "escalation_rule": {
   "when": "a failing metric cannot be attributed to a measured cause",
   "to": "review_queue then the ~5% model path when the paid-provider hold lifts",
   "never": "invent the cause"
  }
 },
 {
  "record_id": "ops-exec-strategic-review-step-2-options",
  "step_no": 2,
  "dept_key": "exec",
  "role_key": null,
  "record_type": "decision_playbook",
  "title": "Strategic review and re-prioritisation — step 2: generate options with the cost and the risk of each",
  "content": "PROCESS: Strategic review and re-prioritisation. STEP 2 OF 6 — Generate options with cost and risk for each.\n\nStep 2 of the strategic review and re-prioritisation process generates the options, each with its cost and its risk. An option is a concrete, owned, reversible-or-not change to what the company is working on; a wish is not an option. The generation is deterministic: every option is drawn from a named gap in the step 1 evidence pack, and no model is called to invent one.\n\nWHAT COUNTS AS AN OPTION. An option names the change, the department that will own it, the metric it is meant to move, the direction of the move, its cost and its risk. \"Do better\" is not an option; \"move this metric this far, owned here, at this cost, with this risk\" is. Cost and risk travel with the option in the same line — an option priced without its risk cannot be compared with the one beside it, and comparison is exactly what the next step does with this list.\n\nWHERE THE OPTIONS COME FROM. One option per failing metric or stalled north-star in the evidence pack, taken from the source that already computes the gap:\n- under-supplied categories from public.fn_strategy_metrics() -> a Supply option (invite, claim, verify) owned by the Supply department, whose north-star is matchable verified suppliers per category;\n- coverage gaps in the same result (a category with no engineered requirement, no active qualification playbook, no mapped regulation) -> a Marketplace Ops option;\n- funnel leaks from public.fn_marketplace_analytics() -> a Demand or a Marketplace Ops option depending on where the leak sits;\n- an OFF_TARGET row in public.v_bi_scorecard whose owner_dept is not exec -> an option owned by that department, never by the Office of the CEO;\n- a goal_period row whose actual_value has not moved -> the option of RETIRING or RE-BASING the goal, which is always on the table and is a decision the CEO officer may take at step 4.\nAlways carry the null option — CHANGE NOTHING THIS PERIOD — with its own cost and risk. A review that cannot choose to do nothing is not a review.\n\nCOST. State cost in the two currencies this company actually spends: AED, and agent/founder attention. AED cost is bounded by the authority that would have to approve it (public.org_authority for the owning dept and action_class, and its threshold_aed) — an option that needs more than that authority is not cheaper for being listed, it is an escalation. Meta ad spend is capped by app_secrets.meta_daily_budget_cap_aed and is founder-gated above the cap. Model cost is a real cost and, while the paid provider is held, an option that can only be executed by a model call has an execution cost of zero and an execution date of 'not until the hold lifts' — say so rather than pricing it.\n\nRISK. Score each option on the four risks the company already tracks: reversibility (can it be undone in one step — see org_action_executor.reversible), customer or supplier impact (anonymity before reveal, the 3 percent reveal fee, the 3-working-day supplier response window), compliance exposure (UAE PDPL, licence validity), and the risk of doing nothing. Risk is stated, not scored away: an option with high risk and high value stays on the list for step 3 to test.\n\nWHAT THIS STEP HANDS ON. A numbered option list; for each: the option, the owning department, the metric it is meant to move, the expected direction, the AED cost, the approving authority, the reversibility, the four risks, and the null option. Step 3 tests this list against the priority hierarchy; the CEO officer decides at step 4.\n\nWHEN THIS STEP GENUINELY NEEDS THE MODEL — an ESCALATION RULE, not a close. This playbook covers options derived from a measured gap. It does NOT cover a net-new strategic idea that no measurement implies — a new market, a new pricing shape, a new product line. When the evidence pack contains a gap this playbook cannot map to a named source, the step closes on this playbook with the options it can derive and an explicit 'no measured source for this gap' line, and the pending review_queue row is the escalation: a reviewer routes the generative half to the ~5 percent model path when the paid-provider hold lifts. Never manufacture an option to fill the list.",
  "structured_data": {
   "process": "strategic_review",
   "step_no": 2,
   "step": "Generate options with cost and risk for each",
   "option_sources": [
    "fn_strategy_metrics().under_supplied -> Supply option",
    "fn_strategy_metrics().coverage gap -> Marketplace Ops option",
    "fn_marketplace_analytics() funnel leak -> Demand or Marketplace Ops option",
    "v_bi_scorecard OFF_TARGET row -> option owned by its owner_dept",
    "goal_period with unmoved actual_value -> retire or re-base the goal",
    "always: the null option, change nothing this period"
   ],
   "cost_currencies": [
    "AED bounded by org_authority.threshold_aed",
    "agent and founder attention",
    "model cost (zero while the paid provider is held, and undeliverable until it lifts)"
   ],
   "risk_axes": [
    "reversibility",
    "customer or supplier impact",
    "compliance exposure (PDPL, licence validity)",
    "the risk of doing nothing"
   ],
   "hands_to": "step 3 (priority-hierarchy test)",
   "model_escalation": "a net-new strategic idea no measurement implies — recorded as an open review, never invented"
  },
  "keywords": [
   "strategic review",
   "re-prioritisation",
   "options",
   "cost",
   "risk",
   "null option",
   "org_authority",
   "fn_strategy_metrics"
  ],
  "escalation_rule": {
   "when": "a gap has no measured source, or a net-new strategic idea is required",
   "to": "review_queue then the ~5% model path when the paid-provider hold lifts",
   "never": "manufacture an option"
  }
 },
 {
  "record_id": "ops-exec-strategic-review-step-3-priority-hierarchy",
  "step_no": 3,
  "dept_key": "exec",
  "role_key": null,
  "record_type": "decision_playbook",
  "title": "Strategic review and re-prioritisation — step 3: test the options against the priority hierarchy",
  "content": "PROCESS: Strategic review and re-prioritisation. STEP 3 OF 6 — Test options against the priority hierarchy.\n\nStep 3 of the strategic review and re-prioritisation process tests every option from step 2 against the company priority hierarchy. The hierarchy is DATA, not judgement: public.priority_hierarchy holds six ranked principles, company_constitution article 4 binds them on all employees, and each rank overrides everything below it. So the test is a deterministic filter and this step is worked with no model call. The step is gated on the constitution: its output is a recommendation FOR that gate, never the decision itself — the decision is the CEO officer's at step 4.\n\nTHE TEST. Take each option in turn and walk the six ranks in order. The first rank that REFUSES the option ends the walk for that option.\nRank 1 — Protect legal and regulatory compliance. No goal, deadline or revenue justifies a compliance breach. An option that risks a UAE regulatory violation is REFUSED here and routed to Trust, Safety and Compliance; it never reaches rank 4 to be traded against revenue.\nRank 2 — Protect customer trust and data security. Anonymity, confidentiality and PDPL obligations outrank speed and convenience. An option that would reveal a supplier identity or contact before the customer has paid to reveal it is REFUSED here.\nRank 3 — Deliver high-quality outcomes. A correct, complete answer late beats a fast wrong one. An option that ships work below its quality standard is REFUSED, or RE-SCOPED until it is not.\nRank 4 — Support sustainable revenue growth. Prefer the option that moves a company goal. This is where options are RANKED against each other, and only options that survived ranks 1 to 3 are ranked here. Revenue that damages trust or compliance is not growth.\nRank 5 — Improve efficiency and reduce costs. Among options that tie at rank 4, choose the cheapest path that still satisfies ranks 1 to 4: deterministic code over a model, a small model over a large one. While the founder's paid-provider hold is in force this rank also decides sequencing — an option executable deterministically today outranks an equivalent option that waits for the model.\nRank 6 — Continuously learn and improve. Between two options that still tie, prefer the one that produces a measurable lesson: a baseline, an outcome_record, a superseded objective. A tie broken by learning is recorded as such.\n\nHOW AN OPTION IS SCORED. For each option record: the highest rank that refused it (or 'survived all six'), the rank at which it was ranked against its peers, the position it reached, and one sentence of reason drawn from that rank's own words. Do NOT re-order by expected value across ranks — a lower rank never overrides a higher one, and an option beaten at rank 1 or 2 is out however valuable it looks at rank 4. The null option from step 2 is tested on the same ladder; if every substantive option is refused above rank 4, the null option is the recommendation.\n\nWHAT IS HANDED TO THE CEO OFFICER. A ranked shortlist for the constitution gate: the surviving options in rank-4 order, each with its refusal history, the refused options with the rank and principle that refused them, the null option with its own cost and risk, and the single sentence this step recommends. The CEO officer at step 4 decides and records the rationale; the exec authority for exec_review is advisory (public.org_authority), so this recommendation moves no money and approves nobody, and refunds remain the founder's alone.\n\nWHEN THIS STEP GENUINELY NEEDS THE MODEL — an ESCALATION RULE, not a close. This playbook covers the hierarchy walk, which is mechanical. It does NOT cover the case where two options are refused by the SAME rank for opposing reasons, or where an option's compliance exposure cannot be settled from public.regulations and public.legal_documents without reading a new instrument. In either case the step still closes on this playbook, records the unresolved pair or the unread instrument by name, and the pending review_queue row raised by the deterministic close is the escalation: a reviewer routes the judgement to Trust, Safety and Compliance, or to the ~5 percent model path when the paid-provider hold lifts. Never resolve an unresolved conflict by preference.",
  "structured_data": {
   "process": "strategic_review",
   "step_no": 3,
   "step": "Test options against the priority hierarchy",
   "gate": "constitution",
   "source_of_truth": [
    "public.priority_hierarchy (6 ranks)",
    "public.company_constitution article 4 — Decision priority hierarchy"
   ],
   "ranks": [
    {
     "rank": 1,
     "principle": "Protect legal and regulatory compliance",
     "effect": "refuses outright; routes to Trust, Safety and Compliance"
    },
    {
     "rank": 2,
     "principle": "Protect customer trust and data security",
     "effect": "refuses outright; anonymity before reveal is absolute"
    },
    {
     "rank": 3,
     "principle": "Deliver high-quality outcomes",
     "effect": "refuses or re-scopes"
    },
    {
     "rank": 4,
     "principle": "Support sustainable revenue growth",
     "effect": "ranks the survivors against each other"
    },
    {
     "rank": 5,
     "principle": "Improve efficiency and reduce costs",
     "effect": "breaks ties; deterministic before model, and sequences while the paid provider is held"
    },
    {
     "rank": 6,
     "principle": "Continuously learn and improve",
     "effect": "breaks remaining ties in favour of a measurable lesson"
    }
   ],
   "rule": "a lower rank never overrides a higher one; the walk stops at the first rank that refuses",
   "hands_to": "the CEO officer at step 4 — a ranked shortlist for the constitution gate, recommendation only",
   "model_escalation": "two options refused by the same rank for opposing reasons, or a compliance exposure that needs an unread instrument — recorded as an open review, never resolved by preference"
  },
  "keywords": [
   "strategic review",
   "re-prioritisation",
   "priority hierarchy",
   "constitution",
   "rank",
   "refusal",
   "priority_hierarchy"
  ],
  "escalation_rule": {
   "when": "two options are refused by the same rank for opposing reasons, or compliance exposure needs an unread instrument",
   "to": "Trust, Safety and Compliance, then the ~5% model path when the hold lifts",
   "never": "resolve the conflict by preference"
  }
 },
 {
  "record_id": "ops-exec-strategic-review-step-4-decide-and-record",
  "step_no": 4,
  "dept_key": "exec",
  "role_key": null,
  "record_type": "standard_operating_procedure",
  "title": "Strategic review and re-prioritisation — step 4: decide and record the rationale",
  "content": "PROCESS: Strategic review and re-prioritisation. STEP 4 OF 6 — Decide and record rationale.\n\nThe DECIDE AND RECORD RATIONALE step of the strategic review and re-prioritisation. The CEO officer decides; the decision and its rationale are recorded in public.decision_record. The decision is taken on the ranked shortlist handed over by the previous step and on the measured evidence; it is recorded, not announced. This step is gated on authority and is worked with no model call, because the decision record is a fixed structure and the ranking that feeds the decision was already settled deterministically.\n\nWHAT IS DECIDED — exactly one of: adopt the top surviving option; adopt it in a re-scoped form recorded here; adopt the null option and change nothing this period; or retire or re-base a goal whose goal_period actual_value has not moved. Nothing else is a decision at this step. Where nothing survived the hierarchy, the decision is the null option and the refusal is the recorded rationale.\n\nWHAT IS RECORDED, in public.decision_record. decided_by (the CEO officer), dept_key, problem (the failing metric and the goal at risk, in the words of the step 1 evidence pack), context, options (the full step 2 list, not only the winner), risks, benefits, recommendation, confidence, expected_outcome, rollback_plan, serves_goal (the company_goals.key this decision is meant to move), reversible, impact_business, impact_financial, financial_aed, impact_legal, impact_customer, impact_supplier and evidence. The rationale is the rank-by-rank walk from step 3 quoted back: which rank refused what, and why the adopted option survived it. A decision that cannot name the rank that decided it is not recorded as decided.\n\nAUTHORITY. public.org_authority holds the ceiling for this department and action class: exec / exec_review is ADVISORY, so this step produces a decision document and never executes it; execution belongs to the departments the cascade opens at step 5, each inside its own authority row and threshold_aed, escalating one level when it is exceeded. Two boundaries are never crossed here: a Stripe refund is the founder's decision alone, and Meta spend above app_secrets.meta_daily_budget_cap_aed is founder-gated. Neither is a strategic-review outcome.\n\nWHAT THIS STEP HANDS ON. The decision_record id, the adopted option, the goal it serves, the expected metric and direction, and the list of departments the cascade must reach. Step 5 supersedes the objectives and opens the re-plan work; step 6 opens the outcome record with a baseline so the decision can be graded later.\n\nWHEN THIS STEP GENUINELY NEEDS THE MODEL — an ESCALATION RULE, not a close. This procedure covers recording the decision the deterministic ranking already implies. It does NOT cover a decision that departs from the step 3 ranking: overriding the ranked order, or adopting an option that step 3 refused, is a judgement this company does not take without a stated reason that goes beyond the hierarchy. Where that is what the situation needs, the step still closes on this procedure adopting the ranked top option, records the proposed departure by name, and the pending review_queue row raised by the deterministic close is the escalation: the departure is put to the ~5 percent model path, or to the founder where it touches money, when the paid-provider hold lifts. Never record a departure as if the hierarchy had produced it.",
  "structured_data": {
   "process": "strategic_review",
   "step_no": 4,
   "step": "Decide and record rationale",
   "gate": "authority",
   "decision_set": [
    "adopt the top surviving option",
    "adopt it re-scoped",
    "adopt the null option (change nothing this period)",
    "retire or re-base a goal whose actual_value has not moved"
   ],
   "record_in": "public.decision_record",
   "required_fields": [
    "decided_by",
    "dept_key",
    "problem",
    "context",
    "options",
    "risks",
    "benefits",
    "recommendation",
    "confidence",
    "expected_outcome",
    "rollback_plan",
    "serves_goal",
    "reversible",
    "evidence"
   ],
   "authority": "public.org_authority exec/exec_review = advisory — decision document only; execution sits with the receiving departments inside their own thresholds",
   "founder_boundaries": [
    "a Stripe refund is the founder's decision alone",
    "Meta spend above meta_daily_budget_cap_aed is founder-gated"
   ],
   "hands_to": "step 5 (cascade) and step 6 (outcome record)",
   "model_escalation": "a departure from the step 3 ranking — recorded as an open review, never presented as the hierarchy's own result"
  },
  "keywords": [
   "strategic review",
   "re-prioritisation",
   "decide",
   "rationale",
   "decision_record",
   "authority",
   "founder boundary"
  ],
  "escalation_rule": {
   "when": "the decision departs from the step 3 ranking",
   "to": "review_queue, and the founder where it touches money",
   "never": "record a departure as if the hierarchy produced it"
  }
 },
 {
  "record_id": "ops-exec-strategic-review-step-5-cascade",
  "step_no": 5,
  "dept_key": "exec",
  "role_key": null,
  "record_type": "standard_operating_procedure",
  "title": "Strategic review and re-prioritisation — step 5: cascade the decision, supersede objectives and open the re-plan work",
  "content": "PROCESS: Strategic review and re-prioritisation. STEP 5 OF 6 — Cascade: supersede objectives, open re-plan work.\n\nStep 5 of the strategic review and re-prioritisation process cascades the step 4 decision: it supersedes the objectives the decision replaces and opens the re-plan work in the departments that must act. A decision that changes no objective and opens no work has not been cascaded, and the review has not happened. This step is worked with no model call, because both acts are table writes with a fixed shape.\n\nSUPERSEDE THE OBJECTIVES. public.department_objective carries dept_key, objective, horizon, goal_key, status, superseded_by, target_value, unit, measure_sql, actual_value and measured_at. For every objective the adopted option replaces: set status to superseded and superseded_by to the id of the objective that replaces it, then insert the replacement with the same dept_key and the goal_key the decision serves. Never delete an objective and never edit one in place — the chain from the superseded row to its replacement is the audit trail, and a broken chain loses the reason the company changed direction. An objective belonging to a department the decision did not touch is left alone.\n\nOPEN THE RE-PLAN WORK. One item per receiving department, written to public.org_tasks with dept_key, title, detail, status proposed, the action_class that will execute it, and needs_founder false unless the work crosses one of the two founder boundaries. The detail names the decision_record id from step 4, the metric the work must move, and the direction. Cross-department work is not drained by a second executor: a task that needs a handoff promotes into a workflow_run by emitting its trigger event, so the workflow spine stays the single execution spine and org_tasks stays the planner's backlog.\n\nWHO RECEIVES WHAT. Route by the north-star that owns the failing metric: Supply for matchable verified suppliers per category; Demand for qualified RFQs per AED of Meta spend; Marketplace Ops for percent of RFQs with at least one fit and quote pass-rate; Finance and Collections for reveal-fee revenue and days-to-collect; Customer Experience for complaint-resolution time and ratings; Trust, Safety and Compliance for fraud and PII incidents and licence validity; Platform and Reliability for uptime and red-view-to-alert latency; Data and Experimentation for KPI freshness, experiments and knowledge accuracy; Agent Ops for agents certified and KPI coverage. The Office of the CEO keeps only the goals it owns itself; a task the Office of the CEO opens on itself for another department's north-star is a routing defect.\n\nWHAT THIS STEP HANDS ON. The superseded objective ids with their replacements, the org_tasks ids opened per department, and the events emitted for any work that crosses a department boundary. Step 6 opens the outcome record with a baseline so this cascade can be graded.\n\nWHEN THIS STEP GENUINELY NEEDS THE MODEL — an ESCALATION RULE, not a close. This procedure covers superseding a named objective and opening work in a department that owns the metric. It does NOT cover writing a new objective for a department that has none for the goal in question, which is that department head's act, not the Office of the CEO's. Where the decision needs an objective nobody owns, the step still closes on this procedure with the supersessions and tasks it can write, records the unowned goal by name, and the pending review_queue row raised by the deterministic close is the escalation to that department head and, when the hold lifts, to the ~5 percent model path. Never author another department's objective to complete the cascade.",
  "structured_data": {
   "process": "strategic_review",
   "step_no": 5,
   "step": "Cascade: supersede objectives, open re-plan work",
   "supersede": {
    "table": "public.department_objective",
    "how": "set status='superseded' and superseded_by=<replacement id>, then insert the replacement with the same dept_key and the decision's goal_key",
    "never": "delete an objective or edit one in place — the supersession chain is the audit trail"
   },
   "open_work": {
    "table": "public.org_tasks",
    "fields": [
     "dept_key",
     "title",
     "detail (names the decision_record id, the metric and the direction)",
     "status=proposed",
     "action_class",
     "needs_founder"
    ],
    "cross_department": "promote into a workflow_run by emitting its trigger event; org_tasks stays the planner's backlog, the workflow spine stays the executor"
   },
   "routing": "by the north-star that owns the failing metric (org_departments.north_star)",
   "hands_to": "step 6 (outcome record with a baseline)",
   "model_escalation": "a goal no department has an objective for — escalated to that department head, never authored on their behalf"
  },
  "keywords": [
   "strategic review",
   "re-prioritisation",
   "cascade",
   "supersede",
   "department_objective",
   "org_tasks",
   "re-plan"
  ],
  "escalation_rule": {
   "when": "the decision needs an objective no department owns",
   "to": "that department head, then the ~5% model path when the hold lifts",
   "never": "author another department's objective"
  }
 },
 {
  "record_id": "ops-exec-strategic-review-step-6-outcome-baseline",
  "step_no": 6,
  "dept_key": "exec",
  "role_key": null,
  "record_type": "standard_operating_procedure",
  "title": "Strategic review and re-prioritisation — step 6: open an outcome record with a baseline",
  "content": "PROCESS: Strategic review and re-prioritisation. STEP 6 OF 6 — Open an outcome record with a baseline.\n\nStep 6 of the strategic review and re-prioritisation process opens an outcome record with a baseline. This is what makes the review gradable: a decision without a baseline can never be shown to have worked, and an un-graded decision teaches the company nothing. The step is worked with no model call — every field below is read from a routine, from the step 4 decision_record, or from the step 1 evidence pack.\n\nOPEN ONE public.outcome_record PER ADOPTED OPTION. actor (the officer closing this review) and dept_key (the department that will execute, not the Office of the CEO). subject_type and subject_id point at the decision: 'decision_record' and the id written at step 4. decision and rationale carry the adopted option and the rank-by-rank reason from step 3. evidence carries the step 1 pack.\n\nTHE BASELINE IS THE POINT OF THIS STEP. expected_metric is the metric_key from public.v_bi_scorecard that the decision is meant to move; expected_direction is that row's direction ('up' or 'down'), never the officer's hope; expected_kpi_id links the owning KPI where one exists. baseline_value is the value of that metric AS MEASURED NOW, and baseline_at is its taken_at — the measurement's own timestamp, never now() and never a value carried over from an earlier review. If the metric is UNMEASURED (v_bi_scorecard.error is not null) the outcome record is still opened, baseline_value is left null and the rationale says the baseline is unavailable and why; a null baseline is honest, a zero baseline is a fabrication that will later read as a real improvement.\n\nWHEN IT WILL BE GRADED. measure_after and due_at are set from the goal's own horizon (public.company_goals.horizon and deadline, and the goal_period period_label the review sits in), not from a default interval. At due_at the record is closed by writing observed_value and observed_at from the same v_bi_scorecard row, delta, a verdict, and the lesson — that is the learning obligation of company_constitution article 14 and rank 6 of the priority hierarchy, and it is what lets a later review know whether this one worked. promoted, rolled_back and rollback_reason record what happened to the change itself.\n\nWHAT THIS STEP HANDS ON, AND WHAT CLOSES THE RUN. The outcome_record id, its expected metric, its baseline value and timestamp, and its due date. With the evidence assembled, the options generated and ranked, the decision recorded, the cascade written and the outcome record open with a baseline, the strategic review and re-prioritisation is complete and the run is done.\n\nWHEN THIS STEP GENUINELY NEEDS THE MODEL — an ESCALATION RULE, not a close. This procedure covers opening the record and setting the baseline from measured values. It does NOT cover inventing an expected_metric for a decision whose effect no existing metric measures. Where that is the case, the step still closes on this procedure with the outcome record open, expected_metric null, and the missing measurement named; the pending review_queue row raised by the deterministic close is the escalation to Data and Experimentation to define the metric, and to the ~5 percent model path when the paid-provider hold lifts. Never nominate a loosely-related metric so the record looks complete.",
  "structured_data": {
   "process": "strategic_review",
   "step_no": 6,
   "step": "Open an outcome record with a baseline",
   "table": "public.outcome_record",
   "link": {
    "subject_type": "decision_record",
    "subject_id": "the id written at step 4"
   },
   "baseline": {
    "expected_metric": "v_bi_scorecard.metric_key the decision is meant to move",
    "expected_direction": "that row's direction — never the officer's hope",
    "baseline_value": "the metric's value as measured now",
    "baseline_at": "that measurement's taken_at, never now()",
    "unmeasured": "leave baseline_value null and say why; a zero baseline later reads as a real improvement"
   },
   "grading": {
    "measure_after_and_due_at": "from company_goals.horizon/deadline and the goal_period period_label",
    "closed_with": [
     "observed_value",
     "observed_at",
     "delta",
     "verdict",
     "lesson",
     "promoted",
     "rolled_back",
     "rollback_reason"
    ],
    "why": "company_constitution article 14 (learning obligations) and priority-hierarchy rank 6"
   },
   "completes": "the strategic review and re-prioritisation run",
   "model_escalation": "a decision whose effect no existing metric measures — escalated to Data and Experimentation, never filled with a loosely-related metric"
  },
  "keywords": [
   "strategic review",
   "re-prioritisation",
   "outcome record",
   "baseline",
   "outcome_record",
   "grading",
   "lesson"
  ],
  "escalation_rule": {
   "when": "no existing metric measures the decision effect",
   "to": "Data and Experimentation to define the metric",
   "never": "nominate a loosely-related metric"
  }
 }
]$qd_sr_playbooks$::jsonb) e
on conflict (record_id) do update set
  title = excluded.title, content = excluded.content, structured_data = excluded.structured_data,
  record_type = excluded.record_type, dept_key = excluded.dept_key, role_key = excluded.role_key,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule,
  runtime_eligible = excluded.runtime_eligible, deterministic = excluded.deterministic,
  supersession_state = excluded.supersession_state, layer = excluded.layer,
  embedding_gte = case when public.ops_knowledge.checksum is distinct from excluded.checksum
                       then null else public.ops_knowledge.embedding_gte end,
  embedding_status = case when public.ops_knowledge.checksum is distinct from excluded.checksum
                          then 'pending' else public.ops_knowledge.embedding_status end,
  checksum = excluded.checksum;

-- ---------------------------------------------------------------------------------------------------
-- RE-OPEN the strategic_review steps parked as awaiting_model. fn_workflow_step_release parks a step
-- after three deterministic attempts with disposition='awaiting_model', and fn_workflow_step_claim then
-- leaves it alone until the founder's hold lifts — correct, because at the time nothing covered it. The
-- input has changed: the company now HAS a written procedure for each of these steps, so the recorded
-- reason ("no company playbook or rule confidently covers this step") is no longer true. The park is
-- lifted only for this workflow, only for steps parked on that reason, and the previous error is kept
-- on the row. attempts is reset so the step gets the same three attempts a never-tried step gets.
-- Idempotent: a step that is not parked on that reason does not match, and a re-opened step no longer
-- carries the disposition.
-- ---------------------------------------------------------------------------------------------------
update public.workflow_step_run s
   set attempts = 0,
       error = jsonb_build_object(
         'reopened_at', now(),
         'reopened_by', 'strategic_review_playbooks_2026_09_04.sql',
         'reason', 'parked as awaiting_model because no company playbook covered the step; the Office '
                || 'of the CEO''s strategic-review procedure for this step has now been written to '
                || 'ops_knowledge, so the deterministic applier has something to apply',
         'previous_error', s.error)
  from public.workflow_run r
 where r.id = s.workflow_run_id
   and r.workflow_key = 'strategic_review'
   and r.status = 'running'
   and s.finished_at is null
   and s.status = 'ready'
   and s.error->>'disposition' = 'awaiting_model';

-- ---------------------------------------------------------------------------------------------------
-- RE-OPEN the strategic_review steps closed on somebody else's procedure. Two shapes were MEASURED on
-- production before this block:
--   * step 2 of runs 8a479fd6, c447a1cf and e6b5823b closed on standard_operating_procedure
--     "SOP 07 — Cost Optimization" at cosine 0.854-0.870 with 3 of 8 step terms — the nearest ACTIONABLE
--     record in scope when this company had no procedure for generating options, sharing the word "cost";
--   * step 4 of run 8a479fd6 closed at 09:33 UTC on this file's own STEP 2 record (0.9186) because, in
--     that run's supplier context, the options record out-scored the decide-and-record one by 0.0006.
--     That is fixed above by moving the option-source list out of the step 2 record's embedded head:
--     re-measured, the step 2 record now scores 0.885-0.894 on the step 4 needs and the step 4 record
--     0.903-0.928, so the decide step takes its own procedure in every live context.
-- A determination that applied another step's procedure is not a determination for this step, so the run
-- steps back to the earliest such step, the review rows are rejected with the reason, and the sealed
-- traces are graded rejected. Nothing is deleted: the previous output is kept under previous_output and
-- the trace keeps its evidence. Idempotent — a step closed on its OWN record never matches, and a
-- re-opened step is no longer 'done'. Scoped to strategic_review only.
-- ---------------------------------------------------------------------------------------------------
do $$
declare v_run uuid; v_min int; v_n int := 0; v_steps bigint[];
begin
  -- The earliest wrongly-closed step of each run, and EVERY step from there on that has to be re-done
  -- with it (a later step read the wrong one's conclusion, so it is re-opened too and its own review row
  -- is withdrawn — a pending review for a step that no longer exists in that form is the kind of orphan
  -- this company keeps finding).
  with firstwrong as (
    select s.workflow_run_id, min(s.step_no) as min_step
      from public.workflow_step_run s
      join public.workflow_run r on r.id = s.workflow_run_id
     where r.workflow_key = 'strategic_review'
       and s.status = 'done'
       and s.output->>'disposition' = 'deterministic_low_confidence'
       and coalesce(s.output->>'playbook_record_id', '')
           not like 'ops-exec-strategic-review-step-' || s.step_no::text || '-%'
     group by s.workflow_run_id)
  select array_agg(s.id)
    into v_steps
    from public.workflow_step_run s
    join firstwrong f on f.workflow_run_id = s.workflow_run_id and s.step_no >= f.min_step
   where s.status in ('done','ready');

  if v_steps is null then
    raise notice 'no strategic_review step is closed on another step''s procedure';
    return;
  end if;

  for v_run, v_min in
    select s.workflow_run_id, min(s.step_no)
      from public.workflow_step_run s
      join public.workflow_run r on r.id = s.workflow_run_id
     where r.workflow_key = 'strategic_review'
       and s.status = 'done'
       and s.output->>'disposition' = 'deterministic_low_confidence'
       and coalesce(s.output->>'playbook_record_id', '')
           not like 'ops-exec-strategic-review-step-' || s.step_no::text || '-%'
     group by s.workflow_run_id
  loop
    update public.workflow_step_run
       set status      = case when step_no = v_min then 'ready' else 'queued' end,
           finished_at = null,
           attempts    = 0,
           output      = jsonb_build_object(
             'reverted_at', now(),
             'reverted_by', 'strategic_review_playbooks_2026_09_04.sql',
             'reason', 'closed on a procedure written for a different step of this process; re-opened so '
                    || 'the step takes its own, now that the Office of the CEO''s strategic-review '
                    || 'procedure exists for every step',
             'previous_output', output),
           error = null
     where workflow_run_id = v_run and step_no >= v_min and status in ('done','ready');
    get diagnostics v_n = row_count;
    update public.workflow_run
       set current_step = v_min, status = 'running', finished_at = null, updated_at = now()
     where id = v_run;
    raise notice 'strategic_review run % stepped back to step % (% step(s))', v_run, v_min, v_n;
  end loop;

  update public.review_queue q
     set status = 'rejected', decided_at = now(),
         decided_by = 'strategic_review_playbooks_2026_09_04.sql',
         founder_comment = 'rejected: this determination, or the one it built on, applied the procedure '
                        || 'written for a different step of the strategic review; the step was re-opened '
                        || 'to take its own'
   where q.kind = 'deterministic_step' and q.status = 'pending'
     and (q.payload->>'step_run_id')::bigint = any(v_steps);

  update public.decision_trace t
     set outcome_status = 'rejected', evaluated_at = now(),
         outcome = jsonb_build_object('graded_by', 'strategic_review_playbooks_2026_09_04.sql',
                     'at', now(),
                     'reason', 'applied another step''s procedure, or built on one that did; the step '
                            || 'was re-opened')
   where t.decision_type = 'deterministic_playbook_application'
     and t.entity_type = 'workflow_step_run'
     and t.entity_id = any (select x::text from unnest(v_steps) x)
     and coalesce(t.outcome_status, '') <> 'rejected';
end $$;

commit;
