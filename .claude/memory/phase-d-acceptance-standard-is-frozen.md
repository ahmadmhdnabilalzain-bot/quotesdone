---
name: phase-d-acceptance-standard-is-frozen
description: "From 24 Aug 2026 the Phase D acceptance target is one frozen document; no audit may add a gate, move a denominator or promote a disclosure without a founder-approved change request."
metadata: 
  node_type: memory
  type: project
  originSessionId: f9a36089-6fc5-4d31-8137-ab97b324a4b4
  modified: 2026-08-24T21:31:10.822Z
---

The founder stopped the changing Phase D acceptance process on **24 Aug 2026**. Eight Phase D
independent acceptance reports had each measured a partly different set. One standard now governs:

`docs/phase-d/PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1.md` — seven frozen baselines as preconditions,
**two** remaining repair gates (FD-01 governance approval authenticity = PCCR-006; FD-02
consequential output domains), a 30-item regression set freezing the 13 gates the 24 August audit
passed with each script's committed sha256, four non-blocking disclosures, change control, and three
termination states.

Authoritative baseline: `audit/phase-d-final/PHASE_D_FINAL_INDEPENDENT_ACCEPTANCE_2026-08-24.md`,
sha256 `18606dd9f98797b7…` — committed, because a frozen standard whose baseline is untracked is not
frozen.

**After his approval:** no new mandatory gate, no changed denominator, no widened pass condition, no
disclosure reinterpreted as a gate — except through `PHASE_D_ACCEPTANCE_STANDARD_CHANGE_REQUEST`
with six required elements. **Removed:** the builder must no longer declare founder approval before
the independent audit; the builder's terminal state is `PHASE_D_READY_FOR_INDEPENDENT_AUDIT` and
approval comes after a pass.

**Why:** an audit finding that becomes a gate by being written down makes the target unreachable by
construction. Findings are findings; gates change only by his decision.

**How to apply:** before treating anything as a Phase D blocker, check it is in §B or §C of that
document. If it is only in a brief, a handover or an audit's findings list, it is a repair, not a
gate. One denominator legitimately moves — the `scripts/sql/phase_d_*.sql` file count — and §C says
so. Related: [[never-state-what-you-have-not-measured]], [[a-blocker-is-a-claim-too]],
[[session-briefs-carry-misdiagnoses]].
