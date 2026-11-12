# hourly (it_engineer) - the 03:00 portal-home FAIL, regcert paid run 50123afa J5

Branch `it_engineer-the-top-of-the-hour-does-not-slow-a-person`, head 1df19fe4e (pushed). No PR opened.

## Verdict: NOT the pg_cron pile. The wait was in Supabase's functions relay, before any of our code ran.

**The request.** supplier_portal dashboard, request_id 01a1cdb2-b0fb (UUIDv7). The edge received it at 03:00:02.427Z.
It ran on a warm isolate (booted 02:57:03Z, 87 ms boot), region ap-southeast-1. The handler started at 03:00:05.515
(agent_runs 4907935) and took 417 ms. Its ~20 sub-calls (traced by trace_id) took 13-71 ms each at the origin and ran
in parallel after auth -> leads -> sanctions. Edge total 3,653 ms = **3,088 ms before the handler** + 417 ms handler +
~150 ms. Harness and browser share: 4,638 - 3,716 = 922 ms (the same as the step's normal runs).

**Ruled out, with evidence:**
- Cold start: the isolate was warm.
- Slow query or lock wait (the #1951 trigger and row lock): the handler took 417 ms, every call was 13-71 ms, and
  postgres_logs had no other lines.
- Harness network: the request had already reached Supabase when the 3.1 s wait began.
- supplier_doc_reread_5min: it runs at :x4/:x9 and takes 72 ms.
- **Our cron:** all 27 jobs in that minute ran from 03:00:00.92 to 02.39 (max 1.46 s, peak 12 at once). They had
  finished before the request arrived.
- No log source (edge, auth, function, postgres) has a row between 02:59:59 and 03:00:05: everything was held.

**The probe that settles it** (free; no data touched; markprobe.mjs). Three calls sent together:

| at | customer_portal keep-warm (no DB) | supplier_portal with no auth header (relay 401, no isolate, no DB) | /rest/v1 401 (same gateway) |
|---|---|---|---|
| 03:30:00.3 | 7.50 s | 5.09 s (4,883 ms in function_edge_logs) | 0.34 s |
| 03:35:00.3 | 2.39 | 1.99 | 0.35 |
| 03:40:00.3 | 2.82 | 2.47 | 0.33 |
| 03:45:00.3 | 2.94 | 2.76 | 0.33 |
| 03:50:00.3 | 3.75 | 2.66 | 0.39 |
| 03:55:00.3 | 1.52 | 1.85 | 0.15 |
| **04:00:00.3** | 3.24 | **4.47** | 0.31 |
| about 1-2 s later | 0.4-1.0 | 0.4-0.8 | 0.1-0.4 |
| mark +150 s (control) | 0.71-0.84 | 0.87-1.00 | 0.30-0.43 |

At 03:30:02.5 and 03:30:04.7, pg_stat_activity showed one active backend: the pg_net worker.

**Shape over 24 h** (function_edge_logs, receipt to first sub-call, all functions). For calls received in the first
0-2 s after a mark:
- :00: p50 4.0 s (88% over 1.5 s)
- other :x0: 2.3 s (68%)
- :x5: 1.6 s (52%)
- the first 0-2 s of minutes that are not marks: 0.27 s (2.3%)
- seconds 20-59 of any minute: 0.15 s (0.7%)

After #1936, the waits in seconds 0-5 are high at :15/:30/:45 (2.5-3.8 s). Our cron's summed work in those minutes is no
higher than at :10/:20/:40.

The calls that arrive during a hold are released together, around 2.4-6 s after the mark. A call that arrives after the
release is fast.

supplier_portal edge totals, POST 200, 24 h:
- :00 s0-5: n 3, p50 3,653 ms (all over 3 s)
- other marks s0-5: n 9, p50 2,716, p95 3,429
- rest of the mark minute: p50 893, p95 1,501
- elsewhere: p50 914, p95 1,565 (harness traffic)
- real UAE traffic: n 13, p50 433, none at a mark

supplier_portal handler time (agent_runs, 7 days):
- mark s0-19: p50 67 / p95 489 ms
- elsewhere: p50 117 / p95 509 ms
- the database side is no slower at marks.

## What changed

- `supabase/functions/supplier_portal/index.ts`: the two sanctions reads by e-mail start beside the company read, and
  the same 403 gate awaits them. This saves one serial hop, about 40-50 ms per request. It is not the fix for the 3 s.
  Test: `supplier_portal/the_email_ban_is_read_beside_the_company.test.ts`. It FAILS on main (both cases) and passes
  here; the folder runs 39/39.
- `scripts/checks/a_sanctioned_party_is_unreachable.test.mjs`: the pin follows the two new lines. A passes; B and C fail
  as they do on main (no token in this container).
- Memory: `a-five-minute-mark-holds-edge-calls-before-our-code.md` + index line. It also corrects the 11 Nov note in
  supplier-registration-certification.md.
- No SQL. I did not re-spread pg_cron, because it would not move this wait. For the record: after #1936, the minute :00
  carries 5.6 s of cron work an hour against 1.7-2.8 s at other marks and ~0.8 s off the marks. lead_email_check costs
  578 ms on every run at offset 0. That is database contention, but it is not on this path.
- The client hedge (fetchRetry HEDGE_MS 4 s, which already covers `dashboard`) is unchanged. A hedge sent 1-2 s later is
  held until the same release, so it cannot meet a 3 s budget.

## What would fix it (not done: too large for a fix round)

1. Make the portal home's first read not go through /functions/v1. A SECURITY DEFINER PostgREST RPC is not held. It
   would derive the supplier from auth.email() and return the dashboard card. That means porting buildDashboard
   (overview.ts, about 16 reads) to SQL and keeping parity tests.
2. Or have the certification report a step that starts in the first 6 s after a mark separately, with the receipt to
   handler gap. That changes the bar, so it is the founder's decision, not ours.
3. Ask Supabase support. Evidence: a JWT-less 401 held 4.9 s at 03:30:00.5Z, request_id 01a1cdb3-... (row in
   function_edge_logs, x 4883).

## At merge

1. No SQL.
2. Deploy `supplier_portal`, away from a :x0/:x5 mark.
3. The website is not touched.
4. No switches or secrets.

## How to re-measure

- Cheap and free: `NODE_USE_ENV_PROXY=1 node <scratchpad>/fixes/hourly/markprobe.mjs out.jsonl <ISO end>`. It times
  keep-warm, the relay 401 and the REST 401 at s0.3-6 of each mark and at +150 s. A fix to the relay shows as a
  keep-warm/401 under 1 s at s0.3.
- The paid certification step "the portal home opens" will still fail whenever that step starts in the first ~3 s
  after a mark, until (1) or (2) above is done.

## Follow-up (main session's question): is the hold our own burst of function calls?  No.

**Our function calls fired from the database.** net._http_response covers every pg_net call, internal or external. In
03:25-04:15Z there was at most ONE per minute. It went out in s0-6 of 03:25, :27, :30, :32, :37, :39, :42, :47, :49, :52,
:57, 04:02, :07 and :12, which is mostly ordinary minutes. In s0-6 of the marks 03:35, 03:40, 03:45, 03:55, 04:00, 04:05 and
04:10 there were **none**.

The cron jobs whose command makes an HTTP call:
- reask_refused_turns `* * * * *` (the kick posts only when work is waiting)
- lead_sourcing_batch `*/10`
- supplier_doc_reread_5min `4-59/5`
- dropbox_backup_second_scheduler `41 */6`

The seat duties' commands are SQL (fn_seat_duty_run).

Over 24 h in function_edge_logs, per s0-6 window:
- pg_net calls: 1.0 at :00, :x0 and :x5, and 1.1 in ordinary minutes
- all other calls (harness and function to function): 16, 11.4 and 11.9 at :00, :x0 and :x5, and 10.7 in ordinary minutes
- So the burst at a mark is the same size as in an ordinary minute.

**Hold against our burst** (median receipt-to-first-call wait of the other calls received in s0-2, per minute, 24 h):

| minute | our pg_net call in s0-2 | minutes | hold p50 | hold p90 |
|---|---|---:|---:|---:|
| ordinary | none | 191 | 487 ms | 995 ms |
| ordinary | yes | 17 | 388 | 732 |
| mark | **none** | 55 | **1,557** | **3,771** |
| mark | yes | 14 | 1,711 | 3,150 |

**Probe at s0.3 of every minute, 04:04-04:14** (the relay 401, which has no isolate):
- ordinary minutes: 0.82-1.43 s, including 04:07 and 04:12, which each carried one of our calls
- the marks 04:05 and 04:10, with none of our calls: 2.10 s and 2.69 s
- the earlier marks 03:30-04:00, also with none of our calls: 1.85-5.09 s

**Verdict: the hold belongs to the platform.** It occurs at marks where none of our calls fired, and it is absent from
ordinary minutes that carry the same number of our calls. Moving our cron or adding pg_sleep staggering would not change
it, so there is no SQL on the branch.

## Support note for Supabase (ready to send)

Project htdblwldjkcgjvmqkbeh (ap-southeast-1). Edge Function requests received in the first 0-5 s after each five-minute
mark (worst at :00, :15, :30, :45 UTC) wait 2-7 s before the function handler starts. Isolates are warm and the database
is idle. A POST with no Authorization header to a verify_jwt function, refused 401 by the relay, is held the same way.
`/rest/v1` through the same project gateway at the same instant answers in 0.15-0.39 s.

Examples (request_id is UUIDv7, so its first 48 bits are the receipt time):
- 01a1cdb2-b0fb-7b60-b592-a79a7c618cb9: supplier_portal, received 03:00:02.427Z 12 Nov, handler started 03:00:05.515,
  execution 3,653 ms, handler 417 ms
- the no-auth 401 to supplier_portal received 2026-11-12T03:30:00.508Z: execution 4,883 ms
- customer_portal 204 received 03:30:00.594Z: execution 7,203 ms
- the 401 probes at 03:35, :40, :45, :50, :55 and 04:00 (s0.3): 1.85-4.47 s

At those moments the project sent no edge-function calls of its own (net._http_response). Is this platform scheduling at
cron marks, and can the project be isolated from it?

## Sizing the durable fix: the portal home's first read as a PostgREST RPC

**The new SQL file** (it_engineer):
- `fn_supplier_portal_home()`: SECURITY DEFINER, `search_path` pinned, revoked from public and anon, granted to authenticated
- finds the supplier as `leads.claimed_by = lower(auth.jwt()->>'email')`
- applies the same sanctions gate: a by-lead or by-e-mail ban answers like the 403
- ports buildDashboard's 16 reads (9 tables and 4 existing RPCs), about 200 lines of SQL, plus a probe

**Parity:** a test calls both the RPC and the edge `dashboard` for ZZ DEMO suppliers in states such as pending,
approved, licence-gated, sanctioned and no-company, and asserts equal JSON.

**Client:**
- BootPrefetch `sup_dash` and `core/session.ts` call `/rest/v1/rpc/fn_supplier_portal_home` with the user's JWT
- they fall back to the function on any error
- the hedge is kept

**Estimate:** about 1.5-2 days, roughly 6 files. It needs the founder's go, because it is a second implementation of
the dashboard that has to be kept in step with the first.

## At merge (unchanged)

- No SQL.
- Deploy `supplier_portal` away from a mark.
- To confirm the platform verdict yourself: run markprobe.mjs and minuteprobe.mjs (in this folder). Marks will read 2-5 s
  at s0.3, ordinary minutes about 1 s, whichever minutes our pg_net calls fall in.
