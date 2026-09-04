-- THE metric_lifecycle WORKFLOW CLOSES EVERY STEP WITH THE MODEL HELD (MASTER_PLAN A1 / §4.2), 4 Sep 2026.
--
-- MEASURED on production htdblwldjkcgjvmqkbeh at 09:12-09:30 UTC, before this file. The workflow has 7
-- steps and trigger kpi.missed; 13 runs are in flight and none has ever passed step 4:
--     step 1  "Define the metric and why it matters"                 11 done  (applier: SOP 01 — Metric Definition, 0.873-0.888)
--     step 2  "Instrument it with a measure that runs"               11 done  (the SWEEP: executor ai_health, used_llm false)
--     step 3  "Measure on cadence and record the actual"              8 done, 1 parked awaiting_model
--     step 4  "Detect variance against target"                        0 done, 8 blocked (3 awaiting_model, 5 retry)
--     steps 5-7                                                       never reached
-- The parked reasons name the defect exactly: step 4's nearest ACTIONABLE record in the cpo's scope is
-- "SOP 06 — Outcome Measurement" at 0.830-0.834 and "SOP 02 — Opportunity Scoring", both BELOW the
-- applier's 0.85 floor; step 3's parked instance reached 0.844 on a growth-flavoured playbook. Nothing
-- in ops_knowledge was written about how THIS company measures, so the applier was correctly refusing.
-- Steps 3 and 4 were not closing because the knowledge did not exist, not because the floor is wrong.
--
-- WHAT THIS FILE ADDS: six authored records — the metric lifecycle as QuotesDone actually runs it, with
-- the fields each step decides from, the determination, and the escalation. They are true to the
-- mechanism, not generic prose: fn_bi_snapshot() and cron bi_snapshot_6h; metric_snapshot.value/error/
-- taken_at; v_bi_scorecard's ON_TARGET / BEHIND (0.7x up, 1.3x down) / OFF_TARGET / UNMEASURED / ERROR;
-- fn_kpi_scoreboard()'s attainment (percent_max inverted, a zero target is a real target) and its
-- MET/NEAR/MISSED/NO DATA verdicts; fn_employee_kpi_measure() at 03:30 UTC writing employee_kpi and
-- employee_kpi_history; fn_kpi_review() on Monday 04:00 UTC opening one org_task, an fn_outcome_open
-- record measured after 14 or 35 days, a kpi_miss agent_remediation and three practice cases; and
-- fn_emit_metric_alerts() on Monday 03:00 UTC emitting kpi.missed, goal.at_risk and metric.alert once
-- per day. record_type is an ACTIONABLE kind, runtime_eligible and deterministic are true, and the
-- keywords are the steps' own words.
--
-- HOW THE TEXT WAS CALIBRATED (no floor was lowered, no corroboration was weakened). workflow_dispatch
-- embeds "<workflow name> — <step> — <trigger context JSON>" and kb_embed stores title + content, each
-- truncated to 1200 characters. Every candidate was scored offline against ALL ELEVEN live trigger
-- contexts of the runs in flight, using the same free in-region gte-small through kb_embed's query mode:
--     step 1  own record wins 11/11 contexts, worst self-cosine 0.9223, worst margin 0.0158
--     step 3  11/11, worst self 0.9105, margin 0.0171      step 4  11/11, worst self 0.9203, margin 0.0324
--     step 5  11/11, worst self 0.9078, margin 0.0073      step 6  11/11, worst self 0.9149, margin 0.0176
--     step 7  11/11, worst self 0.9091, margin 0.0028
-- Step 1 already closed on SOP 01 at 0.873-0.888; its new record wins at 0.9223 so the step does not
-- regress onto a neighbouring rule now that five siblings exist.
--
-- SCOPE, and why two of the six are NOT scoped to Data & Experimentation. The workflow names `cpo` as
-- the actor of steps 4 and 5, and fn_org_agent_resolve('cpo') sits in department `exec`, whose
-- fn_dept_scope is {evolution, exec} — a data_intel record is INVISIBLE to it, so those two are scoped
-- to exec, the seat that performs them. Company scope was measured and rejected: at scope_type
-- 'company' these records outranked the strongest in-scope actionable record on improvement_lifecycle
-- steps 2 and 3 for the cto (0.8503 over 0.8402, 0.8704 over 0.8411) — another packet's workflow. With
-- department scope, 0 of the 166 other active workflow steps would be closed by any of these records.
--
-- STEP 2 DELIBERATELY HAS NO RECORD. It has a real low-risk reversible executor (ai_health,
-- action_class health_report), fn_workflow_step_sweep works it, and it has closed 11/11 with
-- used_llm false — the applier never sees it. Three candidate texts were calibrated for it and none
-- won its own step in more than 7 of 11 contexts against the six records here: at this model's
-- resolution "Instrument it with a measure that runs" is not separable from "Define the metric" or
-- "Measure on cadence". Adding a record that loses its own step would be decoration, so none is added.
--
--   node scripts/apply_sql.mjs scripts/sql/metric_lifecycle_playbooks_close_the_loop_model_off.sql --apply --ddl

