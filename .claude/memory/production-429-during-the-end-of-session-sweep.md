---
name: production-429-during-the-end-of-session-sweep
description: "A mass of \"on production\" test failures at the end of a session is Supabase throttling (429), not code — staging passes the same assertions"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6ee28b3e-1f95-4b49-9341-54ffe11ece66
  modified: 2026-08-14T00:34:42.437Z
---

`node scripts/checks/run.mjs` exited 1 with ~15 "… on production" tests failing, while the *same
assertions on staging passed in the same run*. The error is
`429 {"message":"ThrottlerException: Too Many Requests"}` from the production project.

**Why:** the Row #3 scorer, the MCP query traffic and the test suite all draw on the same production
Management-API quota. Running the full suite while a scorer is still going against production
exhausts it, and the failures land on whichever assertions happen to run last — they look like a
broad production outage and are not.

**How to apply:** the discriminator is **staging passing the identical assertion**, plus a
sub-500ms failure (a throttle rejects instantly; a real query takes longer). Re-run the failing file
on its own before believing it — `sql_files_match_live` failed in the suite and reported
`247 routines, 0 drifted, 0 missing` standalone. Sequence the sweep: let the scorer finish, *then*
run the suite. Same family as the `Failed caching npm package` CI trap — infrastructure, re-run it.
Do not "fix" anything on the strength of a throttled run. See [[end-of-session-log-sweep]].
