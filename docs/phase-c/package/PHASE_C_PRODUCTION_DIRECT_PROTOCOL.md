
# Phase C Production-Direct Protocol

There is no staging project. This does not permit uncontrolled production editing.

## Required sequence

1. Verify current `main`, clean tracked tree and Phase A/B approved baselines.
2. Capture a read-only production inventory and fingerprints.
3. Reconcile current code into the Phase C templates.
4. Build additive/compatible changes locally.
5. Run all source, type, SQL, graph, contract, mock-adapter and network-denial tests locally.
6. Create committed forward migrations, edge-function source, feature/config changes, exact rollback/redeploy instructions and checksums.
7. Commit before production.
8. Rehearse database changes using the exact committed SQL inside an aborted production transaction and prove the fingerprint is unchanged.
9. For Edge Functions or frontend, verify source hashes, build artifacts, deployment settings and rollback versions before deploying one component at a time.
10. Deploy database changes first where backward compatible, then runtime callers.
11. Immediately run all Phase A, Phase B and Phase C invariants against production.
12. Compare repo/deployed/database fingerprints and activation states.
13. Roll back the affected component immediately if any mandatory invariant fails.
14. Stop before Phase D.

## Prohibited

- OpenRouter or other paid inference;
- certification questions or answer keys;
- persistent synthetic customers/suppliers/inquiries/payments;
- live refund execution;
- external messages to real recipients;
- changing cron activation states unless a specific Phase C migration is required and founder-approved;
- enabling a previously disabled automation merely because it is mapped;
- changing Phase A/B frozen definitions;
- silent data deletion;
- uncommitted production SQL/code.

## Command Center deployment

The command center may be enabled only for the canonical founder identity. In Phase C it uses deterministic command routing/clarification and no paid model. Task creation and status operations must be live and auditable.

## Evidence

Return pre/post fingerprints, migration/rollback hashes, deployed component versions, invariant results, provider-network denial results and exact production mutations.
