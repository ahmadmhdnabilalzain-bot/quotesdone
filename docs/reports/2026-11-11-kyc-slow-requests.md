# kyc slow requests, 10-11 Nov 2026: where the time went

it_engineer, 11 Nov 2026. Read-only measurement on production (`htdblwldjkcgjvmqkbeh`): `function_edge_logs`,
`edge_logs`, `function_logs`, `postgres_logs`, `agent_runs`, `cron.job_run_details`. Window: 24 h to 16:30Z on 11 Nov.

## Method

- `function_edge_logs.execution_time_ms` is the edge's total for one request. Its `request_id` is a UUIDv7: the first
  48 bits are the millisecond the request was **received** (19:58:39.611 minus 24,856 ms = 19:58:14.755 = `01a1c70a2ae3`).
- Every call the function made is an `edge_logs` row whose `trace_id` equals that `request_id` without dashes.
- `agent_runs` `fn:kyc` (observe.ts) `started_at` is the moment kyc's handler **started**; `counts.ms` is the handler's time.

## The slow calls

| received (Z) | action | edge total | handler started | handler ms | waited before the handler |
|---|---|---:|---|---:|---:|
| 10 Nov 19:58:14.755 | state | 24,856 | 19:58:39.272 | 200 | 24.5 s |
| 10 Nov 20:10:46.939 | send_sms | 33,345 | 20:11:19.873 | 269 | 32.9 s |
| 11 Nov 02:25:36.759 | state | 10,280 | 02:25:46.794 | 118 | 10.0 s |
| 11 Nov 04:13:33.031 | accept_terms | 25,740 | 04:13:58.433 | 213 | 25.4 s |
| 11 Nov 04:42:48.582 | state | 43,808 | 04:43:31.990 | 256 | 43.4 s |
| 11 Nov 05:01:35.130 | accept_terms | 19,486 | 05:01:54.204 | 286 | 19.1 s |
| 11 Nov 16:00:13.130 | whatsapp_choose | 54,590 | 16:01:06.906 | 680 | 53.8 s |

In all seven the handler ran in the last 0.7 s (agent_runs). For the four whose sub-calls were read by `trace_id`
(19:58, 02:25, 04:43, 16:00), kyc's own calls (auth `/user`, two `sanctions_ban`, `leads`, `customers`, the two
WhatsApp-column reads, then the write for whatsapp_choose) start in the last 0.4 s and each takes 14-78 ms at the origin. No model call, no external API, no slow query, no lock
wait: the handler simply had not started. Each request was on a **warm** isolate (no boot for that execution near the
time; all 239 kyc shutdowns in the window are `EarlyDrop`). Kyc's handler over the 24 h: `state` p50 103 / p95 254 /
max 754 ms (n 730); `accept_terms` max 1,295; `send_sms` max 307; `whatsapp_choose` max 5,900 (one).

While three of those requests waited, other kyc calls were answered by a freshly booted isolate: 19:58:23.8 (603 ms),
04:43:19.4 (575 ms), 04:43:28.7 (752 ms), and resilience_ping's keep-warm at 16:00:22.6 (162 ms).

## Who saw it

All 7 calls over 10 s came from AS "Anthropic, PBC": our own harness (HeadlessChrome, `node`, and Playwright's iPhone
profile) in the cloud container. Callers from the UAE (Etisalat): 8 kyc POSTs, p95 586 ms, none over 3 s. The other
registration reads, same 24 h, end to end: `supplier_api` `me` (15-byte body) n 959, p50 650, p95 1,322, max 4,708 ms;
`supplier_portal` `dashboard` (22 bytes) n 634, p50 863, p95 1,538, max 5,279 ms; none over 10 s. login_otp 0 of 457,
messages_api 0 of 390 over 10 s.

The cloud proxy is not the cause: a keep-warm POST whose body was sent 8 s late reached Supabase only once complete
(the proxy buffers the body; edge total 865 ms, handler 1 ms, 17:07:27Z).

## What else ran at 16:00-16:01

- 21 seat-duty cron jobs started at 16:00:00; 48 cron runs in 16:00:00-16:01:10 used 5.9 s of database time in all, max
  1.0 s, none failed.
- `fn_customer_support_campaign_list_tick` (called by resilience_ping, trace `01a1cb56bbf9...`) hit the 8 s statement
  timeout at 16:00:59.796 (origin 8,026 ms, inside `fn_supplier_invite_candidates`). Over the 24 h, 18 of its 80 calls
  timed out (p50 8,018 ms); the other 62 returned in 14 ms. Not on kyc's path: kyc's reads at 16:01:07 took 18-78 ms.
- `fn_doc_backups_prune_done` 3,560 ms and `fn_it_detect` 1,178 ms at 16:00:23-30 (same resilience_ping run, 57 s).

## Fix

The wait is in the platform before our handler runs, so nothing on the server can shorten it. The portal now hedges the
cheap reads (`state`, `me`, `dashboard`): no answer after 4 s, the same read goes out once more and the first good answer
is taken (`src/lib/fetchRetry.ts`; the customer's boot-script read of kyc state and the project dashboard the same way,
`src/components/me/prefetch.ts`). Writes and reads that reason are never hedged. Prevented by:
`src/lib/fetchRetry.test.mjs` and `scripts/checks/a_stalled_registration_read_is_asked_again.test.mjs`.
