---
name: an-assertion-written-with-the-same-mistake
description: "A migration verified its own rewrite with a string match containing the identical quoting bug, so it passed and broke 46 cron jobs; verify by execution, never by comparing two things you wrote in one breath."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e0e7f847-fa0a-4a92-8b70-4d836e3022fe
  modified: 2026-08-16T08:50:21.220Z
---

16 Aug 2026. A migration rewrote 46 cron job URLs and got SQL quote escaping one level too deep,
writing `key = ''project_ref''` into every command — a syntax error that would have failed all 46 on
their next firing, including `backup_daily` and the uptime/health probes the stand-down deliberately
kept running.

The file's own verification passed, because it asserted the rewritten commands matched
`key = ''project_ref''` — written with the same doubled escaping as the defect. Assertion and bug
came from one mistaken belief about quoting, so they agreed, and agreement was read as proof.

**Why:** this repo already states the principle in
`scripts/checks/authority_gate_single_source.test.mjs` — *"a guard that restates its subject proves
only that somebody typed the same thing twice."* A string comparison between two things the same
author wrote in the same breath verifies nothing at all.

**How to apply:**
- Verify a rewrite by EXECUTING what it produced, not by matching text. For a URL: run the
  expression and assert the resolved value equals what the job had before. For a command: `EXPLAIN`
  it (plans without running). Both catch what a string match cannot.
- Use dollar-quoting (`$q$…$q$`) for any SQL that contains SQL. Three separate quoting mistakes in
  one session, one of them into production; every one would have been impossible with `$q$`.
- When a check refuses code you believe is correct, suspect the CHECK first: an earlier version of
  this same assertion flagged the three jobs that were *already* portable, because it compared
  formatting rather than the property. See [[never-state-what-you-have-not-measured]] and
  [[a-rehearsal-proves-creation-not-execution]].
- `scripts/checks/every_cron_command_still_parses.test.mjs` now holds this: 46 URLs evaluated, 171
  commands planned, and the 34 DO/CALL commands that cannot be planned are NAMED, not counted as
  checked.
