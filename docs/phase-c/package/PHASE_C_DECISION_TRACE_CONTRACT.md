
# Decision and Execution Trace Contract

## Principle

A plausible output is not evidence that the system used the correct employee, authority, workflow, evidence or tool. Traceability is part of execution, not optional reporting.

## Required trace layers

- founder command trace;
- workflow run trace;
- step execution trace;
- role decision trace;
- review/verdict trace;
- tool invocation trace;
- system execution trace;
- handoff trace;
- state-transition audit.

## Consequential decision minimum

- trace ID;
- command/task/workflow/step links;
- canonical actor and manager;
- system actor/executor;
- object ID/version;
- evidence references/hashes;
- applicable rules/gates;
- authority result;
- reviewer identity and independence result;
- assumptions/uncertainty fields when later used;
- proposed action and outcome;
- state before/after;
- output hash;
- event IDs;
- status and timestamps.

Model/provider/token/cost fields may be null in Phase C because paid inference is prohibited. The schema must support them for later phases.

Completed trace rows are append-only or versioned. Correcting a trace creates an annotation or superseding record; it does not rewrite historical evidence.