begin;

-- step 1: Metric lifecycle — define the metric and why it matters
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, module, record_type, title, content, structured_data,
  implementation_status, validation_status, authority_tier, risk_level, version, keywords,
  escalation_rule, layer, jurisdiction, source_type, source_authority, source_freshness,
  confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status
) values (
  'ops-metric_lifecycle-define-the-metric-and-why-it-matters', 'department', 'data_intel', 'data_intel', 'metric_lifecycle', 'decision_rule',
  $qd$Metric lifecycle — define the metric and why it matters$qd$,
  $qd$Define the metric and why it matters. A metric that cannot be executed, owned and tied to a goal is not a metric at QuotesDone, it is a sentence. This rule decides whether a proposed metric is defined well enough to enter the lifecycle at all.

WHICH FIELDS DECIDE IT
- metric_definition.metric_key, .label, .definition, .domain, .owner_dept, .measure_sql, .target, .direction, .active — the company metric;
- employee_kpi.kpi, .metric, .measure_sql, .target_value, .unit, .cadence, .serves_goal, .serves_objective, .kpi_class — the same contract at the seat that owns it;
- company_goals and department_objective — what the metric exists to move.

THE DETERMINATION — a metric is defined only when every one of these is present
1. A label a non-analyst can read, and a definition that says what it counts AND what it excludes.
2. An executable measure_sql returning one number. If it cannot be executed it cannot be measured, and an unmeasurable metric is refused here rather than instrumented later.
3. A direction, 'up' or 'down' — the same number is a success or a failure depending on it.
4. A target with a documented basis for the number. A target invented to look reasonable is what later makes the root-cause step argue about the target instead of the work.
5. Exactly one accountable owner: metric_definition.owner_dept, or employee_kpi.agent_key for a seat KPI.
6. A cadence, so the measurement has a period and a next reading.
7. The goal or objective it serves — employee_kpi.serves_goal or .serves_objective resolving to an active company_goals or department_objective row. A metric that serves no active goal is trivia and is refused: this company runs ten departments, each with one north star, and a metric that moves none of them consumes attention without moving the business.

WHY IT MATTERS is part of the definition, not decoration: state which decision changes when this number moves. A metric nobody would act on is refused here.

ESCALATION
A proposal missing an executable measure, an owner, or an active goal is refused back to the proposer with the missing element named. A proposal that duplicates an existing metric_key is refused as a duplicate and the existing metric is revised instead. Nothing here reaches the founder; only refunds and over-cap Meta spend do.$qd$,
  $qd${"decides":"whether a proposed metric may enter the lifecycle","required_fields":["label","definition","measure_sql","direction","target","owner","cadence","serves_goal"],"refuse_when":["measure_sql not executable","more than one owner or none","serves no active goal","duplicate metric_key"],"output":"accepted definition, or a refusal naming the missing element"}$qd$::jsonb,
  'active', 'author_verified', 'supervised', 'low', '1.0',
  array['metric-definition', 'kpi', 'target-basis', 'owner', 'cadence', 'serves-goal', 'metric-lifecycle']::text[],
  $qd${"refuse_to":"proposer","when":"no executable measure, no single owner, or no active goal served","founder":"never"}$qd$::jsonb,
  'decision_playbook', 'AE', 'authored_expert', 'quotesdone_operating_model', 'stable',
  'internal', true, true, 'current', 'pending'
)
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  module = excluded.module, record_type = excluded.record_type, title = excluded.title,
  content = excluded.content, structured_data = excluded.structured_data,
  implementation_status = excluded.implementation_status, validation_status = excluded.validation_status,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level, version = excluded.version,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule, layer = excluded.layer,
  source_type = excluded.source_type, source_authority = excluded.source_authority,
  runtime_eligible = excluded.runtime_eligible, deterministic = excluded.deterministic,
  supersession_state = excluded.supersession_state,
  -- re-embed only when the embedded text (title + content) actually changed
  embedding_status = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then 'pending' else public.ops_knowledge.embedding_status end,
  embedding_gte    = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then null else public.ops_knowledge.embedding_gte end;

