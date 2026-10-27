---
name: two-boards-one-subject-neither-right
description: "fn_kernel_trigger_state says 19 of 37 sources bypass the kernel and fn_kernel_cutover_measure says 0; the strict one cannot see table-trigger discharge, the lax one never checks the source reaches the trigger's table."
metadata: 
  node_type: memory
  type: project
  originSessionId: a0718a3f-8c12-4c09-9a8e-d518ddb85dd8
  modified: 2026-08-18T07:41:17.450Z
---

Two deployed boards answer "does this autonomous source reach the kernel" and disagree completely:

- `fn_kernel_trigger_state` → `active_autonomous_source_not_yet_routing_through_the_inbox` = **19 of 37**
- `fn_kernel_cutover_measure` → `active_sources_bypassing_the_kernel` = **0**

**Neither is right, and the green one is the weaker.**

`fn_kernel_trigger_state` asks: does some routine's `prosrc` contain this source key as a literal? That
misses the estate's actual discharge model — a table trigger discharges every surface that writes its
table, under the *trigger's own* key. `trg_inquiry_received` emits as
`dbtrigger:public.inquiries:trg_inquiry_received_a`, so `edge:customer_api` writing an inquiry does
reach the kernel and still counts as bypassing.

`fn_kernel_cutover_measure` resolves `phase_c_source_cutover.disposition_evidence` to a routine and
checks that routine calls the kernel. Real, but it **never checks the source actually writes the table
that trigger sits on**. Its `coverage_claims_with_nothing_behind_them` check verifies the routine
exists and reaches the kernel — not that anything connects the source to it.

Proved by `edge:inquiry_intake`, 18 Aug 2026: evidence `routine:trg_inquiry_received`, which fires on
`inquiries`. The function writes `inquiry_intake` (a draft table with **no triggers**) and `customers`.
It never touches `inquiries`. The claim is unsupported and the check passed it.

**The correct predicate is the conjunction:** the source writes table T, AND T carries a trigger that
reaches the kernel. The second half is measurable in `pg_proc`. The first half is not in the database
at all for an edge function or a frontend path — it needs a committed repo-side artefact, checked in
CI the way the component crosswalk is.

**How to apply:** do not quote either number as the coverage of the kernel cutover. Quoting 0 is
worse than quoting 19. A naive regex over the TypeScript is not good enough to build the artefact —
a first attempt missed `inquiries` in `customer_api`, which plainly references it, and a false
negative there marks a real bypass as covered.

Found alongside: `customer.registered` is an ACTIVE registered trigger type for **W04**, no trigger on
`customers` reaches the kernel, `fn_emit_customer_registered` names the event but never calls the
kernel, and **W04 has 0 runs ever**.

Related: [[instruments-report-on-the-wrong-subject]], [[connected-is-a-claim-not-a-measurement]],
[[a-filter-whose-values-a-path-never-wrote]], [[the-map-had-nothing-to-check-it-against]].
