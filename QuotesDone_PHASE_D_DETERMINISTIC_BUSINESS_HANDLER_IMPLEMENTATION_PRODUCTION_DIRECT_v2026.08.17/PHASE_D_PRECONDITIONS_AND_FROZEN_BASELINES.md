# Phase D Preconditions and Frozen Baselines

## Stop conditions

Claude must stop before modifying code or production unless:

1. A fresh independent Phase C audit returned `PHASE_C_FINAL_ACCEPTANCE_PASS`.
2. Phase C is founder-approved, checksummed and tagged.
3. `main` contains every definition deployed to production.
4. Repository→production and production→repository application drift are zero.
5. The working tree is clean except founder-disclosed pre-existing files.
6. All paid-provider routes are held closed.
7. The Phase D test process cannot call a paid provider.
8. Current Phase A, effective Phase B and Phase C fingerprints are recorded.

## Frozen Phase A

Phase D may not silently alter the 10 departments, 90 roles, 86 overlays, reporting lines, role classes, reviewer independence or founder-reserved decisions.

## Frozen effective Phase B

Phase D may not silently alter the 30 workflows, 257 steps, owners, handoffs, rules, gates, states/transitions or founder boundaries.

The effective baseline includes PBCR-001:

- W14-S05 accountable role: `quote_evaluation_specialist`;
- runtime alias may resolve as `quote_evaluation`;
- relevant category overlay is a contributor and cannot own the task.

Any genuine Phase A, B or C defect requires a formal change request.

## Phase C dependency

Phase D must use the canonical Phase C kernel. It may not create another workflow engine, task engine, cancellation path, outbox, trace ledger, approval system or command router.

## Live effective registry export

The packaged Phase B CSVs are source references. Before implementation Claude must export the live founder-approved effective registries and prove the frozen counts/hashes, PBCR-001 and zero unapproved drift.
