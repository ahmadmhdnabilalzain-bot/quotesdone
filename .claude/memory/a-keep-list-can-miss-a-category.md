---
name: a-keep-list-can-miss-a-category
description: "hold_all_automation.sql argued a keep-list \"cannot silently miss a job\" — it cannot, but it missed a CATEGORY, stopping every governance monitor it said it was preserving."
metadata: 
  node_type: memory
  type: project
  originSessionId: e0e7f847-fa0a-4a92-8b70-4d836e3022fe
  modified: 2026-08-16T08:50:36.742Z
---

`scripts/sql/hold_all_automation.sql` (16 Aug 2026) holds the company on the founder's instruction
and states its own principle plainly: *"standing the workforce down is not blinding the
infrastructure or switching off its safety controls"*, keeping `control_mode_sweep_5min` because it
is *"a security control, not work"*.

Its implementation is an eight-name allow-list. It stopped **every governance monitor the company
has** — policy consistency, autonomy audit, approval trace audit, decision conflict scan, regulation
watch, three security audits, and the AI spend guard.

**Why:** the file's argument was that a keep-list cannot silently miss a job where a stop-list can.
True, and it did not miss a job — it missed a CATEGORY, silently, because nothing compared the eight
chosen names against the principle they were chosen to express. A rule and its implementation can
disagree while both look deliberate.

**How to apply:**
- When a file states a principle and then implements an explicit list, check the list against the
  principle. That comparison is the defect class, not the list's completeness.
- Partial resume (16 Aug): 14 internal jobs — the 9 monitor jobs, the spend guard, and 4 internal
  report generators. All are single in-database function calls, no HTTP, no sender.
- **`email_cron_2min`, `sms_flush` and `wa_flush` are the only three paths out of this system.**
  While they are off, nothing any resumed job produces can reach anyone outside the company. That is
  what makes a partial resume safe rather than merely argued — assert it, and refuse to resume if
  any of them is active.
- Intake, dispatchers, department AIs, the task approver, execute sweeps and the knowledge/learning
  loops stay held: he said wait for his workflow. 183 of 205 jobs remain off.
- Row #3 checks that read `cron.job.active` (`RAN`, `MONITOR`, `LAST_OK` in
  `scripts/staging/os2_blueprint/`) go red the moment automation is held. That is the checks being
  correct, not broken. See [[deactivation-is-not-death]].
