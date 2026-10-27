---
name: the-sweep-finds-what-the-increment-missed
description: "Three times in the kernel rebuild the estate-wide sweep caught a defect the increment's own gate had passed — run the whole invariant board after every apply, not just the new check."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 953dddc0-0434-4402-8342-dd32e9bf3929
  modified: 2026-08-16T23:36:00.550Z
---

Every one of these passed its own increment's rehearsal and was caught only by the end-of-session
sweep across the whole estate:

1. **K5 retyped `first_failure` to timestamptz** and left `first_failure = ''` inside
   `fn_phase_c_invariants`, taking all 71 checks and `fn_phase_c_baseline_drift` to 22007. The K5
   rehearsal ran the KERNEL invariants, not the Phase C ones.
2. **K2b moved `fn_founder_command_submit` onto the kernel and left `fn_founder_command_clarify`
   behind.** Answering a clarification still created 4 tasks, 0 runs, 0 outbox rows — the old shape
   on the one path nobody migrated. Found by verifying the K9 UI change end to end over HTTP.
3. **`fn_kernel_workflow_start` wrote the run trace at creation and nothing advanced it** when the
   entry step run moved the run to `active`. `founder_command` had had that guard since K6;
   `phase_c_workflow_run` never got one.

**The pattern:** a rule that exists for one subject and not its sibling, and an increment whose gate
only measures the thing it just built.

**How to apply:** after every apply, run the ESTATE's boards — `fn_phase_c_invariants()`, every
`fn_kernel_*_state()`, `fn_kernel_trace_integrity()`, Phase A/B drift — not only the new one. And
when you add a guard to one table, immediately ask which sibling table has the same lifecycle and no
guard. Also: `apply_sql.mjs` matched dollar tags with `/\$[a-z_]*\$/`, so any tag with a digit
(`$s3_cron$`) failed to parse and reported six byte-identical routines as DIFFERS — a guard that
cries wolf gets the next real drift waved through.

Related: [[freeze-the-population-before-the-write]], [[green-pr-does-not-mean-deployable]],
[[two-files-one-routine-one-commit]], [[finished-capability-with-no-entry-point]].
