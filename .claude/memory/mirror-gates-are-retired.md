---
name: mirror-gates-are-retired
description: Since 3 Sep 2026 no CI gate compares production to a committed copy of itself; production proves its own properties. Never re-emit a CSV to make a check green.
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T19:18:03.681Z
---

Founder, 3 Sep 2026: "the consistent failure with those 2 kernel gates … is a design issue." It was:
the Phase C/D jobs kept the truth twice (production + committed mirrors) and every real change
reddened them until the copies were re-emitted (re-carve: 1 file/1 h of change, 6 files/4 h of
copies). Retired in PR #495 (`docs/agents/RETIRED_MIRROR_GATES.md`): the component crosswalk CSV +
SQL declaration literals (two jobs), ownership-ledger `source_file` = manifest order, Phase D
deliverables byte-for-byte, `pccr_approval_matches_committed_tables`, Phase A/B baseline-digest
drift as a gate, the nine Phase C binding CSV=table id sets.

**Why:** a check may compare production to a PROPERTY (owner exists, reviewer independent, step
executes); it may not compare production to a COPY kept in git.

**How to apply:** new gate = `scripts/checks/phase_c_components_are_owned.test.mjs` (every
component's role active, dept active and the role's, active cron/subscription/edge function IS a
component). Its first run found 4 unowned crons + 10 undeclared subscriptions the mirror never saw.
`fn_kernel_system_trace_state` now counts a firing as NEW from the job's `wrapped_at`, not the epoch
(`a_trace_is_required_from_the_moment_the_door_exists.sql`) — wrapping a job with a long raw history
no longer reports its past as missing traces. Do NOT run `--emit` on the crosswalk, do NOT recompute
`org_phase_baseline` digests, do NOT hand-edit Phase D CSVs to green a gate; regenerate snapshots
only when a reader wants a current copy. `kernel-boards.json` ratchets are for gaps that can only
fall — never a growth counter. Supersedes the mirror bookkeeping in [[a-merge-that-collapses-a-handoff]]
and the crosswalk steps in [[the-cron-command-no-longer-names-the-routine]].
