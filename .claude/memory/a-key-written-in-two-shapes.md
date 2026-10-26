---
name: a-key-written-in-two-shapes
description: "When the same logical key is stored in two shapes, a tool that resolves to the first match invents a deficit — sum every matching key."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8c3f363e-c107-4cc8-a2b7-67b6692cd25a
  modified: 2026-08-24T12:00:00.000Z
---

13 Aug 2026. `scripts/kb/audit_packs.mjs` reported *"TOTAL MISSING: 16608"* and *"91 files never
recorded"* against the knowledge corpus. Neither existed. `package_id` is written in two shapes and
`kb_stage.records` carries **both**: `QD-KB-002` = 667 records in 1 module (an early partial import)
and `QD-KB-002-mep-mechanical-electrical-plumbing-v2026.07.31` = 3,634 in 18. 667 + 3,634 = 4,301 =
exactly the disk count. `resolve()` returned the first match, and `dbByPkg.has(short)` is true, so it
compared the 667-row remnant against the full file and called the package short by 3,634 — six times
over. `file_hashes` is keyed **only** by the long shape, so every lookup under the short id missed.

Separately, the aggregate `*_all_records.jsonl` was skipped by one literal filename; QD-KB-086
numbers its aggregate `24_`, so that package double-counted itself exactly.

**Why:** the figure was about to become a budget — a 16,608-record re-import that would have been
pure waste. It also sat one query away from being reported to the founder as fact.

**How to apply:** before trusting any "missing / short / never recorded" count, check whether the
join key has more than one spelling: `select distinct <key> from <table>` on both sides. Resolve to
**every** matching key and sum; never take the first. And when a tool prints a zero, confirm it read
a non-zero input first — see [[absent-input-scores-as-satisfied]]. Sits with
[[a-verifier-that-reads-what-it-expects]]: on this codebase the instrument is wrong about as often
as the thing it measures.

---

24 Aug 2026 — TWO MORE INSTANCES IN ONE SESSION, both in Phase D and both the same shape: the
RECORD ID and the BUSINESS KEY of one `public.phase_d_object_record` row.

`fn_phase_d_step_context` resolves an IDENTIFIES context key (`safe_package_ref`,
`quote_revision_ref`, `comparison_id`) from `phase_d_scenario_record.canonical_ref->>'canonical_identity'`,
which for a PHASE_D_OBJECT_VIEW object is the **record id**. Two new predicates looked the same row
up by **business_key** and reported it absent:

    GATE-013   "package 550491 names no registered file revision"   — there was one, under the other key
    BR-018     "'550609' is not a live quotation_revision record"   — it was live, under the other key

Both were TRUE of the name they were given and FALSE of the row they were about. BR-012 already
resolved both shapes (`o.business_key = ref or 'supplier_safe_package:' || o.business_key = ref`),
which is exactly why **BR-012 passed and GATE-013 refused on the same package in the same drive** —
two predicates disagreeing in silence about the identity of one row.

**A new Phase D predicate that resolves an object from a context key must resolve every shape —
record_id, business_key, `object_id:business_key` — or it invents a hole.** Related:
[[instruments-report-on-the-wrong-subject]].
