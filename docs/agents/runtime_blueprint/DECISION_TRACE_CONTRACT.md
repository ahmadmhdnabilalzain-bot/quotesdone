# Decision Trace Contract

Every consequential or externally visible employee execution creates one append-only trace that conforms to `schemas/decision_trace.schema.json`.

## Mandatory coverage

The trace must identify:

- company and department objective;
- canonical role and manager;
- task and task class;
- knowledge IDs and versions;
- tools requested and actual results;
- evidence and assumptions;
- missing information;
- authority decision;
- confidence and uncertainty;
- model, tokens, caching and actual cost;
- decision/output;
- expected effect and review date;
- actual outcome and learning link later.

## Enforcement

- No consequential action without a non-null trace ID.
- A tool claim requires a successful tool result ID and hash.
- Completed traces are immutable; later annotations are append-only.
- Management and independent reviewers must be able to read traces.
- Trace creation failure blocks the action rather than running unobserved.
