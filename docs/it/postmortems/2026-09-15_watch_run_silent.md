# Postmortem: `watch:run_silent` — a function stopped running at its usual rhythm

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class | `watch:run_silent:<function>` — 3 functions |
| Handoffs covered | **11** (all high) |
| First / last | 15 Sep 2026 17:47Z / 23 Sep 2026 14:32Z |
| Answering seats | customer_support, sales_engineer |

## Timeline
`send_whatsapp` 7 (18 Sep 06:16Z → 19 Sep 02:00Z), `conversation_archive` 3 (15 Sep 17:47Z → 21:17Z),
`wa_status` 1 (23 Sep 14:32Z). Each resolved within about an hour of its last handoff.

## Impact
`send_whatsapp`: measured as a false alarm — the function had nothing queued. `conversation_archive`, `wa_status`:
internal; cause not measured.

## Root cause
`send_whatsapp` (measured, `IT_FAILURES_18_21_SEP_2026.md` cause 6): `whatsappTick` returned early when nothing was
queued, so the function ran only under load (26 runs in 3.4 days on a 15-minute tick); the run_silent arm compared it
against its own 7-day rhythm (p50 13 min) and called an idle function "silent" — the instrument measured the wrong
subject. For `conversation_archive` and `wa_status` the cause was **not determined**.

## Fix (found in git)
- `1de84e3` (#767): `resilience_ping/index.ts` calls `send_whatsapp` every tick (~0.8 s), so it has a real pulse.

## Action items
1. **it_engineer** — a function whose rhythm is load-driven should be judged on its queue, not on its run cadence.

## Handoff ids covered
`watch:run_silent` (11): 28963, 28993, 28998, 38242, 38828, 38830, 38838, 38846, 38989, 38990, 83463.
