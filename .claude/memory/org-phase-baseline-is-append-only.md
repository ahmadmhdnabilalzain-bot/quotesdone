---
name: org-phase-baseline-is-append-only
description: "A PACR that re-freezes org_phase_baseline must drop a00_org_phase_baseline_append_only, recompute every digest in place, and recreate the trigger in the SAME transaction."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 70bbee7f-3c64-46d9-869f-716c4d48b72e
  modified: 2026-08-31T23:45:26.799Z
---

`public.org_phase_baseline` carries a BEFORE DELETE OR UPDATE trigger `a00_org_phase_baseline_append_only` (fn `fn_org_phase_baseline_append_only`) that REFUSES any UPDATE to a frozen phase row. Its own error hint is the protocol: a Phase change request drops the trigger, makes the change with every digest RECOMPUTED IN PLACE (never a transcribed hash — use the same expressions `fn_phase_a_baseline_drift()` uses), recreates the trigger in the same transaction, and is appended to `scripts/sql/MANIFEST.txt`. The dropped-then-recreated trigger in the file is the record that the freeze was opened deliberately. (PACR-001 predates this trigger and does NOT drop it; do not copy PACR-001's baseline UPDATE verbatim.)

Worked example: `scripts/sql/pacr_002_the_real_company_reporting_shape.sql`. A reporting-edge change does NOT trip the count-scoped `z90_phase_a_freeze` — what catches it is `fn_phase_a_baseline_drift()` + `fn_phase_c_reporting_map_drift()` in CI/acceptance, so re-record `phase_c_reporting_authority` (manager_role_id + every reporting_path re-walked from the new live graph) too. Verify all three drifts + `fn_phase_a_organization_violations()` = 0 by aborted-tx probe before applying. See [[the-window-between-apply-and-merge]].
