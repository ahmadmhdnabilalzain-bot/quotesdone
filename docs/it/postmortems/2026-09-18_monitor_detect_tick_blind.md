# Postmortem: `monitor:detect_tick_blind` — the IT detector persisted no tick

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class | `monitor:detect_tick_blind` — 1 key |
| Handoffs covered | **6** (all high) |
| First / last | 18 Sep 2026 04:02Z / 21 Sep 2026 15:45Z |
| Answering seat | ceo |

## Impact
The IT engineer's detection engine was blind for about 50 hours (no `it_watch_tick` from 19 Sep 07:30Z,
`IT_FAILURES_18_21_SEP_2026.md` cause 1): nothing it detects could be raised in that time. A second symptom was the
"SCHEDULER DOWN" email — `fn_cron_liveness` read the detector's record as the scheduler's heartbeat (cause 2 there).

## Root cause
Same as `duty:heartbeat:itdetect` (`2026-09-15_duty_heartbeat.md`, mechanism 1): `fn_it_detect` took 10,999 ms against
the 8 s statement timeout after scheduled embedding backfills wrote ~6,000 `agent_runs` rows an hour.

## Fix (found in git)
- `1de84e3` (#767): `the_it_detector_reads_agent_runs_once_and_no_subject_can_flood_it.sql` (4,141 ms, bounded)
  and `the_liveness_check_reads_the_scheduler_not_the_detector.sql`.
- `247231d` (#752): the scheduler was never down — the detector was.
- Close note: "fn_it_detect persisted a tick 0 minutes ago". Not recurred since 21 Sep.

## Action items
1. **it_engineer** — `scripts/checks/it_engineer_loop_is_closed.test.mjs` §2 (20,000-row flood < 6,000 ms) guards this; keep it.

## Handoff ids covered
`monitor:detect_tick_blind` (6): 35285, 38667, 38860, 38867, 38869, 40224.
