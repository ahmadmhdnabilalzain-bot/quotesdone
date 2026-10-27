---
name: ci-runs-on-ubicloud
description: "SUPERSEDED 26 Oct 2026 by ci-runs-locally-ubicloud-stopped (ledger 1279). Was: founder 6 Oct 2026 (ledger 1135), all GitHub Actions jobs run on Ubicloud runners."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-26
---

**SUPERSEDED 26 Oct 2026.** Ubicloud is stopped, and there is no paid CI, GitHub Actions included,
until the bugs are cleared. The session runs the checks itself. Read
[[ci-runs-locally-ubicloud-stopped]]. Everything below is history, kept so the `runs-on` expression
in the workflow files can be understood.

---

"from now on always use ubicloud to cut cost from github" (6 Oct 2026). GitHub-hosted Actions cost $28.95 on 5 Oct alone.

**Why (then):** Ubicloud runners are much cheaper. The Ubicloud GitHub app is installed on all of the founder's repos, under the Ubicloud project "Default".
**How it was applied:**
- Every job uses `runs-on: ${{ vars.RUNNER || 'ubicloud-standard-2' }}` (PR #1233).
- To revert, set the repo variable `RUNNER` to `ubuntu-latest`. Do not do this while the 26 Oct ruling stands.
- Ubicloud does not help during a GitHub Actions dispatch outage: on 5–6 Oct jobs stayed queued with 0 runners requested, because GitHub itself wasn't dispatching.
- Workflow-file PRs are hand-merged (the release train's app lacks the workflows permission).
