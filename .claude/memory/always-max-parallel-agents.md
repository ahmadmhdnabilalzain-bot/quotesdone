---
name: always-max-parallel-agents
description: "Founder's standing rule — always use as many agents/parallelism as possible to go faster."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T20:32:45.031Z
---

The founder's standing instruction (1 Sep 2026): **"always use as much agents as possible to proceed faster."**

**Capped at 5 at once, with Sonnet for simple tasks** (1 Nov 2026, ledger 1417) — see [[max-five-agents]]. "As many as possible" means up to that cap.

**Why:** he wants throughput. Wall-clock speed matters to him, within the cap, because a spent weekly limit stops all work (see [[autonomous-company-is-the-standard]] and the ultracode default). A single-threaded pass through work he could have fanned out reads as slow.

**How to apply:** for any substantial build/audit/mapping/authoring task, reach for a `Workflow` with a wide fan-out (parallel/pipeline) rather than doing it serially or with a couple of agents. Prepare downstream steps (ingestion, scoping, verification) in parallel with a running workflow rather than waiting idle. Serial only for genuinely sequential dependencies or trivial one-shot edits.

**What parallel agents do to the gates (4 Sep 2026):** every agent applies to the ONE production
project, so until all their PRs merge, each PR's "repo and database agree" job sees the others'
live routines as drift (12 repo→prod, 6 prod→repo, 3 uncommitted DDL on the first batch). That red
is structural, not a defect: merge the agents' PRs on their real gates (kernel, Phase D, checks),
then run the canonical engine on main once. Main is not branch-protected, so a red parity job does
not block the merge. Give each agent a distinct area (tables, routines, crons) and tell it not to
re-apply older files over live bodies to "clear" sibling drift.

**Integrate through ONE tree (4 Sep 2026).** Five agent PRs each stayed red on parity/source-of-truth
because each branch lacked the others' applied routines. What worked: an `integration-<date>` branch
from main, merging every branch in order with `scripts/sql/MANIFEST.txt` resolved by union (both
sides, deduped) and regenerated files (full_schema.sql, CANONICAL_ROUTINE_MANIFEST.csv) taken from
either side and regenerated afterwards (`--write`, `--emit`, `--emit-ledger-sync`), then the full gate
set run once on that tree (0 findings) and one PR to main. Merge inside the agents' worktrees
(`.claude/worktrees/agent-*`, which hold their branches) — `git checkout -B <agent-branch>` in the
main tree fails with "already used by worktree" and `git push origin <name>` then pushes the worktree's
HEAD. Tell agents up front: register any re-enabled cron in phase_d_committed_scenario_cron, never
re-apply older files to clear sibling drift, append manifest lines idempotently.
