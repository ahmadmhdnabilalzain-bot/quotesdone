---
name: a-five-minute-mark-holds-edge-calls-before-our-code
description: "12 Nov 2026: an edge-function call received in the first ~0-5 s after a five-minute mark (worst at :00, :15, :30, :45) waits 2-7 s in Supabase's functions relay before any of our code runs. A JWT-less 401 is held as long as a real call; /rest/v1 through the same gateway is not; the database is idle. Not our pg_cron pile."
metadata:
  type: lesson
  modified: 2026-11-12
---

**What was measured (it_engineer, branch it_engineer-the-top-of-the-hour-does-not-slow-a-person; report in the fix round
scratchpad `fixes/hourly/REPORT.md`).** Paid regcert run 50123afa, J5 "the portal home opens" 4,638 ms at 03:00:08Z, 12 Nov.
The supplier_portal dashboard was received 03:00:02.427 (UUIDv7 request_id) on a warm isolate, and its handler started at
03:00:05.515 (agent_runs): 3.09 s before our code, then a 417 ms handler whose calls took 13-71 ms each. Every pg_cron job of
that minute had already finished (03:00:00.92-02.39, 27 jobs, max 1.46 s). No log source had a row in 02:59:59-03:00:05.

**The decisive probe (free, no data touched).** At 03:30:00.3Z, sent together: customer_portal keep-warm (`x-qd-warm: 1`, no
DB) 7.50 s; supplier_portal with no Authorization header (the relay's 401, no isolate, no DB) 5.09 s at the client and 4,883 ms
in function_edge_logs; `/rest/v1/` 401 through the same project gateway 0.34 s. pg_stat_activity at 03:30:02.5 and 04.7: one
active backend (the pg_net worker). So the hold is in the functions relay/runtime, not in the database or the API gateway.

**Shape (24 h of function_edge_logs, receipt to first sub-call).** Received in seconds 0-2 after a mark: :00 p50 4.0 s,
other :x0 2.3 s, :x5 1.6 s; other minutes' seconds 0-2: 0.27 s; elsewhere 0.15 s. Calls received in the hold are released
together around s2.4-6; a call that ARRIVES after the release is fast, so a hedge sent 1-2 s later is held to the same
release and does not help a 3 s budget. supplier_portal's own handler at marks: p50 67 / p95 489 ms (7 d) - no slower.

**How to apply.** A slow edge call in the first seconds after a mark is not evidence about our code or our cron: read the
receipt-to-handler gap first (edge-logs-give-a-functions-sub-call-timeline.md). Re-spreading pg_cron does not move it. What
would: a first read that does not go through /functions/v1 (a PostgREST RPC is not held), or a measurement window that
reports the mark separately. This corrects the 11 Nov note in supplier-registration-certification.md that put the :x0/:x5
slowness on the 89 seat_duty jobs: the spread (#1936) was applied and the hold remained.
