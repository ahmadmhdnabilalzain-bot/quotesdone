# Real-employee runtime

A model is not an employee. An employee is a persistent business object whose model is only one replaceable skill.

## Required employee fields

- employee key, title, department and manager;
- responsibilities and prohibited actions;
- delegated authority, monetary ceiling and data-access scope;
- primary KPIs and target values;
- quarterly, weekly and daily objectives;
- open workload and SLA;
- available typed tools;
- approved knowledge scopes;
- default task/model profile;
- performance history;
- mistakes and lessons;
- current improvement plan;
- reputation and autonomy level;
- report cadence and escalation route.

## Closed operating loop

### 1. Observe

Read current events, assigned work, KPI variance, backlog, cost, customer/supplier feedback and exceptions. Do not ask a model to rediscover facts already available through SQL.

### 2. Diagnose

Classify the problem using deterministic thresholds first. Retrieve only the relevant knowledge and previous lessons. Generate possible causes, with evidence and confidence.

### 3. Plan

Create a typed action plan containing:

- expected KPI impact;
- cost and maximum exposure;
- risk;
- authority check;
- canary/control group where appropriate;
- stop condition;
- verification query;
- rollback/compensation.

### 4. Review

The manager or automated policy reviewer checks quality, policy, budget, duplication and evidence. Low-risk approved patterns may pass automatically. Material or novel actions require the defined authority tier.

### 5. Act

Call an allow-listed executor. Every external action uses an idempotency key and writes an event before and after execution.

### 6. Verify

Confirm that the action really occurred using the target system, not the model's own statement.

### 7. Measure

After the measurement window, compare the result with the baseline/control and record the result in the outcome ledger.

### 8. Report

The employee sends a compact report to the manager: work completed, KPI movement, failures, cost, lessons, next action and escalations.

### 9. Learn

Promote successful tactics into approved playbooks. Retire failed tactics. Regulated knowledge changes remain proposals until approved.

## Authority levels

- **A0 Observe:** may read and report only.
- **A1 Recommend:** may propose actions and experiments.
- **A2 Reversible execution:** may perform low-risk actions with canary limits.
- **A3 Standard execution:** may perform proven workflows inside budget and policy.
- **A4 Gated:** money, legal status, privacy, security, supplier bans, public claims and irreversible actions require human or executive approval.

Autonomy is earned per action class—not granted to an entire model or employee forever.
