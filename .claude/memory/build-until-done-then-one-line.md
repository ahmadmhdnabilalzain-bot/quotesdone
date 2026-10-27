---
name: build-until-done-then-one-line
description: Founder's rule, 7 Sep 2026 — when he shares a build, do not stop until every requirement is met, proved and CI green; then one confirmation line
metadata:
  type: feedback
---

*"whenever I share with you a build... you're not allowed to stop until you can confirm with one
message eventually saying your build is fully done, confirmed, and green CI and everything is as per
what you shared. All specs, all requirements has been met. So unless you can do that, you're not
allowed to stop. You keep working around the issue till you solve it."*

**A build** is any spec, prompt, knowledge pack, ZIP or list of requirements he shares — whether or
not he says the word. Open every attached file before starting.

**The line**, said only when true of every requirement, each one proved:
> The build is fully done, confirmed, CI green, and every requirement in what you shared has been met.

**"Confirmed" requires:** every requirement enumerated and individually checked; proved by EXECUTION
in the same session, not by "it applied cleanly"; CI green on the pushed commit (since 26 Oct 2026
GitHub Actions is off, so this means the local gate, `npm run gate` (PR #1597), on that commit, exit 0,
recorded in the PR — see [[ci-runs-locally-ubicloud-stopped]]);
deployed to the repo and the one Supabase project and read back; and nothing quietly reclassified as
out of scope.

**Work around blockers.** A refused apply, a broken regex, a timing-out delete, a guard that fires —
those are the work. "Difficult", "needs a refactor", "failing and I don't know why yet" are NOT
blockers.

**The one exception is a wall**, not a hard problem: a credential only he can mint, a service that is
down. Then finish everything else in full, say once and precisely what is blocked and on what, and
**do not say the line** — see [[quotesdone-definition-of-done]] and
[[never-state-what-you-have-not-measured]]. A false completion is worse than the delay.

**Never** fabricate a pass, weaken a check, or invent an agent to receive work
([[no-job-or-task-without-an-agent]]).
