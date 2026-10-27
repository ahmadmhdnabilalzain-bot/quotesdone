---
name: closing-a-grant-makes-a-record-stale
description: "Revoking EXECUTE changed what a derivation reads, so a recorded classification went stale and a board went red minutes later — and the guard refused the minimal write."
metadata: 
  node_type: memory
  type: project
  originSessionId: ba4ede58-946f-4477-8042-69cef19ee057
  modified: 2026-08-20T03:15:33.278Z
---

20 Aug 2026. E4 revoked EXECUTE from 57 SECURITY DEFINER routines. Within minutes
`fn_kernel_component_exposure_state.external_entry_disagrees_with_derivation` went **0 → 3 of 149**.

The board compares a **recorded** column (`phase_c_component.external_entry`) against a value
**derived** from the catalogue (`fn_kernel_component_reachability`). Changing a permission changes
the derivation, so every recorded row that was recorded *because of* that permission becomes a stale
claim in the same transaction. The three were exactly K11's "3 publicly reachable" bucket, promoted
on 16 Aug for one reason — a PUBLIC grant.

**Why:** a permission is an input to a classification, not just an access control. Anything that
records "this is reachable" has a dependency on the grant that nobody writes down.

**How to apply:** after any grant/revoke sweep, re-run the estate's board set before assuming you are
done — see [[twenty-one-boards-read-them-all]]. Two more things this cost:

- `a00_phase_c_component_classification_guard` **refused** the minimal write: its clause is
  `if new.classification like 'ACTIVE\_%' and not v_reachable then raise`, message "record what is
  true; do not relabel the row". You cannot fix only the column the board checks; the guard forces
  the honest wider write. That is the guard being right — see [[a-disposition-is-not-a-behaviour]].
- `phase_c_component`'s frozen digest covers `classification` and `activation_state` but **not**
  `external_entry`. So the minimal write would have been invisible to `fn_phase_c_freeze_drift()` and
  the honest one is not. Record the amendment, never overwrite the digest —
  [[an-expectation-typed-into-its-own-check]].
