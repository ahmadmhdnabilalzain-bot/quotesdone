---
name: session-briefs-carry-misdiagnoses
description: Brief COUNTS are reliable; brief DIAGNOSES have now been wrong six times. Always re-measure the mechanism before building the fix the brief proposes.
metadata: 
  node_type: memory
  type: project
  originSessionId: 198f60c3-c25a-4d37-845c-efd7f7799cb2
  modified: 2026-08-12T13:23:38.258Z
---

The founder's session briefs give accurate numbers and unreliable explanations of them. Six
measured instances, four of them on 12 Aug 2026 alone — and in every case the count was exact:

- "513 decisions a week, 33 outcomes — add expected_kpi_id/direction/measure_after to
  `decision_log`" → 1,584 of 1,603 rows are `action_gate` permission checks. `decision_log` needed
  no columns. The real defect was 17 high-confidence lessons manufactured from 4 readings.
- "`agent_brain`'s split looks for three `# LAYER` markers that `fn_agent_context_capped` trims
  away" → two of the three strings have **never existed**, and fixing them alone would have been
  worse than nothing because the prefix was not byte-stable.
- "most executors emit nothing to extract" → `action_worker` emits on 254 of 254; it says
  `outcome` and the extractor listened for `recommendation`/`deliverable`/`note`.
- "~4,000 leads match no trade — grow the taxonomy or declare them out of scope" → 514 were lost
  to a hyphen (`building-materials` vs the alias `building materials`).

**Why:** the brief is written from the previous session's last measurement, and the mechanism
behind a number is usually inferred rather than probed.

**How to apply:** take the count as given, re-derive the cause before writing any fix, and say so
plainly in the commit when the brief was wrong. Cheapest probes: run the function against real
input and compare to the claim; check whether the string being matched exists at all; ask whether
the "broken" path has ever executed. See [[instrument-measuring-wrong-subject-is-the-lens]],
[[guarded-by-a-condition-that-cannot-occur]] and [[never-state-what-you-have-not-measured]].
