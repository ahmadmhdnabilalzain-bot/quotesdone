---
name: a-late-hand-over-is-escalated-once-and-the-ceos-decision-closes-it
description: "16 Nov 2026 (ledger 1535/1688): 697 open hand-overs had no dead letters; they were answered work nobody closed. One clock now owns every open agent_actions row, escalates a late one once to the CEO on its own model room, and every CEO choice closes the row."
metadata:
  type: project
---

Measured 16 Nov 2026 (production SELECT): 697 pending agent_actions (399 held_question, 285 handoff, 13 other). Every one of the 150
`seat_handoff_kind` handlers existed; 0 demo rows, 0 duplicates. The loops did not close because:

- the overdue escalation skipped rows with an old support_ceo_report, rows older than 60 days and every non-handoff kind;
- the CEO's case for a late hand-over (`ceo.overdue_handoff`) shared a 30-a-day room with `ceo.it_finding`, which took all of it:
  no such question was ever filed; and its `wait` choice re-asked every 7 days for ever;
- a missed directive was re-issued up to 4 times (114 missed rows from 103 chains), then left on a ceo_task nobody decides.

**Now (scripts/sql/every_hand_over_has_an_owner_and_a_clock_and_closes_or_escalates.sql):** `public.v_handover_open` gives every
open row its owner seat (the seat that owes the next move: `fn_handoff_owing_seat`), registered kind (`seat_handoff_kind`, or
`agent_action_kind` for the rest), handler and due time. Duty `ceo.handover_clock` closes only what can never complete ("no
handler: ...", "test row: ...", "duplicate of #N"), escalates a late row once to the CEO (never the founder), and
`ceo.overdue_handoff` runs on its own room (`decision_policy` `ceo_daily_overdue_cases`). Every CEO choice closes the row through
`fn_handover_close`: 'done' only where the CEO may close it, otherwise 'dismissed' with the decision on the row.

**How to apply:** a new kind of pending work goes into `agent_action_kind` (or `seat_handoff_kind`) in the file that files it.
Count open hand-overs from `v_handover_open`, never from `status = 'pending'` alone, and read the owner from it, not `agent`.
Related: [[nothing-is-one-way]], [[a-handoff-is-answered-at-replied-at-not-decided-at]].
