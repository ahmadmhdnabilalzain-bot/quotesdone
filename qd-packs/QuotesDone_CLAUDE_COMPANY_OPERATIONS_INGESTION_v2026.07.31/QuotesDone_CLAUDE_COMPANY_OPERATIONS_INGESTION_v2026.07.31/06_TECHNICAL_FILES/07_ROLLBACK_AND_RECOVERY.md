# Rollback and recovery plan

## Import rollback

- Every import has a unique `ingestion_run_id`.
- Records retain package version and content hash.
- Promotion must copy or map records through versioned migrations.
- To roll back staging, delete or mark records by ingestion run.
- Never delete prior approved knowledge versions without a retention decision.

## Runtime rollback

- Keep new workflows and rules disabled until activation.
- Activate by department or workflow behind a feature flag.
- Preserve the previous prompt, policy, rule and workflow versions.
- Use canary traffic and defined stop thresholds.
- On failure, disable the new path, restore the previous version and reconcile in-flight cases.

## Data recovery

- Confirm backup and restore before destructive migration.
- Do not rely on a backup that has not been restored in a drill.
- PDPL erasure may be intentionally irreversible; verify identity, scope, legal retention and file list before execution.

## Incident rollback report

Record:

- change and version;
- trigger;
- affected entities;
- rollback time;
- data reconciliation;
- residual risk;
- corrective action;
- regression test.
