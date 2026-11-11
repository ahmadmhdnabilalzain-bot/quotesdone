---
name: a-load-test-runs-on-production-with-tools-that-commit-nothing
description: "11 Nov 2026, ruling 1622: there is no sandbox, so load is measured on production with tools that cannot commit a row or reach a person. Website 200 users and public functions 400 users were clean; embed_ml fails first (546/503 on a cold ramp at ~10/s); intake writes are CPU-bound at ~29 ms per concurrent probe. The chat run needs ai_gateway + site_assistant deployed (load stub)."
metadata:
  type: feedback
---

**The tools** (`scripts/load/`, report `docs/reports/2026-11-11-load-test.md`):
- `ramp_driver.mjs --mix=website|functions|embed|chat`: closed-loop virtual users, think time, aborts when errors
  pass 2% (429 counted). Run it with `NODE_USE_ENV_PROXY=1`. The site's publishable key is `quotesdone2`.
- `db_write_burst.mjs`: an intake (customer + `sent` inquiry + `fn_match_capability`) in a DO block that RAISES, so
  nothing commits. The management API throttles at about 50 concurrent queries (HTTP 429). That limit is the harness's,
  not production's.
- `chat_load_run.mjs`: opens a `rehearsal_window` with `opened_by='load_test'` and `models_allowed=false`, runs the chat
  mix, and tears down in a `finally`. A preflight calls `ai_gateway` as `load_probe`. A gateway without the stub answers
  `fixture_no_spend` (no cost), and then the run refuses to start.

**Traps found:**
- `ai_cost_log.e2e_run_tag` is NULL for a load window, because the trigger keeps a tag only when `models_allowed=true`.
  Guard spend by time window plus `fn` plus the stub's `LOAD TEST run <tag>` text, never by tag (TD-34).
- Notification STATUS counts move during a run (the real outbox), so "before == after" on the counts is a false
  failure. Count notifications *created since the start* that name the run.
- `function_edge_logs.execution_time_ms` is measured at the entry colo (IAD for a US client) and includes the
  Pacific crossing. The in-region time is `response.headers.x_envoy_upstream_service_time`.
- The unified logs: use the MCP `query_logs` with `source='function_edge_logs'` and `log_attributes['…']`. The
  management API `logs.all` endpoint is gone.
- `embed_ml` is the chat path's weak point on a fast ramp. Warm it, or expect 7 to 15% null vectors for about 10 s.
- **The CPU budget (2 s) belongs to a WORKER, not to a request** (chat run 11 Nov 01:26). `function_logs` Shutdown events carry
  `cpu_time_used` and `reason` (`CPUTime` = killed with every request it held, HTTP 546 `WORKER_RESOURCE_LIMIT`;
  `EarlyDrop` = retired). Divide by the worker's request count (join `function_edge_logs` on `execution_id`) to get the CPU
  per turn: `site_assistant` was 145 to 215 ms.
- A `site_assistant` 503 with `sb_error_code=EDGE_FUNCTION_ERROR` was its OWN `no_answer`: read `agent_runs` (agent
  `site_assistant`, "no model produced an answer") before blaming the runtime. Since branch `it_engineer-chat-under-load`
  it answers 200 instead.
- To see where a turn's CPU goes, run the real handler locally against a fake Supabase and `deno run --cpu-prof-md`.
  Never with `--node-modules-dir=auto` against the shared tree: run from `supabase/functions` it also creates
  `supabase/functions/node_modules`, which the fire-and-forget and fetch-timeout checks then scan (TD-14).

**How to apply:** before any capacity claim, rerun the mix at a quiet hour (about 04:00 Dubai) and quote the report's
tables. Never point the chat mix at a gateway that has not passed the preflight.
Related: [[an-edge-call-runs-where-its-caller-is]], [[a-chat-turn-names-no-customer-so-it-carries-the-run-tag]].
