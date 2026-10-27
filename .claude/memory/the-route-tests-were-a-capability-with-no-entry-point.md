---
name: the-route-tests-were-a-capability-with-no-entry-point
description: "344 route tests for the 86 trade categories existed and passed, and their hourly cron had been off since the stand-down; the pack scorecard is what found it, and it is the only check that probes whether an ingested artefact is READ"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-04T09:24:20.456Z
---

`public.kb_operational_route_test` holds 344 cases asserting how a customer's words resolve to one
of the 86 trade categories — the front of the money loop. `fn_kb_route_test_run` is their only
runner and cron **222 `kb_route_tests_hourly`** was inactive since the 16 Aug stand-down, so nothing
had checked category routing for weeks. Driven by hand on 4 Sep 2026: **344 ran in 8 seconds, 344
passed, 0 failed, 0 regressions** — the routing was correct, only its guard was off. Enabled through
`fn_kernel_wrap_and_enable_cron(222, 'knowledge_director', 'data_intel')` with a `cron_registry`
line (`scripts/sql/the_route_tests_run_again.sql`).

**Why it matters beyond this one job:** the pack scorecard
([[the-packs-are-unopened-zips-in-downloads]]) is the only instrument in the estate that probes
whether an ingested artefact is actually READ by a live routine, instead of asserting it. Running it
found this in one line: `NOT READ BY ANY PRODUCTION ROUTINE - 86_CATEGORIES (routing) - route tests`.
The lens is [[finished-capability-with-no-entry-point]], and the scorecard is the tool that spots it
in the knowledge estate.

**How to apply:** before enabling a stood-down guard, run it by hand first and record the numbers.
Turning on a guard over something already broken buries the fix in noise; turning one on over
something measured green means the first red it ever raises is real.
