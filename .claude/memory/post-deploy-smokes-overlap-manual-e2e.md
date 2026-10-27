---
name: post-deploy-smokes-overlap-manual-e2e
description: "Every deploy to main starts an \"IT engineer post-deploy smoke\" that runs E2E against the one production DB; a manual E2E must first check no smoke is running, or their fixtures and leftovers() counts collide"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T23:15:01.905Z
---

**26 Oct 2026:** GitHub Actions is off ([[ci-runs-locally-ubicloud-stopped]]), so no post-deploy smoke
starts on merge. The overlap rule still holds for any E2E run another session starts by hand.

**What happened, 14 Sep 2026.** A helper started E2E journeys a–e (run tag b4d25f10) at 23:02:30Z to prove a teardown
left `leftovers()` = 0. At 23:02:31Z the "IT engineer post-deploy smoke" workflow, triggered by the #681 deploy at
23:01Z, opened its own E2E run (`qd_run:eac8b5e2`) against the same production database. The two ran at the same time.
The helper's result was still clean, but a second window was left open, holding fixture customers, leads and
notifications until its run finished. Earlier that night a crashed run left `qd_run:19e25f67` open for hours, which
silences the failed-run watcher for up to 6 hours.

**Why it matters:** there's only one database (no staging). Concurrent E2E runs can:
- count each other's fixtures in `leftovers()`;
- tear down rows the other still needs;
- make a pass or fail meaningless.

**How to apply:**
- Before any manual E2E, check that no `IT engineer post-deploy smoke` run is in progress or queued, and that no
  `deploy edge functions` run on main is in progress, because it will trigger a smoke. Wait until both are clear.
- Run E2E one at a time, the same discipline as SQL applies: see
  [[two-applied-prs-deadlock-each-others-database-check]].
- When merging several PRs in a row, each deploy starts a smoke, so allow for them before scheduling a manual E2E.
- Carry-over fix: the harness must close its rehearsal window in a finally/teardown even when a run crashes, and a
  duty should flag a window older than its run.

Related: [[parallel-helpers-need-their-own-scratch-folders]], [[test-without-the-founders-credentials]].
