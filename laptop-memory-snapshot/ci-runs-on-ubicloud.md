---
name: ci-runs-on-ubicloud
description: "Founder 6 Oct 2026 (ledger 1135): all GitHub Actions jobs run on Ubicloud runners to cut cost; every new workflow uses the same runs-on expression"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-05T21:20:05.802Z
---

"from now on always use ubicloud to cut cost from github" (6 Oct 2026). GitHub-hosted Actions cost $28.95 on 5 Oct alone.

**Why:** Ubicloud runners are much cheaper. The Ubicloud GitHub app is installed on all of the founder's repos, under the Ubicloud project "Default".
**How to apply:**
- Every job uses `runs-on: ${{ vars.RUNNER || 'ubicloud-standard-2' }}` (PR #1233). Any new workflow uses the same line and never bare `ubuntu-latest`.
- To revert, set the repo variable `RUNNER` to `ubuntu-latest`.
- Ubicloud does not help during a GitHub Actions dispatch outage: on 5–6 Oct jobs stayed queued with 0 runners requested, because GitHub itself wasn't dispatching.
- Workflow-file PRs are hand-merged (the release train's app lacks the workflows permission).
