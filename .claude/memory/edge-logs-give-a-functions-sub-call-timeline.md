---
name: edge-logs-give-a-functions-sub-call-timeline
description: "11 Nov 2026: to find where a slow edge-function request spent its time, read edge_logs for its window — every PostgREST/GoTrue call it made is a row with its start time and origin_time. login_otp verify 2,272 ms = twelve serial hops in a slow DB minute, not one slow call."
metadata:
  type: lesson
  modified: 2026-11-11
---

**The tool.** `mcp__Supabase__query_logs` over a 1-3 s window around the request (logs keep ~1 day):
`select timestamp, source, substring(event_message,1,110) m, log_attributes['response.origin_time'] o,
log_attributes['execution_time_ms'] x from logs where source in ('edge_logs','function_edge_logs','function_logs')`.
Each `edge_logs` row with a `Deno/...SupabaseEdgeRuntime` user agent is one call the function made; its
timestamp is the call's START, `origin_time` the server's share. `function_logs` shows `booted` (a cold isolate)
and `function_edge_logs.execution_time_ms` the gateway's total (about 300 ms more than the handler's own
`agent_runs.counts.ms`). Gaps between consecutive starts = how serial the code is.

**What it showed (it_engineer, branch it_engineer-login-code-speed).** The certification's 2,798 ms login_otp verify was a cold
isolate plus twelve calls one after another in a minute when every origin_time was 5-15x normal (rl_check
169-230 ms against 28). No single call was the cause; the count of serial hops was. In-region verify was
p50 513 / p95 884 ms over 14 days; the scary p95 (7.5 s) was us-east callers that are not pinned to
ap-southeast-1. Always split `agent_runs.counts.region` before reading a latency percentile.

**Since then** login_otp writes `counts.action` and `counts.steps` {limit, check, reads, session} on every run,
so the per-stage p50/p95 is an `agent_runs` query and needs no log window.