-- step 3: Metric lifecycle — measure on cadence and record the actual
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, module, record_type, title, content, structured_data,
  implementation_status, validation_status, authority_tier, risk_level, version, keywords,
  escalation_rule, layer, jurisdiction, source_type, source_authority, source_freshness,
  confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status
) values (
  'ops-metric_lifecycle-measure-on-cadence-and-record-the-actual', 'department', 'data_intel', 'data_intel', 'metric_lifecycle', 'decision_rule',
  $qd$Metric lifecycle — measure on cadence and record the actual$qd$,
  $qd$Measure on cadence and record the actual. At QuotesDone an actual is never asserted in prose: it is executed and stamped, and a metric with no execution has no actual. This rule decides the recorded actual for a metric in the metric lifecycle, and it is fully deterministic.

WHICH FIELDS DECIDE IT
- metric_definition.measure_sql, .target, .direction, .owner_dept, .active — the metric's contract.
- metric_snapshot.value, .error, .taken_at — the recorded actual. fn_bi_snapshot() executes every active metric_definition.measure_sql and inserts one metric_snapshot row per metric, keeping the error text when the SQL raises. Its cadence is the cron bi_snapshot_6h, 35 minutes past every sixth hour.
- employee_kpi.measure_sql, .target_value, .unit, .cadence, .actual_value, .measured_at and employee_kpi_history — the per-employee half. fn_employee_kpi_measure() runs daily at 03:30 UTC (cron employee_kpi_measure_daily), writes actual_value and measured_at from fn_kpi_scoreboard(), and upserts one employee_kpi_history row per (kpi_id, measured_on).

THE DETERMINATION
1. The actual is the LATEST metric_snapshot for this metric_key — v_bi_scorecard takes distinct on metric_key ordered by taken_at desc. Report the value with its taken_at; an actual without its timestamp is not evidence.
2. metric_snapshot.error is not null: the state is ERROR. That is an instrumentation defect, not a business miss. It must not be carried into variance detection and must not open a KPI task against an owner.
3. value is null, or target is null: the state is UNMEASURED. The metric is not instrumented yet, so the lifecycle goes back to instrumenting it, not forward to variance.
4. A measured zero is a real actual. Pre-launch this company reads 0 on most funnel metrics; 0 is a measurement, not a missing one.
5. The cadence is the metric's own, never the reader's. A weekly KPI measured today still carries last period's actual until its cadence turns, and re-running the measure inside a period replaces the snapshot for that period rather than adding a second reading.

ESCALATION
A metric whose measure_sql errors, or returns null, on two consecutive cadence periods is an instrumentation defect owned by Platform & Reliability: raise it there and report the metric as ERROR or UNMEASURED. Nothing in this step notifies the founder — only refunds and over-cap ad spend reach him.$qd$,
  $qd${"decides":"the recorded actual for one metric","reads":["metric_snapshot.value","metric_snapshot.error","metric_snapshot.taken_at","metric_definition.measure_sql","employee_kpi.actual_value","employee_kpi.measured_at","employee_kpi.cadence"],"executed_by":{"company_metric":"fn_bi_snapshot() — cron bi_snapshot_6h, 35 */6 * * *","seat_kpi":"fn_employee_kpi_measure() via fn_kpi_scoreboard() — cron employee_kpi_measure_daily, 30 3 * * *"},"states":{"error_not_null":"ERROR — instrumentation defect","value_or_target_null":"UNMEASURED","measured":"the value with its taken_at"},"output":"the actual, its taken_at, its cadence, and whether it is usable for variance"}$qd$::jsonb,
  'active', 'author_verified', 'supervised', 'low', '1.0',
  array['measurement', 'cadence', 'actual', 'metric-snapshot', 'bi-snapshot', 'employee-kpi', 'metric-lifecycle']::text[],
  $qd${"raise_to":"product_eng","when":"measure_sql errors or returns null on two consecutive cadence periods","founder":"never"}$qd$::jsonb,
  'decision_playbook', 'AE', 'authored_expert', 'quotesdone_operating_model', 'stable',
  'internal', true, true, 'current', 'pending'
)
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  module = excluded.module, record_type = excluded.record_type, title = excluded.title,
  content = excluded.content, structured_data = excluded.structured_data,
  implementation_status = excluded.implementation_status, validation_status = excluded.validation_status,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level, version = excluded.version,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule, layer = excluded.layer,
  source_type = excluded.source_type, source_authority = excluded.source_authority,
  runtime_eligible = excluded.runtime_eligible, deterministic = excluded.deterministic,
  supersession_state = excluded.supersession_state,
  -- re-embed only when the embedded text (title + content) actually changed
  embedding_status = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then 'pending' else public.ops_knowledge.embedding_status end,
  embedding_gte    = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then null else public.ops_knowledge.embedding_gte end;

