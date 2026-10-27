---
name: scope-is-not-attachment
description: A rule scoped to ALL and anchored to nothing cannot be checked — resolve scope to concrete targets and label how each was anchored.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: da613f58-5cf3-4795-ab24-f89cb598e1b2
  modified: 2026-08-15T08:48:27.982Z
---

15 Aug 2026, closing Phase B. GATE-008 "Closure completeness" carried `workflow_scope = 'ALL'`,
so on paper it governed all 30 workflows including W22. Asked to confirm it was *attached* to
W22's closure step, I could not: there was no row anywhere saying GATE-008 → W22-S07. Scope said
"everywhere"; nothing said "here".

**Why:** a rule that applies to everything and points at nothing is unfalsifiable. You cannot
query which step it guards, cannot test that it fired, and cannot show a reader it is enforced —
so it reads as covered while covering nothing in particular. Same family as
[[finished-capability-with-no-entry-point]]: the thing exists, and no path reaches it.

**How to apply:** resolve scope into concrete (rule, workflow, step) rows, and label each row
with HOW it was anchored — `declared_step_property` when the registry itself identifies the step,
`universal` when it genuinely governs every one, `workflow_scope` when no finer anchor is
declared, `phase_level` when it is not a step rule at all. The label is the honest part: without
it a derived attachment gets displayed as a declared one, which is the same defect one level up.

Then the claim becomes a query:

```sql
select * from public.fn_phase_b_gate_attachment() where gate_id='GATE-008' and workflow_id='W22';
```

**Corollary for freezes.** Phase A's freeze guard compares COUNTS, so swapping two managers while
keeping the head-count identical passes the trigger. Phase B's compares the DIGEST of each frozen
subject, so an owner swap is refused at the moment it is written. If you freeze something, freeze
its content, not its cardinality — and force the guard to fire before believing it
([[zero-cannot-tell-a-dead-guard-from-an-idle-system]]).
