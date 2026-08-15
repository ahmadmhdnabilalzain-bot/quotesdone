# QuotesDone Phase B — Complete Business Workflow Architecture

**Package version:** 2026.08.15  
**Execution mode:** production-direct, zero paid inference  
**Dependency:** founder-approved Phase A organization

## Phase B objective

Phase B freezes the complete business-process architecture of QuotesDone.

It defines:

- the 30 canonical company workflows;
- all 257 required workflow steps;
- the accountable owner of every step;
- contributors and independent reviewers;
- start events and required end states;
- business objects and records;
- workflow and step state machines;
- allowed transitions;
- hard gates;
- handoff contracts;
- exception and escalation paths;
- internal SLA/timer policies;
- canonical business rules;
- founder-reserved boundaries;
- closure, cancellation, expiry, retry and supersession behavior;
- the reconciliation method for existing code paths.

## Phase B does not include

Do not work on:

- professional knowledge;
- knowledge retrieval;
- tools or provider connections;
- OpenRouter or model selection;
- prompts;
- decision traces;
- runtime orchestration;
- agent intelligence quality;
- synthetic customers or suppliers;
- Playwright journeys;
- certification;
- paid inference;
- activation of autonomous workflows.

Those belong to later phases.

## Authoritative counts

- 30 canonical workflows
- 257 canonical workflow steps
- 90 canonical standing roles represented
- 86 category overlays governed
- 161 owner-to-owner handoffs
- 47 cross-department handoffs
- 56 canonical business objects
- 54 canonical business rules
- 50 exception/escalation patterns
- 34 SLA/timer policies
- 32 hard or phase-boundary gates
- 347 canonical business events
- 14 workflow states and 35 allowed workflow transitions
- 11 step states and 19 allowed step transitions

## Required reading order

1. `PHASE_B_PRODUCTION_DIRECT_PROTOCOL.md`
2. `PHASE_B_MASTER_SPEC.md`
3. `PHASE_B_INVARIANTS.md`
4. `CLAUDE_PHASE_B_MASTER_PROMPT.md`
5. Machine-readable registries
6. Individual workflow files in `workflows/`

## Zero-cost rule

Phase B must finish with:

```text
OpenRouter requests: 0
Paid model requests: 0
Paid inference cost: USD 0.00
```

## Founder approval boundary

Phase B may reconcile and deploy the structural workflow registry. It may not reopen Phase A, activate new automation, or begin Phase C without founder approval.
