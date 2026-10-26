---
name: workflow-ownership-frozen-in-both-baselines
description: "A workflow's owner/reviewer/contributors is frozen in BOTH the Phase A and Phase B baselines; changing it is a combined PACR+PBCR."
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T03:22:54.748Z
---

Changing a workflow's `accountable_role_id`, `independent_reviewer` or `contributors` drifts **two**
baselines, not one:

- **Phase A** `registry_sha256->'workflow_ownership'->'database'` — a sha256 over
  `org_workflow_ownership` (`workflow_id|workflow_name|accountable_role_id|contributors(;-joined)|independent_reviewer`),
  the exact expression in `fn_phase_a_baseline_drift()`. `org_workflow_ownership` has NO write-time guard,
  only this drift check.
- **Phase B** `registry_sha256->'structure'->'workflow_ownership'->'database'` — from
  `fn_phase_b_structure_digest()` over `phase_b_workflow`, which IS guarded at write time by
  `z90_phase_b_freeze` (needs `set local app.phase_b_change_reason`).

So it is a combined **PACR + PBCR**. The recipe (see `scripts/sql/pbcr_003_*` and `pbcr_004_*`), in ONE tx:
set both `app.phase_a_change_reason` and `app.phase_b_change_reason`; update BOTH `org_workflow_ownership`
and `phase_b_workflow`; `drop trigger a00_org_phase_baseline_append_only`; `jsonb_set` the two `'database'`
digests IN PLACE (PA computed inline with the drift formula, PB from `fn_phase_b_structure_digest` where
subject='workflow_ownership'); recreate `a00`. Also update the two docs CSVs
(`docs/phase-a/PHASE_A_WORKFLOW_OWNERSHIP.csv`, `docs/phase-b/PHASE_B_WORKFLOW_REGISTRY.csv`) for spec
honesty — no CI gate reads them, drift reads the DB digest. REHEARSE the whole tx in an aborted probe
first: both `fn_phase_a_baseline_drift()` and `fn_phase_b_baseline_drift()` must return 0 and
`fn_phase_a_organization_violations()` must stay 0. [[org-phase-baseline-is-append-only]]

`fn_phase_a_baseline_drift` does NOT check `organization_sha256` (only counts + the five registry
digests), so a change to `public.workflow_step` (which IS in organization_sha256) does not drift it.
W01's reviewer is the **founder** (the human apex, not in org_role) — legitimately excluded from any
"reviewer resolves to a role / cross-department" check.
