---
name: expectation-typed-into-its-own-check
description: A check whose expected value is a literal in its own body is a rubber stamp after any approved change; read the approved baseline instead.
metadata:
  type: feedback
---

`fn_phase_b_invariants` carried **fifteen** count literals (`'161'`, `'47'`, …). When PBCR-001
legitimately moved handoffs 161 → 159, the only way to make the check pass again was to retype the
numbers — and the person retyping them is the person who changed the architecture.

**Why:** an expectation and the thing it measures must not be editable by the same hand in the same
change. Literals are; an append-only approval record is not.

**How to apply:** point the expectation at `org_phase_baseline`, which sits behind
`fn_org_phase_baseline_append_only` and can only be moved by a PACR file that drops the trigger in
the open. Then: approved amendment → both move, green honestly; unapproved change → fails; editing
the check → nothing to edit. Make a **missing** baseline FAIL, never pass — see
[[absent-input-scores-as-satisfied]]. Done in `scripts/sql/kernel_k15_invariants_read_the_baseline.sql`.
