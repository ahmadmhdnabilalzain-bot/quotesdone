# Current-Code Reconciliation Policy

Claude must create an implementation matrix before changing a component. Each requirement receives exactly one status:

- `EXISTING_BETTER_KEEP`
- `EXISTING_EQUIVALENT_KEEP`
- `EXISTING_PARTIAL_REPAIR`
- `MISSING_BUILD`
- `CONFLICTING_REPLACE`
- `INACTIVE_INTENTIONAL`
- `BLOCKED_BY_BUSINESS_DECISION`

## Evidence required to keep an existing implementation

An existing component is considered equivalent or better only when all are shown:

1. repository implementation;
2. real runtime caller;
3. staging deployment/database evidence;
4. behavioral success and denial tests;
5. observability and cost evidence;
6. no critical conflict with this architecture.

A table, prompt, function, tool registration or knowledge row without a consumer is not an implementation.

## Compatibility

Legacy role IDs may remain as read/input aliases. All new task, trace, KPI, authority, handoff and learning writes use canonical role IDs. Unknown and inactive identities fail explicitly.
