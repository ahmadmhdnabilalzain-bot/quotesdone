
# Phase C Master Specification — Runtime Connection & Command Center

## 1. Frozen inputs

Phase C may not redesign Phase A or Phase B.

Expected frozen baseline:

- 10 active departments;
- 90 canonical standing roles;
- 86 category overlays;
- 30 workflows;
- 257 workflow steps;
- 161 handoffs;
- 54 business rules;
- 32 gates;
- 50 exception patterns;
- 34 SLA policies;
- 347 canonical events.

Any required organizational or workflow change must be raised as a formal Phase A or Phase B change request. Phase C may not silently change ownership, sequence, reviewer independence, founder boundaries, states, rules or gates.

## 2. Phase C question

For every runtime component, Phase C must answer:

> Which frozen workflow and step does this component serve, which canonical role is accountable, which system actor executes it, which authority applies, which evidence is written, and how can it be observed, retried, stopped and rolled back?

A table, function, edge function, cron job, agent, queue or UI button that cannot answer that question is not connected.

## 3. Required runtime layers

### 3.1 Canonical identity boundary

Every current actor input must resolve before any current action:

```text
canonical role ID
legacy agent key
merged key
packaged role identity
approved title alias
system actor
→ one active canonical role or explicit refusal
```

Resolution occurs before:

- context assembly;
- task assignment;
- authority evaluation;
- reviewer selection;
- knowledge scope selection;
- tool authorization;
- workflow ownership;
- KPI attribution;
- state mutation;
- trace writing;
- learning/remediation.

Unknown or inactive identities fail explicitly. New writes use canonical IDs only. Historical reads preserve original actor information.

### 3.2 Founder Command Center

Use the existing Command Center/OS where possible. Do not create a competing executive console.

The human-facing command secretary is the canonical `chief_of_staff` role. The UI may label the interface **Founder Command Secretary — Chief of Staff** without creating a new employee.

A founder message must follow:

```text
founder authenticated message
→ immutable message record
→ command interpretation interface
→ exact registered intent/workflow target or clarification
→ command plan
→ immediate canonical task creation in the same transaction
→ exact department/role assignment
→ manager and SLA monitoring
→ progress/status back to command center
→ closure summary
```

No raw natural-language message may directly execute a side effect.

Phase C implements the interface and a deterministic command registry/parser. Paid model interpretation is disabled. Low-confidence input asks one concise clarification and creates no task.

### 3.3 Workflow engine

One authoritative workflow engine must:

- create workflow runs from registered start events;
- enforce the frozen state model;
- activate only the correct next steps;
- bind one canonical owner per step;
- enforce prerequisites, gates and founder boundaries;
- preserve first attempt and retry history;
- block invalid transitions;
- close only when required closure criteria pass;
- emit canonical outbox events;
- create compact or full traces according to policy.

Existing better implementations may remain, but duplicate/conflicting engines must be retired or routed into the canonical boundary.

### 3.4 Task engine

Every work item must contain:

- task ID;
- source command/event/workflow;
- workflow/step where applicable;
- canonical accountable role;
- manager;
- objective;
- required inputs;
- requested output;
- acceptance criteria;
- closure criteria;
- priority;
- due date/SLA;
- dependencies;
- reviewer requirement;
- authority class;
- idempotency key;
- state;
- blocker and resolution owner;
- trace IDs.

No generic `Director`, code-runner name, service-role name or unresolved alias may own a task.

### 3.5 System actors versus accountable roles

The technical executor and business owner are different fields.

Example:

```text
executed_as: service_role
system_actor: system.scheduler
accountable_role: supplier_retention_specialist
workflow_step: W19-Sxx
```

A system actor may execute code but may never replace the accountable employee.

### 3.6 Executor registry

Every Edge Function, DB function, trigger, cron job, webhook, queue consumer, event subscriber and state-changing frontend action must have:

- component ID and implementation;
- entry method/caller;
- activation state;
- system actor;
- accountable role and department;
- workflow and step;
- action/authority class;
- side-effect and risk class;
- idempotency strategy;
- retry policy;
- rollback/compensation;
- trace policy;
- tests and evidence.

Known Phase B gaps to close include:

- active/scheduled execution paths without canonical accountability;
- Edge Functions with no caller or external entry classification;
- runtime workflows with no runs or no canonical step binding;
- W21 lacking a runtime implementation;
- canonical workflows present only as registries rather than executable runtime paths.

Previously executed but currently inactive machinery is not automatically dead. Each path must be classified:

- `CANONICAL_KEEP`
- `CANONICAL_BETTER_KEEP`
- `WIRE_TO_CANONICAL`
- `DUPLICATE_PATH`
- `CONFLICTING_PATH`
- `NO_CALLER_UNCLASSIFIED`
- `INACTIVE_HISTORICAL`
- `REPAIR_BEFORE_REACTIVATION`
- `INTENTIONALLY_RETIRED`
- `PHASE_D_CORRECTNESS_GAP`

No active state-changing component may remain unowned or unclassified.

### 3.7 Event outbox and delivery

Business state changes write events and state atomically through an outbox. Event delivery is asynchronous and idempotent.

Every event must have:

- canonical event ID;
- workflow and object version;
- producer;
- accountable role;
- primary consumer;
- payload contract;
- dedupe key;
- delivery status and attempts;
- dead-letter behavior;
- trace links.

A delivery failure must not pretend the business action succeeded. A retry cannot duplicate a side effect.

### 3.8 Handoff runtime

Every one of the 161 frozen handoffs must have a runtime writer/receiver or an explicit deferred implementation status.

The sender retains accountability until the receiver accepts a complete packet. Rejection must state the missing/invalid item and return owner. Every handoff has an SLA and closure evidence.

### 3.9 Authority, review and approval

All non-refund company operations run autonomously through internal authority and independent-review rules.

Founder manual approval is permitted only for `refund_decision`.

Founder-reserved strategic/constitutional changes are `founder_initiated_only`: agents may research or propose, but they do not generate routine founder approval queues and cannot execute without an explicit founder command.

Unknown action classes fail closed.

Reviewer assignment resolves aliases before checking independence. The same effective employee cannot create and approve the same consequential output.

### 3.10 Decision and execution traces

Every externally visible, consequential, state-changing or official role output must have a trace. Phase C defines meaningful trace-required populations rather than mixing unrelated rows.

A completed consequential action without a trace is impossible.

Traces capture identity, workflow/step, evidence, authority, review, input/output hashes, state transition, system actor, task/command links and status. Model-specific fields may remain empty while paid AI is disabled.

### 3.11 Tool boundary

Phase C connects and inventories the tool-adapter boundary but does not perform paid provider testing.

Every tool adapter must have:

- stable tool ID;
- authorized roles;
- input/output schema;
- side-effect classification;
- timeout/retry/idempotency;
- health status;
- explicit empty/error result;
- audit/trace behavior;
- secrets boundary;
- mock/recorded fixture.

A null response cannot mean success. A role cannot claim a tool result without a stored result ID/hash.

### 3.12 Knowledge scope interface

Phase C does not add or certify professional knowledge. It connects the deterministic interface that maps:

```text
role + department + task + workflow + category + jurisdiction + company stage
→ permitted knowledge scopes
```

The interface must expose missing/orphan scope errors, preserve source/version metadata and record retrieved IDs when later used. It must not call embeddings or paid models in Phase C.

### 3.13 Output and truncation

Every handler has a versioned output contract. Structured responses validate before state mutation.

Incomplete/truncated output cannot be executed. Phase C tests truncation with fixtures, not paid models.

### 3.14 Management and autonomy

Managers receive tasks, progress, blockers and KPI/closure evidence. They can assign, reassign, remediate and close work within authority.

The founder is not the company's task queue. Routine uncertainty is resolved through internal evidence, specialist consultation, reviewer verdict, manager decision, or fail-closed blocking.

Only refunds create founder approval tasks.

## 4. Command immediacy

A safely routable founder command must create its command plan and immediate tasks in one database transaction before the API returns.

The response must include:

- command ID;
- interpretation/status;
- workflow IDs;
- task IDs;
- primary owner;
- child owners;
- priority;
- due date/SLA;
- any clarification or blocker.

Downstream execution may be asynchronous. Command/task creation may not be lost in an uncommitted queue.

## 5. Phase C exclusions

Phase C does not:

- change Phase A organization or Phase B workflows;
- import or improve professional knowledge;
- choose final paid models;
- call OpenRouter or other paid inference;
- run V3 certification;
- create persistent demo customers, suppliers, inquiries or payments;
- activate disabled business automation merely because it is now mapped;
- prove professional judgment quality;
- claim launch readiness.

Those belong to later phases.

## 6. Definition of done

Phase C is complete only when the actual codebase has one canonical runtime connection path, every active component is accountable and classified, founder commands create exact tasks, founder approvals are limited to refunds, traces/handoffs/events/authority are wired, and every zero-cost invariant passes in production after committed transactional rehearsal/deployment.