-- step 4: Metric lifecycle — detect variance against target
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, module, record_type, title, content, structured_data,
  implementation_status, validation_status, authority_tier, risk_level, version, keywords,
  escalation_rule, layer, jurisdiction, source_type, source_authority, source_freshness,
  confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status
) values (
  'ops-metric_lifecycle-detect-variance-against-target', 'department', 'exec', 'exec', 'metric_lifecycle', 'decision_rule',
  $qd$Metric lifecycle — detect variance against target$qd$,
  $qd$Detect variance against target. The banding QuotesDone runs is already deterministic; this step states the band and the size of the gap against the target, it does not invent a threshold.

WHICH FIELDS DECIDE IT
- the actual: the latest metric_snapshot.value, with its taken_at, for this metric_key;
- the target and its sense: metric_definition.target and metric_definition.direction ('up' or 'down');
- for an employee KPI: employee_kpi.target_value, .unit, .cadence, and the attainment and verdict computed by fn_kpi_scoreboard().

THE DETERMINATION — a company metric, exactly as v_bi_scorecard bands it
- error is not null: ERROR. value is null or target is null: UNMEASURED.
- direction 'up': value >= target is ON_TARGET; value >= 0.7 * target is BEHIND; otherwise OFF_TARGET.
- direction 'down': value <= target is ON_TARGET; value <= 1.3 * target is BEHIND; otherwise OFF_TARGET.
- State the gap as target minus value for direction 'up', and value minus target for direction 'down'.

THE DETERMINATION — an employee KPI, exactly as fn_kpi_scoreboard computes it
- attainment = 100 * actual / target. Unit percent_max inverts it: least(100, 100 * target / actual).
- A target of 0 is a real target: it attains 100 when the actual is <= 0 and 0 otherwise.
- verdict: MET at attainment >= 100, NEAR at >= 90, MISSED below 90, NO DATA when the actual is null.

WHAT FOLLOWS FROM THE BAND
OFF_TARGET or MISSED is a variance and goes to root cause — is it the work or the target? — never straight to a target change. BEHIND is a variance under watch: record it, do not open a remediation. ERROR and UNMEASURED are instrumentation defects and must never be reported as an owner's miss. A MISSED employee KPI is already actioned by fn_kpi_review (weekly, Monday 04:00 UTC): one org_task per missed KPI, an outcome record opened by fn_outcome_open and measured after 14 days for a weekly cadence or 35 days otherwise, an agent_remediation of failure class kpi_miss, and three practice cases. Do not open a second task for the same metric; fn_kpi_review already refuses a duplicate by title.

ESCALATION
A metric that is OFF_TARGET and serves an active company goal raises goal.at_risk for its owner_dept — fn_emit_metric_alerts does this once per department per day, Monday 03:00 UTC, alongside one kpi.missed per metric and one metric.alert for the scorecard. A variance never reaches the founder; only refunds and over-cap Meta spend do.$qd$,
  $qd${"decides":"the variance band and the size of the gap","company_metric_bands":{"up":"value >= target ON_TARGET; value >= 0.7*target BEHIND; else OFF_TARGET","down":"value <= target ON_TARGET; value <= 1.3*target BEHIND; else OFF_TARGET","error":"ERROR","missing":"UNMEASURED"},"employee_kpi":{"attainment":"100*actual/target; percent_max inverts to least(100, 100*target/actual); target 0 attains 100 when actual <= 0","verdict":"MET >= 100, NEAR >= 90, MISSED < 90, NO DATA when actual is null"},"next":{"OFF_TARGET":"root cause","MISSED":"root cause; fn_kpi_review has already opened the org_task, outcome record and kpi_miss remediation","BEHIND":"record, no remediation","ERROR":"instrumentation defect to product_eng","UNMEASURED":"back to instrumentation"},"output":"band, gap, attainment, verdict, and whether it is an owner miss or an instrument defect"}$qd$::jsonb,
  'active', 'author_verified', 'supervised', 'medium', '1.0',
  array['variance', 'target', 'scorecard', 'attainment', 'off-target', 'behind', 'metric-lifecycle']::text[],
  $qd${"emits":"goal.at_risk for owner_dept when the metric serves an active company goal","by":"fn_emit_metric_alerts (Monday 03:00 UTC, once per department per day)","founder":"never"}$qd$::jsonb,
  'decision_playbook', 'AE', 'authored_expert', 'quotesdone_operating_model', 'stable',
  'internal', true, true, 'current', 'pending'
)
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  module = excluded.module, record_type = excluded.record_type, title = excluded.title,
  content = excluded.content, structured_data = excluded.structured_data,
  implementation_status = excluded.implementation_status, validation_status = excluded.validation_status,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level, version = excluded.version,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule, layer = excluded.layer,
  source_type = excluded.source_type, source_authority = excluded.source_authority,
  runtime_eligible = excluded.runtime_eligible, deterministic = excluded.deterministic,
  supersession_state = excluded.supersession_state,
  -- re-embed only when the embedded text (title + content) actually changed
  embedding_status = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then 'pending' else public.ops_knowledge.embedding_status end,
  embedding_gte    = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then null else public.ops_knowledge.embedding_gte end;

