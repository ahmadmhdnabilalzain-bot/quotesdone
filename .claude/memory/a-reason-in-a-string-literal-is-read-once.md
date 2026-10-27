---
name: a-reason-in-a-string-literal-is-read-once
description: Move "why this did not run" out of the function body into a register the build can contradict.
metadata:
  type: feedback
---

`fn_phase_d_run_injected_defects()` carried each case's blocker as a text literal inside the
function. That is where a stale reason hides best. The fix, 24 Aug 2026:
`public.phase_d_injected_defect_disposition` (defect_id, disposition, reason,
what_would_make_it_executable), with length floors so a row cannot restate the id, and
`build_injected_defect_result.mjs` failing the build **both ways** — a case that did not run and has
no row, and a row that survives a case that has since closed.

**Why:** a reason in a register can be diffed and contradicted. A reason in a string literal is read
once, by whoever wrote it.

**How to apply:** whenever a check reports "N not run, each with a named blocker", ask where the
name lives and who re-reads it. See [[a-blocker-is-a-claim-too]].
