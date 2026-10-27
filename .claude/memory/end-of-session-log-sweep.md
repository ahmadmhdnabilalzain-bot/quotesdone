---
name: end-of-session-log-sweep
description: "Always sweep GitHub Actions, Vercel and Supabase logs for failures before ending a session — it is a procedure, not a reaction to a report."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e175f498-4f90-4620-9e30-b42766f74ea1
  modified: 2026-08-09T21:53:05.206Z
---

**Before ending any session, check all three platforms for failures — unprompted.** GitHub Actions
runs, Vercel deployments, and Supabase (advisors, edge-function logs, and failed `cron.job_run_details`)
on **both** projects.

**Why:** the founder found out about a dead CI from a GitHub quota email, not from me — and the
whole estate is asynchronous. A cron that starts failing, an edge function throwing after a deploy,
or a Supabase advisor warning appears hours after the change that caused it, long after the work
looks finished. Deploying and measuring a scorer proves the change; it does not prove the platform
around it is still healthy.

**26 Oct 2026:** GitHub Actions is off until the bugs are cleared ([[ci-runs-locally-ubicloud-stopped]]).
Step 1 then confirms nothing ran unexpectedly; the session's own local check run takes its place.
There is one Supabase project, not two (staging was deleted 15 Aug 2026).

**How to apply:**
1. `gh run list --limit 20` — any `failure` since the session started, and WHY. Jobs with **zero
   steps** mean the runner never started: that is billing or quota, not code. A YAML error reports
   `startup_failure` instead.
2. Vercel deployments — latest build state per project, and runtime errors.
3. Supabase, on staging AND production: `get_advisors` (security + performance), edge-function logs,
   and `select ... from cron.job_run_details where status <> 'succeeded'` in the recent window.
4. Report what was checked and what was found, including "nothing" — a silent sweep is
   indistinguishable from a skipped one.

See [[quotesdone-definition-of-done]] and [[quotesdone-autonomy-and-staging-rules]].
