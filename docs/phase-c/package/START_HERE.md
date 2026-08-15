
# QuotesDone Phase C — Runtime Connection & Founder Command Center

**Version:** 1.0.0  
**Deployment mode:** production-direct, no staging  
**Paid inference permitted:** no  
**OpenRouter budget:** USD 0.00  
**Production project:** `htdblwldjkcgjvmqkbeh`

## Purpose

Phase A froze **who exists**: 10 departments, 90 canonical accountable roles and 86 on-demand category overlays.

Phase B froze **how the company must work**: 30 workflows, 257 steps, 161 handoffs, rules, gates, states, exceptions, SLAs, events and founder boundaries.

Phase C connects the frozen organization and workflows to the real QuotesDone runtime:

- frontend and command-center actions;
- Edge Functions and APIs;
- database functions, triggers and state writers;
- cron jobs, queues, webhooks and event delivery;
- canonical actor resolution;
- workflow and task execution;
- authority and independent review;
- handoffs and SLAs;
- execution/decision traces;
- tool and knowledge interfaces;
- output, idempotency, retry and cost guards;
- the founder command channel through the Chief of Staff.

## Founder operating rule

QuotesDone is intended to operate fully autonomously.

The founder does **not** receive routine approval tasks. The only routine manual approval is a specific refund decision.

The founder may communicate with the Chief of Staff through the Command Center to:

- give an order;
- set or change priority;
- ask for status or explanation;
- cancel or supersede work;
- initiate a founder-reserved policy/constitutional change.

The Chief of Staff converts the instruction into an immediate command record and one or more tasks assigned to the exact canonical department and role. It does not perform another department's work itself.

## Read order

1. `PHASE_C_FROZEN_BASELINE_REFERENCE.json`
2. `PHASE_C_MASTER_SPEC.md`
3. `PHASE_C_FOUNDER_AUTONOMY_POLICY.md`
4. `PHASE_C_COMMAND_CENTER_ARCHITECTURE.md`
5. `PHASE_C_PRODUCTION_DIRECT_PROTOCOL.md`
6. `PHASE_C_INVARIANTS.md`
7. `CLAUDE_PHASE_C_MASTER_PROMPT.md`

## Strict boundary

Phase C uses deterministic code, mocks, recorded fixtures, local tests and aborted transactions only.

It must produce:

```text
OpenRouter requests: 0
Other paid inference requests: 0
Paid inference cost: USD 0.00
```

It must not run certification, professional-quality scoring or synthetic persistent business journeys. Those belong to later phases.
