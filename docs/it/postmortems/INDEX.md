# IT postmortems, by failure class

Seat: it_engineer. One file per failure class, named `<first-seen date>_<class>.md`. Blameless: each says what
happened, the root cause, how it was detected, the fix found in git, and action items with an owner seat.

## What is counted (the measurement boundary)

The backlog is **closed `it.finding` handoffs of severity critical or high that have no `it_incident` row** — the
number `fn_it_engineer_postmortem()` reports as `historical_without_postmortem` (duty `it_engineer.postmortem`,
`scripts/sql/every_serious_incident_gets_a_postmortem.sql`). That duty only writes incidents for handoffs closed after
it was registered, so this history had none.

- Read on production `htdblwldjkcgjvmqkbeh`, 28 Sep 2026 ~13:40 UTC, read-only (`scripts/qsql.mjs`).
- Frozen at **handoff id <= 101627** (the newest in the set at the read). The live count keeps growing — it was
  560 an hour earlier and the brief said 559 — because recurring classes keep closing new occurrences.
- **Class** = the first two segments of the finding's issue key (`duty:heartbeat`, `watch:run_failure`, …). One handoff
  is one *occurrence*; a class seen 333 times can be one root cause. Where two families share a root cause they share
  a postmortem (`duty:unsigned_revision` + `duty:unsigned_change`).
- Counts are of handoffs, not of distinct faults, and not of emails the founder received.

## Classes

| Class | Handoffs | Critical | Postmortem |
|---|---:|---:|---|
| `duty:heartbeat` | 333 | 0 | [2026-09-15_duty_heartbeat.md](2026-09-15_duty_heartbeat.md) |
| `duty:smoke` | 73 | 0 | [2026-09-14_duty_smoke.md](2026-09-14_duty_smoke.md) |
| `duty:demo` | 41 | 0 | [2026-09-14_duty_demo.md](2026-09-14_duty_demo.md) |
| `duty:delivery` | 20 | 0 | [2026-09-15_duty_delivery.md](2026-09-15_duty_delivery.md) |
| `duty:journey` | 17 | 0 | [2026-09-14_duty_journey.md](2026-09-14_duty_journey.md) |
| `watch:run_failure` | 15 | 3 | [2026-09-14_watch_run_failure.md](2026-09-14_watch_run_failure.md) |
| `duty:unsigned_revision` | 13 | 13 | [2026-09-14_duty_unsigned_routine_change.md](2026-09-14_duty_unsigned_routine_change.md) |
| `duty:unsigned_change` | 2 | 2 | [2026-09-14_duty_unsigned_routine_change.md](2026-09-14_duty_unsigned_routine_change.md) |
| `watch:run_silent` | 11 | 0 | [2026-09-15_watch_run_silent.md](2026-09-15_watch_run_silent.md) |
| `monitor:detect_tick_blind` | 6 | 0 | [2026-09-18_monitor_detect_tick_blind.md](2026-09-18_monitor_detect_tick_blind.md) |
| `duty:security` | 1 | 1 | [2026-09-23_duty_security.md](2026-09-23_duty_security.md) |
| **Covered by a postmortem** | **532** | **19** | 11 families, 10 files |
| `duty:org_task_queue` | 4 | 0 | none |
| `duty:table_export` | 3 | 0 | none (cause 11 of `docs/it/IT_FAILURES_18_21_SEP_2026.md`) |
| `watch:error_events` | 3 | 0 | none |
| `duty:backup_enqueue_new_documents` | 2 | 0 | none |
| `duty:integration` | 2 | 1 | none |
| `duty:workflow_heartbeat` | 2 | 0 | none |
| `watch:queue_not_draining` | 2 | 0 | none |
| `watch:scheduler_gap` | 2 | 0 | none |
| `duty:backup_enqueue_backfill` | 1 | 0 | none |
| `duty:credential` | 1 | 1 | none — ZZ DEMO fixture (`zz_demo_provider`) |
| `duty:expiry` | 1 | 0 | none — ZZ DEMO fixture (`zz_demo_licence`) |
| `duty:journey_heartbeat` | 1 | 0 | none |
| `duty:live_code` | 1 | 0 | none — ZZ DEMO fixture (`zzdemo0`) |
| `duty:marketing_duties` | 1 | 0 | none |
| `duty:otp` | 1 | 1 | none |
| `duty:payment` | 1 | 1 | none — ZZ DEMO fixture (`cs_test_zzdemo`) |
| `duty:uptime` | 1 | 1 | none — ZZ DEMO fixture (`zz-demo.invalid`) |
| `monitor:it_loop` | 1 | 0 | none |
| `watch:refusal_rate` | 1 | 0 | none |
| **Without a postmortem** | **31** | **5** | 19 classes |
| **Total** | **563** | **24** | 30 classes |

532 + 31 = 563, the measured total. Critical: 19 + 5 = 24.

## The query that produced every number above

```sql
with h as (
  select a.id, a.detail->>'severity' sev, split_part(a.detail->>'issue_key', ':', 1) || ':' || split_part(a.detail->>'issue_key', ':', 2) cls
    from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
     and a.detail->>'severity' in ('critical', 'high') and a.id <= 101627
     and not exists (select 1 from public.it_incident i where i.handoff_id = a.id))
select cls, count(*) n, count(*) filter (where sev = 'critical') critical from h group by rollup (cls) order by cls nulls last;
-- rollup row: n = 563, critical = 24 (28 Sep 2026)
```

## Closing the backlog by class

There is **no postmortem table**; `public.it_incident` is the estate's postmortem record (cause, fix, regression check).
`scripts/sql/the_historical_serious_faults_are_closed_by_their_class_postmortem.sql` (PENDING, not applied) opens one
`it_incident` per covered handoff with the cause and fix of its class and the path of the file here, so the 532 leave
the backlog by class and the 31 stay visible. The same file adds the duty that chases findings open more than 24 hours
with the seat that owns them.
