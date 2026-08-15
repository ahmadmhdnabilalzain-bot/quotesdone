# Phase B Unresolved-Decision Policy

Claude should resolve routine process-architecture questions using:

1. Founder-reserved decisions;
2. Phase A organization;
3. the canonical business model;
4. the 30 workflow specifications;
5. safety, privacy, financial and legal invariants;
6. existing code when it is demonstrably equivalent or better.

Ask the founder only when a decision would:

- alter a founder-reserved commercial rule;
- reopen Phase A;
- change who pays whom;
- create a public service promise or contractual SLA;
- accept material legal/financial/security/privacy risk;
- require a new country/market;
- create an unapproved binding commitment.

Technical implementation, table names, migration shape, registry design, deterministic constraints and reconciliation mechanics are Claude's responsibility.

Unresolved runtime wiring is not a Phase B founder decision. Record it as `PHASE_C_WIRING_GAP`.
