# QuotesDone Phase D — Deterministic Business-Handler Implementation

**Version:** 2026.08.17  
**Deployment model:** production-direct, incremental, reversible  
**Paid inference:** prohibited  
**Primary objective:** implement and prove the real business handler behind every frozen Phase B workflow step.

## Mandatory precondition

Do not begin Phase D until a fresh independent session has returned:

`PHASE_C_FINAL_ACCEPTANCE_PASS`

and the founder has approved, checksummed, tagged and frozen Phase C.

If Phase C is not frozen, stop. Do not use Phase D to hide or bypass a Phase C defect.

## Phase D scope

Phase D converts the frozen organization, workflows and execution kernel into functioning deterministic application code:

- 30 workflows;
- 257 workflow steps;
- effective handoffs reconciled against the live frozen registry;
- 56 business objects;
- 54 business rules;
- 32 hard gates;
- 347 canonical events;
- customer, supplier, admin and internal operational handlers;
- frontend/API/database/storage connections;
- authorization, RLS, state transitions, idempotency, failure handling and rollback;
- mocked capability and provider boundaries where later intelligence or external delivery is required.

## Phase D is not

- knowledge ingestion or professional-agent training;
- tool/model assignment;
- OpenRouter testing;
- V3 certification;
- persistent demo-account simulation;
- live external messaging;
- live payments or refunds;
- activation of autonomous business jobs merely because code exists.

## Read order

1. `PHASE_D_PRECONDITIONS_AND_FROZEN_BASELINES.md`
2. `PHASE_D_MASTER_SPEC.md`
3. `PHASE_D_HANDLER_ARCHITECTURE.md`
4. `PHASE_D_PRODUCTION_DIRECT_PROTOCOL.md`
5. `PHASE_D_ZERO_COST_AND_PROVIDER_POLICY.md`
6. `PHASE_D_IMPLEMENTATION_WAVES.md`
7. `PHASE_D_TEST_AND_ACCEPTANCE_PLAN.md`
8. `PHASE_D_DEFINITION_OF_DONE.md`
9. `CLAUDE_PHASE_D_MASTER_PROMPT.md`

The builder may end only with `PHASE_D_READY_FOR_FOUNDER_APPROVAL` or `PHASE_D_NOT_READY`.
