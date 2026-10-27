---
name: ci-runs-locally-ubicloud-stopped
description: "Founder 26 Oct 2026 (ledger 1279): Ubicloud is stopped; no paid CI, GitHub Actions included, until the bugs are cleared; the Claude session runs the checks and actions itself. Supersedes ci-runs-on-ubicloud (ledger 1135)."
metadata:
  type: feedback
  modified: 2026-10-26
---

**The ruling, 26 Oct 2026 (ledger 1279):** *"Ubicloud is stopped. No paid service for CI, GitHub
Actions included, until the bugs are cleared. Claude sessions do the checks and actions themselves;
GitHub Actions comes back once the bugs are cleared."*

This supersedes [[ci-runs-on-ubicloud]] (6 Oct, ledger 1135).

**What it means in practice:**
- A PR has **no GitHub CI status** to wait for. "CI green" now means: the session (normally the
  release operator) ran the checks locally on the PR's head and they passed, and it says so in the
  PR with the commands and the exit codes.
- The local gate is `npm run gate` (`scripts/ci/local_gate.mjs`, PR #1597). Beyond it, the set is the one in the `quotesdone-session` and
  `quotesdone-organised-like-an-auditor-will-read-it` skills: `node scripts/checks/run.mjs`,
  `npm test` (redirect to a file and echo `$?`, never pipe to `tail`),
  `canonical_routine_manifest.mjs`, `export_from_either_source_is_identical.mjs`,
  `verify_deploy_parity.mjs`, `deno check` for edge functions, and the build.
- Anything a workflow used to do on merge (edge-function deploys, post-deploy smokes, scheduled
  jobs run by Actions) is done by the session by hand, or it does not happen. Do not assume a deploy
  or a smoke ran because a PR merged.
- Vercel's own build still reports a status on PRs; that is Vercel, not Actions, and it is not the
  check suite.
- The merge-chain rules in [[never-merge-on-a-red-check]] and
  [[a-merge-chain-must-read-status-contexts-by-state]] still apply to whatever statuses remain
  (Vercel). Gate the merge on the local run's exit code as well.
- Do not re-enable Actions, add a runner, or point `RUNNER` anywhere until the founder says the bugs
  are cleared.

**In a Claude cloud container (27 Oct 2026, it_engineer):** no Docker, a 13.4 GB memory cgroup and an egress
proxy that refuses cdn.jsdelivr.net. The gate handles all three itself: otp-race on a throwaway local Postgres
cluster, the +esm import type-checked from npm at the same version (the row says so), heavy steps on
memory-sized lanes (running them all at once got scan-redact and scan-takeoff OOM-killed, which looked like a
failing test). A step whose host is refused (dwg needs cdn.jsdelivr.net for its WASM) is NOT RUN, which fails
the verdict: only the founder can allow the host (cloud environment network settings). The management API
429s when several sessions share the token; db.mjs backs off, so do not parallelise the production steps.

Related: [[github-is-the-single-source-of-truth]], [[ci-green-does-not-mean-npm-test-green]].
