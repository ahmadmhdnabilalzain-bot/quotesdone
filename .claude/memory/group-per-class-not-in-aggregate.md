---
name: group-per-class-not-in-aggregate
description: Healthy totals hide classes that have failed every time they ran — group action_execution and agent_runs BY CLASS and look for zero successes ever.
metadata: 
  node_type: memory
  type: project
  originSessionId: 4ca61bec-f10b-4b3c-a015-46d98c25918e
  modified: 2026-08-13T23:11:30.571Z
---

13 Aug 2026. `action_execution` read 662 succeeded against 50 failed — healthy. Grouped **per
action_class**, two classes had never succeeded once:

- `knowledge_fill_gap` 0/3 — its only caller could not satisfy its one required argument
- `money_verify` 1 attempt on staging, **0 on production** — the money invariants had never
  verified anything on either project

The discriminator: every *other* class has successes **newer** than its failures — they broke and
recovered. A class with failures and nothing else has never worked at all.

Same query shape on `agent_runs` (`having count(*) filter (where status='ok') = 0`) surfaced four
more, though three were deliberate refusals logged as `error`.

**The follow-on lens: does every KIND have a runner?** `org_action_executor` holds `edge` and `rpc`;
both the dispatcher and the workflow sweep filtered `kind = 'edge'`, so 16 rpc rows had no runner
anywhere and `knowledge_fill` sat 13-deep in `ready`. Ask of any dispatch table: enumerate the
distinct kinds, then find the code that names each one.

Related: [[guarded-by-a-condition-that-cannot-occur]], [[finished-capability-with-no-entry-point]].

**And check-caused regressions are the check working.** Scheduling `action_invoke_rpc_5min` without
adding it to `public.cron_registry` dropped Row #3 130→129 via `s38-manual-always-current`. Register
the job; never relax the check. Cf. [[green-pr-does-not-mean-deployable]].