-- step 5: Metric lifecycle — root cause: is it the work or the target?
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, module, record_type, title, content, structured_data,
  implementation_status, validation_status, authority_tier, risk_level, version, keywords,
  escalation_rule, layer, jurisdiction, source_type, source_authority, source_freshness,
  confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status
) values (
  'ops-metric_lifecycle-root-cause-the-work-or-the-target', 'department', 'exec', 'exec', 'metric_lifecycle', 'decision_playbook',
  $qd$Metric lifecycle — root cause: is it the work or the target?$qd$,
  $qd$Root cause: is it the work or the target? A missed metric has exactly four possible causes at QuotesDone, and the work is the default. The target is presumed right until evidence says otherwise, because a company that revises the target whenever it misses has no targets.

WHICH FIELDS DECIDE IT
- the band and the size of the miss: v_bi_scorecard.state, and attainment from fn_kpi_scoreboard();
- the history: employee_kpi_history rows for this kpi_id — how many measured periods, and was the target ever met;
- the instrument: metric_snapshot.error and whether metric_definition.measure_sql changed since the target was set;
- the input: whether the upstream volume this metric depends on existed at all in the period;
- the owner: employee_kpi.agent_key and metric_definition.owner_dept, and employee_kpi.serves_goal.

THE DETERMINATION — classify into exactly one cause
1. INSTRUMENT. metric_snapshot.error is not null, or the actual is null, or measure_sql changed inside the period. The number is not evidence of anything. Owner: Platform and Reliability. No remediation against the metric's owner.
2. STARVED INPUT. The metric measures a stage whose upstream volume was zero or near zero in the period — pre-launch this is the honest cause of most funnel misses, and 0 paid reveals against a target of 40 with 0 inquiries is not the owner failing, it is the stage upstream having nothing to hand on. The accountable owner is the upstream department, not this metric's owner, and the remedy belongs to that department's goal.
3. EXECUTION. The input existed, the instrument is sound, and the work did not close the gap. This is the default when 1 and 2 are excluded. It is the only cause that justifies a remediation against the owner, and fn_kpi_review has already opened the org_task, the outcome record and the kpi_miss remediation for it.
4. TARGET MIS-SET. Allowed only on all three of: at least three consecutive measured periods, the target never met since it was set, and no documented basis for the original number. Absent any one of these the cause is not the target.

This step is gated for review, so the output is a recommendation with its cause class and its evidence, not the decision itself.

ESCALATION
Cause 4 on a metric that serves an active company goal goes to that goal's owner before any revision is proposed. Nothing here changes a target, and nothing here reaches the founder.$qd$,
  $qd${"decides":"which of four causes produced the miss","causes":{"INSTRUMENT":"snapshot error, null actual, or measure_sql changed inside the period — owner is product_eng, no remediation against the metric owner","STARVED_INPUT":"the upstream volume was zero or near zero in the period — the accountable owner is the upstream department","EXECUTION":"input existed and the instrument is sound — the default, and the only cause that justifies a remediation against the owner","TARGET_MIS_SET":"requires all three: >= 3 consecutive measured periods, never met since the target was set, and no documented basis for the number"},"output":"one cause class with its evidence, for the review gate"}$qd$::jsonb,
  'active', 'author_verified', 'supervised', 'medium', '1.0',
  array['root-cause', 'target', 'starved-input', 'execution', 'instrument', 'kpi-miss', 'metric-lifecycle']::text[],
  $qd${"gate":"review — the output is a recommendation, not the decision","raise_to":"the goal's owner when the cause is TARGET MIS-SET on a metric serving an active company goal","founder":"never"}$qd$::jsonb,
  'decision_playbook', 'AE', 'authored_expert', 'quotesdone_operating_model', 'stable',
  'internal', true, true, 'current', 'pending'
)
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  module = excluded.module, record_type = excluded.record_type, title = excluded.title,
  content = excluded.content, structured_data = excluded.structured_data,
  implementation_status = excluded.implementation_status, validation_status = excluded.validation_status,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level, version = excluded.version,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule, layer = excluded.layer,
  source_type = excluded.source_type, source_authority = excluded.source_authority,
  runtime_eligible = excluded.runtime_eligible, deterministic = excluded.deterministic,
  supersession_state = excluded.supersession_state,
  -- re-embed only when the embedded text (title + content) actually changed
  embedding_status = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then 'pending' else public.ops_knowledge.embedding_status end,
  embedding_gte    = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then null else public.ops_knowledge.embedding_gte end;

