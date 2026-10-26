---
name: filter-values-written-by-a-path-that-never-ran
description: "A status filter can be unsatisfiable because its values come from a writer that has never executed — check the live distinct values, not the enum."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8c3f363e-c107-4cc8-a2b7-67b6692cd25a
  modified: 2026-08-13T12:23:52.153Z
---

`fn_supplier_capability_chase` — the only mechanism that asks a supplier to confirm their scope —
ran on cron 24 times and sent 0 emails. Its loop required
`review_status in ('insufficient','awaiting_confirmation')`. The live distinct values across all
15,306 rows were `derived` (15,305) and `confirmed` (1). Both filtered-for statuses are written by
exactly one place: `capability_agent`'s `analyze` action, which reads uploaded documents — a path
no scraped directory lead has ever taken.

**Why:** this is a distinct sub-shape of [[guarded-by-a-condition-that-cannot-occur]]. The guard is
not logically impossible and the values are legal in the schema; they are simply produced only by
code that has never run for this population. Reading the enum, the CHECK constraint or the writer's
source all look fine. Only `select distinct <col>, count(*)` shows it.

**How to apply:** for any routine that selects on a status/kind/type literal, run
`select distinct <col> from <table>` and intersect. If a literal is absent, find its writer and ask
whether that writer has ever executed for this population. And when fixing: do not just add the
observed value to the list — ask what the right population is. Adding `'derived'` here would have
cold-emailed 15,305 scraped leads; the correct gate was the relationship (`leads.claimed`), not a
status. Check now lives in `scripts/checks/capability_chase_guard_is_satisfiable.test.mjs`.
