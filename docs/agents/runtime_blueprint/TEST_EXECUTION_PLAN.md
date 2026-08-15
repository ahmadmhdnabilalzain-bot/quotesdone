# Test Execution Plan

## 1. Deterministic tests — no OpenRouter calls

- role and alias resolution;
- manager graph;
- department inheritance;
- role-to-knowledge mapping;
- category overlay mapping;
- tool permission matrix;
- credential/adapter health states;
- trace schema/writer/read path;
- output schema validation;
- cost cap refusal;
- handoff state machine;
- no self-review;
- inactive identity refusal.

## 2. Small smoke

Run 30 cases only, selected across:

- 4 managers;
- 8 event operators;
- 6 on-demand specialists;
- 4 reviewers;
- 8 category overlays.

Do not retry professional errors. Preserve first attempt. Retry only proved infrastructure failures.

## 3. Targeted regression

Use builder-authored unseen cases for the known failure classes:

- tool not connected;
- wrong/unnecessary tool;
- missing trace;
- missing/wrong knowledge;
- cross-department handoff;
- role identity collision;
- output truncation;
- weak revenue/KPI causal link;
- infrastructure timeout/rate limit;
- unsafe action.

## 4. Cost report

Every run reports:

- requests;
- models;
- prompt/output/reasoning/cached tokens;
- actual usage cost;
- average/p95 cost per case;
- first-attempt success;
- retries;
- cache hit rate;
- stopped-by-budget count.