-- step 6: Metric lifecycle — revise the metric or retire it
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, module, record_type, title, content, structured_data,
  implementation_status, validation_status, authority_tier, risk_level, version, keywords,
  escalation_rule, layer, jurisdiction, source_type, source_authority, source_freshness,
  confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status
) values (
  'ops-metric_lifecycle-revise-the-metric-or-retire-it', 'department', 'data_intel', 'data_intel', 'metric_lifecycle', 'decision_rule',
  $qd$Metric lifecycle — revise the metric or retire it$qd$,
  $qd$Revise the metric or retire it. This is the authority-gated end of the metric lifecycle, and what may be changed is decided by the cause class the root-cause step produced, not by how uncomfortable the number is.

WHICH FIELDS DECIDE IT
- the cause class from root cause: INSTRUMENT, STARVED INPUT, EXECUTION or TARGET MIS-SET;
- what the metric serves: employee_kpi.serves_goal and .serves_objective, department_objective.goal_key, company_goals.active for metric_definition.owner_dept;
- the metric's contract: metric_definition.measure_sql, .target, .direction, .active, and employee_kpi.target_value, .unit, .cadence, .active.

THE DETERMINATION
- INSTRUMENT: revise the MEASURE. Correct measure_sql, leave the target untouched, and re-measure a full cadence period before reporting a variance again.
- STARVED INPUT: revise NOTHING on this metric. The metric is telling the truth. Record the upstream dependency and let the upstream department own the gap.
- EXECUTION: revise NOTHING. The remediation and the practice cases already opened by fn_kpi_review are the response; changing the target here would erase the company's own measurement of a real shortfall.
- TARGET MIS-SET: propose a revised target with the three pieces of evidence root cause required — the measured periods, the never-met history, and the absence of a documented basis for the original number. Never revise a target inside the period being reported, and never revise it downward to the current actual.
- RETIRE (metric_definition.active = false, or employee_kpi.active = false) only when the metric no longer serves anything: no active company_goals row for its owner_dept depends on it, no department_objective points at it, and no active employee_kpi carries it as serves_goal. A failing metric is never retired for failing; that is the one move that turns measurement into decoration.

This step is authority-gated: the output is the proposed revision or retirement with its evidence, for the authority that owns it, not the change itself.

ESCALATION
A target change on a metric that serves an active company goal goes to that goal's owner. A retirement that would leave a company goal with no measure is refused, and the goal's owner is told why. Nothing here reaches the founder; only refunds and over-cap Meta spend do.$qd$,
  $qd${"decides":"what may be changed, given the cause class","by_cause":{"INSTRUMENT":"revise the measure, not the target; re-measure a full cadence period before reporting variance again","STARVED_INPUT":"revise nothing — record the upstream dependency","EXECUTION":"revise nothing — the remediation already opened is the response","TARGET_MIS_SET":"propose a revised target with the three pieces of evidence; never inside the reported period, never down to the current actual"},"retire_only_when":["no active company_goals row for the owner_dept depends on it","no department_objective points at it","no active employee_kpi carries it as serves_goal"],"never":"retire a metric because it is failing","output":"the proposed revision or retirement, with its evidence, for the authority gate"}$qd$::jsonb,
  'active', 'author_verified', 'gated', 'high', '1.0',
  array['revise-target', 'retire-metric', 'authority-gate', 'goodhart', 'serves-goal', 'metric-lifecycle']::text[],
  $qd${"gate":"authority — the output is a proposal, not the change","raise_to":"the goal's owner for a target change on a metric serving an active company goal","refuse":"a retirement that would leave an active company goal with no measure","founder":"never"}$qd$::jsonb,
  'decision_playbook', 'AE', 'authored_expert', 'quotesdone_operating_model', 'stable',
  'internal', true, true, 'current', 'pending'
)
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  module = excluded.module, record_type = excluded.record_type, title = excluded.title,
  content = excluded.content, structured_data = excluded.structured_data,
  implementation_status = excluded.implementation_status, validation_status = excluded.validation_status,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level, version = excluded.version,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule, layer = excluded.layer,
  source_type = excluded.source_type, source_authority = excluded.source_authority,
  runtime_eligible = excluded.runtime_eligible, deterministic = excluded.deterministic,
  supersession_state = excluded.supersession_state,
  -- re-embed only when the embedded text (title + content) actually changed
  embedding_status = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then 'pending' else public.ops_knowledge.embedding_status end,
  embedding_gte    = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then null else public.ops_knowledge.embedding_gte end;

