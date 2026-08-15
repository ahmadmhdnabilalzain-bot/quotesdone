# Claude Code Master Implementation Prompt

Implement and verify the attached **QuotesDone Agent Runtime Connection Blueprint v2026.08.14** against the current QuotesDone codebase.

This package is the target connection architecture for:

- 10 departments;
- 90 accountable roles;
- 86 category overlays;
- tools, knowledge, traces, handoffs, models, output controls and cost governance.

## Decision rule

Do not replace a demonstrably better existing implementation. For every component, classify current code using `CURRENT_CODE_RECONCILIATION_POLICY.md`. Keep an existing design only when it has a real caller, behavioral evidence, observability and no conflict with mandatory invariants. Otherwise repair or build it.

## Non-negotiable failures to close

The previous certification exposed:

- tools called but no usable results;
- null decision traces;
- knowledge not retrieved;
- broken cross-department handoffs;
- wrong/unnecessary tool selection;
- truncated consequential answers;
- role identity sharing/collisions;
- weak connection between role decisions and company objectives;
- uncontrolled OpenRouter test spend.

Do not run the full certification while implementing this package.

## Work sequence

### 1. Reconcile current code

Create `docs/agents/runtime_connection_reconciliation.csv` with every package requirement and one status:

`EXISTING_BETTER_KEEP`, `EXISTING_EQUIVALENT_KEEP`, `EXISTING_PARTIAL_REPAIR`, `MISSING_BUILD`, `CONFLICTING_REPLACE`, `INACTIVE_INTENTIONAL`, or `BLOCKED_BY_BUSINESS_DECISION`.

### 2. Canonical organization

Validate and enforce:

- exactly 10 active canonical departments;
- exactly 90 accountable active roles;
- the runtime-mode counts in `ROLE_CONNECTION_MATRIX.csv`;
- 86 category overlays;
- 96 packaged knowledge identities resolved to active roles;
- no orphan knowledge;
- no reporting cycles;
- no self-review;
- aliases accepted on input only, canonical IDs written everywhere.

Do not blindly rename working identities. Preserve compatibility and historical records.

### 3. Connect the one runtime boundary

Every employee/task entry point must follow `RUNTIME_SEQUENCE.md`. Inventory all functions/endpoints that accept agent, actor, assignee, reviewer, manager, role or title. Canonical resolution must occur before context, knowledge, tools, authority, task assignment, review, KPI attribution, trace and learning.

Inactive or unknown identities must return explicit errors.

### 4. Tool broker

Implement `TOOL_REGISTRY.yaml`, `TOOL_POLICY_GROUPS.yaml` and `schemas/tool_result.schema.json`.

- no simulated tool result;
- no null success;
- no all-tools call;
- deterministic required/optional/forbidden selection;
- health, permission, timeout and retry states;
- result IDs/hashes in traces;
- fail closed when required evidence is unavailable.

Use existing adapters when equivalent and working.

### 5. Decision traces

Implement `DECISION_TRACE_CONTRACT.md` and its schema at the agent boundary. Every consequential or externally visible output/action must have a complete non-null trace before execution. Connect trace readers to management, independent review, KPI review and remediation.

### 6. Knowledge retrieval

Implement `KNOWLEDGE_RETRIEVAL_CONTRACT.md` through the actual agent runtime. Verify role, department, task and category knowledge retrieval with traced stable IDs. Do not load full ZIPs/prompts. Keep deterministic rules authoritative. Current facts require live tools.

### 7. Model routing

Implement `MODEL_CATALOG.yaml`, `MODEL_ROUTING_POLICY.yaml` and the exact role assignments in `ROLE_CONNECTION_MATRIX.csv`.

- verify all model IDs via the OpenRouter Models API before enabling;
- store verification timestamp;
- use no model for deterministic work;
- use role default only after task-class routing;
- independent review uses a separate role and normally a different model family;
- Opus 5 only on critical policy-triggered escalation;
- no silent expensive fallback;
- use `:exacto`/Auto Exacto for tool-sensitive tasks;
- enable prompt caching for stable context;
- record actual usage/cost.

If current code has a better measured model for a task class, retain it only with evidence and update the reconciliation matrix.

### 8. Category overlays

Connect all rows in `CATEGORY_OVERLAY_CONNECTION_MATRIX.csv`. Category overlays are internal expertise, not independent actors. They return structured requirements to `rfq_qualification_mgr` and cannot dispatch or override safety/regulation.

### 9. Cross-department handoffs

Implement the handoff schema and `CROSS_DEPARTMENT_HANDOFFS.csv`. A handoff must contain evidence, receiving owner, acceptance criteria, closure criteria, deadline and return state. One accountable owner remains until closure.

### 10. Output and truncation controls

Implement `OUTPUT_AND_TRUNCATION_POLICY.md`. Detect provider length stops and schema incompleteness. Never execute a truncated consequential output. Reduce irrelevant context and permit at most one controlled repair call by default.

### 11. Cost controls

Implement `COST_GOVERNANCE.yaml` and OpenRouter guardrails. Use dedicated keys. No full certification until approved. No spend above the configured key/task/run ceilings. Do not drain the founder's general key.

### 12. Tests

Follow `TEST_EXECUTION_PLAN.md` and `IMPLEMENTATION_ACCEPTANCE_GATES.md`.

Run deterministic zero-cost tests first. Then a 30-case smoke under USD 3. Stop immediately if its hard cap cannot be enforced. Only proceed to the targeted USD 20 regression after the smoke passes.

Do not use hidden certification questions or answer keys.

## Required evidence

Create:

- `docs/agents/runtime_connection_reconciliation.csv`
- `docs/agents/runtime_identity_coverage.csv`
- `docs/agents/tool_connectivity_report.md`
- `docs/agents/decision_trace_coverage.md`
- `docs/agents/knowledge_retrieval_coverage.md`
- `docs/agents/model_assignment_report.csv`
- `docs/agents/cross_department_handoff_report.md`
- `docs/agents/output_truncation_report.md`
- `docs/agents/cost_guardrail_report.md`
- `docs/agents/runtime_connection_test_evidence.md`

## Completion standard

Do not claim complete from created objects. Completion requires:

- all deterministic Gate A checks pass;
- the USD 3 smoke passes within budget;
- actual tools return results or explicit fail-closed errors;
- decision trace coverage is 100%;
- required knowledge retrieval is 100%;
- cross-department handoffs retain ownership and closure;
- output truncation is 0 in the smoke/regression suite;
- unsafe actions are 0;
- cost ceilings are proven impossible to exceed;
- no certification material was accessed;
- no production autonomy was activated merely because connections were repaired.

Continue implementation automatically between work packages. Ask the founder only for an irreducible commercial or policy decision.

Return final branch, commit, implementation statuses, exact metrics, remaining blockers and the recommended next independent test size/budget.
