---
name: a-merge-that-collapses-a-handoff
description: "Parking a persona whose Phase B step hands to/from its successor's step is refused by phase_b_handoff_two_parties; walk the handoffs before deciding a roster"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T16:34:02.008Z
---

The STAFF_ORG re-carve (3 Sep 2026, PACR-004) parked 34 personas; the Phase B handoff guard
refused 22 handoffs in W01, W02, W07, W21–W28, W30 because a parked persona's step handed to (or
from) a step owned by its successor, so both steps would have had one owner. 15 personas were kept
seated by a RULE that walks phase_b_handoff (sender first) until no collision remains — not by a
list. Net roster: 71 seated, 24 parked (plan wanted ~48).

**Why:** the founder's approved workflows treat those personas as distinct parties; a roster
decision cannot override a workflow design. Reaching ~48 means merging those 22 handoffs — a
Phase B workflow redesign he has not asked for.

**How to apply:** before parking/merging any role, run the collision query (map parked→successor
over phase_b_handoff from/to step owners); also expect these seams every time the org changes:
fn_role_identity_isolation_guard (a seat may not produce AND review one packaged department —
reviewer-auditor identities go to the successor's manager), org_role_identity convention (an inactive
employee holds NO identity rows; successors hold them as runtime_composite), org_agent_alias must
cover BOTH the agent key and the canonical role id of a parked persona, fn_dept_scope reads
org_departments.merged_into (re-parent legacy knowledge departments to a new department), the
kernel write guard on phase_c_task needs `set local kernel.maintenance_reason`, and
org_phase_baseline digests (A: departments/reporting_graph/workflow_ownership/organization; B:
structure subjects) must be recomputed in the same transaction (drop/recreate the append-only
trigger). The four files staff_org_recarve*_2026_09_03.sql are the worked example. See
[[the-org-is-ten-departments-now]] (superseded counts) and [[expectation-typed-into-its-own-check]].