-- step 7: Metric lifecycle — report the measured actual, and the evidence behind it, to the executive who has to act
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, module, record_type, title, content, structured_data,
  implementation_status, validation_status, authority_tier, risk_level, version, keywords,
  escalation_rule, layer, jurisdiction, source_type, source_authority, source_freshness,
  confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status
) values (
  'ops-metric_lifecycle-report-the-measured-actual-and-its-evidence', 'department', 'data_intel', 'data_intel', 'metric_lifecycle', 'decision_rule',
  $qd$Metric lifecycle — report the measured actual, and the evidence behind it, to the executive who has to act$qd$,
  $qd$Report the measured actual, and the evidence behind it, to the executive that has to act on it. A report that carries a number without the evidence behind it is an opinion, and this company does not act on opinions.

WHICH FIELDS DECIDE IT
- who has to act: metric_definition.owner_dept and that department's head, or for an employee KPI the owner employee_kpi.agent_key and that agent's manager in org_agents — where the top of the org is its own department head, so a manager that resolves to nothing means the owner is the recipient;
- what is reported: metric_definition.metric_key and .label, the actual from metric_snapshot.value with its taken_at, .target, .direction, the band from v_bi_scorecard.state, and attainment and verdict from fn_kpi_scoreboard();
- the evidence: the metric_snapshot row behind the actual, the employee_kpi_history rows for the periods quoted, the cause class from root cause, and the revision or retirement decided at the authority gate.

THE DETERMINATION
1. Address exactly one accountable executive — the one who can act on the gap. A report addressed to everybody is addressed to nobody.
2. State the actual with its taken_at, the target, the band, the gap, and the cause class. Never a narrative without the timestamp of the reading it rests on.
3. State the cadence, so the reader knows when the next reading lands and whether acting now can move it.
4. ERROR and UNMEASURED are reported as instrumentation defects to Platform and Reliability, not as a business miss to the metric's owner.
5. The report is an internal record — the decision trace, the review queue row and the org insight. Reporting never sends an outbound email or WhatsApp to a customer, a supplier or the founder.

ESCALATION
When the metric is OFF_TARGET and serves an active company goal, the same reading is raised as goal.at_risk for its owner_dept, which fn_emit_metric_alerts emits once per department per day. Only refunds and over-cap Meta spend reach the founder; a scorecard reading never does.$qd$,
  $qd${"decides":"who receives the reading and what must be in it","recipient":"the head of metric_definition.owner_dept, or for a seat KPI the manager of employee_kpi.agent_key — the top of the org is its own department head","must_contain":["metric_key and label","actual with its taken_at","target and direction","band from v_bi_scorecard","attainment and verdict","cause class","the revision or retirement decided","the evidence rows behind the number"],"channel":"internal record only — decision trace, review queue, org insight","output":"one addressed reading with its evidence and its next reading date"}$qd$::jsonb,
  'active', 'author_verified', 'supervised', 'low', '1.0',
  array['report', 'evidence', 'accountable-executive', 'taken-at', 'scorecard', 'goal-at-risk', 'metric-lifecycle']::text[],
  $qd${"emits":"goal.at_risk for owner_dept when an OFF_TARGET metric serves an active company goal","never":"an outbound email or WhatsApp to a customer, a supplier or the founder","founder":"never"}$qd$::jsonb,
  'decision_playbook', 'AE', 'authored_expert', 'quotesdone_operating_model', 'stable',
  'internal', true, true, 'current', 'pending'
)
on conflict (record_id) do update set
  scope_type = excluded.scope_type, scope_key = excluded.scope_key, dept_key = excluded.dept_key,
  module = excluded.module, record_type = excluded.record_type, title = excluded.title,
  content = excluded.content, structured_data = excluded.structured_data,
  implementation_status = excluded.implementation_status, validation_status = excluded.validation_status,
  authority_tier = excluded.authority_tier, risk_level = excluded.risk_level, version = excluded.version,
  keywords = excluded.keywords, escalation_rule = excluded.escalation_rule, layer = excluded.layer,
  source_type = excluded.source_type, source_authority = excluded.source_authority,
  runtime_eligible = excluded.runtime_eligible, deterministic = excluded.deterministic,
  supersession_state = excluded.supersession_state,
  -- re-embed only when the embedded text (title + content) actually changed
  embedding_status = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then 'pending' else public.ops_knowledge.embedding_status end,
  embedding_gte    = case when public.ops_knowledge.title is distinct from excluded.title
                            or public.ops_knowledge.content is distinct from excluded.content
                          then null else public.ops_knowledge.embedding_gte end;

-- ---------------------------------------------------------------------------------------------------
-- RE-OPEN THE metric_lifecycle STEPS THAT PARKED FOR THE ABSENT KNOWLEDGE. fn_workflow_step_release
-- parks a step as disposition='awaiting_model' after three "no company playbook" attempts, and
-- fn_workflow_step_claim then refuses to claim it while the model is held. That refusal was correct
-- when nothing covered the step; the six records above are exactly the input it was waiting for, so the
-- park no longer describes reality. This clears the park for metric_lifecycle ONLY, and only for steps
-- whose recorded reason is the missing-playbook one — a step parked for any other reason is untouched,
-- and no step's status or run position is changed. Idempotent: a re-opened step no longer matches.
-- ---------------------------------------------------------------------------------------------------
do $$
declare v_n int;
begin
  update public.workflow_step_run sr
     set attempts = 0,
         error = jsonb_build_object(
           'reopened_at', now(),
           'reopened_by', 'metric_lifecycle_playbooks_close_the_loop_model_off.sql',
           'disposition', 'reopened',
           'reason', 'parked because no company playbook covered the step; six authored metric-lifecycle '
                     || 'records now cover steps 1 and 3 to 7, so the step is claimable again',
           'previous', sr.error)
    from public.workflow_run r
   where r.id = sr.workflow_run_id
     and r.workflow_key = 'metric_lifecycle'
     and r.status = 'running'
     and sr.status = 'ready'
     and sr.finished_at is null
     and coalesce(sr.error->>'reason', '') ~* '^no company playbook';
  get diagnostics v_n = row_count;
  raise notice 're-opened % metric_lifecycle step(s) parked for the absent playbook', v_n;
end $$;

commit;
